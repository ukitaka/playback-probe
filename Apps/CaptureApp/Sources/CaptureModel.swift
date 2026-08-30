import CoreAudio
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
        /// A process was chosen but is not running, so there is nothing to
        /// listen to yet.
        case waitingForProcess(String)
        case failed(String)
    }

    private(set) var hubState: HubState = .stopped
    private(set) var tapState: TapState = .stopped
    /// Most recent audio level, or `nil` when the tap has reported nothing yet.
    private(set) var level: Float?
    private(set) var status = PlaybackStatus()
    /// Audio processes the Mac currently knows about, for the picker.
    private(set) var availableProcesses: [AudioProcess] = []
    /// Bundle identifier being listened to, or `nil` for everything.
    private(set) var selectedBundleIdentifier: String?
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
    /// Audio objects the running tap was built for, so that a process
    /// reappearing under a new object is noticed.
    private var tappedObjectIDs: [AudioObjectID] = []
    private var ticksUntilProcessRefresh = 0

    /// How often the menu re-reads what the hub knows.
    ///
    /// The audio callback runs on Core Audio's real-time thread and must not
    /// drive a view, so the interface polls instead. Ten times a second is
    /// enough for a level meter to look continuous.
    private static let refreshInterval: TimeInterval = 0.1

    /// How often the list of audio processes is re-read. Far less often than
    /// the level: enumerating processes is not free, and an application takes
    /// longer than a tenth of a second to launch.
    private static let processRefreshTicks = 20

    /// Where the chosen process is remembered between launches.
    ///
    /// Also settable from a shell, which is how a test rig points the tap at an
    /// application without anyone opening the menu:
    /// `defaults write io.github.ukitaka.PlaybackProbeCapture audioProcess <bundle id>`
    private static let selectionDefaultsKey = "audioProcess"

    init(port: UInt16 = PlaybackHub.defaultPort) {
        hub = PlaybackHub(port: port)
        selectedBundleIdentifier = UserDefaults.standard.string(forKey: Self.selectionDefaultsKey)
    }

    var hubURL: String {
        switch hubState {
        case let .listening(port): "http://127.0.0.1:\(port)"
        case .stopped, .failed: "not listening"
        }
    }

    func start() {
        startHub()
        // The capture app always provides the audio oracle, even while it is
        // waiting for a chosen process to appear.
        hub.store.isAudioTapConfigured = true
        if selectedBundleIdentifier == nil {
            startTap()
        } else {
            // A remembered process may not be running yet; refreshProcesses
            // attaches once it appears.
            refreshProcesses()
        }
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

    /// Chooses what to listen to.
    ///
    /// - Parameter bundleIdentifier: `nil` listens to everything the Mac plays.
    ///   Naming a process avoids hearing the rest of the machine, which matters
    ///   on a Mac someone is also using: a browser playing a video is louder
    ///   than the threshold and would keep the audio oracle reporting sound
    ///   long after the player under test stopped.
    func select(bundleIdentifier: String?) {
        guard bundleIdentifier != selectedBundleIdentifier else { return }
        selectedBundleIdentifier = bundleIdentifier
        UserDefaults.standard.set(bundleIdentifier, forKey: Self.selectionDefaultsKey)
        stopTap()
        refreshProcesses()
        if bundleIdentifier == nil {
            startTap()
        }
    }

    /// Re-reads the process list and follows the chosen process on and off.
    ///
    /// An application in a simulator gets a new audio object every launch, so a
    /// tap bound to yesterday's object hears nothing. Comparing what is there
    /// against what the tap was built for is what makes selection survive the
    /// application being relaunched between tests.
    private func refreshProcesses() {
        availableProcesses = ((try? AudioProcess.all()) ?? [])
            .filter { $0.bundleIdentifier != nil }
            .sorted { ($0.bundleIdentifier ?? "") < ($1.bundleIdentifier ?? "") }

        // Nothing is decided while a start is in flight. Tearing a tap down
        // and building another one every two seconds thrashes Core Audio's
        // aggregate devices, and the second start would be swallowed by the
        // guard in `startTap` anyway.
        guard let selectedBundleIdentifier, !isStarting else { return }
        let matching = availableProcesses
            .filter { $0.bundleIdentifier == selectedBundleIdentifier }
            .map(\.id)
            .sorted()
        guard matching != tappedObjectIDs else { return }

        stopTap()
        if matching.isEmpty {
            tapState = .waitingForProcess(selectedBundleIdentifier)
        } else {
            // `tappedObjectIDs` is set on success, not here. Recording the
            // intention would leave the two agreeing after a start that never
            // happened, and nothing would ever retry.
            startTap(source: .processes(matching), objectIDs: matching)
        }
    }

    /// Starts the tap off the main thread.
    ///
    /// Creating the audio callback blocks until Core Audio answers, and the
    /// first time it is the permission prompt that answers. Doing that on the
    /// main actor freezes the whole application for as long as the dialog is
    /// on screen — including the menu that explains what it is waiting for.
    func startTap(source: AudioLevelTap.Source = .systemWide, objectIDs: [AudioObjectID] = []) {
        guard tap == nil, !isStarting else { return }
        isStarting = true
        tapState = .starting

        let tap = AudioLevelTap(source: source)
        let store = hub.store
        Task.detached(priority: .userInitiated) {
            do {
                try tap.start { level in
                    // The audio thread: record and return.
                    store.audioLevels.append(
                        AudioLevelSample(timestamp: Date().timeIntervalSince1970, rms: level)
                    )
                }
                await self.tapDidStart(tap, objectIDs: objectIDs)
            } catch {
                await self.tapDidFail(error)
            }
        }
    }

    private func tapDidStart(_ tap: AudioLevelTap, objectIDs: [AudioObjectID]) {
        isStarting = false
        self.tap = tap
        tappedObjectIDs = objectIDs
        hub.store.isAudioTapAttached = true
        hub.store.audioTapError = nil
        tapState = .running
        logger.notice("Audio tap running")
    }

    private func tapDidFail(_ error: any Error) {
        isStarting = false
        tappedObjectIDs = []
        tapState = .failed("\(error)")
        hub.store.audioTapError = "\(error)"
        logger.error("Audio tap could not start: \(error, privacy: .public)")
    }

    func stopTap(configured: Bool = true) {
        hub.store.isAudioTapConfigured = configured
        tap?.stop()
        tap = nil
        hub.store.isAudioTapAttached = false
        tappedObjectIDs = []
        if case .running = tapState {
            tapState = .stopped
        }
    }

    private func refresh() {
        if ticksUntilProcessRefresh <= 0 {
            ticksUntilProcessRefresh = Self.processRefreshTicks
            refreshProcesses()
        }
        ticksUntilProcessRefresh -= 1

        level = hub.store.audioLevels.latest?.rms
        status = hub.store.status()
        eventCount = hub.store.events().count
    }

    func reset() {
        hub.store.reset()
        refresh()
    }
}
