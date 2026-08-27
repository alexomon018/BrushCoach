import SwiftUI

extension View {
    /// A card chrome that costs a single shadow pass.
    ///
    /// The shadow is attached to the filled shape *inside* `background`, so Core
    /// Animation can use its fast path for a known shape instead of rasterizing
    /// the whole composed card (fill + stroke + content) offscreen every frame.
    func premiumCard(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background {
            shape
                .fill(.white.opacity(0.9))
                .shadow(color: Color.deepInk.opacity(0.09), radius: 14, y: 7)
        }
        .overlay {
            shape.strokeBorder(.white.opacity(0.92), lineWidth: 1)
        }
    }
}

struct TactileCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .brightness(configuration.isPressed ? -0.018 : 0)
            .animation(.snappy(duration: 0.18, extraBounce: 0.08), value: configuration.isPressed)
    }
}

struct PrimaryCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.deepInk)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(Color.mintFresh.opacity(configuration.isPressed ? 0.72 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
