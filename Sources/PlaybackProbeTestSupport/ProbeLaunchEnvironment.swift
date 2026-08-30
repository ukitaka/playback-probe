import Foundation
import PlaybackProbeSchema

/// Builds the launch environment that turns the probe on inside an application
/// under test.
///
/// Deliberately free of XCTest: the caller applies the dictionary to whatever
/// launches the application, which keeps this usable outside XCUITest.
public enum ProbeLaunchEnvironment {
    /// - Parameters:
    ///   - logURL: Where the probe should append its observations. Use
    ///     ``ProbeLogLocation/makeSharedLogURL()`` unless you have a path both
    ///     processes are known to reach.
    ///   - sampleInterval: Sampling period for the state and time oracles.
    ///   - hubURL: Base URL of a hub to report to as well, such as
    ///     `http://127.0.0.1:8642`. Needed only when host-side oracles are in
    ///     play; the state and time oracles work from the log alone.
    ///   - libraryURL: The probe to inject. Defaults to the copy loaded in this
    ///     process.
    public static func make(
        logURL: URL,
        sampleInterval: TimeInterval = 0.2,
        hubURL: URL? = nil,
        libraryURL: URL? = nil
    ) throws -> [String: String] {
        let library = try libraryURL ?? ProbeLibrary.url()
        var environment = [
            ProbeLibrary.insertLibrariesKey: library.path,
            ProbeConfiguration.enabledKey: "1",
            ProbeConfiguration.logPathKey: logURL.path,
            ProbeConfiguration.sampleIntervalKey: String(Int(sampleInterval * 1000)),
        ]
        if let hubURL {
            environment[ProbeConfiguration.hubURLKey] = hubURL.absoluteString
        }
        return environment
    }
}

/// Chooses a log path that both the application under test and the test runner
/// can open.
public enum ProbeLogLocation {
    /// A fresh log file in the simulator device's shared data directory.
    ///
    /// The application and the test runner have separate containers, so a path
    /// derived from either one's sandbox is not readable by the other.
    public static func makeSharedLogURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        let root = environment["SIMULATOR_SHARED_RESOURCES_DIRECTORY"] ?? NSTemporaryDirectory()
        let directory = URL(fileURLWithPath: root).appending(path: "PlaybackProbeLogs")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "\(UUID().uuidString).jsonl")
    }
}
