/// Accessibility identifiers the UI tests drive the demo through.
///
/// Compiled into both the application and the UI test bundle so that a renamed
/// control breaks the build instead of a test.
enum DemoIdentifier {
    static let playButton = "play-button"
    static let pauseButton = "pause-button"
    static let presentCorrectOverlayButton = "present-correct-overlay-button"
    static let presentLeakyOverlayButton = "present-leaky-overlay-button"
    static let dismissOverlayButton = "dismiss-overlay-button"
}
