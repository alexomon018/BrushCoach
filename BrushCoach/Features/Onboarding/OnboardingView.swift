import BrushKit
import SwiftUI

struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var step = 0
    @State private var settings = RoutineSettings.shared
    let complete: () -> Void

    private static let stepCount = 3

    private var canAdvance: Bool {
        step != 1 || settings.preferences.brushingHand != nil
    }

    var body: some View {
        ZStack {
            onboardingBackground

            VStack(spacing: 18) {
                progressHeader

                ScrollView {
                    pageContent
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)

                Button(primaryTitle, action: advance)
                    .buttonStyle(CompanionPrimaryButtonStyle())
                    .disabled(!canAdvance)
                    .accessibilityHint(step == 1 && !canAdvance ? "Choose your brushing hand first" : "")
            }
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, horizontalSizeClass == .regular ? 28 : 24)
            .padding(.vertical, 16)
        }
        .preferredColorScheme(.dark)
    }

    private var onboardingBackground: some View {
        ZStack {
            Color.deepInk
            RadialGradient(
                colors: [Color.rinseBlue.opacity(0.2), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 390
            )
            LinearGradient(
                colors: [.clear, Color.mintFresh.opacity(0.055)],
                startPoint: .center,
                endPoint: .bottomLeading
            )
        }
        .ignoresSafeArea()
    }

    private var progressHeader: some View {
        VStack(spacing: 12) {
            HStack {
                if step > 0 {
                    Button(action: goBack) {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.weight(.bold))
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Previous step")
                } else {
                    Label("BRUSHCOACH", systemImage: "sparkles")
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(Color.mintFresh)
                }

                Spacer()

                Text("\(step + 1) OF \(Self.stepCount)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.56))
            }
            .frame(height: 34)

            HStack(spacing: 7) {
                ForEach(0..<Self.stepCount, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Color.mintFresh : .white.opacity(0.14))
                        .frame(height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step + 1) of \(Self.stepCount)")
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        Group {
            switch step {
            case 0: welcomeStep
            case 1: handStep
            default: readyStep
            }
        }
        .id(step)
        .transition(reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }

    private var welcomeStep: some View {
        VStack(spacing: 22) {
            ToothMascotView(mood: .ready, action: .idle, darkBackdrop: true)
                .frame(width: 148, height: 154)

            onboardingCopy(
                eyebrow: "YOUR WRIST-SIZED COACH",
                title: "Two minutes that stay on track.",
                body: "BrushCoach guides the pace so you can focus on gentle, thorough brushing."
            )

            HStack(spacing: 10) {
                OnboardingStat(value: "2 min", label: "total", systemImage: "timer")
                OnboardingStat(value: "6", label: "zones", systemImage: "circle.hexagongrid.fill")
                OnboardingStat(value: "20 sec", label: "each", systemImage: "applewatch.radiowaves.left.and.right")
            }
        }
    }

    private var handStep: some View {
        VStack(spacing: 20) {
            ToothMascotView(mood: .cheery, action: .brushing, darkBackdrop: true)
                .frame(width: 96, height: 102)

            VStack(spacing: 10) {
                Text("REQUIRED · ONE QUESTION")
                    .font(.companionEyebrow)
                    .tracking(1.35)
                    .foregroundStyle(Color.mintFresh)

                Text("Which hand holds your brush?")
                    .font(.system(size: 32, weight: .semibold, design: .serif))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)

                Text("This tells BrushCoach when your Watch can check strokes—and when it should simply guide the pace.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.68))
                    .lineSpacing(3)
            }

            HStack(spacing: 12) {
                ForEach(BrushingHand.allCases, id: \.self) { hand in
                    HandChoiceButton(
                        hand: hand,
                        isSelected: settings.preferences.brushingHand == hand
                    ) {
                        withAnimation(.snappy(duration: 0.28)) {
                            settings.preferences.brushingHand = hand
                        }
                    }
                }
            }

            Label("You can change this later in Routine", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.52))
        }
    }

    private var readyStep: some View {
        VStack(spacing: 20) {
            ToothMascotView(mood: .proud, action: .success, darkBackdrop: true)
                .frame(width: 116, height: 122)

            onboardingCopy(
                eyebrow: "READY WHEN YOU ARE",
                title: "Your routine is ready.",
                body: "Start from iPhone or Watch. Your wrist handles the pacing and your progress returns here."
            )

            VStack(spacing: 0) {
                ReadyRow(systemImage: "applewatch", title: "Guided on Watch", detail: "A gentle tap moves to each zone")
                Divider().overlay(.white.opacity(0.1))
                ReadyRow(systemImage: "moon.zzz.fill", title: "Wrist-down reliable", detail: "The timer follows real elapsed time")
                Divider().overlay(.white.opacity(0.1))
                ReadyRow(systemImage: "iphone.gen3", title: "Saved on iPhone", detail: "History stays private and close by")
            }
            .padding(.horizontal, 16)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            }

            VStack(spacing: 3) {
                Text("OPTIONAL, LATER")
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(Color.rinseBlue)
                Text("Add reminders, Apple Health, or experimental calibration only when they are useful to you.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.52))
            }
        }
    }

    private func onboardingCopy(eyebrow: String, title: String, body: String) -> some View {
        VStack(spacing: 11) {
            Text(eyebrow)
                .font(.companionEyebrow)
                .tracking(1.4)
                .foregroundStyle(Color.rinseBlue)
            Text(title)
                .font(.system(size: 36, weight: .semibold, design: .serif))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Text(body)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.68))
                .lineSpacing(3)
        }
    }

    private var primaryTitle: String {
        switch step {
        case 0: "See how it works"
        case 1: settings.preferences.brushingHand == nil ? "Choose a hand" : "Use this hand"
        default: "Open BrushCoach"
        }
    }

    private func advance() {
        guard canAdvance else { return }
        guard step < Self.stepCount - 1 else {
            complete()
            return
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
            step += 1
        }
    }

    private func goBack() {
        guard step > 0 else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
            step -= 1
        }
    }
}

private struct OnboardingStat: View {
    let value: String
    let label: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.mintFresh)
            VStack(spacing: 1) {
                Text(value)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 86)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.09), lineWidth: 1)
        }
    }
}

private struct ReadyRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.mintFresh)
                .frame(width: 36, height: 36)
                .background(Color.mintFresh.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 58)
    }
}

private struct HandChoiceButton: View {
    let hand: BrushingHand
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 25, weight: .medium))
                        .scaleEffect(x: hand == .left ? -1 : 1)
                        .frame(width: 48, height: 48)
                        .background(isSelected ? .white.opacity(0.25) : .white.opacity(0.07), in: Circle())

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 17, weight: .bold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.deepInk, Color.mintFresh)
                            .offset(x: 5, y: -3)
                    }
                }

                Text(hand.displayName)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .foregroundStyle(isSelected ? Color.deepInk : .white)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? Color.mintFresh : .white.opacity(0.07))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isSelected ? .clear : .white.opacity(0.13), lineWidth: 1)
            }
        }
        .buttonStyle(TactileCardButtonStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
