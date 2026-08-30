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

        // Reachability first. Touching the hub before knowing it is there turns
        // "no hub, so skip" into a failure.
        let health = try? client.health()
        try XCTSkipIf(health == nil, "No hub is listening at \(client.baseURL)")
        // Asks whether the host provides an audio oracle, not whether a tap is
        // attached this instant: a host listening to one process rather than
        // the whole Mac attaches only once that process makes a sound.
        try XCTSkipUnless(health?.isAudioTapConfigured == true, "The hub has no audio tap")

        application = try XCUIApplication.withProbe(
            logURL: ProbeLogLocation.makeSharedLogURL(),
            hubURL: client.baseURL
        )
        application.launch()
        try client.reset()
    }

    override func tearDown() {
        application?.terminate()
        super.tearDown()
    }

    func testSoundReachesTheOutputWhilePlaying() throws {
        application.buttons[DemoIdentifier.playButton].tap()

        // Waits for the agreement it then asserts. Waiting on audio alone
        // returns during a transition, when another oracle has not caught up
        // and the oracles legitimately disagree for a tick.
        let status = try client.waitForStatus(timeout: 15) {
            $0.audioActive == true && $0.isPlaying == true
        }
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

    /// All four oracles at once. The player here is honest, so they agree; the
    /// value is that one lying about having paused would show up as a
    /// disagreement rather than a pass.
    func testEveryOracleAgreesWhilePlaying() throws {
        application.buttons[DemoIdentifier.playButton].tap()

        let status = try client.waitForStatus(timeout: 15) {
            $0.audioActive == true && $0.isPlaying == true
        }
        XCTAssertEqual(status.playerState, .playing)
        XCTAssertEqual(status.currentTimeAdvancing, true)
        XCTAssertEqual(status.videoAdvancing, true, "The video oracle should agree while playing")
    }
}
