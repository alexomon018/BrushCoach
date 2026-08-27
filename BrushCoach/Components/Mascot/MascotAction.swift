import SwiftUI

enum ToothMood {
    case ready, cheery, proud, waiting
}

enum ToothAction {
    case idle, brushing, success, bedtime, protection, flossing, rinsing
}

/// Resolves whether the mascot's looping animations should run at all.
///
/// Repeating animations pin Core Animation to the display refresh rate for as
/// long as they exist, so they are stopped whenever the mascot is off-screen,
/// the app is backgrounded, or the user has asked for reduced motion.
struct MascotAnimationGate {
    let isOnScreen: Bool
    let scenePhase: ScenePhase
    let reduceMotion: Bool

    var isRunning: Bool { isOnScreen && scenePhase == .active && !reduceMotion }
}

extension View {
    /// Drives a looping animation flag, cancelling the loop outright when `running` is false.
    func mascotLoop(
        running: Bool,
        animation: Animation,
        flag: Binding<Bool>
    ) -> some View {
        onChange(of: running, initial: true) { _, isRunning in
            guard isRunning else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { flag.wrappedValue = false }
                return
            }
            withAnimation(animation) { flag.wrappedValue = true }
        }
    }
}
