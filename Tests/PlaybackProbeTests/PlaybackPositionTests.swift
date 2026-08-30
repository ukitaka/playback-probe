import Foundation
import PlaybackProbeSchema
import PlaybackProbeTestSupport
import Testing

@Suite("Judging whether the playback position advanced")
struct PlaybackPositionTests {
    @Test("reports advancing while the position climbs")
    func advancing() {
        #expect(samples(at: [1.0, 1.2, 1.4, 1.6]).isPlaybackPositionAdvancing())
    }

    @Test("reports stopped when the position is held")
    func held() {
        #expect(!samples(at: [4.2, 4.2, 4.2, 4.2]).isPlaybackPositionAdvancing())
    }

    /// Looping content seeks back to the start, so a window that straddles the
    /// seek ends lower than it began even though the player never stopped.
    /// Comparing only the first and last sample would call this stopped.
    @Test("reports advancing across a loop back to the start")
    func loopWraparound() {
        #expect(samples(at: [14.6, 14.8, 0.1, 0.3]).isPlaybackPositionAdvancing())
    }

    @Test("needs at least two samples to judge anything")
    func singleSample() {
        #expect(!samples(at: [1.0]).isPlaybackPositionAdvancing())
        #expect(!samples(at: []).isPlaybackPositionAdvancing())
    }

    @Test("ignores drift below the threshold")
    func drift() {
        #expect(!samples(at: [2.0, 2.001, 2.002]).isPlaybackPositionAdvancing())
    }

    private func samples(at positions: [Double]) -> [ProbeEvent] {
        positions.enumerated().map { index, position in
            ProbeEvent(
                kind: .sample,
                timestamp: Double(index) * 0.2,
                playerID: "player-1",
                playerState: .playing,
                currentTime: position
            )
        }
    }
}
