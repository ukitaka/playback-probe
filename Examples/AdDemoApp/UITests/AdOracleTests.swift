import Foundation
import PlaybackProbeSchema
import PlaybackProbeTestSupport
import XCTest

/// Answers whether PlaybackProbe sees a video ad played by the Google IMA SDK.
///
/// The SDK creates and owns the ad's player; nothing in the application hands
/// it one or can reach it afterwards. That is the arrangement the probe exists
/// for, so this is the interesting case rather than an edge case.
///
/// Needs a network: the ad comes from Google's sample ad server. When the ad
/// does not load, the tests skip rather than fail, because an unreachable ad
/// server says nothing about the probe.
final class AdOracleTests: XCTestCase {
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

    /// The probe finds the content player, which the application does own. If
    /// this fails, nothing about the ad case can be concluded.
    func testProbeSeesTheContentPlayer() throws {
        application.buttons[AdDemoIdentifier.playContentButton].tap()

        let events = try log.waitForEvents { !$0.events(of: .playerAttached).isEmpty }
        XCTAssertEqual(events.events(of: .playerAttached).first?.playerID, "player-1")
    }

    /// The question this spike exists to answer.
    func testProbeSeesThePlayerTheAdSDKCreated() throws {
        application.buttons[AdDemoIdentifier.playContentButton].tap()
        let contentEvents = try log.waitForEvents(timeout: 15) {
            $0.events(of: .sample).count >= 10
        }
        let playersBeforeAd = distinctPlayerIDs()

        // Control for everything below: the same sampler, in the same run, on
        // a player whose picture is known to move. Without this, a still ad
        // and a broken sampler look identical.
        XCTAssertTrue(
            contentEvents.isVideoAdvancing(),
            """
            The video oracle did not see the content player's frames move, so \
            nothing can be concluded about the ad
            """
        )

        application.buttons[AdDemoIdentifier.requestAdButton].tap()
        let adStatus = try adPlaybackStatus()
        print("[ad-spike] ad status: \(adStatus)")

        let events = try log.waitForEvents(timeout: 15) {
            $0.events(of: .playerAttached).count > playersBeforeAd.count
        }
        let adPlayerIDs = distinctPlayerIDs(in: events).subtracting(playersBeforeAd)
        let playersAfterAd = distinctPlayerIDs(in: events).sorted()
        print("[ad-spike] players before ad: \(playersBeforeAd.sorted()), after: \(playersAfterAd)")
        let adPlayerID = try XCTUnwrap(adPlayerIDs.first, """
        The ad played, but the probe never saw a second player. The SDK is \
        rendering it through something other than an AVPlayer whose rate \
        changes, so only the audio oracle covers ads.
        """)

        // Watched for several seconds rather than a moment. The ad player is
        // found the instant it is created, when it has barely any position to
        // report, and an ad can open on a static frame: a verdict from its
        // first second would describe the ad's opening rather than the oracle.
        let observed = try log.waitForEvents(timeout: 30) {
            $0.events(of: .sample).count(where: { $0.playerID == adPlayerID }) >= 25
        }
        let samples = observed.events(of: .sample).filter { $0.playerID == adPlayerID }
        describe(adPlayerID, samples)

        XCTAssertTrue(
            samples.contains { $0.playerState == .playing },
            "The ad player was found but never reported playing"
        )
        XCTAssertTrue(
            samples.isPlaybackPositionAdvancing(),
            "The ad player was found but its position never moved"
        )
        XCTAssertTrue(samples.hasVideoOracle, "The video oracle was not running on the ad player")
    }

    /// Prints what every oracle saw of the ad.
    ///
    /// Whether the picture moved is reported rather than asserted: that is a
    /// property of the creative, not of the probe. Google's sample ad is a
    /// still image for its whole duration, and the control in the test above
    /// already shows the oracle working on a picture that does move.
    private func describe(_ adPlayerID: String, _ samples: [ProbeEvent]) {
        let positions = samples.compactMap(\.currentTime).map { String(format: "%.2f", $0) }
        let hashes = samples.compactMap(\.videoFrameHash)
        let distances = zip(hashes, hashes.dropFirst()).compactMap {
            FrameFingerprint.hammingDistance($0, $1)
        }
        print("""
        [ad-spike] ad player \(adPlayerID): \(samples.count) samples
        [ad-spike]   positions: \(positions)
        [ad-spike]   frames: \(hashes.count) of \(samples.count) samples carried one
        [ad-spike]   frame distances: \(distances)
        [ad-spike]   picture moving: \(samples.isVideoAdvancing())
        """)
    }

    /// Waits for the SDK to report that an ad is on screen, and skips when it
    /// could not fetch one.
    @discardableResult
    private func adPlaybackStatus() throws -> String {
        let status = application.staticTexts[AdDemoIdentifier.statusLabel]
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            let value = status.value as? String ?? status.label
            if value.contains("ad playing") { return value }
            if value.contains("failed") || value.contains("error") {
                throw XCTSkip("The ad server could not be reached: \(value)")
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        throw XCTSkip("No ad started within 20s; the ad server is probably unreachable")
    }

    private func distinctPlayerIDs(in events: [ProbeEvent]? = nil) -> Set<String> {
        Set((events ?? log.events()).events(of: .playerAttached).compactMap(\.playerID))
    }
}
