import SwiftUI

/// Marks when a screen's content first appeared, so rows that are scrolled into
/// view later can skip the entrance animation.
private struct RevealAnchorKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

extension EnvironmentValues {
    var revealAnchor: Date? {
        get { self[RevealAnchorKey.self] }
        set { self[RevealAnchorKey.self] = newValue }
    }
}

/// How long after a screen appears entrance animations stay eligible. Anything
/// appearing after this was scrolled into view, and animating it fights the scroll.
private let revealWindow: TimeInterval = 0.7

private struct RevealGroupModifier: ViewModifier {
    @State private var anchor = Date.now

    func body(content: Content) -> some View {
        content.environment(\.revealAnchor, anchor)
    }
}

private struct StaggeredRevealModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.revealAnchor) private var anchor
    @State private var revealed = false
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 14)
            .onAppear(perform: reveal)
    }

    private func reveal() {
        guard !revealed else { return }
        let scrolledIn = anchor.map { Date.now.timeIntervalSince($0) > revealWindow } ?? true
        guard !reduceMotion, !scrolledIn else {
            revealed = true
            return
        }
        withAnimation(.snappy(duration: 0.42, extraBounce: 0.04).delay(Double(index) * 0.055)) {
            revealed = true
        }
    }
}

extension View {
    /// Establishes the entrance-animation window for the contained `staggeredReveal` items.
    func revealGroup() -> some View {
        modifier(RevealGroupModifier())
    }

    func staggeredReveal(index: Int) -> some View {
        modifier(StaggeredRevealModifier(index: index))
    }
}
