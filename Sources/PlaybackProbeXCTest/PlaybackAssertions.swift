import Foundation
import PlaybackProbeSchema
import PlaybackProbeTestSupport
import XCTest

/// Asserts that playback stops, waiting for the stop to become observable.
///
/// Prefer this over sleeping a guessed amount and asserting: the probe cannot
/// report a state change before its next sampling tick, so how long "already
/// stopped" takes to appear depends on the sampling interval and on the
/// machine. This waits for the evidence instead of assuming it has arrived.
///
/// Passes only once an entire `window` of samples agrees, so a player that
/// pauses for a single tick and resumes does not slip through.
public func XCTAssertPlaybackStops(
    _ log: ProbeEventLog,
    timeout: TimeInterval = ProbeEventLog.defaultTimeout,
    window: TimeInterval = ProbeEventLog.defaultWindow,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        try log.waitUntilPlaybackStopped(timeout: timeout, window: window)
    } catch {
        XCTFail(failureMessage(message(), error), file: file, line: line)
    }
}

/// Asserts that playback starts, waiting for it to become observable.
public func XCTAssertPlaybackStarts(
    _ log: ProbeEventLog,
    timeout: TimeInterval = ProbeEventLog.defaultTimeout,
    window: TimeInterval = ProbeEventLog.defaultWindow,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        try log.waitUntilPlaybackStarted(timeout: timeout, window: window)
    } catch {
        XCTFail(failureMessage(message(), error), file: file, line: line)
    }
}

/// Asserts that playback keeps running for `window`.
///
/// Deliberately not a wait. "Still playing" is a claim about a stretch of time,
/// and waiting would return the moment it saw one playing sample, which is the
/// weaker claim.
public func XCTAssertPlaybackContinues(
    _ log: ProbeEventLog,
    for window: TimeInterval = ProbeEventLog.defaultWindow,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let observation = log.observePlayback(for: window)
    if !observation.isPlaying {
        XCTFail(
            failureMessage(message(), "Expected playback to continue. Observed: \(observation.summary)"),
            file: file,
            line: line
        )
    }
}

private func failureMessage(_ message: String, _ detail: Any) -> String {
    message.isEmpty ? "\(detail)" : "\(message) - \(detail)"
}
