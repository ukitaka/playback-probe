import AVFoundation
import UIKit

/// Stands in for a third-party online video platform SDK.
///
/// It owns an `AVPlayer` and deliberately never exposes it, mirroring the
/// situation the probe exists to solve: the UI test cannot reach the player, so
/// playback state has to be observed from inside the process instead.
final class HiddenPlayerSDK {
    private let player: AVPlayer
    private var looper: NSObjectProtocol?

    init(contentURL: URL) {
        player = AVPlayer(url: contentURL)
        player.actionAtItemEnd = .none

        looper = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
    }

    deinit {
        if let looper {
            NotificationCenter.default.removeObserver(looper)
        }
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    /// Returns a view rendering the hidden player. The player itself stays
    /// private; only pixels leave the SDK.
    func makeVideoView() -> UIView {
        PlayerContainerView(player: player)
    }
}

private final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    init(player: AVPlayer) {
        super.init(frame: .zero)
        backgroundColor = .black
        // swiftlint:disable:next force_cast
        let playerLayer = layer as! AVPlayerLayer
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
