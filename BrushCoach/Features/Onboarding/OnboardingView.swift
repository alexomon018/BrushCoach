import BrushKit
import SwiftUI

struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @State private var settings = RoutineSettings.shared
    let complete: () -> Void

    private static let pages: [OnboardingPage] = [
        OnboardingPage(
            kind: .message,
            icon: "timer",
            eyebrow: "THE ROUTINE",
            title: "Two minutes. Twice daily.",
            body: "Six zones keep the full mouth moving, with a clear haptic every 20 seconds.",
            mood: .ready,
            action: .idle
        ),
        OnboardingPage(
            kind: .message,
            icon: "angle",
            eyebrow: "THE TECHNIQUE",
            title: "Meet the gumline gently.",
            body: "Use fluoride toothpaste and a soft-bristled brush. Hold it around 45° and move in short, gentle strokes.",
            mood: .cheery,
            action: .brushing
        ),
        OnboardingPage(
            kind: .message,
            icon: "applewatch",
            eyebrow: "THE COACH",
            title: "Lower your wrist. Keep brushing.",
            body: "The Watch session follows real elapsed time, even when the display sleeps. Your history stays local and can be written to Apple Health.",
            mood: .proud,
            action: .protection
        ),
        OnboardingPage(
            kind: .handedness,
            icon: "hand.raised.fill",
            eyebrow: "ONE QUESTION",
            title: "Which hand holds the brush?",
            body: "Your Watch already knows which wrist it's on. If that's your brushing hand, BrushCoach can check your strokes — if not, it will say so instead of guessing.",
            mood: .cheery,
            action: .brushing
        )
    ]

    private var current: OnboardingPage { Self.pages[page] }

    private var canAdvance: Bool {
        current.kind == .message || settings.preferences.brushingHand != nil
    }

    var body: some View {
        ZStack {
            Color.deepInk.ignoresSafeArea()
            VStack(spacing: 26) {
                pageIndicator
                Spacer(minLength: 0)
                pageContent
                Spacer(minLength: 0)
                Button(primaryTitle, action: advance)
                    .buttonStyle(PrimaryCapsuleButtonStyle())
                    .disabled(!canAdvance)
                    .opacity(canAdvance ? 1 : 0.4)
            }
            .padding(24)
        }
    }

    private var primaryTitle: String {
        switch (page, current.kind) {
        case (_, .handedness):
            settings.preferences.brushingHand == nil ? "Choose a hand" : "Set up my routine"
        case (Self.pages.count - 1, _):
            "Set up my routine"
        default:
            "Continue"
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 7) {
            ForEach(Self.pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Color.mintFresh : .white.opacity(0.18))
                    .frame(width: index == page ? 34 : 9, height: 7)
            }
            Spacer()
            Text("BRUSH WELL")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Color.rinseBlue)
        }
    }

    private var pageContent: some View {
        VStack(spacing: 20) {
            ToothMascotView(mood: current.mood, action: current.action, darkBackdrop: true)
                .frame(width: current.kind == .handedness ? 96 : 132,
                       height: current.kind == .handedness ? 102 : 140)
            if current.kind == .message {
                Image(systemName: current.icon)
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(Color.mintFresh)
            }
            VStack(spacing: 12) {
                Text(current.eyebrow)
                    .font(.caption.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(Color.rinseBlue)
                Text(current.title)
                    .font(.system(size: current.kind == .handedness ? 32 : 38,
                                  weight: .semibold, design: .serif))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                Text(current.body)
                    .font(current.kind == .handedness ? .subheadline : .body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.68))
                    .lineSpacing(3)
            }
            if current.kind == .handedness {
                handChoice
            }
        }
        .id(page)
        .transition(reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }

    private var handChoice: some View {
        HStack(spacing: 12) {
            ForEach(BrushingHand.allCases, id: \.self) { hand in
                HandChoiceButton(
                    hand: hand,
                    isSelected: settings.preferences.brushingHand == hand
                ) {
                    settings.preferences.brushingHand = hand
                }
            }
        }
        .padding(.top, 4)
    }

    private func advance() {
        guard canAdvance else { return }
        guard page < Self.pages.count - 1 else {
            complete()
            return
        }
        withAnimation(.spring(response: 0.52, dampingFraction: 0.84)) { page += 1 }
    }
}

private struct HandChoiceButton: View {
    let hand: BrushingHand
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 8) {
                Image(systemName: hand == .left ? "hand.raised.fill" : "hand.raised.fill")
                    .font(.system(size: 22, weight: .medium))
                    .scaleEffect(x: hand == .left ? -1 : 1)
                Text(hand.displayName)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .foregroundStyle(isSelected ? Color.deepInk : .white)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.mintFresh : .white.opacity(0.08))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? .clear : .white.opacity(0.16), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct OnboardingPage {
    enum Kind { case message, handedness }

    let kind: Kind
    let icon: String
    let eyebrow: String
    let title: String
    let body: String
    let mood: ToothMood
    let action: ToothAction
}
