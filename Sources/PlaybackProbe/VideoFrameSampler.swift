import AVFoundation
import CoreVideo
import Foundation
import PlaybackProbeSchema

/// Reads frames out of a player that is already rendering them elsewhere.
///
/// `AVPlayerItemVideoOutput` is public API and several outputs can be attached
/// to the same item, so this observes an SDK's player without displacing
/// whatever the SDK does with it.
final class VideoFrameSampler {
    private var output: AVPlayerItemVideoOutput?
    private weak var attachedItem: AVPlayerItem?

    /// A fingerprint of the frame on screen now, or `nil` when there is no new
    /// one.
    ///
    /// "No new frame" is not "the picture is frozen": it happens in the moment
    /// after attaching an output, across a seek, and whenever the tick lands
    /// between two frames. Returning the previous hash instead would invent a
    /// still picture, so the caller records nothing.
    func sample(from player: AVPlayer) -> String? {
        guard let item = player.currentItem else { return nil }
        attach(to: item)
        guard let output else { return nil }

        let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: itemTime),
              let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
        else {
            return nil
        }

        guard let grid = Self.brightnessGrid(from: buffer) else { return nil }
        return FrameFingerprint.averageHash(grid: grid)
    }

    /// Follows the player onto a new item.
    ///
    /// The item changes more often than it looks: an ad SDK swaps one in for
    /// the break and back again, and a looping player replaces its own. The old
    /// output is removed so a long session does not accumulate them.
    private func attach(to item: AVPlayerItem) {
        guard item !== attachedItem else { return }
        if let output, let attachedItem {
            attachedItem.remove(output)
        }
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(output)
        self.output = output
        attachedItem = item
    }

    /// Mean brightness of each cell of a coarse grid over the frame.
    private static func brightnessGrid(from buffer: CVPixelBuffer) -> [Float]? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width >= FrameFingerprint.gridSize, height >= FrameFingerprint.gridSize else { return nil }

        // Rows are padded, so a row's start is bytesPerRow apart rather than
        // width * 4. Indexing by width would read progressively more garbage.
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = base.assumingMemoryBound(to: UInt8.self)

        let cellWidth = width / FrameFingerprint.gridSize
        let cellHeight = height / FrameFingerprint.gridSize
        // Sample a bounded number of points per cell, so the cost does not grow
        // with resolution.
        let columnStep = Swift.max(1, cellWidth / 4)
        let rowStep = Swift.max(1, cellHeight / 4)

        var grid = [Float]()
        grid.reserveCapacity(FrameFingerprint.gridSize * FrameFingerprint.gridSize)

        for gridRow in 0 ..< FrameFingerprint.gridSize {
            for gridColumn in 0 ..< FrameFingerprint.gridSize {
                var total: Float = 0
                var count = 0
                var pixelY = gridRow * cellHeight
                while pixelY < (gridRow + 1) * cellHeight, pixelY < height {
                    var pixelX = gridColumn * cellWidth
                    while pixelX < (gridColumn + 1) * cellWidth, pixelX < width {
                        // 32BGRA is blue, green, red, alpha in memory order.
                        let offset = pixelY * bytesPerRow + pixelX * 4
                        let blue = Float(pixels[offset])
                        let green = Float(pixels[offset + 1])
                        let red = Float(pixels[offset + 2])
                        total += (red + green + blue) / 3
                        count += 1
                        pixelX += columnStep
                    }
                    pixelY += rowStep
                }
                grid.append(count > 0 ? total / Float(count) : 0)
            }
        }
        return grid
    }
}
