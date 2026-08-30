import Foundation

/// What every oracle currently says, and whether they agree.
///
/// This is the toolkit's public contract and is deliberately platform-neutral:
/// the planned Android implementation serves the same shape from entirely
/// different sources, so a test written against it does not care which platform
/// answered.
///
/// Each oracle is optional because "no opinion" and "says no" are different
/// answers. A video oracle that is not running must not be mistaken for one
/// reporting that nothing is rendering.
public struct PlaybackStatus: Codable, Sendable, Equatable {
    /// What the player reports about its own intent. `nil` when no player has
    /// been found in the application yet.
    public var playerState: PlayerState?
    /// Whether the playback position moved over the observation window.
    public var currentTimeAdvancing: Bool?
    /// Whether sound reached the output over the observation window.
    public var audioActive: Bool?
    /// Whether new video frames were rendered over the observation window.
    public var videoAdvancing: Bool?

    public init(
        playerState: PlayerState? = nil,
        currentTimeAdvancing: Bool? = nil,
        audioActive: Bool? = nil,
        videoAdvancing: Bool? = nil
    ) {
        self.playerState = playerState
        self.currentTimeAdvancing = currentTimeAdvancing
        self.audioActive = audioActive
        self.videoAdvancing = videoAdvancing
    }

    /// Each oracle's answer to "is playback happening", dropping the ones with
    /// no opinion.
    ///
    /// `waitingToPlay` counts as no opinion: the player wants to play and is
    /// starved of data, which is neither playing nor stopped.
    public var oracleVerdicts: [Bool] {
        var verdicts: [Bool] = []
        switch playerState {
        case .playing: verdicts.append(true)
        case .paused: verdicts.append(false)
        case .waitingToPlay, .unknown, nil: break
        }
        if let currentTimeAdvancing { verdicts.append(currentTimeAdvancing) }
        if let audioActive { verdicts.append(audioActive) }
        if let videoAdvancing { verdicts.append(videoAdvancing) }
        return verdicts
    }

    /// Whether every oracle with an opinion points the same way.
    ///
    /// Inconsistency is the interesting signal, not an error: it is exactly the
    /// shape of the bugs a single oracle misses, such as a player reporting
    /// `paused` while sound keeps coming out of a second instance.
    public var consistent: Bool {
        Set(oracleVerdicts).count <= 1
    }

    /// The agreed answer, or `nil` when the oracles disagree or none has an
    /// opinion.
    public var isPlaying: Bool? {
        consistent ? oracleVerdicts.first : nil
    }

    private enum CodingKeys: String, CodingKey {
        case playerState, currentTimeAdvancing, audioActive, videoAdvancing, consistent
    }

    /// `consistent` is derived, but it is part of the wire contract so that a
    /// client in another language does not have to reimplement the rule.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(playerState, forKey: .playerState)
        try container.encodeIfPresent(currentTimeAdvancing, forKey: .currentTimeAdvancing)
        try container.encodeIfPresent(audioActive, forKey: .audioActive)
        try container.encodeIfPresent(videoAdvancing, forKey: .videoAdvancing)
        try container.encode(consistent, forKey: .consistent)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playerState = try container.decodeIfPresent(PlayerState.self, forKey: .playerState)
        currentTimeAdvancing = try container.decodeIfPresent(Bool.self, forKey: .currentTimeAdvancing)
        audioActive = try container.decodeIfPresent(Bool.self, forKey: .audioActive)
        videoAdvancing = try container.decodeIfPresent(Bool.self, forKey: .videoAdvancing)
    }
}
