import Foundation
import PlaybackProbeSchema

public extension ProbeEventLog {
    /// How long to keep polling before giving up. Generous relative to the
    /// measured observation latency, because a timeout here means something is
    /// wrong rather than slow.
    static let defaultTimeout: TimeInterval = 5

    /// How much uninterrupted evidence a verdict needs.
    ///
    /// Must span at least two sampling intervals, since it takes two samples to
    /// tell whether the playback position moved. One second covers the probe's
    /// own 500ms default as well as the 200ms `ProbeLaunchEnvironment` sets, so
    /// the verdict does not depend on which one is in effect. Lower it when you
    /// know the sampling interval and want the assertion to return sooner.
    static let defaultWindow: TimeInterval = 1.0

    /// What the oracles reported over the last `window` seconds.
    func observePlayback(
        window: TimeInterval = defaultWindow,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> PlaybackObservation {
        PlaybackObservation(samples: events().samples(since: now - window), window: window)
    }

    /// Waits until playback is observed stopped, and stayed stopped.
    ///
    /// This is the call that absorbs observation latency, so that a test does
    /// not have to reason about sampling intervals: after asking the player to
    /// stop, wait for this instead of sleeping a guessed amount.
    ///
    /// Returns as soon as an entire `window` of samples agrees that playback is
    /// stopped, so a player that pauses for one tick and resumes does not pass.
    @discardableResult
    func waitUntilPlaybackStopped(
        timeout: TimeInterval = defaultTimeout,
        window: TimeInterval = defaultWindow,
        pollInterval: TimeInterval = 0.05
    ) throws -> PlaybackObservation {
        try waitUntil(
            timeout: timeout,
            window: window,
            pollInterval: pollInterval,
            expecting: "playback to stop"
        ) {
            $0.isStopped
        }
    }

    /// Waits until playback is observed running.
    @discardableResult
    func waitUntilPlaybackStarted(
        timeout: TimeInterval = defaultTimeout,
        window: TimeInterval = defaultWindow,
        pollInterval: TimeInterval = 0.05
    ) throws -> PlaybackObservation {
        try waitUntil(
            timeout: timeout,
            window: window,
            pollInterval: pollInterval,
            expecting: "playback to start"
        ) {
            $0.isPlaying
        }
    }

    /// Watches for `window` seconds and reports what happened.
    ///
    /// Use this for the opposite question — "is it *still* playing?" — which
    /// cannot be answered by waiting for something to appear. Waiting would
    /// return the instant it saw playback, whereas the claim is about the whole
    /// window.
    func observePlayback(for window: TimeInterval) -> PlaybackObservation {
        Thread.sleep(forTimeInterval: window)
        return observePlayback(window: window)
    }

    private func waitUntil(
        timeout: TimeInterval,
        window: TimeInterval,
        pollInterval: TimeInterval,
        expecting: String,
        predicate: (PlaybackObservation) -> Bool
    ) throws -> PlaybackObservation {
        let deadline = Date().addingTimeInterval(timeout)
        var latest = observePlayback(window: window)
        while Date() < deadline {
            latest = observePlayback(window: window)
            if predicate(latest) { return latest }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        throw PlaybackWaitError.timedOut(expected: expecting, timeout: timeout, observed: latest)
    }
}

public enum PlaybackWaitError: Error, CustomStringConvertible {
    case timedOut(expected: String, timeout: TimeInterval, observed: PlaybackObservation)

    public var description: String {
        switch self {
        case let .timedOut(expected, timeout, observed):
            """
            Timed out after \(String(format: "%.1f", timeout))s waiting for \(expected). \
            Last seen: \(observed.summary)
            """
        }
    }
}
