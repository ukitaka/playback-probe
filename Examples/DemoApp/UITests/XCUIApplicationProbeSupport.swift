import Foundation
import PlaybackProbeSchema
import PlaybackProbeTestSupport
import XCTest

extension XCUIApplication {
    /// An application configured to load the probe and record to `logURL`.
    static func withProbe(
        logURL: URL,
        sampleInterval: TimeInterval = 0.2,
        hubURL: URL? = nil
    ) throws -> XCUIApplication {
        let application = XCUIApplication()
        let environment = try ProbeLaunchEnvironment.make(
            logURL: logURL,
            sampleInterval: sampleInterval,
            hubURL: hubURL
        )
        application.launchEnvironment.merge(environment) { _, injected in injected }
        return application
    }

    /// An application that loads the probe without enabling it, to exercise the
    /// guard that keeps an accidentally linked probe inert.
    static func withProbeLoadedButDisabled(logURL: URL) throws -> XCUIApplication {
        let application = XCUIApplication()
        application.launchEnvironment[ProbeLibrary.insertLibrariesKey] = try ProbeLibrary.url().path
        application.launchEnvironment[ProbeConfiguration.logPathKey] = logURL.path
        return application
    }
}

extension ProbeEventLog {
    /// `waitForEvents` reported as a test failure at the caller's line rather
    /// than as a thrown error.
    @discardableResult
    func waitForEvents(
        describedAs description: String,
        timeout: TimeInterval = 10,
        until predicate: ([ProbeEvent]) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [ProbeEvent] {
        do {
            return try waitForEvents(timeout: timeout, until: predicate)
        } catch {
            XCTFail("Timed out waiting for \(description): \(error)", file: file, line: line)
            return events()
        }
    }
}
