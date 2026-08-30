import Foundation
import PlaybackProbeSchema
import Testing

@Suite("ProbeConfiguration")
struct ProbeConfigurationTests {
    @Test("stays disabled when the switch is absent")
    func absentSwitch() {
        #expect(ProbeConfiguration(environment: [:]) == nil)
    }

    @Test("stays disabled for values that are not an opt-in", arguments: ["0", "false", "no", ""])
    func negativeValues(value: String) {
        #expect(ProbeConfiguration(environment: [ProbeConfiguration.enabledKey: value]) == nil)
    }

    @Test("enables on any accepted spelling", arguments: ["1", "true", "TRUE", "yes"])
    func positiveValues(value: String) {
        #expect(ProbeConfiguration(environment: [ProbeConfiguration.enabledKey: value]) != nil)
    }

    @Test("reads the sampling interval in milliseconds")
    func samplingInterval() throws {
        let configuration = try #require(ProbeConfiguration(environment: [
            ProbeConfiguration.enabledKey: "1",
            ProbeConfiguration.sampleIntervalKey: "250",
        ]))
        #expect(configuration.sampleInterval == 0.25)
    }

    @Test("falls back to the default interval when the value is unusable", arguments: ["", "0", "-1", "soon"])
    func unusableInterval(value: String) throws {
        let configuration = try #require(ProbeConfiguration(environment: [
            ProbeConfiguration.enabledKey: "1",
            ProbeConfiguration.sampleIntervalKey: value,
        ]))
        #expect(configuration.sampleInterval == ProbeConfiguration.defaultSampleInterval)
    }
}
