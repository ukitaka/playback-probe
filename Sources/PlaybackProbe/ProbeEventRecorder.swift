import Foundation
import os

/// Serialises probe events to the unified log and, when configured, appends
/// them to a JSON Lines file.
///
/// The file is the channel a UI test reads: the test runner is a separate
/// process and cannot see the application's standard output, but it can read a
/// path both processes agree on.
final class ProbeEventRecorder: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.github.ukitaka.PlaybackProbe", category: "probe")
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private let lock = NSLock()
    private var fileHandle: FileHandle?

    init(logPath: String?) {
        guard let logPath else { return }
        fileHandle = Self.openLogFile(at: logPath, logger: logger)
    }

    deinit {
        try? fileHandle?.close()
    }

    func record(_ event: ProbeEvent) {
        logger.debug("\(String(describing: event), privacy: .public)")

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
