import SwiftUI

/// The companion app's layout contract. Screens may compose content differently,
/// but they all inherit the same readable width, edge inset and spacing rhythm.
enum CompanionMetrics {
    static let maxContentWidth: CGFloat = 680
    static let compactPageInset: CGFloat = 20
    static let regularPageInset: CGFloat = 28
    static let pageTopSpacing: CGFloat = 8
    static let pageBottomSpacing: CGFloat = 32

    static let sectionSpacing: CGFloat = 26
    static let componentSpacing: CGFloat = 14
    static let rowSpacing: CGFloat = 14
    static let rowIconSize: CGFloat = 44
    static let controlHeight: CGFloat = 56

    static let cardPadding: CGFloat = 18
    static let featureCardPadding: CGFloat = 22
    static let compactCardPadding: CGFloat = 14
    static let cardRadius: CGFloat = 24
    static let featureCardRadius: CGFloat = 28
    static let compactCardRadius: CGFloat = 22
}

extension Font {
    static let companionHero = Font.system(size: 34, weight: .semibold, design: .serif)
    static let companionFeatureTitle = Font.system(size: 28, weight: .semibold, design: .serif)
    static let companionEyebrow = Font.caption2.weight(.bold)
    static let companionMetric = Font.system(.body, design: .rounded, weight: .bold)
}

enum CompanionCardKind {
    case standard
    case feature
    case compact

    fileprivate var padding: CGFloat {
        switch self {
        case .standard: CompanionMetrics.cardPadding
        case .feature: CompanionMetrics.featureCardPadding
        case .compact: CompanionMetrics.compactCardPadding
        }
    }

    fileprivate var radius: CGFloat {
        switch self {
        case .standard: CompanionMetrics.cardRadius
        case .feature: CompanionMetrics.featureCardRadius
        case .compact: CompanionMetrics.compactCardRadius
        }
    }

    fileprivate var shadowRadius: CGFloat {
        switch self {
        case .feature: 18
        case .standard, .compact: 12
        }
    }

    fileprivate var shadowY: CGFloat {
        switch self {
        case .feature: 9
        case .standard, .compact: 6
        }
    }
}

private struct CompanionPageFrameModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let topSpacing: CGFloat
    let bottomSpacing: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: CompanionMetrics.maxContentWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, horizontalSizeClass == .regular
                     ? CompanionMetrics.regularPageInset
                     : CompanionMetrics.compactPageInset)
            .padding(.top, topSpacing)
            .padding(.bottom, bottomSpacing)
    }
}

extension View {
    /// Centers scroll content at a readable width on iPad while keeping the same
    /// edge alignment across every compact-width screen.
    func companionPageFrame(
        top: CGFloat = CompanionMetrics.pageTopSpacing,
        bottom: CGFloat = CompanionMetrics.pageBottomSpacing
    ) -> some View {
        modifier(CompanionPageFrameModifier(topSpacing: top, bottomSpacing: bottom))
    }

    /// Applies one of the deliberately small set of companion card tiers.
    func companionCard(_ kind: CompanionCardKind = .standard) -> some View {
        padding(kind.padding)
            .premiumCard(
                cornerRadius: kind.radius,
                shadowRadius: kind.shadowRadius,
                shadowY: kind.shadowY
            )
    }

    /// A card chrome that costs a single shadow pass.
    ///
    /// The shadow is attached to the filled shape *inside* `background`, so Core
    /// Animation can use its fast path for a known shape instead of rasterizing
    /// the whole composed card (fill + stroke + content) offscreen every frame.
    func premiumCard(
        cornerRadius: CGFloat,
        shadowRadius: CGFloat = 12,
        shadowY: CGFloat = 6
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background {
            shape
                .fill(.white.opacity(0.92))
                .shadow(color: Color.deepInk.opacity(0.08), radius: shadowRadius, y: shadowY)
        }
        .overlay {
            shape.strokeBorder(.white.opacity(0.96), lineWidth: 1)
        }
    }
}

struct TactileCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The press reads through scale alone. `brightness` is a colour filter over
    /// the whole label, so on a card carrying the mouth map it re-rasterised that
    /// entire tree for every frame of the press — a heavy price for a 0.018 shift
    /// nobody can see.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .animation(.snappy(duration: 0.18, extraBounce: 0.08), value: configuration.isPressed)
    }
}

struct CompanionPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.deepInk)
            .frame(maxWidth: .infinity)
            .frame(height: CompanionMetrics.controlHeight)
            .background(
                Color.mintFresh.opacity(!isEnabled ? 0.38 : configuration.isPressed ? 0.72 : 1),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
