import Foundation
import PlaybackProbeSchema

/// Reads the JSON Lines log the probe writes from inside the application under
/// test.
public struct ProbeEventLog: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Every event written so far. Empty until the application creates the file.
    public func events() -> [ProbeEvent] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return contents
            .split(separator: "\n")
            .compactMap { line in
                // The final line can be half-written while the application is
                // still running. Skip it rather than treat it as corruption.
                try? decoder.decode(ProbeEvent.self, from: Data(line.utf8))
            }
    }

    /// Polls until `predicate` holds, and returns the events that satisfied it.
    @discardableResult
    public func waitForEvents(
        timeout: TimeInterval = 10,
        pollInterval: TimeInterval = 0.1,
        until predicate: ([ProbeEvent]) -> Bool
    ) throws -> [ProbeEvent] {
        let deadline = Date().addingTimeInterval(timeout)
        var latest = events()
        while Date() < deadline {
            latest = events()
            if predicate(latest) { return latest }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        throw ProbeEventLogError.timedOut(timeout: timeout, eventsSeen: latest.count)
    }
}

public enum ProbeEventLogError: Error, CustomStringConvertible {
    case timedOut(timeout: TimeInterval, eventsSeen: Int)

    public var description: String {
        switch self {
        case let .timedOut(timeout, eventsSeen):
            "Timed out after \(timeout)s waiting on the probe log; \(eventsSeen) events were written."
        }
    }
}
