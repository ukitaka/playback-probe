import Foundation

// Rules for reading a run of samples. They live beside the wire type because
// both the test side and the host-side hub reach verdicts from the same
// evidence, and the two must not drift apart.

public extension [ProbeEvent] {
    func events(of kind: ProbeEvent.Kind) -> [ProbeEvent] {
        filter { $0.kind == kind }
    }

    /// Samples recorded at or after `timestamp`, in the order they were written.
    func samples(since timestamp: TimeInterval) -> [ProbeEvent] {
        events(of: .sample).filter { $0.timestamp >= timestamp }
    }

    /// Whether the playback position moved across these samples.
    ///
    /// Judged pairwise rather than by comparing the first and last sample,
    /// because looping content seeks back to the start: a window straddling
    /// that seek has a lower last value than first while playing perfectly
    /// normally.
    ///
    /// The threshold absorbs the rounding in `CMTime.seconds` and the jitter
    /// between the sampling timer and the player's own clock.
    func isPlaybackPositionAdvancing(threshold: Double = 0.05) -> Bool {
        let positions = events(of: .sample).compactMap(\.currentTime)
        guard positions.count >= 2 else { return false }
        return zip(positions, positions.dropFirst()).contains { $1 - $0 > threshold }
    }
}
