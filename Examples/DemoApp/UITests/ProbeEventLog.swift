import Foundation
import PlaybackProbe
import XCTest

/// Reads the JSON Lines log the probe writes from inside the application.
struct ProbeEventLog {
    let url: URL

    /// Every event written so far. Returns an empty array until the
    /// application creates the file.
    func events() -> [ProbeEvent] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return contents
            .split(separator: "\n")
            .compactMap { line in
                // A partially flushed final line is expected while the
                // application is still running; skip it rather than fail.
                try? decoder.decode(ProbeEvent.self, from: Data(line.utf8))
            }
    }

    /// Polls until `predicate` holds, and returns the events that satisfied it.
    @discardableResult
    func waitForEvents(
        timeout: TimeInterval = 10,
        pollInterval: TimeInterval = 0.1,
        description: String,
        until predicate: ([ProbeEvent]) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [ProbeEvent] {
        let deadline = Date().addingTimeInterval(timeout)
        var latest = events()
        while Date() < deadline {
            latest = events()
            if predicate(latest) { return latest }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        XCTFail(
            "Timed out waiting for \(description). Events so far: \(latest.count)",
            file: file,
            line: line
        )
        return latest
    }
}

extension [ProbeEvent] {
    func events(of kind: ProbeEvent.Kind) -> [ProbeEvent] {
        filter { $0.kind == kind }
    }

    /// Samples recorded at or after `timestamp`, in the order they were written.
    func samples(since timestamp: TimeInterval) -> [ProbeEvent] {
        events(of: .sample).filter { $0.timestamp >= timestamp }
    }

    /// Whether the playback position moved across these samples.
    ///
    /// The threshold absorbs the rounding in `CMTime.seconds` and the jitter
    /// between the sampling timer and the player's own clock.
    func isPlaybackPositionAdvancing(threshold: Double = 0.05) -> Bool {
        let positions = events(of: .sample).compactMap(\.currentTime)
        guard let first = positions.first, let last = positions.last else { return false }
        return last - first > threshold
    }
}
