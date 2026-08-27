import BrushKit
import SwiftUI

struct RecordingView: View {
    @State private var model = RecordingViewModel()
    @AppStorage("recordingWatchWrist") private var watchWrist = WatchWrist.left.rawValue

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                statusHeader
                captureDisplay
                controls
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .background(Color.captureInk.ignoresSafeArea())
        .navigationTitle("Capture")
    }

    private var statusHeader: some View {
        HStack {
            Label("LOCAL DATA", systemImage: "lock.fill")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rinseBlue)
            Spacer()
            Text(model.sampleCount.formatted())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var captureDisplay: some View {
        switch model.phase {
        case .idle:
            VStack(spacing: 8) {
                ZoneGlyph(label: model.selectedLabel)
                    .frame(height: 54)
                Text(model.selectedLabel.displayName)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.enamel)
                Text("10 seconds · 50 Hz request")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .countdown(let count):
            VStack(spacing: 4) {
                Text(count.formatted())
                    .font(.system(size: 58, weight: .black, design: .rounded))
                    .foregroundStyle(Color.recordCoral)
                    .contentTransition(.numericText())
                Text("Get into position")
                    .font(.caption)
                    .foregroundStyle(Color.enamel)
            }
        case .recording:
            VStack(spacing: 7) {
                Waveform(samples: model.waveform)
                    .frame(height: 54)
                HStack(alignment: .firstTextBaseline) {
                    Text(model.elapsed.formatted(.number.precision(.fractionLength(1))))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("/ 10s")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(Color.enamel)
                ProgressView(value: model.elapsed, total: 10)
                    .tint(Color.recordCoral)
            }
        case .saved(let count):
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 43))
                    .foregroundStyle(Color.mintSignal)
                Text("Saved \(count) samples")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.enamel)
                Text("Queued for iPhone")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            VStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(Color.recordCoral)
                Text(message)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.enamel)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            if !model.isBusy {
                NavigationLink {
                    LabelPicker(selection: $model.selectedLabel)
                } label: {
                    Label("Choose label", systemImage: "tag")
                }
                .buttonStyle(.bordered)

                Button {
                    model.begin(watchWrist: WatchWrist(rawValue: watchWrist))
                } label: {
                    Label(model.canRecordAgain ? "Record again" : "Record 10 seconds", systemImage: "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.recordCoral)

                Picker("Watch wrist", selection: $watchWrist) {
                    Text("Left wrist").tag(WatchWrist.left.rawValue)
                    Text("Right wrist").tag(WatchWrist.right.rawValue)
                }
                .font(.caption)
            } else {
                Button(role: .destructive) {
                    model.cancel()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private struct LabelPicker: View {
    @Binding var selection: BrushZoneLabel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(BrushZoneLabel.allCases) { label in
            Button {
                selection = label
                dismiss()
            } label: {
                HStack {
                    ZoneDot(label: label)
                    Text(label.displayName)
                    Spacer()
                    if selection == label {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.rinseBlue)
                    }
                }
            }
        }
        .navigationTitle("Trace label")
    }
}

private struct ZoneGlyph: View {
    let label: BrushZoneLabel

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<6, id: \.self) { index in
                Capsule()
                    .fill(index == selectedIndex ? Color.rinseBlue : Color.enamel.opacity(0.13))
                    .frame(width: index == selectedIndex ? 19 : 12, height: index == selectedIndex ? 43 : 31)
                    .rotationEffect(.degrees(Double(index - 2) * 7))
            }
        }
        .accessibilityLabel(label.displayName)
    }

    private var selectedIndex: Int {
        switch label {
        case .upperRight: 0
        case .upperCentre: 1
        case .upperLeft: 2
        case .lowerLeft: 3
        case .lowerCentre: 4
        case .lowerRight: 5
        case .transition: 2
        case .idle: 3
        }
    }
}

private struct ZoneDot: View {
    let label: BrushZoneLabel

    var body: some View {
        Circle()
            .fill(label == .idle ? Color.secondary : label == .transition ? Color.recordCoral : Color.rinseBlue)
            .frame(width: 9, height: 9)
    }
}

private struct Waveform: View {
    let samples: [Double]

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                guard samples.count > 1 else { return }
                for (index, sample) in samples.enumerated() {
                    let x = proxy.size.width * Double(index) / Double(samples.count - 1)
                    let normalized = min(1, sample / 1.4)
                    let y = proxy.size.height * (0.5 - normalized * 0.42)
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Color.rinseBlue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
