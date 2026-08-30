import AVFoundation

/// Playback state of a single player, normalised across platforms.
///
/// The wire representation is shared with the Android implementation, so the
/// raw values must not change without updating the aggregate schema.
public enum PlayerState: String, Codable, Sendable {
    case paused
    case waitingToPlay
    case playing
    case unknown

    init(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .paused: self = .paused
        case .waitingToPlayAtSpecifiedRate: self = .waitingToPlay
        case .playing: self = .playing
        @unknown default: self = .unknown
        }
    }
}
