import Foundation
import os
import PlaybackProbeSchema

/// Forwards observations from inside the application to the hub.
///
/// Reporting must never slow the application down or change its timing, since
/// that would alter the very playback being measured. So sending is
/// fire-and-forget, and events pile up rather than block while a request is in
/// flight.
final class HubReporter: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.github.ukitaka.PlaybackProbe", category: "hub")
    private let endpoint: URL
    private let session: URLSession
    private let encoder = JSONEncoder()

    private let lock = NSLock()
    private var pending: [ProbeEvent] = []
    private var isSending = false

    /// Bounds memory if the hub is unreachable for a long test. Dropping the
    /// oldest keeps the recent window, which is all any verdict looks at.
    private let backlogLimit = 512

    init(hubURL: URL, session: URLSession = .shared) {
        endpoint = hubURL.appending(path: "player-state")
        self.session = session
    }

    func send(_ event: ProbeEvent) {
        lock.lock()
        pending.append(event)
        if pending.count > backlogLimit {
            pending.removeFirst(pending.count - backlogLimit)
        }
        lock.unlock()
        flush()
    }

    /// Sends everything queued, as one batch.
    ///
    /// Only one request is ever in flight. Under load this coalesces a burst of
    /// samples into a single post instead of opening a connection per sample.
    private func flush() {
        lock.lock()
        guard !isSending, !pending.isEmpty else {
            lock.unlock()
            return
        }
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        isSending = true
        lock.unlock()

        guard let body = try? encoder.encode(batch) else {
            logger.error("Could not encode a batch of \(batch.count) events")
            finishSending()
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        session.dataTask(with: request) { [weak self] _, _, error in
            if let error {
                self?.logger.error("Could not reach the hub: \(error, privacy: .public)")
            }
            self?.finishSending()
        }.resume()
    }

    private func finishSending() {
        lock.lock()
        isSending = false
        let hasMore = !pending.isEmpty
        lock.unlock()
        if hasMore { flush() }
    }
}
