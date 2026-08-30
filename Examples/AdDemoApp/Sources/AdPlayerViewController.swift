import AVFoundation
import GoogleInteractiveMediaAds
import UIKit

/// A minimal Google IMA integration, built to answer one question: when the
/// SDK plays a video ad, does PlaybackProbe see it?
///
/// The SDK creates and owns the ad's player. Nothing here hands it one, and
/// nothing here can reach it afterwards, which is exactly the arrangement the
/// probe is meant to cope with.
final class AdPlayerViewController: UIViewController {
    /// Google's documented sample tag, which serves a single linear pre-roll.
    /// Reaching it needs a network, so anything built on this is not hermetic.
    private static let sampleAdTag = """
    https://pubads.g.doubleclick.net/gampad/ads?iu=/21775744923/external/single_ad_samples\
    &sz=640x480&cust_params=sample_ct%3Dlinear&ciu_szs=300x250%2C728x90&gdfp_req=1&output=vast\
    &unviewed_position_start=1&env=vp&impl=s&correlator=
    """

    private let contentPlayer: AVPlayer
    private let contentLayer: AVPlayerLayer
    private let videoView = UIView()
    private let statusLabel = UILabel()

    private var adsLoader: IMAAdsLoader!
    private var adsManager: IMAAdsManager?
    private var contentPlayhead: IMAAVPlayerContentPlayhead?

    init() {
        let url = Bundle.main.url(forResource: "sample", withExtension: "mp4")!
        contentPlayer = AVPlayer(url: url)
        contentLayer = AVPlayerLayer(player: contentPlayer)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)

        setUpViews()

        adsLoader = IMAAdsLoader(settings: nil)
        adsLoader.delegate = self
        contentPlayhead = IMAAVPlayerContentPlayhead(avPlayer: contentPlayer)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        contentLayer.frame = videoView.bounds
    }

    private func setUpViews() {
        videoView.backgroundColor = .black
        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.layer.addSublayer(contentLayer)
        view.addSubview(videoView)

        statusLabel.accessibilityIdentifier = AdDemoIdentifier.statusLabel
        statusLabel.text = "idle"
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        let playContent = UIButton(type: .system)
        playContent.setTitle("Play content", for: .normal)
        playContent.accessibilityIdentifier = AdDemoIdentifier.playContentButton
        playContent.addTarget(self, action: #selector(playContent(_:)), for: .touchUpInside)

        let requestAd = UIButton(type: .system)
        requestAd.setTitle("Request ad", for: .normal)
        requestAd.accessibilityIdentifier = AdDemoIdentifier.requestAdButton
        requestAd.addTarget(self, action: #selector(requestAd(_:)), for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [playContent, requestAd])
        buttons.axis = .horizontal
        buttons.distribution = .fillEqually
        buttons.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(buttons)

        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoView.heightAnchor.constraint(equalTo: videoView.widthAnchor, multiplier: 9.0 / 16.0),

            buttons.topAnchor.constraint(equalTo: videoView.bottomAnchor, constant: 16),
            buttons.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            buttons.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            statusLabel.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
    }

    @objc private func playContent(_: UIButton) {
        contentPlayer.play()
        report("content playing")
    }

    @objc private func requestAd(_: UIButton) {
        contentPlayer.pause()
        report("requesting ad")

        let displayContainer = IMAAdDisplayContainer(adContainer: videoView, viewController: self)
        let request = IMAAdsRequest(
            adTagUrl: Self.sampleAdTag,
            adDisplayContainer: displayContainer,
            contentPlayhead: contentPlayhead,
            userContext: nil
        )
        adsLoader.requestAds(with: request)
    }

    /// Mirrored into the accessibility tree so a UI test can tell an ad that
    /// failed to load apart from one that played without the probe seeing it.
    private func report(_ status: String) {
        statusLabel.text = status
        statusLabel.accessibilityValue = status
    }
}

extension AdPlayerViewController: IMAAdsLoaderDelegate {
    func adsLoader(_: IMAAdsLoader, adsLoadedWith adsLoadedData: IMAAdsLoadedData) {
        adsManager = adsLoadedData.adsManager
        adsManager?.delegate = self
        adsManager?.initialize(with: nil)
        report("ad loaded")
    }

    func adsLoader(_: IMAAdsLoader, failedWith adErrorData: IMAAdLoadingErrorData) {
        report("ad failed to load: \(adErrorData.adError.message ?? "unknown")")
    }
}

extension AdPlayerViewController: IMAAdsManagerDelegate {
    func adsManager(_ adsManager: IMAAdsManager, didReceive event: IMAAdEvent) {
        switch event.type {
        case .LOADED:
            adsManager.start()
        case .STARTED:
            report("ad playing")
        case .ALL_ADS_COMPLETED:
            report("ad finished")
        default:
            break
        }
    }

    func adsManager(_: IMAAdsManager, didReceive error: IMAAdError) {
        report("ad error: \(error.message ?? "unknown")")
    }

    func adsManagerDidRequestContentPause(_: IMAAdsManager) {
        contentPlayer.pause()
    }

    func adsManagerDidRequestContentResume(_: IMAAdsManager) {
        contentPlayer.play()
        report("content resumed")
    }
}
