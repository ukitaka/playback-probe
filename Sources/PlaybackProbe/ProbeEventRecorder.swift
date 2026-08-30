import Foundation
import os
import PlaybackProbeSchema

/// Fans one observation out to every channel that is configured.
///
/// The file is the channel a UI test reads on its own: the test runner is a
/// separate process and cannot see the application's standard output, but it
/// can read a path both processes agree on. The hub is the channel that lets
/// the host-side oracles be combined with these, and is optional so that the
/// state and time oracles keep working with nothing else running.
final class ProbeEventRecorder: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.github.ukitaka.PlaybackProbe", category: "probe")
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private let lock = NSLock()
    private var fileHandle: FileHandle?
    private let reporter: HubReporter?

    init(logPath: String?, hubURL: URL? = nil) {
        reporter = hubURL.map { HubReporter(hubURL: $0) }
        guard let logPath else { return }
        fileHandle = Self.openLogFile(at: logPath, logger: logger)
    }

    deinit {
        try? fileHandle?.close()
    }

    func record(_ event: ProbeEvent) {
        logger.debug("\(String(describing: event), privacy: .public)")
        reporter?.send(event)

        guard let data = try? encoder.encode(event) else {
            logger.error("Failed to encode probe event of kind \(event.kind.rawValue, privacy: .public)")
            return
        }

        lock.lock()
        defer { lock.unlock() }
        guard let fileHandle else { return }
        do {
            try fileHandle.write(contentsOf: data + Data("\n".utf8))
        } catch {
            logger.error("Failed to append probe event: \(error, privacy: .public)")
        }
    }

    private static func openLogFile(at path: String, logger: Logger) -> FileHandle? {
        let url = URL(fileURLWithPath: path)
        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            logger.error("Failed to create probe log directory: \(error, privacy: .public)")
            return nil
        }

        if !fileManager.fileExists(atPath: path) {
            fileManager.createFile(atPath: path, contents: nil)
        }

        do {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            return handle
        } catch {
            logger.error("Failed to open probe log at \(path, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }
}
