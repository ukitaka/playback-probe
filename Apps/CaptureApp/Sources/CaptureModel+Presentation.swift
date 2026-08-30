import SwiftUI

extension CaptureModel {
    enum Indicator {
        case idle
        case good
        case bad

        var color: Color {
            switch self {
            case .idle: .secondary
            case .good: .green
            case .bad: .red
            }
        }
    }

    var hasStarted: Bool {
        if case .stopped = hubState { false } else { true }
    }

    var isCapturing: Bool {
        if case .running = tapState { true } else { false }
    }

    var hubStateIndicator: Indicator {
        switch hubState {
        case .stopped: .idle
        case .listening: .good
        case .failed: .bad
        }
    }

    var tapStateIndicator: Indicator {
        switch tapState {
        case .stopped, .starting: .idle
        case .running: .good
        case .failed: .bad
        }
    }

    var tapDetail: String {
        switch tapState {
        case .stopped: "stopped"
        case .starting: "waiting for permission"
        case .running: "listening to this Mac"
        case .failed: "refused"
        }
    }

    /// Shown when something needs a person, rather than leaving them to work
    /// out why a green build produces no audio evidence.
    var permissionAdvice: String? {
        switch (tapState, hubState) {
        case let (.failed(message), _):
            """
            \(message)

            Grant audio capture in System Settings > Privacy & Security, then \
            start the tap again.
            """
        case let (_, .failed(message)):
            message
        case (.starting, _):
            """
            Core Audio has not answered yet. If macOS is asking for permission \
            to record this Mac's audio, that is what it is waiting for.
            """
        case (.running, _) where level == nil:
            """
            The tap is running but has heard nothing yet. An output device with \
            nothing to play does not run its callback at all.
            """
        default:
            nil
        }
    }
}
