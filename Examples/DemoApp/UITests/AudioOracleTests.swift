import Foundation
import PlaybackProbeSchema
import PlaybackProbeTestSupport
import XCTest

/// Covers the audio oracle: what the Mac actually plays, as opposed to what the
/// player says about itself.
///
/// Skipped unless a hub with a running tap is reachable. Run these with
/// `PLAYBACK_PROBE_AUDIO=1 Scripts/run-demo-tests.sh`, and note that the
/// simulator only produces sound while Simulator.app is running.
final class AudioOracleTests: XCTestCase {
    private var client: PlaybackStatusClient!
    private var application: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        let configured = PlaybackStatusClient.fromEnvironment()
        try XCTSkipIf(configured == nil, "No hub was configured for this run")
        client = configured
        try client.reset()

        try XCTSkipUnless(
            client.health().isAudioTapAttached,
            "The hub has no audio tap attached"
        )

        application = try XCUIApplication.withProbe(
            logURL: ProbeLogLocation.makeSharedLogURL(),
            hubURL: client.baseURL
        )
        application.launch()
    }

    override func tearDown() {
        application?.terminate()
        super.tearDown()
    }

    func testSoundReachesTheOutputWhilePlaying() throws {
        application.buttons[DemoIdentifier.playButton].tap()

        let status = try client.waitForStatus(timeout: 15) { $0.audioActive == true }
        XCTAssertEqual(status.playerState, .playing)
        XCTAssertTrue(status.consistent)
    }

    func testSoundStopsWithTheOverlayThatPauses() throws {
        application.buttons[DemoIdentifier.playButton].tap()
        try client.waitForStatus(timeout: 15) { $0.audioActive == true }

        application.buttons[DemoIdentifier.presentCorrectOverlayButton].tap()

        // Sound already buffered keeps arriving for a moment after a pause, so
        // this waits for silence rather than asserting it immediately.
        let status = try client.waitForStatus(timeout: 15) { $0.audioActive == false }
        XCTAssertEqual(status.playerState, .paused)
        XCTAssertTrue(status.consistent, "Every oracle should agree that playback stopped")
    }

    /// The failure the audio oracle exists for. Here the player is honest, so
    /// all four agree; the value is that a player which lied about pausing
    /// would show up as an inconsistency rather than a pass.
    func testEveryOracleAgreesWhilePlaying() throws {
        application.buttons[DemoIdentifier.playButton].tap()

        let status = try client.waitForStatus(timeout: 15) {
            $0.audioActive == true && $0.currentTimeAdvancing == true
        }
        XCTAssertEqual(status.isPlaying, true)
        XCTAssertEqual(status.playerState, .playing)
    }
}
