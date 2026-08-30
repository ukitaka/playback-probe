import Foundation
import PlaybackProbeHub
import PlaybackProbeSchema
import Testing

/// Exercises the hub over a real socket, because the parts that break in a
/// hand-written server are the ones a direct call to the router never touches:
/// framing, content length and connection handling.
@Suite("The hub over HTTP", .serialized)
struct PlaybackHubTests {
    @Test("answers a health check")
    func health() async throws {
        try await withHub { client in
            let response = try await client.get("/health")
            #expect(response.status == 200)
            #expect(response.json["ok"] as? Bool == true)
        }
    }

    @Test("aggregates player samples posted by the probe")
    func playerSamples() async throws {
        try await withHub { client in
            let now = Date().timeIntervalSince1970
            let events = [
                ProbeEvent(kind: .sample, timestamp: now - 0.4, playerState: .playing, currentTime: 1.0),
                ProbeEvent(kind: .sample, timestamp: now - 0.2, playerState: .playing, currentTime: 1.2),
                ProbeEvent(kind: .sample, timestamp: now, playerState: .playing, currentTime: 1.4),
            ]
            let posted = try await client.post("/player-state", body: JSONEncoder().encode(events))
            #expect(posted.json["accepted"] as? Int == 3)

            let status = try await client.getStatus("/playback-status?window=2000")
            #expect(status.playerState == .playing)
            #expect(status.currentTimeAdvancing == true)
            #expect(status.consistent)
        }
    }

    @Test("accepts a single event as well as a batch")
    func singleEvent() async throws {
        try await withHub { client in
            let event = ProbeEvent(kind: .playerAttached, playerID: "player-1")
            let posted = try await client.post("/player-state", body: JSONEncoder().encode(event))
            #expect(posted.json["accepted"] as? Int == 1)
        }
    }

    @Test("combines the audio oracle with the player oracles")
    func audioAndPlayer() async throws {
        try await withHub { client in
            let now = Date().timeIntervalSince1970
            let events = [
                ProbeEvent(kind: .sample, timestamp: now - 0.2, playerState: .paused, currentTime: 3.0),
                ProbeEvent(kind: .sample, timestamp: now, playerState: .paused, currentTime: 3.0),
            ]
            _ = try await client.post("/player-state", body: JSONEncoder().encode(events))
            _ = try await client.post("/audio-level", body: Data(#"{"rms":0.5}"#.utf8))

            // A paused player that is still audible: the disagreement is the
            // finding, not an error.
            let status = try await client.getStatus("/playback-status")
            #expect(status.playerState == .paused)
            #expect(status.currentTimeAdvancing == false)
            #expect(status.audioActive == true)
            #expect(!status.consistent)
        }
    }

    @Test("reports the latest level and whether the window had sound")
    func levels() async throws {
        try await withHub { client in
            let empty = try await client.get("/level")
            #expect(empty.json["rms"] is NSNull || empty.json["rms"] == nil)

            _ = try await client.post("/audio-level", body: Data(#"{"rms":0.25}"#.utf8))

            let level = try await client.get("/level")
            #expect((level.json["rms"] as? Double).map { abs($0 - 0.25) < 0.0001 } == true)

            let active = try await client.get("/audio-active?window=1500")
            #expect(active.json["audioActive"] as? Bool == true)
            #expect(active.json["window"] as? Double == 1.5)
        }
    }

    @Test("clears everything on reset")
    func reset() async throws {
        try await withHub { client in
            _ = try await client.post("/audio-level", body: Data(#"{"rms":0.5}"#.utf8))
            _ = try await client.post("/reset", body: Data())

            let status = try await client.getStatus("/playback-status")
            #expect(status.audioActive == nil)
            #expect(status.playerState == nil)
        }
    }

    @Test("rejects a body it cannot read")
    func badBody() async throws {
        try await withHub { client in
            let response = try await client.post("/player-state", body: Data("not json".utf8))
            #expect(response.status == 400)
        }
    }

    @Test("distinguishes an unknown path from a wrong method")
    func routing() async throws {
        try await withHub { client in
            let unknownPath = try await client.get("/nope")
            #expect(unknownPath.status == 404)
            let wrongMethod = try await client.get("/reset")
            #expect(wrongMethod.status == 405)
        }
    }

    private func withHub(_ body: (HubClient) async throws -> Void) async throws {
        let hub = PlaybackHub(port: 0)
        try hub.start()
        defer { hub.stop() }
        let port = try #require(hub.port)
        try await body(HubClient(port: port))
    }
}

private struct HubClient {
    let port: UInt16

    struct Response {
        var status: Int
        var body: Data
        var json: [String: Any] {
            (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        }
    }

    func get(_ path: String) async throws -> Response {
        try await send(path, method: "GET", body: nil)
    }

    func post(_ path: String, body: Data) async throws -> Response {
        try await send(path, method: "POST", body: body)
    }

    func getStatus(_ path: String) async throws -> PlaybackStatus {
        let response = try await get(path)
        return try JSONDecoder().decode(PlaybackStatus.self, from: response.body)
    }

    private func send(_ path: String, method: String, body: Data?) async throws -> Response {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = method
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return Response(status: status, body: data)
    }
}
