import Foundation
import PlaybackProbeSchema

/// Collects what every oracle reports and answers the aggregate question.
///
/// The probe pushes player samples in from inside the application under test;
/// the audio tap pushes levels in from the host. Neither knows about the other,
/// and only this store sees enough to say whether they agree.
public final class PlaybackStatusStore: @unchecked Sendable {
    /// Observation window used when a request does not ask for one.
    public static let defaultWindow: TimeInterval = 1.0

    public let audioLevels: AudioLevelHistory

    /// Whether a host-side audio tap has been attached to this hub.
    ///
    /// Cannot be inferred from the level history: an output device with nothing
    /// to play does not run its callback at all, so a freshly started tap looks
    /// identical to no tap until the first sound. The host that owns the tap
    /// says so explicitly instead.
    public var isAudioTapAttached: Bool {
        get { lock.lock(); defer { lock.unlock() }; return audioTapAttached }
        set { lock.lock(); audioTapAttached = newValue; lock.unlock() }
    }

    /// Why the audio tap is not running, when something tried and failed.
    ///
    /// Reported through the hub because that is the one place everything else
    /// already looks. A refused tap is otherwise visible only to whoever is
    /// sitting in front of the machine, which is no use to a test run.
    public var audioTapError: String? {
        get { lock.lock(); defer { lock.unlock() }; return tapError }
        set { lock.lock(); tapError = newValue; lock.unlock() }
    }

    private var audioTapAttached = false
    private var tapError: String?

    private let lock = NSLock()
    private var recorded: [RecordedEvent] = []
    private let sampleLimit: Int

    public init(audioLevels: AudioLevelHistory = AudioLevelHistory(), sampleLimit: Int = 2048) {
        self.audioLevels = audioLevels
        self.sampleLimit = sampleLimit
    }

    /// Records one observation from the probe. Events other than samples are
    /// kept too, so that a caller can see whether a player was ever attached.
    public func record(_ event: ProbeEvent, receivedAt: TimeInterval = Date().timeIntervalSince1970) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(RecordedEvent(event: event, receivedAt: receivedAt))
        if recorded.count > sampleLimit {
            recorded.removeFirst(recorded.count - sampleLimit)
        }
    }

    public func record(_ events: [ProbeEvent], receivedAt: TimeInterval = Date().timeIntervalSince1970) {
        for event in events {
            record(event, receivedAt: receivedAt)
        }
    }

    /// Every event received so far, oldest first.
    public func events() -> [ProbeEvent] {
        recordedEvents().map(\.event)
    }

    /// Every event with the moment the hub received it.
    public func recordedEvents() -> [RecordedEvent] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    /// What all oracles say about the last `window` seconds.
    public func status(
        window: TimeInterval = defaultWindow,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> PlaybackStatus {
        // Windowed on when the hub received each event, not on the timestamp
        // the probe wrote. Those come from a different machine's clock: the
        // simulator here, an emulator on Android. Even a second of skew would
        // empty the window and make a healthy player look like a stopped one.
        let recent = recordedEvents()
            .filter { $0.receivedAt >= now - window }
            .map(\.event)
            .events(of: .sample)

        return PlaybackStatus(
            playerState: recent.last?.playerState,
            // Movement needs two readings. With one or none the honest answer
            // is "no opinion", not "not moving".
            currentTimeAdvancing: recent.count >= 2 ? recent.isPlaybackPositionAdvancing() : nil,
            audioActive: audioLevels.isActive(within: window, now: now),
            // Absent unless frames actually arrived: a probe with video
            // sampling switched off must not be read as evidence of stopped
            // rendering.
            videoAdvancing: recent.hasVideoOracle ? recent.isVideoAdvancing() : nil
        )
    }

    public func reset() {
        lock.lock()
        recorded.removeAll(keepingCapacity: true)
        lock.unlock()
        audioLevels.reset()
    }
}

/// An event together with the moment the hub received it.
public struct RecordedEvent: Sendable {
    public let event: ProbeEvent
    /// Seconds since the Unix epoch, on the hub's clock.
    public let receivedAt: TimeInterval

    public init(event: ProbeEvent, receivedAt: TimeInterval) {
        self.event = event
        self.receivedAt = receivedAt
    }
}
