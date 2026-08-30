import Foundation
import PlaybackProbeSchema

/// What the oracles said over one window of time.
///
/// A verdict needs a window rather than a single reading: one sample can only
/// report intent (`timeControlStatus`), and it takes two to tell whether the
/// playback position actually moved.
public struct PlaybackObservation: Sendable {
    /// Samples inside the window, oldest first.
    public let samples: [ProbeEvent]
    /// Length of the window these samples were taken from.
    public let window: TimeInterval

    public init(samples: [ProbeEvent], window: TimeInterval) {
        self.samples = samples
        self.window = window
    }

    /// The states seen in the window, in order and without repeats.
    public var states: [PlayerState] {
        samples.compactMap(\.playerState).reduce(into: []) { result, state in
            if result.last != state { result.append(state) }
        }
    }

    public var isPositionAdvancing: Bool {
        samples.isPlaybackPositionAdvancing()
    }

    /// Whether the video oracle was running over this window.
    public var hasVideoOracle: Bool {
        samples.hasVideoOracle
    }

    public var isVideoAdvancing: Bool {
        samples.isVideoAdvancing()
    }

    /// Whether there is enough evidence to say anything at all.
    public var isConclusive: Bool {
        samples.count >= 2
    }

    /// Every oracle agrees playback is stopped: the player reports paused for
    /// the whole window, the position never moved, and the picture did not
    /// change if anything was watching it.
    ///
    /// `waitingToPlay` does not count as stopped. The player intends to play
    /// and is only starved of data, which is a different bug.
    public var isStopped: Bool {
        isConclusive
            && samples.allSatisfy { $0.playerState == .paused }
            && !isPositionAdvancing
            && !(hasVideoOracle && isVideoAdvancing)
    }

    /// Playback is running: the player reports playing, the position moved,
    /// and the picture changed if anything was watching it.
    public var isPlaying: Bool {
        isConclusive
            && samples.contains { $0.playerState == .playing }
            && isPositionAdvancing
            && (!hasVideoOracle || isVideoAdvancing)
    }

    /// A one-line description for a failure message.
    public var summary: String {
        guard isConclusive else {
            return """
            only \(samples.count) sample(s) in the last \(formatted(window)); either the probe never \
            attached to a player, or the window is shorter than two sampling intervals
            """
        }
        let stateList = states.map(\.rawValue).joined(separator: " then ")
        let positions = samples.compactMap(\.currentTime)
        let positionText = positions.isEmpty
            ? "no position readings"
            : "position \(formatted(positions.first!)) to \(formatted(positions.last!))"
        let videoText = hasVideoOracle
            ? ", picture \(isVideoAdvancing ? "moving" : "still")"
            : ""
        return "\(samples.count) samples over \(formatted(window)): \(stateList), \(positionText)\(videoText)"
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.2fs", value)
    }
}
