import Accelerate
import AudioToolbox

/// Turns a buffer of audio into a single level.
///
/// Separated from the tap so it can be tested without any audio hardware or
/// capture permission, which is most of what can go wrong in this file.
public enum AudioLevel {
    /// Root mean square amplitude, in the range 0...1 for normalised input.
    ///
    /// RMS rather than peak: a single loud sample says nothing about whether
    /// sound is actually playing, whereas the mean energy over a buffer does.
    public static func rootMeanSquare(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard let base = samples.baseAddress, !samples.isEmpty else { return 0 }
        var result: Float = 0
        vDSP_rmsqv(base, 1, &result, vDSP_Length(samples.count))
        return result
    }

    public static func rootMeanSquare(_ samples: [Float]) -> Float {
        samples.withUnsafeBufferPointer(rootMeanSquare)
    }

    /// Root mean square across every channel of a render callback's buffers.
    ///
    /// Channels are pooled rather than reported separately: the question is
    /// whether anything is coming out, not which speaker it came from.
    public static func rootMeanSquare(of bufferList: UnsafePointer<AudioBufferList>) -> Float {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        var sumOfSquares: Float = 0
        var totalFrames = 0

        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            guard count > 0 else { continue }
            let samples = UnsafeBufferPointer(
                start: data.assumingMemoryBound(to: Float.self),
                count: count
            )
            let rms = rootMeanSquare(samples)
            sumOfSquares += rms * rms * Float(count)
            totalFrames += count
        }

        guard totalFrames > 0 else { return 0 }
        return (sumOfSquares / Float(totalFrames)).squareRoot()
    }
}
