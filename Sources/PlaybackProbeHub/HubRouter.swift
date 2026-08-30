import Foundation
import PlaybackProbeSchema

/// Maps requests onto the store.
///
/// Deliberately a plain function of request to response, with no networking, so
/// that the behaviour of every endpoint can be tested without opening a socket.
struct HubRouter {
    let store: PlaybackStatusStore

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    func respond(to request: HTTPRequest) -> HTTPResponse {
        switch (request.method, request.path) {
        case ("GET", "/health"):
            encode(["ok": true])

        case ("GET", "/level"):
            level()

        case ("GET", "/audio-active"):
            audioActive(window: window(from: request))

        case ("POST", "/audio-level"):
            recordAudioLevel(request)

        case ("POST", "/player-state"):
            recordPlayerState(request)

        case ("GET", "/events"):
            recentEvents(limit: limit(from: request))

        case ("GET", "/playback-status"):
            playbackStatus(window: window(from: request))

        case ("POST", "/reset"):
            reset()

        case let (method, path) where Self.knownPaths.contains(path):
            .error(405, "\(method) is not allowed on \(path)")

        case let (_, path):
            .error(404, "no endpoint at \(path)")
        }
    }

    private static let knownPaths: Set<String> = [
        "/health", "/level", "/audio-active", "/audio-level", "/player-state", "/playback-status", "/reset",
        "/events",
    ]

    /// Windows are given in milliseconds, which is how a test thinks about
    /// them, and held internally in seconds.
    private func window(from request: HTTPRequest) -> TimeInterval {
        guard let raw = request.query["window"], let milliseconds = Double(raw), milliseconds > 0 else {
            return PlaybackStatusStore.defaultWindow
        }
        return milliseconds / 1000
    }

    private func limit(from request: HTTPRequest) -> Int {
        request.query["limit"].flatMap(Int.init).map { max(1, $0) } ?? 20
    }

    /// Raw events as received, newest last.
    ///
    /// Diagnostic: it answers "is anything arriving at all", which is the first
    /// question when a status comes back empty. `hubTime` is included so that a
    /// caller can compare the hub's clock against the timestamps the probe
    /// wrote, since the two run on different machines.
    private func recentEvents(limit: Int) -> HTTPResponse {
        struct Entry: Encodable {
            var receivedAt: TimeInterval
            var event: ProbeEvent
        }
        struct Payload: Encodable {
            var hubTime: TimeInterval
            var total: Int
            var events: [Entry]
        }
        let all = store.recordedEvents()
        let payload = Payload(
            hubTime: Date().timeIntervalSince1970,
            total: all.count,
            events: all.suffix(limit).map { Entry(receivedAt: $0.receivedAt, event: $0.event) }
        )
        guard let data = try? encoder.encode(payload) else {
            return .error(400, "could not encode the events")
        }
        return .json(data)
    }

    private func level() -> HTTPResponse {
        guard let latest = store.audioLevels.latest else {
            // No reading at all means the tap is not running. Reporting zero
            // would look exactly like silence.
            return encode(["rms": Double?.none, "timestamp": nil])
        }
        return encode(["rms": Double(latest.rms), "timestamp": latest.timestamp])
    }

    private func audioActive(window: TimeInterval) -> HTTPResponse {
        encode([
            "audioActive": store.audioLevels.isActive(within: window).map(AnyEncodableValue.bool),
            "window": AnyEncodableValue.number(window),
        ].compactMapValues { $0 })
    }

    private func recordAudioLevel(_ request: HTTPRequest) -> HTTPResponse {
        struct Payload: Decodable {
            var rms: Float
            var timestamp: TimeInterval?
        }
        do {
            let payload = try JSONDecoder().decode(Payload.self, from: request.body)
            store.audioLevels.append(
                AudioLevelSample(
                    timestamp: payload.timestamp ?? Date().timeIntervalSince1970,
                    rms: payload.rms
                )
            )
            return encode(["accepted": 1])
        } catch {
            return .error(400, "could not decode an audio level: \(error)")
        }
    }

    private func recordPlayerState(_ request: HTTPRequest) -> HTTPResponse {
        let decoder = JSONDecoder()
        // The probe batches when it can and sends a single event when it
        // cannot, so accept either shape.
        if let events = try? decoder.decode([ProbeEvent].self, from: request.body) {
            store.record(events)
            return encode(["accepted": events.count])
        }
        do {
            let event = try decoder.decode(ProbeEvent.self, from: request.body)
            store.record(event)
            return encode(["accepted": 1])
        } catch {
            return .error(400, "could not decode a probe event: \(error)")
        }
    }

    private func playbackStatus(window: TimeInterval) -> HTTPResponse {
        do {
            return try .json(encoder.encode(store.status(window: window)))
        } catch {
            return .error(400, "could not encode the status: \(error)")
        }
    }

    private func reset() -> HTTPResponse {
        store.reset()
        return encode(["ok": true])
    }

    private func encode(_ value: [String: some Encodable & Sendable]) -> HTTPResponse {
        guard let data = try? encoder.encode(value) else {
            return .error(400, "could not encode the response")
        }
        return .json(data)
    }
}

/// Minimal boxed value, so that a response can mix booleans and numbers without
/// declaring a type per endpoint.
enum AnyEncodableValue: Encodable, Sendable {
    case bool(Bool)
    case number(Double)

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        }
    }
}
