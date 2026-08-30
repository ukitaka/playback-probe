import Foundation
import PlaybackProbeSchema
import PlaybackProbeTestSupport
import XCTest

/// Covers the video oracle: whether frames are still being rendered, as
/// opposed to what the player says or where its clock is.
final class VideoOracleTests: XCTestCase {
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

    override func tearDown() {
        application?.terminate()
        super.tearDown()
    }

    func testFramesAdvanceWhilePlaying() throws {
        application.buttons[DemoIdentifier.playButton].tap()

        let observation = try waitForFrames()
        XCTAssertTrue(observation.isVideoAdvancing, observation.summary)
    }

    func testFramesStopWithTheOverlayThatPauses() throws {
        application.buttons[DemoIdentifier.playButton].tap()
        try waitForFrames()

        application.buttons[DemoIdentifier.presentCorrectOverlayButton].tap()

        let observation = try log.waitUntilPlaybackStopped()
        XCTAssertTrue(observation.hasVideoOracle)
        XCTAssertFalse(observation.isVideoAdvancing, observation.summary)
    }

    /// The clearest statement of why this toolkit exists. The overlay covers
    /// the video, so a screenshot of this is indistinguishable from the
    /// correct case, and the video oracle still reports frames going by.
    func testFramesKeepAdvancingBehindTheLeakyOverlay() throws {
        application.buttons[DemoIdentifier.playButton].tap()
        try waitForFrames()

        application.buttons[DemoIdentifier.presentLeakyOverlayButton].tap()
        XCTAssertTrue(application.buttons[DemoIdentifier.dismissOverlayButton].waitForExistence(timeout: 5))

        let observation = log.observePlayback(for: 1.5)
        XCTAssertTrue(
            observation.isVideoAdvancing,
            "Frames should keep being rendered behind the overlay: \(observation.summary)"
        )
    }

    @discardableResult
    private func waitForFrames() throws -> PlaybackObservation {
        try log.waitUntilPlaybackStarted()
    }
}
