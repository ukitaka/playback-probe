import Foundation

/// One audio level reading.
public struct AudioLevelSample: Sendable, Equatable {
    /// Seconds since the Unix epoch.
    public let timestamp: TimeInterval
    /// Root mean square amplitude of the buffer, in the range 0...1.
    public let rms: Float

    public init(timestamp: TimeInterval, rms: Float) {
        self.timestamp = timestamp
        self.rms = rms
    }
}

/// A bounded history of audio levels.
///
/// A test asks whether sound was produced over a window rather than at an
/// instant, because the audio callback fires on the hardware's schedule and a
/// poll will usually land between two buffers. An instantaneous reading would
/// report silence for a player that is plainly audible.
public final class AudioLevelHistory: @unchecked Sendable {
    /// Level above which a buffer counts as sound rather than noise floor.
    /// Roughly -40 dBFS.
    public static let defaultThreshold: Float = 0.01

    private let lock = NSLock()
    private var samples: [AudioLevelSample]
    private let capacity: Int
    private var nextIndex = 0
    private var count = 0

    /// - Parameter capacity: How many readings to keep. The default holds about
    ///   a minute at typical Core Audio buffer sizes, which is far more than a
    ///   test window needs.
    public init(capacity: Int = 4096) {
        precondition(capacity > 0)
        self.capacity = capacity
        samples = []
        samples.reserveCapacity(capacity)
    }

    public func append(_ sample: AudioLevelSample) {
        lock.lock()
        defer { lock.unlock() }
        if samples.count < capacity {
            samples.append(sample)
        } else {
            samples[nextIndex] = sample
        }
        nextIndex = (nextIndex + 1) % capacity
        count = Swift.min(count + 1, capacity)
    }

    /// The most recent reading, or `nil` if nothing has arrived yet.
    public var latest: AudioLevelSample? {
        lock.lock()
        defer { lock.unlock() }
        guard count > 0 else { return nil }
        let index = (nextIndex - 1 + capacity) % capacity
        return index < samples.count ? samples[index] : samples.last
    }

    /// Every reading taken in the last `window` seconds, oldest first.
    public func samples(
        within window: TimeInterval,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> [AudioLevelSample] {
        lock.lock()
        defer { lock.unlock() }
        let cutoff = now - window
        return samples.filter { $0.timestamp >= cutoff }.sorted { $0.timestamp < $1.timestamp }
    }

    /// Whether any reading in the window exceeded the threshold.
    ///
    /// Returns `nil` when no reading covers the window at all: that means the
    /// tap is not running, which must not be reported as silence.
    public func isActive(
        within window: TimeInterval,
        threshold: Float = defaultThreshold,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> Bool? {
        let recent = samples(within: window, now: now)
        guard !recent.isEmpty else { return nil }
        return recent.contains { $0.rms > threshold }
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        samples.removeAll(keepingCapacity: true)
        nextIndex = 0
        count = 0
    }
}
