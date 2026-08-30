import AVFoundation
import PlaybackProbeSchema

extension PlayerState {
    init(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .paused: self = .paused
        case .waitingToPlayAtSpecifiedRate: self = .waitingToPlay
        case .playing: self = .playing
        @unknown default: self = .unknown
        }
    }
}
