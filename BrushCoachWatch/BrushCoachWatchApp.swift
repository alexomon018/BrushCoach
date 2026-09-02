import SwiftUI

@main
struct BrushCoachWatchApp: App {
    @AppStorage("hasSeenWatchOnboarding") private var hasSeenOnboarding = false
    @State private var model = CoachViewModel()
    @State private var handledLaunchArguments = false

    init() {
        WatchTraceTransfer.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if hasSeenOnboarding {
                    CoachView(model: model)
                } else {
                    WatchOnboardingView {
                        hasSeenOnboarding = true
                        model.startSession()
                    }
                }
            }
            .onOpenURL {
                hasSeenOnboarding = true
                model.handle(url: $0)
            }
            .task {
                guard !handledLaunchArguments else { return }
                handledLaunchArguments = true
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-startSession") {
                    hasSeenOnboarding = true
                    model.startSession()
                }
                #endif
            }
        }
    }
}

private struct WatchOnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    let start: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.watchInk, .watchInk, .watchBlue.opacity(0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ViewThatFits(in: .vertical) {
                content(compact: false)
                content(compact: true)
            }
        }
        .navigationBarBackButtonHidden()
    }

    private func content(compact: Bool) -> some View {
        VStack(spacing: compact ? 6 : WatchMetrics.sectionSpacing) {
            progress

            Spacer(minLength: 0)

            Group {
                if step == 0 {
                    pacingStep(compact: compact)
                } else {
                    wristDownStep(compact: compact)
                }
            }
            .id(step)
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            Spacer(minLength: 0)

            Button(step == 0 ? "Continue" : "Start first brush") {
                if step == 0 {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) { step = 1 }
                } else {
                    start()
                }
            }
            .watchPrimaryControl(tint: .watchMint, foreground: .watchInk)
        }
        .watchPageFrame()
        .padding(.top, 18)
    }

    private var progress: some View {
        HStack(spacing: 6) {
            if step > 0 {
                Button {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) { step = 0 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous step")
            }

            ForEach(0..<2, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? Color.watchMint : .white.opacity(0.15))
                    .frame(height: 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step + 1) of 2")
    }

    private func pacingStep(compact: Bool) -> some View {
        VStack(spacing: compact ? 5 : 8) {
            OnboardingZoneRail()
                .frame(height: 42)
            Text("Two minutes, your way")
                .font(.watchScreenTitle)
                .multilineTextAlignment(.center)
            Text("Brush freely. After calibration, six mouth areas are tracked automatically.")
                .font(.system(size: compact ? 9 : 10))
                .foregroundStyle(.white.opacity(0.64))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func wristDownStep(compact: Bool) -> some View {
        VStack(spacing: compact ? 5 : 8) {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: compact ? 28 : 34, weight: .semibold))
                .foregroundStyle(Color.watchMint)
                .symbolEffect(.pulse)
            Text("Lower your wrist")
                .font(.watchScreenTitle)
                .multilineTextAlignment(.center)
            Text("Keep brushing. The timer follows real time and sends the result to iPhone.")
                .font(.system(size: compact ? 9 : 10))
                .foregroundStyle(.white.opacity(0.64))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OnboardingZoneRail: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<6, id: \.self) { index in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(index == 0 ? Color.watchMint : .white.opacity(0.13))
                    .frame(height: height(for: index))
            }
        }
        .accessibilityHidden(true)
    }

    private func height(for index: Int) -> CGFloat {
        switch index { case 0, 5: 23; case 1, 4: 32; default: 41 }
    }
}
