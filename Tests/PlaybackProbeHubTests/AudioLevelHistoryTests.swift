import Foundation
@testable import PlaybackProbeHub
import Testing

@Suite("Audio level history")
struct AudioLevelHistoryTests {
    /// No reading at all means the tap is not running. Reporting silence would
    /// make a broken tap look exactly like a correctly paused player, which is
    /// the false pass this whole oracle exists to prevent.
    @Test("has no opinion when nothing has been recorded")
    func empty() {
        #expect(AudioLevelHistory().isActive(within: 1, now: 100) == nil)
        #expect(AudioLevelHistory().latest == nil)
    }

    @Test("reports sound when any reading in the window is above the threshold")
    func active() {
        let history = AudioLevelHistory()
        history.append(AudioLevelSample(timestamp: 99.5, rms: 0.0))
        history.append(AudioLevelSample(timestamp: 99.8, rms: 0.4))
        #expect(history.isActive(within: 1, now: 100) == true)
    }

    @Test("reports silence when every reading in the window is at the noise floor")
    func silent() {
        let history = AudioLevelHistory()
        history.append(AudioLevelSample(timestamp: 99.5, rms: 0.0001))
        history.append(AudioLevelSample(timestamp: 99.9, rms: 0.0))
        #expect(history.isActive(within: 1, now: 100) == false)
    }

    /// Sound before the window must not keep a stopped player looking alive.
    @Test("ignores readings older than the window")
    func outsideWindow() {
        let history = AudioLevelHistory()
        history.append(AudioLevelSample(timestamp: 90, rms: 0.9))
        #expect(history.isActive(within: 1, now: 100) == nil)
        history.append(AudioLevelSample(timestamp: 99.9, rms: 0.0))
        #expect(history.isActive(within: 1, now: 100) == false)
    }

    @Test("keeps only the most recent readings once full")
    func ringBuffer() {
        let history = AudioLevelHistory(capacity: 3)
        for index in 0 ..< 10 {
            history.append(AudioLevelSample(timestamp: Double(index), rms: Float(index) / 10))
        }
        #expect(history.latest?.timestamp == 9)
        #expect(history.samples(within: 100, now: 10).count == 3)
    }

    @Test("forgets everything on reset")
    func reset() {
        let history = AudioLevelHistory()
        history.append(AudioLevelSample(timestamp: 99.9, rms: 0.5))
        history.reset()
        #expect(history.latest == nil)
    }
}
