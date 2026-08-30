import PlaybackProbeSchema
import PlaybackProbeTestSupport
import PlaybackProbeXCTest
import XCTest

/// Covers the state and time oracles: what the probe reports while the player
/// is running, and what it reports once something is supposed to have stopped
/// it.
///
/// None of these tests sleep before asserting. The assertions wait for the
/// evidence themselves, which is the point of the API.
final class PlaybackOracleTests: XCTestCase {
    private var application: XCUIApplication!
    private var log: ProbeEventLog!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        let logURL = try ProbeLogLocation.makeSharedLogURL()
        log = ProbeEventLog(url: logURL)
        application = try XCUIApplication.withProbe(logURL: logURL)
        application.launch()
    }

    func testOraclesReportPlaybackWhilePlaying() {
        application.buttons[DemoIdentifier.playButton].tap()

        XCTAssertPlaybackStarts(log)
    }

    func testPauseStopsPlayback() {
        startPlayback()

        application.buttons[DemoIdentifier.pauseButton].tap()

        XCTAssertPlaybackStops(log)
    }

    func testOverlayThatPausesStopsPlayback() {
        startPlayback()

        application.buttons[DemoIdentifier.presentCorrectOverlayButton].tap()

        XCTAssertPlaybackStops(log, "Playback continued behind the overlay")
    }

    /// The bug the toolkit exists to catch. The overlay hides the video, so a
    /// screenshot cannot tell this apart from the correct case.
    func testOverlayThatForgetsToPauseIsDetected() {
        startPlayback()

        application.buttons[DemoIdentifier.presentLeakyOverlayButton].tap()
        XCTAssertTrue(application.buttons[DemoIdentifier.dismissOverlayButton].waitForExistence(timeout: 5))

        XCTAssertPlaybackContinues(log, "The demo's leaky overlay is expected to leave the player running")
    }

    /// Proves the stop assertion is not vacuous: pointed at the leaky overlay
    /// it must fail. Without this, an assertion that never fails would look
    /// exactly like a passing suite.
    func testStopAssertionFailsWhenPlaybackLeaks() {
        startPlayback()

        application.buttons[DemoIdentifier.presentLeakyOverlayButton].tap()

        XCTExpectFailure("The leaky overlay leaves the player running, so the stop assertion must fail") {
            XCTAssertPlaybackStops(log, timeout: 2)
        }
    }

    private func startPlayback() {
        application.buttons[DemoIdentifier.playButton].tap()
        XCTAssertPlaybackStarts(log)
    }
}
