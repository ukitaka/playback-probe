import Foundation
import PlaybackProbeSchema
import PlaybackProbeTestSupport
import Testing

@Suite("Reaching a verdict from a window of samples")
struct PlaybackObservationTests {
    @Test("calls it stopped when the state holds at paused and the position does not move")
    func stopped() {
        let observation = observe([(.paused, 4.2), (.paused, 4.2), (.paused, 4.2)])
        #expect(observation.isStopped)
        #expect(!observation.isPlaying)
    }

    @Test("refuses to judge a single sample")
    func inconclusive() {
        let observation = observe([(.paused, 4.2)])
        #expect(!observation.isConclusive)
        #expect(!observation.isStopped)
        #expect(!observation.isPlaying)
        #expect(observation.summary.contains("sampling intervals"))
    }

    /// The failure the state oracle alone would miss: the player claims to be
    /// paused while the position keeps climbing.
    @Test("does not call it stopped when the position keeps moving")
    func statePausedButPositionMoving() {
        #expect(!observe([(.paused, 1.0), (.paused, 1.3), (.paused, 1.6)]).isStopped)
    }

    @Test("does not call it stopped when the window still contains playback")
    func windowStraddlesTheStop() {
        #expect(!observe([(.playing, 1.0), (.paused, 1.2), (.paused, 1.2)]).isStopped)
    }

    /// Buffering is not stopping: the player intends to play and is starved of
    /// data, which is a different bug from failing to pause.
    @Test("does not call buffering stopped")
    func buffering() {
        #expect(!observe([(.waitingToPlay, 2.0), (.waitingToPlay, 2.0)]).isStopped)
    }

    @Test("calls it playing when the state and the position agree")
    func playing() {
        let observation = observe([(.playing, 1.0), (.playing, 1.2), (.playing, 1.4)])
        #expect(observation.isPlaying)
        #expect(!observation.isStopped)
    }

    /// A stalled player still reports `playing`, so the time oracle is what
    /// keeps this from counting as playback.
    @Test("does not call a frozen position playing")
    func frozenWhileClaimingToPlay() {
        #expect(!observe([(.playing, 3.0), (.playing, 3.0), (.playing, 3.0)]).isPlaying)
    }

    @Test("summarises what it saw for a failure message")
    func summary() {
        let summary = observe([(.playing, 1.0), (.paused, 1.4)]).summary
        #expect(summary.contains("playing then paused"))
        #expect(summary.contains("2 samples"))
    }

    private func observe(
        _ readings: [(PlayerState, Double)],
        window: TimeInterval = 1.0
    ) -> PlaybackObservation {
        let samples = readings.enumerated().map { index, reading in
            ProbeEvent(
                kind: .sample,
                timestamp: Double(index) * 0.2,
                playerID: "player-1",
                playerState: reading.0,
                currentTime: reading.1
            )
        }
        return PlaybackObservation(samples: samples, window: window)
    }
}
