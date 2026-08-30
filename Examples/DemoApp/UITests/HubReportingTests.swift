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

        client = try XCTUnwrap(
            PlaybackStatusClient.fromEnvironment(),
            "No hub configured for this run"
        )
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
        // No audio oracle is running, so it must have no opinion rather than
        // report silence, which would look like a stopped player.
        XCTAssertNil(status.audioActive)
        XCTAssertNil(status.videoAdvancing)
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

    private func isHubReachable() -> Bool {
        (try? client.status()) != nil
    }
}
