import PlaybackProbeSchema
import SwiftUI

struct MenuContentView: View {
    @Bindable var model: CaptureModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            AudioLevelMeter(level: model.level)
            Divider()
            oracles
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatusRow(label: "Hub", detail: model.hubURL, state: model.hubStateIndicator)
            StatusRow(label: "Audio tap", detail: model.tapDetail, state: model.tapStateIndicator)
            if let advice = model.permissionAdvice {
                Text(advice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// What the test side would see right now, so that a failing assertion can
    /// be compared against the machine rather than guessed at.
    private var oracles: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Oracles").font(.caption).foregroundStyle(.secondary)
            OracleRow(name: "Player state", value: model.status.playerState?.rawValue)
            OracleRow(name: "Position advancing", value: model.status.currentTimeAdvancing?.description)
            OracleRow(name: "Audio active", value: model.status.audioActive?.description)
            OracleRow(name: "Picture advancing", value: model.status.videoAdvancing?.description)
            OracleRow(name: "Oracles agree", value: model.status.consistent.description)
            Text("\(model.eventCount) events received")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            if model.isCapturing {
                Button("Stop tap") { model.stopTap() }
            } else {
                Button("Start tap") { model.startTap() }
            }
            Button("Reset") { model.reset() }
            Spacer()
            Button("Quit") {
                model.stop()
                NSApplication.shared.terminate(nil)
            }
        }
        .font(.callout)
    }
}

private struct StatusRow: View {
    let label: String
    let detail: String
    let state: CaptureModel.Indicator

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(state.color).frame(width: 8, height: 8)
            Text(label).font(.callout.weight(.medium))
            Spacer()
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct OracleRow: View {
    let name: String
    /// `nil` means the oracle has no opinion, which is deliberately shown as
    /// such rather than as a negative.
    let value: String?

    var body: some View {
        HStack {
            Text(name).font(.callout)
            Spacer()
            Text(value ?? "no opinion")
                .font(.callout.monospaced())
                .foregroundStyle(value == nil ? .tertiary : .primary)
        }
    }
}

/// A level meter, so that "the tap is running but the machine is silent" can be
/// seen rather than inferred.
private struct AudioLevelMeter: View {
    let level: Float?

    /// Quietest level worth drawing. Below this is the noise floor.
    private static let floor: Float = -60

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Level").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(readout).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(.tint)
                        .frame(width: geometry.size.width * CGFloat(fraction))
                }
            }
            .frame(height: 8)
        }
    }

    /// Drawn on a decibel scale. Sound that is plainly audible sits at a small
    /// fraction of full scale, and a linear meter would leave it invisible.
    private var fraction: Float {
        guard let level, level > 0 else { return 0 }
        let decibels = 20 * log10(level)
        return min(1, max(0, (decibels - Self.floor) / -Self.floor))
    }

    private var readout: String {
        guard let level else { return "no signal yet" }
        guard level > 0 else { return "silent" }
        return String(format: "%.0f dBFS", 20 * log10(level))
    }
}
