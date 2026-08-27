import SwiftUI

/// The object the mascot is holding. Each prop owns its own looping state so a
/// blink or a float tick never re-evaluates the prop's paths.
struct MascotProp: View {
    let size: CGFloat
    let action: ToothAction
    let running: Bool

    @State private var swinging = false
    @State private var shieldPresented = false
    @State private var flossing = false
    @State private var rinsing = false

    var body: some View {
        content
    }

    private func presentShield() {
        guard running else {
            shieldPresented = true
            return
        }
        withAnimation(.spring(response: 0.58, dampingFraction: 0.68).delay(0.12)) {
            shieldPresented = true
        }
    }

    @ViewBuilder
    private var content: some View {
        switch action {
        case .idle, .success:
            EmptyView()
        case .brushing:
            Toothbrush(size: size)
                .offset(y: size * 0.15)
                .rotationEffect(.degrees(swinging ? -55 : -28))
                .mascotLoop(
                    running: running,
                    animation: .easeInOut(duration: 0.17).repeatForever(autoreverses: true),
                    flag: $swinging
                )
        case .bedtime:
            Nightcap(size: size)
                .offset(x: -size * 0.11, y: -size * 0.3)
        case .protection:
            Shield(size: size)
                .offset(x: size * 0.31, y: size * 0.12)
                .offset(x: shieldPresented ? 0 : size * 0.23)
                .scaleEffect(shieldPresented ? 1 : 0.72)
                .opacity(shieldPresented ? 1 : 0)
                .onAppear(perform: presentShield)
        case .flossing:
            Floss(size: size)
                .offset(y: -size * 0.05)
                .rotationEffect(.degrees(flossing ? 4 : -4))
                .mascotLoop(
                    running: running,
                    animation: .easeInOut(duration: 0.48).repeatForever(autoreverses: true),
                    flag: $flossing
                )
        case .rinsing:
            RinseCup(size: size)
                .offset(x: size * 0.27, y: size * 0.04)
                .rotationEffect(.degrees(rinsing ? -14 : 2), anchor: .bottomLeading)
                .mascotLoop(
                    running: running,
                    animation: .easeInOut(duration: 0.82).repeatForever(autoreverses: true),
                    flag: $rinsing
                )
        }
    }
}

private struct Toothbrush: View {
    let size: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: size * 0.012) {
                ForEach(0..<4, id: \.self) { _ in
                    Capsule()
                        .fill(Color.mintFresh)
                        .frame(width: size * 0.018, height: size * 0.075)
                }
            }
            RoundedRectangle(cornerRadius: size * 0.025, style: .continuous)
                .fill(Color.sketchLavender)
                .frame(width: size * 0.075, height: size * 0.34)
                .overlay(alignment: .bottom) {
                    Circle()
                        .fill(.white.opacity(0.8))
                        .frame(width: size * 0.025)
                        .padding(.bottom, size * 0.035)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.025, style: .continuous)
                        .stroke(Color.deepInk, lineWidth: max(1, size * 0.009))
                }
        }
    }
}

private struct Floss: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: size * 0.04, y: size * 0.02))
                path.addQuadCurve(
                    to: CGPoint(x: size * 0.36, y: size * 0.02),
                    control: CGPoint(x: size * 0.2, y: size * 0.28)
                )
            }
            .stroke(
                Color.sketchLavender,
                style: StrokeStyle(lineWidth: max(1.2, size * 0.012), lineCap: .round)
            )

            HStack(spacing: size * 0.25) {
                flossHandle
                flossHandle
            }
            .offset(y: -size * 0.035)
        }
        .frame(width: size * 0.4, height: size * 0.27)
    }

    private var flossHandle: some View {
        Capsule()
            .fill(Color.achievementGold)
            .frame(width: size * 0.035, height: size * 0.11)
            .overlay { Capsule().stroke(Color.deepInk, lineWidth: max(1, size * 0.008)) }
    }
}

private struct RinseCup: View {
    let size: CGFloat

    var body: some View {
        RinseCupShape()
            .fill(Color.rinseBlue.opacity(0.9))
            .overlay {
                RinseCupShape().stroke(Color.deepInk, lineWidth: max(1.2, size * 0.011))
            }
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color.mintFresh)
                    .frame(width: size * 0.15, height: size * 0.025)
                    .padding(.top, size * 0.018)
            }
            .frame(width: size * 0.19, height: size * 0.23)
    }
}

private struct Nightcap: View {
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .trailing) {
            NightcapShape()
                .fill(Color.sketchLavender)
                .overlay {
                    NightcapShape().stroke(Color.deepInk, lineWidth: max(1.2, size * 0.012))
                }
            Circle()
                .fill(Color.mintFresh)
                .overlay { Circle().stroke(Color.deepInk, lineWidth: max(1, size * 0.009)) }
                .frame(width: size * 0.08, height: size * 0.08)
                .offset(x: size * 0.02, y: -size * 0.07)
        }
        .frame(width: size * 0.38, height: size * 0.22)
    }
}

private struct Shield: View {
    let size: CGFloat

    var body: some View {
        ShieldShape()
            .fill(Color.achievementGold.opacity(0.94))
            .overlay {
                ShieldShape().stroke(Color.deepInk, lineWidth: max(1.5, size * 0.014))
            }
            .overlay {
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.095, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: size * 0.28, height: size * 0.32)
    }
}
