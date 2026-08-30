import SwiftUI

struct PlayerScreen: View {
    private let sdk = HiddenPlayerSDK(contentURL: Bundle.main.url(
        forResource: "sample",
        withExtension: "mp4"
    )!)

    @State private var isShowingOverlay = false

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                VideoView(sdk: sdk)
                    .aspectRatio(16 / 9, contentMode: .fit)

                HStack(spacing: 12) {
                    Button("Play") { sdk.play() }
                        .accessibilityIdentifier(DemoIdentifier.playButton)
                    Button("Pause") { sdk.pause() }
                        .accessibilityIdentifier(DemoIdentifier.pauseButton)
                }

                // The two overlay buttons differ only in whether they pause the
                // player. Both look identical on screen once the overlay covers
                // it, which is exactly why a visual assertion cannot tell them
                // apart and the probe is needed.
                Button("Overlay (pauses)") {
                    sdk.pause()
                    isShowingOverlay = true
                }
                .accessibilityIdentifier(DemoIdentifier.presentCorrectOverlayButton)

                Button("Overlay (keeps playing)") {
                    isShowingOverlay = true
                }
                .accessibilityIdentifier(DemoIdentifier.presentLeakyOverlayButton)

                Spacer()
            }
            .padding()

            if isShowingOverlay {
                overlayView
            }
        }
    }

    private var overlayView: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 24) {
                Text("Overlay")
                    .font(.largeTitle)
                    .foregroundStyle(.white)
                Button("Dismiss") {
                    isShowingOverlay = false
                    sdk.play()
                }
                .accessibilityIdentifier(DemoIdentifier.dismissOverlayButton)
                .foregroundStyle(.white)
            }
        }
    }
}

private struct VideoView: UIViewRepresentable {
    let sdk: HiddenPlayerSDK

    func makeUIView(context _: Context) -> UIView {
        sdk.makeVideoView()
    }

    func updateUIView(_: UIView, context _: Context) {}
}
