import Foundation
import PlaybackProbeSchema
import Testing

@Suite("Fingerprinting a frame")
struct FrameFingerprintTests {
    private static let cells = FrameFingerprint.gridSize * FrameFingerprint.gridSize

    @Test("gives a flat frame no set bits, since nothing is above the mean")
    func flat() throws {
        let hash = try #require(FrameFingerprint.averageHash(grid: [Float](
            repeating: 0.5,
            count: Self.cells
        )))
        #expect(hash.allSatisfy { $0 == "0" })
    }

    @Test("is stable for the same frame")
    func stable() {
        let grid = (0 ..< Self.cells).map { Float($0) }
        #expect(FrameFingerprint.averageHash(grid: grid) == FrameFingerprint.averageHash(grid: grid))
    }

    @Test("sets a bit for each cell brighter than the mean")
    func halfBright() throws {
        let half = Self.cells / 2
        let grid = [Float](repeating: 0, count: half) + [Float](repeating: 1, count: half)
        let hash = try #require(FrameFingerprint.averageHash(grid: grid))
        let flat = try #require(FrameFingerprint.averageHash(grid: [Float](repeating: 0, count: Self.cells)))
        #expect(FrameFingerprint.hammingDistance(hash, flat) == half)
    }

    @Test("distinguishes frames that differ")
    func differing() {
        let first = FrameFingerprint.averageHash(grid: (0 ..< Self.cells).map { Float($0) })
        let second = FrameFingerprint.averageHash(grid: (0 ..< Self.cells).map { Float(Self.cells - $0) })
        #expect(first != second)
    }

    @Test("refuses a grid of the wrong size rather than hashing rubbish")
    func wrongSize() {
        #expect(FrameFingerprint.averageHash(grid: [1, 2, 3]) == nil)
    }

    @Test("counts differing bits between two hashes")
    func hamming() {
        #expect(FrameFingerprint.hammingDistance("0000", "000f") == 4)
        #expect(FrameFingerprint.hammingDistance("00", "0000") == nil, "lengths must match")
        #expect(FrameFingerprint.hammingDistance("zz", "00") == nil, "non-hex is not comparable")
    }
}

@Suite("Judging whether the picture moved")
struct VideoAdvancingTests {
    @Test("reports movement when consecutive frames differ")
    func moving() {
        #expect(samples(hashes: ["0000", "ffff"]).isVideoAdvancing())
    }

    @Test("reports a still picture when every frame is the same")
    func still() {
        #expect(!samples(hashes: ["00ff", "00ff", "00ff"]).isVideoAdvancing())
    }

    /// A decoder that is not quite deterministic must not read as playback.
    @Test("tolerates a couple of flipped bits between still frames")
    func almostStill() {
        #expect(!samples(hashes: ["00ff", "00fd"]).isVideoAdvancing())
    }

    /// A tick landing between two frames carries no hash and must not be read
    /// as the picture repeating.
    @Test("ignores a tick that caught no frame")
    func missingFrame() {
        var events = samples(hashes: ["0000", "ffff"])
        events.insert(ProbeEvent(kind: .sample, playerState: .playing, videoSampled: true), at: 1)
        #expect(events.isVideoAdvancing())
        #expect(events.hasVideoOracle)
    }

    /// A paused player stops producing frames entirely rather than repeating
    /// the last one, so an entire window without frames is the evidence that
    /// the picture is not advancing.
    @Test("calls a window with no frames at all not advancing")
    func pausedProducesNoFrames() {
        let events = (0 ..< 5).map { _ in
            ProbeEvent(kind: .sample, playerState: .paused, videoSampled: true)
        }
        #expect(events.hasVideoOracle)
        #expect(!events.isVideoAdvancing())
    }

    @Test("has no opinion when the oracle was not running")
    func oracleOff() {
        let events = [ProbeEvent(kind: .sample, playerState: .playing)]
        #expect(!events.hasVideoOracle)
        #expect(!events.isVideoAdvancing())
    }

    private func samples(hashes: [String]) -> [ProbeEvent] {
        hashes.enumerated().map { index, hash in
            ProbeEvent(
                kind: .sample,
                timestamp: Double(index) * 0.2,
                playerID: "player-1",
                playerState: .playing,
                videoSampled: true,
                videoFrameHash: hash
            )
        }
    }
}
