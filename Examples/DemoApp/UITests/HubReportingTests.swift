import Foundation
import PlaybackProbeSchema
import PlaybackProbeTestSupport
import XCTest

/// Covers the path from the probe inside the application, over the network, to
/// the hub on the host.
///
/// Skipped unless a hub is running and its URL was passed in. Run these with
/// `Scripts/run-demo-tests.sh`, which starts one.
final class HubReportingTests: XCTestCase {
    private var client: PlaybackStatusClient!
    private var application: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        // Skipped, not failed: a plain `xcodebuild test` runs without a hub,
        // and these are the only tests that need one.
        let configured = PlaybackStatusClient.fromEnvironment()
        try XCTSkipIf(configured == nil, "No hub was configured for this run")
        client = configured
        try XCTSkipUnless(isHubReachable(), "No hub is listening at \(client.baseURL)")

        // Otherwise the previous test's playback is still inside the window.
        try client.reset()

        application = try XCUIApplication.withProbe(
            logURL: ProbeLogLocation.makeSharedLogURL(),
            hubURL: client.baseURL
        )
        application.launch()
    }

    func testHubSeesPlaybackStart() throws {
        application.buttons[DemoIdentifier.playButton].tap()

        let status = try client.waitUntilPlaying()
        XCTAssertEqual(status.playerState, .playing)
        XCTAssertEqual(status.currentTimeAdvancing, true)
        // An oracle that is not running must have no opinion rather than
        // report silence, which would look like a stopped player. Whether the
        // audio oracle is running depends on how the hub was started.
        if try !client.health().isAudioTapAttached {
            XCTAssertNil(status.audioActive)
        }
        XCTAssertNil(status.videoAdvancing, "The video oracle is not implemented yet")
        XCTAssertTrue(status.consistent)
    }

    func testHubSeesPlaybackStop() throws {
        application.buttons[DemoIdentifier.playButton].tap()
        try client.waitUntilPlaying()

        application.buttons[DemoIdentifier.presentCorrectOverlayButton].tap()

        let status = try client.waitUntilStopped()
        XCTAssertEqual(status.playerState, .paused)
        XCTAssertEqual(status.currentTimeAdvancing, false)
    }

    func testHubSeesTheOverlayThatForgetsToPause() throws {
        application.buttons[DemoIdentifier.playButton].tap()
        try client.waitUntilPlaying()

        application.buttons[DemoIdentifier.presentLeakyOverlayButton].tap()
        XCTAssertTrue(application.buttons[DemoIdentifier.dismissOverlayButton].waitForExistence(timeout: 5))

        Thread.sleep(forTimeInterval: 1)
        let status = try client.status()
        XCTAssertEqual(status.isPlaying, true, "The leaky overlay is expected to leave the player running")
    }

    override func tearDown() {
        // Otherwise the previous test's application keeps sampling into the
        // next one's window.
        application?.terminate()
        super.tearDown()
    }

    private func isHubReachable() -> Bool {
        (try? client.status()) != nil
    }
}
