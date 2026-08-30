import Foundation

/// A single observation emitted by the probe.
///
/// Events are appended to the log as JSON Lines so that a test can read the
/// file incrementally without waiting for the process to exit.
public struct ProbeEvent: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// The probe finished bootstrapping and is watching for players.
        case probeStarted
        /// A player instance was discovered and is now being sampled.
        case playerAttached
        /// A previously attached player was deallocated.
        case playerReleased
        /// A periodic reading of the state and time oracles.
        case sample
    }

    public var kind: Kind
    /// Seconds since the Unix epoch, taken on the host clock.
    public var timestamp: TimeInterval
    /// Stable identifier of the player within this process, such as `player-1`.
    public var playerID: String?
    public var playerState: PlayerState?
    /// `AVPlayer.currentTime()` in seconds. Absent when it is not a finite value.
    public var currentTime: Double?
    public var rate: Float?
    /// Whether the video oracle looked at all on this tick. Absent when video
    /// sampling is switched off, which is what tells "no opinion" apart from
    /// "looked, and the picture was not moving".
    public var videoSampled: Bool?
    /// Average hash of the frame on screen, as hex. Absent when no new frame
    /// was ready. A paused player produces none at all, so absence across a
    /// window is itself the evidence that the picture is not advancing.
    public var videoFrameHash: String?
    /// Only present on `probeStarted`. See `PlaybackProbe.isBootstrappedByConstructor`.
    public var bootstrappedByConstructor: Bool?
    public var message: String?

    public init(
        kind: Kind,
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        playerID: String? = nil,
        playerState: PlayerState? = nil,
        currentTime: Double? = nil,
        rate: Float? = nil,
        videoSampled: Bool? = nil,
        videoFrameHash: String? = nil,
        bootstrappedByConstructor: Bool? = nil,
        message: String? = nil
    ) {
        self.kind = kind
        self.timestamp = timestamp
        self.playerID = playerID
        self.playerState = playerState
        self.currentTime = currentTime
        self.rate = rate
        self.videoSampled = videoSampled
        self.videoFrameHash = videoFrameHash
        self.bootstrappedByConstructor = bootstrappedByConstructor
        self.message = message
    }
}
