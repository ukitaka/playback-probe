import Foundation
import PlaybackProbeHub
import PlaybackProbeSchema
import Testing

@Suite("Aggregating what the oracles report")
struct PlaybackStatusStoreTests {
    /// The probe stamps events with the clock of the machine it runs on: a
    /// simulator here, an emulator on Android. The hub runs on the host. If the
    /// window were applied to the probe's timestamps, a clock offset of a second
    /// would empty it and a healthy player would look stopped.
    @Test("windows on when the hub received an event, not on the sender's clock")
    func toleratesClockSkew() {
        let store = PlaybackStatusStore()
        let now = Date().timeIntervalSince1970
        let skew: TimeInterval = 3600

        store.record(
            [
                ProbeEvent(kind: .sample, timestamp: now + skew, playerState: .playing, currentTime: 1.0),
                ProbeEvent(
                    kind: .sample,
                    timestamp: now + skew + 0.2,
                    playerState: .playing,
                    currentTime: 1.2
                ),
            ],
            receivedAt: now
        )

        let status = store.status(window: 1, now: now)
        #expect(status.playerState == .playing)
        #expect(status.currentTimeAdvancing == true)
    }

    @Test("drops events the hub received before the window")
    func outsideWindow() {
        let store = PlaybackStatusStore()
        let now = Date().timeIntervalSince1970
        store.record(ProbeEvent(kind: .sample, playerState: .playing, currentTime: 1), receivedAt: now - 10)

        #expect(store.status(window: 1, now: now).playerState == nil)
        #expect(store.status(window: 30, now: now).playerState == .playing)
    }

    /// One sample can report intent but cannot show movement, so the time
    /// oracle must say nothing rather than "not moving".
    @Test("has no opinion on movement from a single sample")
    func singleSample() {
        let store = PlaybackStatusStore()
        let now = Date().timeIntervalSince1970
        store.record(ProbeEvent(kind: .sample, playerState: .playing, currentTime: 1), receivedAt: now)

        let status = store.status(window: 1, now: now)
        #expect(status.playerState == .playing)
        #expect(status.currentTimeAdvancing == nil)
    }

    @Test("leaves an oracle that is not running out of the status")
    func absentOracles() {
        let store = PlaybackStatusStore()
        let status = store.status()
        #expect(status.audioActive == nil)
        #expect(status.videoAdvancing == nil)
        #expect(status.playerState == nil)
    }

    @Test("keeps non-sample events for diagnosis without treating them as samples")
    func nonSampleEvents() {
        let store = PlaybackStatusStore()
        let now = Date().timeIntervalSince1970
        store.record(ProbeEvent(kind: .playerAttached, playerID: "player-1"), receivedAt: now)

        #expect(store.events().count == 1)
        #expect(store.status(window: 1, now: now).playerState == nil)
    }
}
