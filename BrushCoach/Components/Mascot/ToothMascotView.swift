import SwiftUI

/// The hand-drawn tooth mascot.
///
/// Every looping animation in this tree is gated on `isOnScreen`. A
/// `repeatForever` animation keeps Core Animation committing frames for as long
/// as it exists, so leaving one running on a hidden tab costs the whole app its
/// frame budget — which is what made scrolling elsewhere feel heavy.
struct ToothMascotView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    let mood: ToothMood
    var action = ToothAction.idle
    var darkBackdrop = false
    /// False while the mascot is on a tab or screen the user is not looking at.
    var isOnScreen = true

    @State private var floating = false
    @State private var sleepyRock = false

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                MascotParticles(size: size, action: action, running: running)
                MascotArms(size: size, action: action)
                MascotBody(
                    size: size,
                    mood: mood,
                    action: action,
                    darkBackdrop: darkBackdrop,
                    running: running
                )
                MascotProp(size: size, action: action, running: running)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(y: reduceMotion ? 0 : (floating ? -2.5 : 2.5))
            .rotationEffect(.degrees(bodyRotation))
        }
        .mascotLoop(
            running: running,
            animation: .easeInOut(duration: 2.2).repeatForever(autoreverses: true),
            flag: $floating
        )
        .mascotLoop(
            running: running && action == .bedtime,
            animation: .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
            flag: $sleepyRock
        )
        .accessibilityHidden(true)
    }

    private var running: Bool {
        MascotAnimationGate(
            isOnScreen: isOnScreen,
            scenePhase: scenePhase,
            reduceMotion: reduceMotion
        ).isRunning
    }

    private var bodyRotation: Double {
        guard !reduceMotion else { return 0 }
        if action == .bedtime { return sleepyRock ? 3.2 : -3.2 }
        return floating ? 1.2 : -1.2
    }
}

private struct MascotBody: View {
    let size: CGFloat
    let mood: ToothMood
    let action: ToothAction
    let darkBackdrop: Bool
    let running: Bool

    @State private var popped = false

    var body: some View {
        ToothShape()
            .fill(.white)
            // Shadowing the filled shape rather than the composed group lets Core
            // Animation use its shadow-path fast path instead of an offscreen pass.
            .shadow(
                color: darkBackdrop ? .black.opacity(0.3) : Color.deepInk.opacity(0.16),
                radius: size * 0.11,
                y: size * 0.075
            )
            .overlay {
                ToothShape()
                    .stroke(Color.deepInk, lineWidth: max(1.5, size * 0.018))
            }
            .overlay {
                ToothShape()
                    .stroke(
                        Color.sketchLavender.opacity(0.38),
                        style: StrokeStyle(
                            lineWidth: max(1, size * 0.008),
                            lineCap: .round,
                            dash: [size * 0.018, size * 0.036]
                        )
                    )
                    .padding(size * 0.018)
            }
            .frame(width: size * 0.67, height: size * 0.76)
            .overlay {
                MascotFace(
                    width: size * 0.67,
                    height: size * 0.76,
                    mood: mood,
                    action: action,
                    running: running
                )
            }
            .scaleEffect(popped ? 1 : 0.84)
            .offset(y: popped ? 0 : size * 0.09)
            .onAppear(perform: syncPop)
            .onChange(of: action) { _, _ in syncPop() }
    }

    private func syncPop() {
        guard action == .success, running else {
            popped = true
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { popped = false }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.54)) { popped = true }
    }
}

/// Owns the blink loop so a blink invalidates the face alone, not the arms,
/// props and particles as well.
private struct MascotFace: View {
    let width: CGFloat
    let height: CGFloat
    let mood: ToothMood
    let action: ToothAction
    let running: Bool

    @State private var blinking = false

    var body: some View {
        let eyesClosed = action == .bedtime || mood == .proud || blinking

        ZStack {
            HStack(spacing: width * 0.18) {
                eye(closed: eyesClosed)
                eye(closed: eyesClosed)
            }
            .offset(y: -height * 0.07)

            MouthShape(smiling: mood != .waiting || action == .bedtime)
                .stroke(
                    Color.deepInk,
                    style: StrokeStyle(lineWidth: max(1.5, width * 0.027), lineCap: .round)
                )

            HStack(spacing: width * 0.34) {
                Circle().fill(Color.sketchLavender.opacity(0.32))
                Circle().fill(Color.sketchLavender.opacity(0.32))
            }
            .frame(width: width * 0.58)
            .offset(y: height * 0.02)
        }
        .task(id: blinkLoopID) { await runBlinkLoop() }
    }

    private var blinkLoopID: Bool { running && action != .bedtime }

    private func eye(closed: Bool) -> some View {
        Capsule()
            .fill(Color.deepInk)
            .frame(width: width * 0.04, height: closed ? width * 0.025 : width * 0.08)
            .animation(running ? .easeInOut(duration: 0.09) : nil, value: closed)
    }

    private func runBlinkLoop() async {
        guard blinkLoopID else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2.7))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.08)) { blinking = true }
            try? await Task.sleep(for: .milliseconds(130))
            withAnimation(.easeInOut(duration: 0.08)) { blinking = false }
        }
    }
}

private struct MouthShape: Shape {
    let smiling: Bool

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let mouthWidth = width * 0.18
        let y = height * 0.56
        return Path { path in
            path.move(to: CGPoint(x: width * 0.5 - mouthWidth / 2, y: y))
            if smiling {
                path.addQuadCurve(
                    to: CGPoint(x: width * 0.5 + mouthWidth / 2, y: y),
                    control: CGPoint(x: width * 0.5, y: y + height * 0.07)
                )
            } else {
                path.addLine(to: CGPoint(x: width * 0.5 + mouthWidth / 2, y: y))
            }
        }
    }
}

private struct MascotArms: View {
    let size: CGFloat
    let action: ToothAction

    var body: some View {
        ZStack {
            arm(.left)
            arm(.right)
            hand(.left)
            hand(.right)
        }
    }

    private enum ArmSide { case left, right }

    private func arm(_ side: ArmSide) -> some View {
        armPath(side)
            .stroke(Color.deepInk, style: StrokeStyle(lineWidth: max(1.5, size * 0.017), lineCap: .round))
    }

    private func hand(_ side: ArmSide) -> some View {
        Circle()
            .fill(Color.deepInk)
            .frame(width: size * 0.045, height: size * 0.045)
            .position(endpoint(side))
    }

    private func armPath(_ side: ArmSide) -> Path {
        let start = CGPoint(x: size * (side == .left ? 0.22 : 0.78), y: size * 0.53)
        let end = endpoint(side)
        let control = CGPoint(
            x: (start.x + end.x) / 2 + size * (side == .left ? -0.045 : 0.045),
            y: min(start.y, end.y) - size * 0.035
        )
        return Path { path in
            path.move(to: start)
            path.addQuadCurve(to: end, control: control)
        }
    }

    private func endpoint(_ side: ArmSide) -> CGPoint {
        let isLeft = side == .left
        switch action {
        case .idle:
            return CGPoint(x: size * (isLeft ? 0.12 : 0.88), y: size * 0.59)
        case .brushing:
            return CGPoint(x: size * (isLeft ? 0.36 : 0.64), y: size * 0.64)
        case .success:
            return CGPoint(x: size * (isLeft ? 0.1 : 0.9), y: size * 0.24)
        case .bedtime:
            return CGPoint(x: size * (isLeft ? 0.15 : 0.85), y: size * 0.6)
        case .protection:
            return CGPoint(x: size * (isLeft ? 0.13 : 0.79), y: size * 0.62)
        case .flossing:
            return CGPoint(x: size * (isLeft ? 0.36 : 0.64), y: size * 0.43)
        case .rinsing:
            return CGPoint(x: size * (isLeft ? 0.14 : 0.72), y: size * (isLeft ? 0.61 : 0.55))
        }
    }
}
