import Foundation
import PlaybackProbe
import XCTest

/// Locates the built probe library and configures an application to load it.
enum ProbeInjection {
    /// Environment variable dyld reads to load extra libraries into a process.
    /// Honoured on the simulator only; a device rejects libraries whose Team ID
    /// does not match the host application.
    static let insertLibrariesKey = "DYLD_INSERT_LIBRARIES"

    /// Returns the path of the probe library to inject.
    ///
    /// The test bundle links PlaybackProbe, so the library is already loaded
    /// into this process and can be located by asking for the bundle that
    /// contains one of its classes. That is exact, unlike guessing at build
    /// product layout, which differs between a bare `.dylib` product and the
    /// `PackageFrameworks/` framework Xcode's SwiftPM integration produces.
    static func probeLibraryURL() throws -> URL {
        guard let url = Bundle(for: PlaybackProbe.self).executableURL else {
            throw ProbeInjectionError.libraryNotLoaded
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProbeInjectionError.libraryMissing(path: url.path)
        }
        return url
    }

    /// Creates a log file both processes can reach.
    ///
    /// The application and the test runner have separate containers, so the log
    /// goes in the simulator device's shared data directory instead.
    static func makeLogURL() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        let root = environment["SIMULATOR_SHARED_RESOURCES_DIRECTORY"] ?? NSTemporaryDirectory()
        let directory = URL(fileURLWithPath: root).appending(path: "PlaybackProbeLogs")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "\(UUID().uuidString).jsonl")
    }

    /// Builds an application configured to load the probe and write to `logURL`.
    static func makeApplication(
        logURL: URL,
        sampleIntervalMilliseconds: Int = 200
    ) throws -> XCUIApplication {
        let application = XCUIApplication()
        application.launchEnvironment[insertLibrariesKey] = try probeLibraryURL().path
        application.launchEnvironment[ProbeConfiguration.enabledKey] = "1"
        application.launchEnvironment[ProbeConfiguration.logPathKey] = logURL.path
        application
            .launchEnvironment[ProbeConfiguration.sampleIntervalKey] = String(sampleIntervalMilliseconds)
        return application
    }
}

enum ProbeInjectionError: Error, CustomStringConvertible {
    case libraryNotLoaded
    case libraryMissing(path: String)

    var description: String {
        switch self {
        case .libraryNotLoaded:
            "PlaybackProbe is not loaded in the test runner; check that the UI test target links it."
        case let .libraryMissing(path):
            "PlaybackProbe reports its executable at \(path), but no file exists there."
        }
    }
}
