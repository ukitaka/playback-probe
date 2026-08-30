import Foundation
import PlaybackProbeSchema
import PlaybackProbeTestSupport
import XCTest

/// Measures how long a test must wait after asking the player to stop before
/// the stop is observable.
///
/// This is the number that decides whether a naive "tap, then assert" test is
/// flaky. It is reported rather than tightly bounded, because it depends on the
/// sampling interval and on the machine.
final class PauseLatencyMeasurementTests: XCTestCase {
    private let cycles = 12

    /// Sampling intervals to compare. The probe cannot report a state change
    /// sooner than its next tick, so this is expected to dominate.
    private let intervals: [TimeInterval] = [0.05, 0.2, 0.5]

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    func testPauseIsObservableWithinOneSamplingTick() throws {
        for interval in intervals {
            let measurement = try measureLatency(sampleInterval: interval)
            report(sampleInterval: interval, measurement)

            // The pause itself lands in roughly 140ms; what a test actually
            // waits for is the next sampling tick on top of that.
            XCTAssertLessThan(
                measurement.sinceRequested.max() ?? .infinity,
                interval + 0.5,
                "Observing the pause took longer than one sampling tick plus slack"
            )
        }
    }

    private struct Measurement {
        var sinceRequested: [Double]
        var sinceTapReturned: [Double]
        var tapDurations: [Double]
    }

    private func measureLatency(sampleInterval: TimeInterval) throws -> Measurement {
        let logURL = try ProbeLogLocation.makeSharedLogURL()
        let log = ProbeEventLog(url: logURL)
        let application = try XCUIApplication.withProbe(logURL: logURL, sampleInterval: sampleInterval)
        application.launch()
        defer { application.terminate() }

        var measurement = Measurement(sinceRequested: [], sinceTapReturned: [], tapDurations: [])

        for _ in 0 ..< cycles {
            let playCutoff = Date().timeIntervalSince1970
            application.buttons[DemoIdentifier.playButton].tap()
            _ = try log.waitForEvents {
                $0.samples(since: playCutoff).contains { $0.playerState == .playing }
            }
            // Randomised so the pause does not always land at the same
            // phase of the sampling timer. Without this, every cycle takes the
            // same time and the measurement only ever sees one phase, making
            // the sampling interval look irrelevant.
            Thread.sleep(forTimeInterval: 0.2 + Double.random(in: 0 ... max(sampleInterval, 0.05)))

            let requestedAt = Date().timeIntervalSince1970
            application.buttons[DemoIdentifier.pauseButton].tap()
            let tapReturnedAt = Date().timeIntervalSince1970

            let events = try log.waitForEvents {
                $0.samples(since: requestedAt).contains { $0.playerState == .paused }
            }
            let firstPaused = try XCTUnwrap(
                events.samples(since: requestedAt).first { $0.playerState == .paused }
            )
            measurement.sinceRequested.append(firstPaused.timestamp - requestedAt)
            measurement.sinceTapReturned.append(firstPaused.timestamp - tapReturnedAt)
            measurement.tapDurations.append(tapReturnedAt - requestedAt)
        }

        return measurement
    }

    private func report(sampleInterval: TimeInterval, _ measurement: Measurement) {
        print("""
        [latency] sampling=\(Int(sampleInterval * 1000))ms \
        observable_after_tap_call=\(summary(measurement.sinceRequested)) \
        observable_after_tap_returns=\(summary(measurement.sinceTapReturned)) \
        xcuitest_tap_duration=\(summary(measurement.tapDurations))
        """)
    }

    private func summary(_ values: [Double]) -> String {
        let sorted = values.sorted()
        guard let first = sorted.first, let last = sorted.last else { return "n/a" }
        let format = { (value: Double) in String(format: "%.0f", value * 1000) }
        return "[min \(format(first)) med \(format(sorted[sorted.count / 2])) max \(format(last))]ms"
    }
}
