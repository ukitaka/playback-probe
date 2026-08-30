import Foundation
import Network

/// A small HTTP server on the loopback interface that every oracle reports to
/// and the test reads from.
///
/// The probe runs inside the simulator, which shares loopback with the host, so
/// one address reaches all three parties: the injected probe, the host-side
/// audio tap and the test runner.
public final class PlaybackHub: @unchecked Sendable {
    /// Port the toolkit uses by default. Nothing well-known lives here.
    public static let defaultPort: UInt16 = 8642

    public let store: PlaybackStatusStore

    private let requestedPort: UInt16
    private let queue = DispatchQueue(label: "com.github.ukitaka.PlaybackProbe.hub")
    private let lock = NSLock()
    private var listener: NWListener?
    private var resolvedPort: UInt16?

    /// - Parameter port: Pass `0` to let the system choose, which is what tests
    ///   should do so that concurrent runs cannot collide.
    public init(store: PlaybackStatusStore = PlaybackStatusStore(), port: UInt16 = defaultPort) {
        self.store = store
        requestedPort = port
    }

    deinit {
        listener?.cancel()
    }

    /// The port actually being listened on, known only once started.
    public var port: UInt16? {
        lock.lock()
        defer { lock.unlock() }
        return resolvedPort
    }

    /// Starts listening and returns once the listener is ready, so that a
    /// caller can rely on `port` and on the endpoint accepting connections.
    public func start(timeout: TimeInterval = 5) throws {
        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true
        parameters.allowLocalEndpointReuse = true

        guard let port = NWEndpoint.Port(rawValue: requestedPort) else {
            throw PlaybackHubError.invalidPort(requestedPort)
        }
        let listener = try NWListener(using: parameters, on: port)

        let ready = DispatchSemaphore(value: 0)
        let failure = LockedBox<NWError?>(nil)

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready.signal()
            case let .failed(error):
                failure.value = error
                ready.signal()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        lock.lock()
        self.listener = listener
        lock.unlock()

        listener.start(queue: queue)

        guard ready.wait(timeout: .now() + timeout) == .success else {
            listener.cancel()
            throw PlaybackHubError.startTimedOut(timeout)
        }
        if let error = failure.value {
            listener.cancel()
            throw PlaybackHubError.listenerFailed(error)
        }

        lock.lock()
        resolvedPort = listener.port?.rawValue ?? requestedPort
        lock.unlock()
    }

    public func stop() {
        lock.lock()
        let listener = listener
        self.listener = nil
        resolvedPort = nil
        lock.unlock()
        listener?.cancel()
    }

    private func accept(_ connection: NWConnection) {
        let router = HubRouter(store: store)
        connection.start(queue: queue)
        receive(on: connection, accumulated: Data(), router: router)
    }

    /// Reads until a whole request has arrived, answers it and closes.
    ///
    /// One request per connection: this endpoint serves a handful of polls per
    /// test, and keep-alive would buy nothing for the complexity of tracking
    /// pipelined requests.
    private func receive(on connection: NWConnection, accumulated: Data, router: HubRouter) {
        connection
            .receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { chunk, _, isComplete, error in
                if error != nil {
                    connection.cancel()
                    return
                }

                var buffer = accumulated
                if let chunk { buffer.append(chunk) }

                do {
                    guard let request = try HTTPRequest.parse(buffer) else {
                        if isComplete {
                            connection.cancel()
                        } else {
                            self.receive(on: connection, accumulated: buffer, router: router)
                        }
                        return
                    }
                    self.send(router.respond(to: request), on: connection)
                } catch {
                    self.send(.error(400, "\(error)"), on: connection)
                }
            }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(
            content: response.serialised(),
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { [weak self] _ in
                guard let self else { return }
                // Backstop for a client that never closes, so connections
                // cannot pile up over a long test run.
                queue.asyncAfter(deadline: .now() + Self.lingerTimeout) { connection.cancel() }
                closeWhenPeerIsDone(connection)
            }
        )
    }

    /// Waits for the client to close before tearing the connection down.
    ///
    /// `cancel()` is abortive. Calling it as soon as the send completes resets
    /// the socket, and the client sees the response vanish rather than arrive:
    /// URLSession reports "the network connection was lost" even though the
    /// bytes were written. `.finalMessage` above sends the FIN; this waits for
    /// the peer's.
    private func closeWhenPeerIsDone(_ connection: NWConnection) {
        connection
            .receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] _, _, isComplete, error in
                if isComplete || error != nil {
                    connection.cancel()
                } else {
                    self?.closeWhenPeerIsDone(connection)
                }
            }
    }

    /// How long to wait for a client to close before forcing it.
    private static let lingerTimeout: TimeInterval = 5
}

public enum PlaybackHubError: Error, CustomStringConvertible {
    case invalidPort(UInt16)
    case startTimedOut(TimeInterval)
    case listenerFailed(NWError)

    public var description: String {
        switch self {
        case let .invalidPort(port):
            "\(port) is not a usable port."
        case let .startTimedOut(timeout):
            "The hub did not become ready within \(timeout)s."
        case let .listenerFailed(error):
            "The hub could not listen: \(error)."
        }
    }
}

/// A value that can be written from the listener's callback and read after it.
private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) { storage = value }

    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); storage = newValue; lock.unlock() }
    }
}
