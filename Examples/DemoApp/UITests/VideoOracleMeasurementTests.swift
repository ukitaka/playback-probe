import Foundation
import PlaybackProbeSchema
import PlaybackProbeTestSupport
import XCTest

/// Measures how far consecutive frame hashes drift, which is what the video
/// oracle's tolerance has to be set against.
///
/// Opt-in like the latency measurement: it reports numbers rather than
/// enforcing a bound. Run with `PLAYBACK_PROBE_MEASURE=1`.
final class VideoOracleMeasurementTests: XCTestCase {
    private var application: XCUIApplication!
    private var log: ProbeEventLog!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PLAYBACK_PROBE_MEASURE"] == "1",
            "Set PLAYBACK_PROBE_MEASURE=1 to run the video measurement"
        )
        let logURL = try ProbeLogLocation.makeSharedLogURL()
        log = ProbeEventLog(url: logURL)
        application = try XCUIApplication.withProbe(logURL: logURL, sampleInterval: 0.2)
        application.launch()
    }

    override func tearDown() {
        application?.terminate()
        super.tearDown()
    }

    func testFrameHashDistances() throws {
        application.buttons[DemoIdentifier.playButton].tap()
        try report("playing", distances(over: 3))

        application.buttons[DemoIdentifier.pauseButton].tap()
        Thread.sleep(forTimeInterval: 1)
        try report("paused", distances(over: 3))

        // The overlay covers the player's layer. If a covered layer stopped
        // producing buffers, the video oracle would report a still picture for
        // a player that never stopped, which is the false pass this exists to
        // catch.
        application.buttons[DemoIdentifier.playButton].tap()
        Thread.sleep(forTimeInterval: 1)
        application.buttons[DemoIdentifier.presentLeakyOverlayButton].tap()
        Thread.sleep(forTimeInterval: 1)
        try report("playing behind an overlay", distances(over: 3))
    }

    /// Consecutive Hamming distances among the frames seen in the next
    /// `seconds`, plus how many ticks carried no frame at all.
    private struct Reading {
        var distances: [Int]
        var missed: Int
        var isAdvancing: Bool
    }

    private func distances(over seconds: TimeInterval) throws -> Reading {
        let cutoff = Date().timeIntervalSince1970
        Thread.sleep(forTimeInterval: seconds)
        let samples = log.events().samples(since: cutoff)
        let hashes = samples.compactMap(\.videoFrameHash)
        let distances = zip(hashes, hashes.dropFirst()).compactMap {
            FrameFingerprint.hammingDistance($0, $1)
        }
        return Reading(
            distances: distances,
            missed: samples.count - hashes.count,
            isAdvancing: samples.isVideoAdvancing()
        )
    }

    private func report(_ label: String, _ reading: Reading) {
        let sorted = reading.distances.sorted()
        let summary = sorted.isEmpty
            ? "no frame pairs"
            : "min \(sorted.first!) median \(sorted[sorted.count / 2]) max \(sorted.last!)"
        print("[video] \(label): \(reading.distances.count) pairs, \(summary), "
            + "\(reading.missed) ticks with no new frame, verdict advancing=\(reading.isAdvancing)")
    }
}
