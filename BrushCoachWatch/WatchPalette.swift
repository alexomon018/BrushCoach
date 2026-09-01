import BrushDesign
import SwiftUI

/// The watch app's names for the brand colours.
///
/// The values live in `BrushBrand`. Three of these used to be literals identical
/// to the companion app's, and `rinseBlue` used to be a literal that was *not* —
/// the same symbol meaning a different colour in each target. Capture's blue is
/// now named for what it is, so the two can no longer be confused.
extension Color {
    // Coach
    static let watchInk = BrushBrand.ink
    static let watchBlue = BrushBrand.blueBright
    static let watchMint = BrushBrand.mint
    static let watchCoral = BrushBrand.coral

    // Capture
    static let captureInk = BrushBrand.captureInk
    static let enamel = BrushBrand.enamel
    static let captureBlue = BrushBrand.blueVivid
    static let recordCoral = BrushBrand.recordCoral
    static let mintSignal = BrushBrand.mintSignal
}

/// Watch-scale counterparts to the companion layout rules. The values are
/// intentionally tighter, but every Watch screen now shares the same inset,
/// spacing and control treatment.
enum WatchMetrics {
    static let horizontalInset: CGFloat = 10
    static let sectionSpacing: CGFloat = 10
    static let componentSpacing: CGFloat = 8
    static let controlRadius: CGFloat = 14
    static let panelRadius: CGFloat = 18
}

extension Font {
    static let watchEyebrow = Font.system(size: 9, weight: .bold, design: .rounded)
    static let watchScreenTitle = Font.system(.headline, design: .rounded, weight: .bold)
}

extension View {
    func watchPageFrame(bottom: CGFloat = 8) -> some View {
        padding(.horizontal, WatchMetrics.horizontalInset)
            .padding(.bottom, bottom)
    }

    func watchPrimaryControl(tint: Color, foreground: Color = .white) -> some View {
        buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: WatchMetrics.controlRadius))
            .controlSize(.regular)
            .tint(tint)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
    }

    func watchSecondaryControl(tint: Color) -> some View {
        buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: WatchMetrics.controlRadius))
            .controlSize(.regular)
            .tint(tint)
            .frame(maxWidth: .infinity)
    }

    func watchPanel() -> some View {
        padding(WatchMetrics.componentSpacing)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: WatchMetrics.panelRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WatchMetrics.panelRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            }
    }
}
