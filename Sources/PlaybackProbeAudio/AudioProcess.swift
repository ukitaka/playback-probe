import AudioToolbox
import CoreAudio
import Foundation

/// A process Core Audio knows about.
///
/// Needed because a tap is created for audio objects, not for process
/// identifiers, and because which process actually carries a simulator's sound
/// is not obvious: it may be the simulated application, or a part of the
/// simulator runtime. Listing what is producing output while a video plays is
/// how you find out.
public struct AudioProcess: Sendable, Identifiable {
    public let id: AudioObjectID
    public let processIdentifier: pid_t?
    public let bundleIdentifier: String?
    /// Whether the process is producing output right now.
    public let isProducingOutput: Bool

    /// Every process Core Audio knows about.
    public static func all() throws -> [AudioProcess] {
        try AudioObjectID.readProcessList().map { objectID in
            AudioProcess(
                id: objectID,
                processIdentifier: objectID.readProcessPID(),
                bundleIdentifier: objectID.readProcessBundleID(),
                isProducingOutput: objectID.readIsRunningOutput()
            )
        }
    }

    /// Processes producing output right now. Play something first, then look.
    public static func producingOutput() throws -> [AudioProcess] {
        try all().filter(\.isProducingOutput)
    }

    public var description: String {
        let name = bundleIdentifier ?? "(no bundle identifier)"
        let pid = processIdentifier.map(String.init) ?? "?"
        return "\(name) [pid \(pid), object \(id)]\(isProducingOutput ? " playing" : "")"
    }
}
