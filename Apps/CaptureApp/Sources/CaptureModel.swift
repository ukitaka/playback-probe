import Foundation
import Observation
import os
import PlaybackProbeAudio
import PlaybackProbeHub
import PlaybackProbeSchema

/// Owns the hub and the audio tap, and publishes enough of their state for the
/// menu to show whether either is actually working.
///
/// The menu exists because both can fail silently. A hub nobody is reporting to
/// and a tap that was refused permission both look exactly like a stopped
/// player, so the point of the interface is to make "nothing is happening"
/// distinguishable from "nothing is running".
@Observable
@MainActor
final class CaptureModel {
    enum HubState {
        case stopped
        case listening(port: UInt16)
        case failed(String)
    }

    enum TapState {
        case stopped
        /// Waiting for Core Audio, which is also where the permission prompt
        /// is answered.
        case starting
        case running
        case failed(String)
    }

    private(set) var hubState: HubState = .stopped
    private(set) var tapState: TapState = .stopped
    /// Most recent audio level, or `nil` when the tap has reported nothing yet.
    private(set) var level: Float?
    private(set) var status = PlaybackStatus()
    /// Events the hub has received since it started, as a sign of life.
    private(set) var eventCount = 0

    /// State changes go to the unified log as well as the menu. A tap that was
    /// refused is otherwise only visible to someone who opens the menu, which
    /// is no use on a machine running tests unattended.
    private let logger = Logger(subsystem: "com.github.ukitaka.PlaybackProbe", category: "capture")

    private let hub: PlaybackHub
    private var tap: AudioLevelTap?
    private var isStarting = false
    private var refreshTimer: Timer?

    /// How often the menu re-reads what the hub knows.
    ///
    /// The audio callback runs on Core Audio's real-time thread and must not
    /// drive a view, so the interface polls instead. Ten times a second is
    /// enough for a level meter to look continuous.
    private static let refreshInterval: TimeInterval = 0.1

    init(port: UInt16 = PlaybackHub.defaultPort) {
        hub = PlaybackHub(port: port)
    }

    var hubURL: String {
        switch hubState {
        case let .listening(port): "http://127.0.0.1:\(port)"
        case .stopped, .failed: "not listening"
        }
    }

    func start() {
        startHub()
        startTap()
        refreshTimer = Timer
            .scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        stopTap()
        hub.stop()
        hubState = .stopped
    }

    private func startHub() {
        do {
            try hub.start()
            hubState = .listening(port: hub.port ?? 0)
            // Bound to a local: the logging macro captures its arguments in an
            // autoclosure, which needs an explicit `self` that the formatter
            // then removes again.
            let address = hubURL
            logger.notice("Hub listening on \(address, privacy: .public)")
        } catch {
            hubState = .failed("\(error)")
            logger.error("Hub could not start: \(error, privacy: .public)")
        }
    }

    /// Starts the tap off the main thread.
    ///
    /// Creating the audio callback blocks until Core Audio answers, and the
    /// first time it is the permission prompt that answers. Doing that on the
    /// main actor freezes the whole application for as long as the dialog is
    /// on screen — including the menu that explains what it is waiting for.
    func startTap() {
        guard tap == nil, !isStarting else { return }
        isStarting = true
        tapState = .starting

        let tap = AudioLevelTap()
        let store = hub.store
        Task.detached(priority: .userInitiated) {
            do {
                try tap.start { level in
                    // The audio thread: record and return.
                    store.audioLevels.append(
                        AudioLevelSample(timestamp: Date().timeIntervalSince1970, rms: level)
                    )
                }
                await self.tapDidStart(tap)
            } catch {
                await self.tapDidFail(error)
            }
        }
    }

    private func tapDidStart(_ tap: AudioLevelTap) {
        isStarting = false
        self.tap = tap
        hub.store.isAudioTapAttached = true
        hub.store.audioTapError = nil
        tapState = .running
        logger.notice("Audio tap running")
    }

    private func tapDidFail(_ error: any Error) {
        isStarting = false
        tapState = .failed("\(error)")
        hub.store.audioTapError = "\(error)"
        logger.error("Audio tap could not start: \(error, privacy: .public)")
    }

    func stopTap() {
        tap?.stop()
        tap = nil
        hub.store.isAudioTapAttached = false
        if case .running = tapState {
            tapState = .stopped
        }
    }

    private func refresh() {
        level = hub.store.audioLevels.latest?.rms
        status = hub.store.status()
        eventCount = hub.store.events().count
    }

    func reset() {
        hub.store.reset()
        refresh()
    }
}
