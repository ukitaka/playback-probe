import Foundation

/// A parsed HTTP request.
///
/// The hub speaks just enough HTTP to be reachable from `curl`, a Swift test
/// client and the probe inside the simulator. It is a local debugging endpoint,
/// not a web server: one request per connection, no keep-alive, no chunked
/// transfer.
struct HTTPRequest {
    var method: String
    var path: String
    var query: [String: String]
    var headers: [String: String]
    var body: Data

    /// Parses a request from `data`, or returns `nil` if more bytes are needed.
    ///
    /// Throws only when the bytes cannot be a valid request, so the caller can
    /// tell "wait for more" apart from "reject this".
    static func parse(_ data: Data) throws -> HTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: separator) else { return nil }

        guard let head = String(data: data[data.startIndex ..< headerEnd.lowerBound], encoding: .utf8) else {
            throw HTTPError.malformed("headers are not valid UTF-8")
        }

        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { throw HTTPError.malformed("empty request") }

        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { throw HTTPError.malformed("bad request line") }

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex ..< colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let target = String(requestLine[1])
        let (path, query) = Self.splitTarget(target)

        let expectedLength = headers["content-length"].flatMap(Int.init) ?? 0
        let bodyStart = headerEnd.upperBound
        let available = data.distance(from: bodyStart, to: data.endIndex)
        guard available >= expectedLength else { return nil }

        let bodyEnd = data.index(bodyStart, offsetBy: expectedLength)
        return HTTPRequest(
            method: String(requestLine[0]).uppercased(),
            path: path,
            query: query,
            headers: headers,
            body: Data(data[bodyStart ..< bodyEnd])
        )
    }

    private static func splitTarget(_ target: String) -> (path: String, query: [String: String]) {
        guard let mark = target.firstIndex(of: "?") else { return (target, [:]) }
        let path = String(target[target.startIndex ..< mark])
        var query: [String: String] = [:]
        for pair in target[target.index(after: mark)...].split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard let name = parts.first else { continue }
            let value = parts.count > 1 ? String(parts[1]) : ""
            query[String(name)] = value.removingPercentEncoding ?? value
        }
        return (path, query)
    }
}

struct HTTPResponse {
    var status: Int
    var body: Data
    var contentType = "application/json"

    static func json(_ body: Data, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, body: body)
    }

    static func error(_ status: Int, _ message: String) -> HTTPResponse {
        let escaped = message.replacingOccurrences(of: "\"", with: "'")
        return HTTPResponse(status: status, body: Data("{\"error\":\"\(escaped)\"}".utf8))
    }

    func serialised() -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reason(for: status))\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }

    private static func reason(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        default: "Unknown"
        }
    }
}

enum HTTPError: Error {
    case malformed(String)
}
