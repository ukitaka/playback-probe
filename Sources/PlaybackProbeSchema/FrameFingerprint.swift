import Foundation

/// Reduces a video frame to something small enough to send and compare.
///
/// An average hash: the frame is sampled onto a grid and each cell becomes one
/// bit, set when the cell is brighter than the frame's mean. Two frames of the
/// same still image agree; a frame that moved does not. That survives the
/// compression noise a pixel-exact comparison would trip over.
public enum FrameFingerprint {
    /// Cells per side.
    ///
    /// Measured rather than chosen: at 8 cells a side, consecutive frames of
    /// moving video differed by a median of one bit, because averaging over a
    /// large cell smooths away everything but the largest movement. At 16 the
    /// same frames differ by a median of six, which movement can be told from
    /// noise by.
    public static let gridSize = 16

    /// - Parameter grid: Brightness per cell, row by row. Returns `nil` unless
    ///   there are exactly `gridSize` squared values.
    public static func averageHash(grid: [Float]) -> String? {
        guard grid.count == gridSize * gridSize else { return nil }
        let mean = grid.reduce(0, +) / Float(grid.count)

        var hex = ""
        hex.reserveCapacity(grid.count / 4)
        for nibbleStart in stride(from: 0, to: grid.count, by: 4) {
            var nibble = 0
            for offset in 0 ..< 4 where grid[nibbleStart + offset] > mean {
                nibble |= 1 << offset
            }
            hex.append(String(nibble, radix: 16))
        }
        return hex
    }

    /// How many bits two hashes differ by, or `nil` if they are not comparable.
    ///
    /// A distance rather than equality, because a still frame is not guaranteed
    /// to decode bit-identically.
    public static func hammingDistance(_ first: String, _ second: String) -> Int? {
        guard first.count == second.count else { return nil }
        var distance = 0
        for (left, right) in zip(first, second) {
            guard let leftBits = left.hexDigitValue, let rightBits = right.hexDigitValue else {
                return nil
            }
            distance += (leftBits ^ rightBits).nonzeroBitCount
        }
        return distance
    }
}
