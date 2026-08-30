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

public extension [ProbeEvent] {
    /// How many bits a still frame may differ by and still count as still.
    ///
    /// Measured on the demo at a 16 cell grid, sampling every 200ms:
    /// consecutive frames of moving video differed by 3 to 8 bits, median 6.
    /// Two bits of slack sits below that and still covers a decoder that is
    /// not quite deterministic.
    static var stillFrameTolerance: Int { 2 }

    /// Whether the video oracle was running, which is how "switched off" is
    /// told apart from "looked, and nothing was moving".
    var hasVideoOracle: Bool {
        events(of: .sample).contains { $0.videoSampled == true }
    }

    /// Whether the picture changed across these samples.
    ///
    /// A paused player stops producing frames altogether rather than repeating
    /// the last one, so too few frames to compare is itself the answer: the
    /// picture is not advancing. Over a window that is safe, while a single
    /// tick landing between two frames would not be.
    func isVideoAdvancing(tolerance: Int = stillFrameTolerance) -> Bool {
        let hashes = events(of: .sample).compactMap(\.videoFrameHash)
        guard hashes.count >= 2 else { return false }
        return zip(hashes, hashes.dropFirst()).contains { first, second in
            (FrameFingerprint.hammingDistance(first, second) ?? 0) > tolerance
        }
    }
}
