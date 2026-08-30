import Foundation
import PlaybackProbeSchema
import PlaybackProbeTestSupport
import Testing

@Suite("Reading the probe's event log")
struct ProbeEventLogTests {
    @Test("returns nothing when the application has not created the file yet")
    func missingFile() {
        let log = ProbeEventLog(url: URL(fileURLWithPath: "/nonexistent/probe.jsonl"))
        #expect(log.events().isEmpty)
    }

    @Test("reads events written as JSON Lines")
    func readsLines() throws {
        let log = try makeLog(contents: """
        {"kind":"probeStarted","timestamp":1,"bootstrappedByConstructor":true}
        {"kind":"playerAttached","timestamp":2,"playerID":"player-1"}
        {"kind":"sample","timestamp":3,"playerID":"player-1","playerState":"playing","currentTime":0.5}

        """)

        let events = log.events()
        #expect(events.count == 3)
        #expect(events.first?.bootstrappedByConstructor == true)
        #expect(events.last?.playerState == .playing)
    }

    /// The probe appends while the application runs, so the reader can catch
    /// the file mid-write. A half-flushed final line must not lose the events
    /// before it.
    @Test("skips a partially written final line")
    func partialLine() throws {
        let log = try makeLog(contents: """
        {"kind":"playerAttached","timestamp":2,"playerID":"player-1"}
        {"kind":"sample","timesta
        """)

        let events = log.events()
        #expect(events.count == 1)
        #expect(events.first?.kind == .playerAttached)
    }

    @Test("filters samples by the time they were taken")
    func samplesSince() throws {
        let log = try makeLog(contents: """
        {"kind":"sample","timestamp":10,"currentTime":1}
        {"kind":"sample","timestamp":20,"currentTime":2}
        {"kind":"sample","timestamp":30,"currentTime":3}

        """)

        #expect(log.events().samples(since: 20).count == 2)
    }

    private func makeLog(contents: String) throws -> ProbeEventLog {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "\(UUID().uuidString).jsonl")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return ProbeEventLog(url: url)
    }
}
