import PlaybackProbeHub
import SwiftUI

/// The host-side half of PlaybackProbe: the hub every oracle reports to, and
/// the audio tap that watches what the Mac is playing.
///
/// It exists as an application rather than the `playback-probe-hub` command for
/// one reason: macOS grants audio capture permission to a signed application
/// bundle, and remembers it. A command-line tool has no stable identity to
/// remember, so it is at the mercy of whatever permission its terminal happens
/// to hold.
@main
struct CaptureApp: App {
    @State private var model = CaptureModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            Label(
                "PlaybackProbe",
                systemImage: model.isCapturing ? "waveform.circle.fill" : "waveform.circle"
            )
        }
        .menuBarExtraStyle(.window)
        .onChange(of: model.hasStarted, initial: true) {
            if !model.hasStarted { model.start() }
        }
    }
}
