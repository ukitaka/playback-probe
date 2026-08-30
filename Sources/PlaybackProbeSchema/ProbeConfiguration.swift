import Foundation

/// Probe settings read from the host process environment.
///
/// The probe is configured entirely through the environment because it is
/// injected into an application that knows nothing about it. XCUITest supplies
/// these through `XCUIApplication.launchEnvironment`.
public struct ProbeConfiguration: Sendable {
    /// Master switch. The probe stays inert unless this is explicitly enabled,
    /// so a build that accidentally links the probe is a no-op in production.
    public static let enabledKey = "PLAYBACK_PROBE_ENABLED"

    /// Absolute path of the JSON Lines event log. Optional; without it events
    /// are only emitted to the unified log.
    public static let logPathKey = "PLAYBACK_PROBE_LOG_PATH"

    /// Sampling period for the state and time oracles, in milliseconds.
    public static let sampleIntervalKey = "PLAYBACK_PROBE_SAMPLE_INTERVAL_MS"

    public static let defaultSampleInterval: TimeInterval = 0.5

    public var logPath: String?
    public var sampleInterval: TimeInterval

    /// Returns `nil` when the probe is not enabled for this process.
    public init?(environment: [String: String]) {
        guard let rawEnabled = environment[Self.enabledKey],
              Self.isEnabled(rawEnabled)
        else {
            return nil
        }

        logPath = environment[Self.logPathKey].flatMap { $0.isEmpty ? nil : $0 }

        if let rawInterval = environment[Self.sampleIntervalKey],
           let milliseconds = Double(rawInterval),
           milliseconds > 0
        {
            sampleInterval = milliseconds / 1000
        } else {
            sampleInterval = Self.defaultSampleInterval
        }
    }

    private static func isEnabled(_ value: String) -> Bool {
        switch value.lowercased() {
        case "1", "true", "yes": true
        default: false
        }
    }
}
