import PlaybackProbe
import XCTest

/// Covers the injection path: the library is loaded by dyld, its constructor
/// runs before `main()`, and it finds a player the test has no reference to.
final class ProbeInjectionTests: XCTestCase {
    private var logURL: URL!
    private var log: ProbeEventLog!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        logURL = try ProbeInjection.makeLogURL()
        log = ProbeEventLog(url: logURL)
    }

    func testProbeStartsFromLoadTimeConstructor() throws {
        let application = try ProbeInjection.makeApplication(logURL: logURL)
        application.launch()

        let events = log.waitForEvents(description: "the probe start event") {
            !$0.events(of: .probeStarted).isEmpty
        }

        let start = try XCTUnwrap(events.events(of: .probeStarted).first)
        XCTAssertEqual(
            start.bootstrappedByConstructor,
            true,
            "The probe should have been started by its load-time constructor, not by hand"
        )
    }

    func testProbeAttachesToPlayerHiddenInsideSDK() throws {
        let application = try ProbeInjection.makeApplication(logURL: logURL)
        application.launch()

        application.buttons[DemoIdentifier.playButton].tap()

        let events = log.waitForEvents(description: "a player to be attached") {
            !$0.events(of: .playerAttached).isEmpty
        }

        let attached = try XCTUnwrap(events.events(of: .playerAttached).first)
        XCTAssertEqual(attached.playerID, "player-1")
    }

    func testProbeStaysInertWhenNotEnabled() throws {
        // The guard that keeps an accidentally linked probe from doing anything
        // in a production build.
        let application = XCUIApplication()
        application.launchEnvironment[ProbeInjection.insertLibrariesKey] = try ProbeInjection
            .probeLibraryURL().path
        application.launchEnvironment[ProbeConfiguration.logPathKey] = logURL.path
        // PLAYBACK_PROBE_ENABLED deliberately omitted.
        application.launch()

        application.buttons[DemoIdentifier.playButton].tap()
        Thread.sleep(forTimeInterval: 2)

        XCTAssertTrue(log.events().isEmpty, "The probe wrote events despite not being enabled")
    }
}
