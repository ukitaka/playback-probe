import AVFoundation
import SwiftUI

@main
struct DemoApp: App {
    init() {
        // Without an active playback session the simulator produces no audio,
        // which the audio oracle needs.
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            PlayerScreen()
        }
    }
}
