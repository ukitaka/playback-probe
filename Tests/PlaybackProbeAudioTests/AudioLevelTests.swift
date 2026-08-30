import Foundation
import PlaybackProbeAudio
import Testing

@Suite("Reducing a buffer to a level")
struct AudioLevelTests {
    @Test("reports nothing for silence")
    func silence() {
        #expect(AudioLevel.rootMeanSquare([Float](repeating: 0, count: 512)) == 0)
    }

    @Test("reports nothing for an empty buffer")
    func empty() {
        #expect(AudioLevel.rootMeanSquare([]) == 0)
    }

    /// A full-scale sine has an RMS of 1 over root two. This is the check that
    /// the level is a mean energy rather than a peak.
    @Test("reports the mean energy of a sine, not its peak")
    func sine() {
        let samples = (0 ..< 4096).map { sin(Float($0) * 2 * .pi / 64) }
        let expected = Float(1) / Float(2).squareRoot()
        #expect(abs(AudioLevel.rootMeanSquare(samples) - expected) < 0.01)
    }

    @Test("reports full scale for a constant signal")
    func constant() {
        #expect(abs(AudioLevel.rootMeanSquare([Float](repeating: 1, count: 128)) - 1) < 0.0001)
    }

    /// A quiet buffer has to land below the threshold the hub treats as the
    /// noise floor, or a paused player would look audible.
    @Test("puts a very quiet signal below the active threshold")
    func quiet() {
        let samples = (0 ..< 1024).map { sin(Float($0) * 2 * .pi / 64) * 0.001 }
        #expect(AudioLevel.rootMeanSquare(samples) < 0.01)
    }
}
