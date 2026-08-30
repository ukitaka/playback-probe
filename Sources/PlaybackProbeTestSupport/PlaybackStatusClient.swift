import Foundation
import PlaybackProbeSchema

/// Asks the hub what every oracle currently reports.
///
/// The hub runs on the host, not in the simulator: an iOS process cannot hold
/// a listening socket reliably while it is in the background, which is exactly
/// where the XCUITest runner sits whenever the application under test is in
/// front. Simulator processes share the host's loopback, so the application and
/// the runner both reach it at `127.0.0.1`.
///
/// Calls are synchronous because a UI test reads as a sequence of steps and has
/// nothing else to do while waiting.
public struct PlaybackStatusClient: Sendable {
    public let baseURL: URL
    public var requestTimeout: TimeInterval

    public init(baseURL: URL, requestTimeout: TimeInterval = 5) {
        self.baseURL = baseURL
        self.requestTimeout = requestTimeout
    }

    /// A client for the hub a harness named in the environment, or `nil` when
    /// no hub was configured for this run.
    ///
    /// With `xcodebuild`, pass it through as
    /// `TEST_RUNNER_PLAYBACK_PROBE_HUB_URL`; the prefix is stripped before the
    /// runner sees it.
    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> PlaybackStatusClient? {
        guard let raw = environment[ProbeConfiguration.hubURLKey], let url = URL(string: raw) else {
            return nil
        }
        return PlaybackStatusClient(baseURL: url)
    }

    /// What the oracles say about the last `window` seconds.
    public func status(window: TimeInterval = 1.0) throws -> PlaybackStatus {
        let data = try send(
            "playback-status",
            method: "GET",
            query: ["window": String(Int(window * 1000))]
        )
        return try JSONDecoder().decode(PlaybackStatus.self, from: data)
    }

    /// What the hub reports about itself.
    ///
    /// `isAudioTapAttached` is the honest way to ask whether the audio oracle
    /// is available. The level history cannot answer it: an idle output device
    /// does not run its callback, so a working tap that has heard nothing yet
    /// looks the same as no tap at all.
    public func health() throws -> HubHealth {
        try JSONDecoder().decode(HubHealth.self, from: send("health", method: "GET"))
    }

    /// Clears every oracle's history. Call between tests so that one test's
    /// playback cannot satisfy the next test's assertion.
    public func reset() throws {
        _ = try send("reset", method: "POST")
    }

    /// Waits until every oracle agrees that playback is running.
    ///
    /// Requires the time oracle to have decided, not just the player's own
    /// report. `PlaybackStatus.isPlaying` alone is satisfied by a single
    /// sample, which can say what the player intends but cannot yet show that
    /// the position moved.
    @discardableResult
    public func waitUntilPlaying(
        timeout: TimeInterval = 10,
        window: TimeInterval = 1.0
    ) throws -> PlaybackStatus {
        try waitForStatus(timeout: timeout, window: window) {
            $0.currentTimeAdvancing == true && $0.isPlaying == true
        }
    }

    /// Waits until every oracle agrees that playback has stopped.
    @discardableResult
    public func waitUntilStopped(
        timeout: TimeInterval = 10,
        window: TimeInterval = 1.0
    ) throws -> PlaybackStatus {
        try waitForStatus(timeout: timeout, window: window) {
            $0.currentTimeAdvancing == false && $0.isPlaying == false
        }
    }

    /// Polls until the status satisfies `predicate`.
    @discardableResult
    public func waitForStatus(
        timeout: TimeInterval = 10,
        window: TimeInterval = 1.0,
        pollInterval: TimeInterval = 0.05,
        until predicate: (PlaybackStatus) -> Bool
    ) throws -> PlaybackStatus {
        let deadline = Date().addingTimeInterval(timeout)
        var latest = try status(window: window)
        while Date() < deadline {
            latest = try status(window: window)
            if predicate(latest) { return latest }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        throw PlaybackStatusClientError.timedOut(timeout: timeout, last: latest)
    }

    private func send(_ path: String, method: String, query: [String: String] = [:]) throws -> Data {
        // Built through URLComponents rather than by appending a string:
        // `URL.appending(path:)` percent-encodes the "?", which turns a query
        // into part of the path and quietly produces a 404.
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw PlaybackStatusClientError.unreachable(baseURL, underlying: nil)
        }
        components.path = (components.path.hasSuffix("/") ? components.path : components.path + "/") + path
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw PlaybackStatusClientError.unreachable(baseURL, underlying: nil)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = requestTimeout

        let result = LockedResult()
        let finished = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            result.set(data: data, response: response as? HTTPURLResponse, error: error)
            finished.signal()
        }.resume()

        guard finished.wait(timeout: .now() + requestTimeout + 1) == .success else {
            throw PlaybackStatusClientError.unreachable(url, underlying: nil)
        }
        if let error = result.error {
            throw PlaybackStatusClientError.unreachable(url, underlying: error)
        }
        guard let data = result.data, let response = result.response else {
            throw PlaybackStatusClientError.unreachable(url, underlying: nil)
        }
        // Checked explicitly: every field of PlaybackStatus is optional, so an
        // error body would otherwise decode into a status where no oracle has
        // an opinion, and a routing mistake would look like a quiet player.
        guard (200 ..< 300).contains(response.statusCode) else {
            throw PlaybackStatusClientError.badResponse(
                url: url,
                status: response.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
        return data
    }
}

/// What the hub reports about itself.
public struct HubHealth: Decodable, Sendable {
    public var isReachable: Bool
    public var isAudioTapAttached: Bool

    private enum CodingKeys: String, CodingKey {
        case isReachable = "ok"
        case isAudioTapAttached = "audioTapAttached"
    }
}

public enum PlaybackStatusClientError: Error, CustomStringConvertible {
    case unreachable(URL, underlying: (any Error)?)
    case badResponse(url: URL, status: Int, body: String)
    case timedOut(timeout: TimeInterval, last: PlaybackStatus)

    public var description: String {
        switch self {
        case let .unreachable(url, underlying):
            """
            Could not reach the hub at \(url). Start it with `swift run playback-probe-hub`\
            \(underlying.map { ". Underlying error: \($0)" } ?? ".")
            """
        case let .badResponse(url, status, body):
            "The hub answered \(status) for \(url): \(body)"
        case let .timedOut(timeout, last):
            "Timed out after \(String(format: "%.1f", timeout))s. Last status: \(last)"
        }
    }
}

/// Carries the callback's result back to the waiting caller.
private final class LockedResult: @unchecked Sendable {
    private let lock = NSLock()
    private var storedData: Data?
    private var storedError: (any Error)?

    private var storedResponse: HTTPURLResponse?

    func set(data: Data?, response: HTTPURLResponse?, error: (any Error)?) {
        lock.lock()
        storedData = data
        storedResponse = response
        storedError = error
        lock.unlock()
    }

    var data: Data? { lock.lock(); defer { lock.unlock() }; return storedData }
    var response: HTTPURLResponse? { lock.lock(); defer { lock.unlock() }; return storedResponse }
    var error: (any Error)? { lock.lock(); defer { lock.unlock() }; return storedError }
}
