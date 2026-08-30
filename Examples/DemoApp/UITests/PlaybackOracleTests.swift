import PlaybackProbe
import XCTest

/// Covers the state and time oracles: what the probe reports while the player
/// is running, and what it reports once something is supposed to have stopped
/// it.
final class PlaybackOracleTests: XCTestCase {
    private var application: XCUIApplication!
    private var log: ProbeEventLog!

    /// Long enough for several sampling ticks and for the player to settle
    /// after a state change.
    private let settlingTime: TimeInterval = 1.5

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        let logURL = try ProbeInjection.makeLogURL()
        log = ProbeEventLog(url: logURL)
        application = try ProbeInjection.makeApplication(logURL: logURL)
        application.launch()
    }

    func testOraclesReportPlaybackWhilePlaying() throws {
        startPlayback()

        let recent = try samplesFromNow()
        XCTAssertEqual(recent.last?.playerState, .playing)
        XCTAssertTrue(
            recent.isPlaybackPositionAdvancing(),
            "The playback position should advance while the player is playing"
        )
    }

    func testOverlayThatPausesStopsPlayback() throws {
        startPlayback()

        application.buttons[DemoIdentifier.presentCorrectOverlayButton].tap()

        let recent = try samplesFromNow()
        XCTAssertEqual(recent.last?.playerState, .paused)
        XCTAssertFalse(
            recent.isPlaybackPositionAdvancing(),
            "The playback position should not advance behind the overlay"
        )
    }

    /// The bug the toolkit exists to catch. The overlay hides the video, so a
    /// screenshot cannot tell this apart from the correct case, but the probe
    /// can.
    func testOverlayThatForgetsToPauseIsDetected() throws {
        startPlayback()

        application.buttons[DemoIdentifier.presentLeakyOverlayButton].tap()
        XCTAssertTrue(application.buttons[DemoIdentifier.dismissOverlayButton].waitForExistence(timeout: 5))

        let recent = try samplesFromNow()
        XCTAssertEqual(
            recent.last?.playerState,
            .playing,
            "The demo's leaky overlay is expected to leave the player running"
        )
        XCTAssertTrue(
            recent.isPlaybackPositionAdvancing(),
            "The demo's leaky overlay is expected to leave the playback position advancing"
        )
    }

    private func startPlayback() {
        application.buttons[DemoIdentifier.playButton].tap()
        log.waitForEvents(description: "playback to start") {
            $0.events(of: .sample).contains { $0.playerState == .playing }
        }
    }

    /// Waits out the settling time, then returns only the samples taken after
    /// this call, so that a previous state cannot leak into the assertion.
    private func samplesFromNow(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [ProbeEvent] {
        let cutoff = Date().timeIntervalSince1970
        Thread.sleep(forTimeInterval: settlingTime)
        let recent = log.events().samples(since: cutoff)
        XCTAssertGreaterThanOrEqual(
            recent.count,
            2,
            "Not enough samples to judge whether playback advanced",
            file: file,
            line: line
        )
        return recent
    }
}
