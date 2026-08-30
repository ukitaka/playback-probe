import Foundation
import PlaybackProbeSchema
import Testing

@Suite("Cross-oracle agreement")
struct PlaybackStatusTests {
    @Test("agrees when every oracle says playback is running")
    func allPlaying() {
        let status = PlaybackStatus(playerState: .playing, currentTimeAdvancing: true, audioActive: true)
        #expect(status.consistent)
        #expect(status.isPlaying == true)
    }

    @Test("agrees when every oracle says playback has stopped")
    func allStopped() {
        let status = PlaybackStatus(playerState: .paused, currentTimeAdvancing: false, audioActive: false)
        #expect(status.consistent)
        #expect(status.isPlaying == false)
    }

    /// The bug the audio oracle exists for: the captured player is paused, but
    /// something in the process is still producing sound.
    @Test("flags a paused player that is still making noise")
    func pausedButAudible() {
        let status = PlaybackStatus(playerState: .paused, currentTimeAdvancing: false, audioActive: true)
        #expect(!status.consistent)
        #expect(status.isPlaying == nil)
    }

    /// Buffering is neither playing nor stopped, so it must not by itself
    /// contradict the other oracles.
    @Test("treats buffering as no opinion")
    func buffering() {
        let status = PlaybackStatus(
            playerState: .waitingToPlay,
            currentTimeAdvancing: false,
            audioActive: false
        )
        #expect(status.oracleVerdicts.count == 2)
        #expect(status.consistent)
    }

    @Test("is trivially consistent when no oracle has an opinion")
    func noOpinions() {
        let status = PlaybackStatus()
        #expect(status.consistent)
        #expect(status.isPlaying == nil)
    }

    @Test("keeps an unavailable oracle out of the encoded status")
    func encoding() throws {
        let status = PlaybackStatus(playerState: .paused, currentTimeAdvancing: false, audioActive: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = try String(data: encoder.encode(status), encoding: .utf8)

        #expect(json ==
            #"{"audioActive":false,"consistent":true,"currentTimeAdvancing":false,"playerState":"paused"}"#)
        // videoAdvancing is absent rather than false: the oracle is not
        // running, which is not the same as reporting no rendering.
        #expect(json?.contains("videoAdvancing") == false)
    }

    @Test("round-trips through JSON")
    func roundTrip() throws {
        let original = PlaybackStatus(playerState: .playing, currentTimeAdvancing: true, audioActive: nil)
        let decoded = try JSONDecoder().decode(PlaybackStatus.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }
}
