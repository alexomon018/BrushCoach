import BrushKit
import SwiftUI

struct CalibrationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = CalibrationViewModel()

    var body: some View {
        ZStack {
            Color.watchInk.ignoresSafeArea()
            switch model.phase {
            case .intro:
                IntroView(model: model)
            case .baseline(let remaining):
                StageView(
                    eyebrow: "HOLD STILL",
                    title: "Rest your arm",
                    detail: "Let BrushCoach learn what not-brushing looks like.",
                    seconds: remaining,
                    tint: .watchBlue,
                    windows: model.stageWindows
                )
            case .reposition(let index, let remaining):
                StageView(
                    eyebrow: "NEXT UP",
                    title: model.zoneNames[index],
                    detail: "Move the brush into place.",
                    seconds: remaining,
                    tint: .watchBlue,
                    windows: nil
                )
            case .capturing(let index, let remaining):
                StageView(
                    eyebrow: "BRUSH NORMALLY",
                    title: model.zoneNames[index],
                    detail: "Move as you actually would. Don't watch the screen.",
                    seconds: remaining,
                    tint: .watchMint,
                    windows: model.stageWindows
                )
            case .building:
                BuildingView()
            case .complete(let quality):
                CompleteView(quality: quality) { dismiss() }
            case .failed(let message):
                FailedView(message: message, retry: model.start) { dismiss() }
            }
        }
        .navigationTitle("Calibrate")
        .navigationBarBackButtonHidden(model.isRunning)
        .toolbar {
            if model.isRunning {
                ToolbarItem(placement: .topBarLeading) {
                    Button { model.cancel() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel calibration")
                }
            }
        }
        .onDisappear { model.cancel() }
    }
}

private struct IntroView: View {
    @Bindable var model: CalibrationViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "wand.and.rays")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.watchMint)
                Text("Teach your technique")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("About \(model.estimatedMinutes) minutes. Hold still, then brush each zone when prompted. Brush the way you normally do.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)

                Label("Stays on this Watch", systemImage: "lock.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.watchBlue)

                Button("Start", action: model.start)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.watchMint)
                    .foregroundStyle(Color.watchInk)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 8)
        }
    }
}

private struct StageView: View {
    let eyebrow: String
    let title: String
    let detail: String
    let seconds: Int
    let tint: Color
    /// `nil` hides the capture indicator during stages that collect nothing.
    let windows: Int?

    var body: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            Text(eyebrow)
                .font(.system(size: 9, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(tint)
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(seconds.formatted())
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(tint)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if let windows {
                Label("\(windows) captured", systemImage: windows > 0 ? "waveform" : "waveform.slash")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(windows > 0 ? Color.watchMint : Color.watchCoral)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .accessibilityElement(children: .combine)
    }
}

private struct BuildingView: View {
    var body: some View {
        VStack(spacing: 8) {
            ProgressView().tint(Color.watchMint)
            Text("Building your profile")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

private struct CompleteView: View {
    let quality: Double
    let done: () -> Void

    /// Named for what it measures. A high score means the six captures looked
    /// distinct from each other, which is a precondition for zone estimates
    /// working — not evidence that they will.
    private var verdict: (title: String, detail: String, tint: Color) {
        switch quality {
        case 0.8...:
            ("Clearly distinct", "Your six zones looked different from each other.", .watchMint)
        case 0.55..<0.8:
            ("Partly distinct", "Some zones looked alike. Estimates will often stay hidden.", .watchBlue)
        default:
            ("Hard to tell apart", "Your zones looked very similar. Expect few estimates.", .watchCoral)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(verdict.tint)
                Text(verdict.title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text((quality * 100).formatted(.number.precision(.fractionLength(0))) + "% separation")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(verdict.tint)
                Text(verdict.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                Text("Zone estimates are experimental and are never used to decide whether a session counted.")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                Button("Done", action: done)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.watchBlue)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 8)
        }
    }
}

private struct FailedView: View {
    let message: String
    let retry: () -> Void
    let back: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.watchCoral)
                Text(message)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.8))
                Button("Try again", action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.watchMint)
                    .foregroundStyle(Color.watchInk)
                Button("Back", action: back)
                    .buttonStyle(.bordered)
                    .tint(Color.watchBlue)
            }
            .padding(.horizontal, 8)
        }
    }
}
