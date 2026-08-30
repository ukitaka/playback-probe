import AVFoundation
import Foundation
import ProbeBootstrap

/// Observes every `AVPlayer` in the host process and records what it sees.
///
/// The probe does not decide whether playback stopped. It records raw state and
/// time samples; the aggregation and the actual assertions live on the test
/// side, so that the same evidence can back different judgements.
public final class PlaybackProbe: @unchecked Sendable {
    public static let shared = PlaybackProbe()

    /// Guards every stored property. The probe is reached from the load-time
    /// constructor, from the notification queue and from the sampling timer.
    private let lock = NSLock()

    private var isRunning = false
    private var configuration: ProbeConfiguration?
    private var recorder: ProbeEventRecorder?
    private var observer: NSObjectProtocol?
    private var timer: DispatchSourceTimer?

    /// Attached players, keyed by object identity so that repeated
    /// notifications from the same instance do not attach it twice.
    private var attachedPlayers: [ObjectIdentifier: AttachedPlayer] = [:]
    private var attachedPlayerCount = 0

    /// Whether the library was started by its load-time constructor, as opposed
    /// to being linked into the application and started by hand. Recorded with
    /// the start event so that a failing test can tell injection problems apart
    /// from observation problems.
    public var isBootstrappedByConstructor: Bool {
        playback_probe_bootstrap_did_run()
    }

    private init() {}

    /// Starts observing, unless the environment does not enable the probe.
    ///
    /// Called from the load-time constructor, before `main()`. Only observer
    /// registration happens here; anything touching UIKit would run too early.
    public func start(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard let configuration = ProbeConfiguration(environment: environment) else { return }

        lock.lock()
        guard !isRunning else {
            lock.unlock()
            return
        }
        isRunning = true
        self.configuration = configuration
        let recorder = ProbeEventRecorder(logPath: configuration.logPath)
        self.recorder = recorder
        lock.unlock()

        // `object: nil` makes this fire for every AVPlayer in the process,
        // including instances owned by a third-party SDK that the test has no
        // reference to. The notification's object is that instance.
        observer = NotificationCenter.default.addObserver(
            forName: AVPlayer.rateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let player = notification.object as? AVPlayer else { return }
            self?.attach(to: player)
        }

        startSampling(interval: configuration.sampleInterval)
        recorder.record(
            ProbeEvent(
                kind: .probeStarted,
                bootstrappedByConstructor: isBootstrappedByConstructor
            )
        )
    }

    /// Registers a player for sampling. Safe to call repeatedly with the same
    /// instance; only the first call attaches.
    public func attach(to player: AVPlayer) {
        let identifier = ObjectIdentifier(player)

        lock.lock()
        guard isRunning, attachedPlayers[identifier] == nil else {
            lock.unlock()
            return
        }
        attachedPlayerCount += 1
        let attached = AttachedPlayer(id: "player-\(attachedPlayerCount)", player: player)
        attachedPlayers[identifier] = attached
        let recorder = recorder
        lock.unlock()

        recorder?.record(
            ProbeEvent(
                kind: .playerAttached,
                playerID: attached.id,
                playerState: PlayerState(player.timeControlStatus),
                currentTime: Self.finiteSeconds(player.currentTime()),
                rate: player.rate
            )
        )
    }

    private func startSampling(interval: TimeInterval) {
        // Sampled on the main queue because AVPlayer is not documented as
        // thread-safe. The work per tick is a handful of property reads.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.sample()
        }

        lock.lock()
        self.timer = timer
        lock.unlock()

        timer.resume()
    }

    private func sample() {
        lock.lock()
        let recorder = recorder
        var released: [AttachedPlayer] = []
        var live: [AttachedPlayer] = []
        for (identifier, attached) in attachedPlayers {
            if attached.player == nil {
                released.append(attached)
                attachedPlayers.removeValue(forKey: identifier)
            } else {
                live.append(attached)
            }
        }
        lock.unlock()

        guard let recorder else { return }

        for attached in released {
            recorder.record(ProbeEvent(kind: .playerReleased, playerID: attached.id))
        }

        for attached in live {
            guard let player = attached.player else { continue }
            recorder.record(
                ProbeEvent(
                    kind: .sample,
                    playerID: attached.id,
                    playerState: PlayerState(player.timeControlStatus),
                    currentTime: Self.finiteSeconds(player.currentTime()),
                    rate: player.rate
                )
            )
        }
    }

    /// `AVPlayer.currentTime()` is indefinite before an item is ready, and
    /// `CMTime.seconds` turns that into NaN, which JSON cannot represent.
    private static func finiteSeconds(_ time: CMTime) -> Double? {
        let seconds = time.seconds
        return seconds.isFinite ? seconds : nil
    }
}

/// Weak box around an observed player, so that the probe never keeps a player
/// alive past the point the application would have released it.
private final class AttachedPlayer {
    let id: String
    weak var player: AVPlayer?

    init(id: String, player: AVPlayer) {
        self.id = id
        self.player = player
    }
}
