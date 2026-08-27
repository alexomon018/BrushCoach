import SwiftUI

struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    let complete: () -> Void

    private static let pages = [
        OnboardingPage(
            icon: "timer",
            eyebrow: "THE ROUTINE",
            title: "Two minutes. Twice daily.",
            body: "Six zones keep the full mouth moving, with a clear haptic every 20 seconds.",
            mood: .ready,
            action: .idle
        ),
        OnboardingPage(
            icon: "angle",
            eyebrow: "THE TECHNIQUE",
            title: "Meet the gumline gently.",
            body: "Use fluoride toothpaste and a soft-bristled brush. Hold it around 45° and move in short, gentle strokes.",
            mood: .cheery,
            action: .brushing
        ),
        OnboardingPage(
            icon: "applewatch",
            eyebrow: "THE COACH",
            title: "Lower your wrist. Keep brushing.",
            body: "The Watch session follows real elapsed time, even when the display sleeps. Your history stays local and can be written to Apple Health.",
            mood: .proud,
            action: .protection
        )
    ]

    private var current: OnboardingPage { Self.pages[page] }

    var body: some View {
        ZStack {
            Color.deepInk.ignoresSafeArea()
            VStack(spacing: 30) {
                pageIndicator
                Spacer()
                pageContent
                Spacer()
                Button(page == Self.pages.count - 1 ? "Set up my routine" : "Continue", action: advance)
                    .buttonStyle(PrimaryCapsuleButtonStyle())
            }
            .padding(24)
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
            Text("ADA-ALIGNED")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Color.rinseBlue)
        }
    }

    private var pageContent: some View {
        VStack(spacing: 22) {
            ToothMascotView(mood: current.mood, action: current.action, darkBackdrop: true)
                .frame(width: 132, height: 140)
            Image(systemName: current.icon)
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(Color.mintFresh)
            VStack(spacing: 12) {
                Text(current.eyebrow)
                    .font(.caption.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(Color.rinseBlue)
                Text(current.title)
                    .font(.system(size: 38, weight: .semibold, design: .serif))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                Text(current.body)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.68))
                    .lineSpacing(4)
            }
        }
        .id(page)
        .transition(reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }

    private func advance() {
        guard page < Self.pages.count - 1 else {
            complete()
            return
        }
        withAnimation(.spring(response: 0.52, dampingFraction: 0.84)) { page += 1 }
    }
}

private struct OnboardingPage {
    let icon: String
    let eyebrow: String
    let title: String
    let body: String
    let mood: ToothMood
    let action: ToothAction
}
