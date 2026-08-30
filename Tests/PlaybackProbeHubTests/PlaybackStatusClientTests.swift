import Foundation
import PlaybackProbeHub
import PlaybackProbeSchema
import PlaybackProbeTestSupport
import Testing

/// Runs the test-side client against a real hub.
///
/// Both halves were individually correct while the pair was broken: the client
/// built its query by string concatenation, which percent-encoded the "?" into
/// the path, and the hub answered 404. Since every field of `PlaybackStatus` is
/// optional, that error body decoded cleanly into a status where no oracle had
/// an opinion, which reads exactly like a stopped player.
@Suite("The status client against a live hub", .serialized)
struct PlaybackStatusClientTests {
    @Test("reads a status through a query parameter")
    func statusWithWindow() throws {
        try withHub { hub, client in
            let now = Date().timeIntervalSince1970
            hub.store.record([
                ProbeEvent(kind: .sample, timestamp: now - 0.4, playerState: .playing, currentTime: 1.0),
                ProbeEvent(kind: .sample, timestamp: now, playerState: .playing, currentTime: 1.4),
            ])

            let status = try client.status(window: 2)
            #expect(status.playerState == .playing)
            #expect(status.currentTimeAdvancing == true)
        }
    }

    /// The window has to actually reach the hub. If it silently did not, a
    /// stale sample outside the window would still be reported.
    @Test("honours the window it asks for")
    func windowIsApplied() throws {
        try withHub { hub, client in
            let now = Date().timeIntervalSince1970
            // Received long ago as well as timestamped long ago: the window
            // applies to when the hub saw the event.
            hub.store.record(
                ProbeEvent(kind: .sample, timestamp: now - 30, playerState: .playing, currentTime: 1),
                receivedAt: now - 30
            )

            let narrow = try client.status(window: 1)
            #expect(narrow.playerState == nil)
            let wide = try client.status(window: 60)
            #expect(wide.playerState == .playing)
        }
    }

    @Test("clears the hub on reset")
    func reset() throws {
        try withHub { hub, client in
            hub.store.record(ProbeEvent(kind: .sample, playerState: .playing, currentTime: 1))
            try client.reset()
            let status = try client.status(window: 60)
            #expect(status.playerState == nil)
        }
    }

    @Test("reports an error response instead of decoding it as an empty status")
    func rejectsErrorBodies() throws {
        try withHub { _, client in
            let client = PlaybackStatusClient(baseURL: client.baseURL.appending(path: "nonexistent"))
            #expect(throws: PlaybackStatusClientError.self) {
                try client.status()
            }
        }
    }

    @Test("reports an unreachable hub")
    func unreachable() throws {
        // Port 1 is reserved and nothing listens there.
        let client = PlaybackStatusClient(baseURL: URL(string: "http://127.0.0.1:1")!, requestTimeout: 1)
        #expect(throws: PlaybackStatusClientError.self) {
            try client.status()
        }
    }

    @Test("waits until the status satisfies a condition")
    func waiting() throws {
        try withHub { hub, client in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                hub.store.record([
                    ProbeEvent(kind: .sample, playerState: .playing, currentTime: 1.0),
                    ProbeEvent(kind: .sample, playerState: .playing, currentTime: 1.4),
                ])
            }
            let status = try client.waitForStatus(timeout: 5) { $0.isPlaying == true }
            #expect(status.playerState == .playing)
        }
    }

    private func withHub(_ body: (PlaybackHub, PlaybackStatusClient) throws -> Void) throws {
        let hub = PlaybackHub(port: 0)
        try hub.start()
        defer { hub.stop() }
        let port = try #require(hub.port)
        let client = try PlaybackStatusClient(baseURL: #require(URL(string: "http://127.0.0.1:\(port)")))
        try body(hub, client)
    }
}
