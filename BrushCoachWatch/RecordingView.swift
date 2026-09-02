import BrushKit
import SwiftUI

struct RecordingView: View {
    @State private var model = RecordingViewModel()
    @AppStorage("recordingWatchWrist") private var watchWrist = WatchWrist.left.rawValue
    @AppStorage("recordingDurationSeconds") private var durationSeconds = Int(RecordingViewModel.defaultDuration)

    var body: some View {
        ScrollView {
            VStack(spacing: WatchMetrics.sectionSpacing) {
                statusHeader
                captureDisplay
                    .watchPanel()
                controls
            }
            // The wrist and length rows sit at the very bottom of the scroll, so
            // the page needs more clearance than the default before the bezel.
            .watchPageFrame(bottom: 16)
        }
        .background(Color.captureInk.ignoresSafeArea())
        .navigationTitle("Capture")
    }

    private var statusHeader: some View {
        HStack {
            Label("LOCAL DATA", systemImage: "lock.fill")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.captureBlue)
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
            VStack(spacing: 6) {
                ZoneGlyph(label: model.selectedLabel)
                    .frame(height: 40)
                Text(model.selectedLabel.displayName)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.enamel)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                // Kept to one line: the spelled-out version wrapped mid-unit
                // ("50 / Hz request") inside the panel.
                Text("\(durationSeconds)s · 50 Hz")
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
                    Text("/ \(Int(model.duration))s")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(Color.enamel)
                ProgressView(value: model.elapsed, total: model.duration)
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
        VStack(spacing: WatchMetrics.componentSpacing) {
            if model.isBusy {
                Button(role: .destructive) {
                    model.cancel()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                .watchSecondaryControl(tint: .recordCoral)
            } else {
                NavigationLink {
                    LabelPicker(selection: $model.selectedLabel)
                } label: {
                    Label("Choose label", systemImage: "tag")
                }
                .watchSecondaryControl(tint: .captureBlue)

                Button {
                    model.begin(
                        duration: TimeInterval(durationSeconds),
                        watchWrist: WatchWrist(rawValue: watchWrist)
                    )
                } label: {
                    Label(
                        model.canRecordAgain ? "Record again" : "Record \(durationSeconds) seconds",
                        systemImage: "record.circle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .watchPrimaryControl(tint: .recordCoral)

                // Both settings push their own list. The inline wheel style ran
                // off the bottom of the scroll view and overlapped the controls
                // above it.
                Picker("Capture length", selection: $durationSeconds) {
                    ForEach(RecordingViewModel.durationOptions, id: \.self) { seconds in
                        Text("\(seconds) seconds").tag(seconds)
                    }
                }
                .pickerStyle(.navigationLink)

                Picker("Watch wrist", selection: $watchWrist) {
                    Text("Left wrist").tag(WatchWrist.left.rawValue)
                    Text("Right wrist").tag(WatchWrist.right.rawValue)
                }
                .pickerStyle(.navigationLink)
            }
        }
        .tint(Color.captureBlue)
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
                            .foregroundStyle(Color.captureBlue)
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
                    .fill(index == selectedIndex ? Color.captureBlue : Color.enamel.opacity(0.13))
                    .frame(width: index == selectedIndex ? 16 : 10, height: index == selectedIndex ? 34 : 25)
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
            .fill(label == .idle ? Color.secondary : label == .transition ? Color.recordCoral : Color.captureBlue)
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
            .stroke(Color.captureBlue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
