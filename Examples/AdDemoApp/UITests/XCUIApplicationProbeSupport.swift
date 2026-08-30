import Foundation
import PlaybackProbeTestSupport
import XCTest

extension XCUIApplication {
    /// An application configured to load the probe and record to `logURL`.
    static func withProbe(logURL: URL, sampleInterval: TimeInterval = 0.2) throws -> XCUIApplication {
        let application = XCUIApplication()
        let environment = try ProbeLaunchEnvironment.make(logURL: logURL, sampleInterval: sampleInterval)
        application.launchEnvironment.merge(environment) { _, injected in injected }
        return application
    }
}
