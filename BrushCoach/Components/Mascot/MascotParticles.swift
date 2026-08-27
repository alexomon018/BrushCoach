import SwiftUI

/// Sparkles, bubbles, confetti and droplets. Split out of the mascot root so the
/// body float and the blink loop never re-evaluate these paths.
struct MascotParticles: View {
    let size: CGFloat
    let action: ToothAction
    let running: Bool

    var body: some View {
        Sparkle(size: size, x: 0.1, y: 0.18, delay: 0, color: sparkleColor, running: running)
        Sparkle(size: size, x: 0.88, y: 0.31, delay: 0.25, color: sparkleColor, running: running)

        switch action {
        case .brushing:
            Bubble(size: size, scale: 0.055, x: 0.34, delay: 0, running: running)
            Bubble(size: size, scale: 0.075, x: 0.52, delay: 0.22, running: running)
            Bubble(size: size, scale: 0.045, x: 0.66, delay: 0.46, running: running)
        case .success:
            Confetti(size: size, x: 0.16, y: 0.25, rotation: -32, color: .achievementGold, running: running)
            Confetti(size: size, x: 0.28, y: 0.12, rotation: 18, color: .mintFresh, running: running)
            Confetti(size: size, x: 0.73, y: 0.13, rotation: -18, color: .achievementGold, running: running)
            Confetti(size: size, x: 0.86, y: 0.27, rotation: 36, color: .sketchLavender, running: running)
        case .bedtime:
            Image(systemName: "moon.stars")
                .font(.system(size: size * 0.14, weight: .medium))
                .foregroundStyle(Color.sketchLavender.opacity(0.7))
                .position(x: size * 0.86, y: size * 0.18)
        case .rinsing:
            RinseDrop(size: size, scale: 0.035, x: 0.73, y: 0.31, delay: 0, running: running)
            RinseDrop(size: size, scale: 0.05, x: 0.82, y: 0.24, delay: 0.2, running: running)
            RinseDrop(size: size, scale: 0.03, x: 0.89, y: 0.34, delay: 0.38, running: running)
        case .idle, .protection, .flossing:
            EmptyView()
        }
    }

    private var sparkleColor: Color {
        switch action {
        case .success, .protection: .achievementGold
        case .bedtime: Color.rinseBlue.opacity(0.35)
        default: .mintFresh
        }
    }
}

private struct Sparkle: View {
    let size: CGFloat
    let x: CGFloat
    let y: CGFloat
    let delay: Double
    let color: Color
    let running: Bool

    @State private var twinkling = false

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size * 0.11, weight: .semibold))
            .foregroundStyle(color)
            .scaleEffect(twinkling ? 1 : 0.72)
            .opacity(twinkling ? 1 : 0.55)
            .position(x: size * x, y: size * y)
            .mascotLoop(
                running: running,
                animation: .easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(delay),
                flag: $twinkling
            )
    }
}

private struct Bubble: View {
    let size: CGFloat
    let scale: CGFloat
    let x: CGFloat
    let delay: Double
    let running: Bool

    @State private var rising = false

    var body: some View {
        Circle()
            .fill(Color.mintFresh.opacity(0.17))
            .overlay {
                Circle().stroke(Color.rinseBlue.opacity(0.62), lineWidth: max(1, size * 0.008))
            }
            .frame(width: size * scale, height: size * scale)
            .position(x: size * x, y: size * 0.48)
            .offset(y: rising ? -size * 0.31 : size * 0.12)
            .opacity(rising ? 0 : 0.9)
            .mascotLoop(
                running: running,
                animation: .easeOut(duration: 1.25).repeatForever(autoreverses: false).delay(delay),
                flag: $rising
            )
    }
}

private struct Confetti: View {
    let size: CGFloat
    let x: CGFloat
    let y: CGFloat
    let rotation: Double
    let color: Color
    let running: Bool

    @State private var celebrating = false

    var body: some View {
        Capsule()
            .fill(color)
            .frame(width: size * 0.025, height: size * 0.09)
            .rotationEffect(.degrees(rotation))
            .position(x: size * x, y: size * y)
            .scaleEffect(celebrating ? 1 : 0.2)
            .opacity(celebrating ? 1 : 0)
            .onAppear {
                guard running else {
                    celebrating = true
                    return
                }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.54)) { celebrating = true }
            }
    }
}

private struct RinseDrop: View {
    let size: CGFloat
    let scale: CGFloat
    let x: CGFloat
    let y: CGFloat
    let delay: Double
    let running: Bool

    @State private var lifting = false

    var body: some View {
        Circle()
            .fill(Color.rinseBlue.opacity(0.72))
            .frame(width: size * scale, height: size * scale)
            .position(x: size * x, y: size * y)
            .offset(y: lifting ? -size * 0.06 : size * 0.04)
            .opacity(lifting ? 0.28 : 0.9)
            .mascotLoop(
                running: running,
                animation: .easeInOut(duration: 0.8).repeatForever(autoreverses: true).delay(delay),
                flag: $lifting
            )
    }
}
