import BrushKit
import SwiftUI

/// How much of the result surface a screen shows. Today needs the verdict and
/// the map above the fold so the next action stays reachable; the detail screen
/// has the room for the reasoning behind it.
enum SessionResultPresentation {
    case summary
    case full
}

/// The result surface shared by the latest-brush screen and history details.
/// It mirrors the classifier's exact six-region granularity: jaw × left/centre/right.
struct SessionResultCard: View {
    let session: BrushSession
    var presentation: SessionResultPresentation = .full

    private var analysis: SessionAnalysis? { session.analysis }
    private var hasUsableCoverage: Bool {
        analysis?.hasUsableZoneCoverage(forSessionLasting: session.duration) == true
    }
    private var durations: ZoneDurations? {
        guard analysis?.zoneEstimationAttempted == true else { return nil }
        return analysis?.zoneDurations
    }
    private var dangerZones: [BrushZoneLabel] {
        hasUsableCoverage ? analysis?.underBrushedZones ?? [] : []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: presentation == .full ? 18 : 14) {
            header

            MouthCoverageMap(
                durations: durations,
                usesCoverageThresholds: hasUsableCoverage
            )
            .frame(height: presentation == .full ? 360 : 288)

            switch presentation {
            case .summary:
                // A degraded reading still has to explain itself here. A good
                // one does not: the headline verdict already carries it.
                if hasUsableCoverage {
                    summaryHighlight
                } else {
                    coverageStatus
                }
                fullBreakdownHint
            case .full:
                coverageStatus

                if hasUsableCoverage {
                    CoverageLegend()
                    if dangerZones.isEmpty {
                        balancedFeedback
                    } else {
                        dangerFeedback
                    }
                    recommendation
                }

                Text("The map shows six broad regions. Wrist motion cannot distinguish inner, outer, and chewing surfaces within a region.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .companionCard(.feature)
    }

    /// The verdict is the headline. When and how long are one quiet line under
    /// it — the screen it sits on already says these are brushing results.
    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(resultTitle)
                .font(.companionFeatureTitle)
                .foregroundStyle(Color.deepInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 7) {
                Text(session.startedAt, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                Text("·")
                Text(Duration.seconds(session.duration), format: .time(pattern: .minuteSecond))
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resultTitle: String {
        guard hasUsableCoverage else { return "Your mouth map" }
        switch dangerZones.count {
        case 0: return "Coverage looks balanced"
        case 1: return "One area needs attention"
        default: return "\(dangerZones.count) areas need attention"
        }
    }

    @ViewBuilder
    private var coverageStatus: some View {
        if hasUsableCoverage, let analysis {
            HStack(spacing: 10) {
                Image(systemName: dangerZones.isEmpty ? "checkmark.seal.fill" : "scope")
                    .foregroundStyle(dangerZones.isEmpty ? Color.mintDeep : Color.coachCoral)
                Text("\(analysis.zoneDurations.total.rounded().formatted()) seconds confidently mapped. A danger area is below 16 seconds of the 20-second target.")
                    .font(.subheadline)
                    .foregroundStyle(Color.deepInk)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else if let analysis, analysis.zoneEstimationAttempted {
            Label(
                "Only \(analysis.zoneDurations.total.rounded().formatted()) seconds were confidently mapped. At least 72 seconds are needed before flagging danger areas.",
                systemImage: "waveform.badge.exclamationmark"
            )
            .font(.subheadline)
            .foregroundStyle(Color.rinseBlue)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Label(
                "No zone reading was recorded. Wear the Watch on your brushing hand and calibrate zones on the Watch to unlock this map.",
                systemImage: "applewatch.slash"
            )
            .font(.subheadline)
            .foregroundStyle(Color.rinseBlue)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The single line Today needs: the thinnest region, or confirmation that
    /// there isn't one. The per-zone reasoning lives on the detail screen.
    @ViewBuilder
    private var summaryHighlight: some View {
        if let worst = dangerZones.first {
            summaryLine(
                systemImage: "scope",
                tint: Color.coachCoral,
                text: "\(worst.displayName) is the thinnest at \(Int((analysis?.zoneDurations[worst] ?? 0).rounded())) seconds."
            )
        } else {
            summaryLine(
                systemImage: "checkmark.seal.fill",
                tint: Color.mintDeep,
                text: "Every region cleared the danger threshold."
            )
        }
    }

    private func summaryLine(systemImage: String, tint: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.deepInk)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The card itself is the tap target; this is only its affordance, so
    /// VoiceOver hears the link's own hint instead of reading a chevron.
    private var fullBreakdownHint: some View {
        HStack(spacing: 4) {
            Text("See full breakdown")
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.rinseBlue)
        .accessibilityHidden(true)
    }

    private var balancedFeedback: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.headline)
                .foregroundStyle(Color.deepInk)
                .frame(width: 38, height: 38)
                .background(Color.mintFresh, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Every region cleared the danger threshold")
                    .font(.headline)
                    .foregroundStyle(Color.deepInk)
                Text("Keep the same full-mouth sweep next time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dangerFeedback: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DANGER AREAS")
                .font(.companionEyebrow)
                .tracking(1.2)
                .foregroundStyle(Color.coachCoral)

            ForEach(Array(dangerZones.enumerated()), id: \.element.id) { index, zone in
                if index > 0 { Divider() }
                HStack(alignment: .top, spacing: 12) {
                    Text("\(Int((analysis?.zoneDurations[zone] ?? 0).rounded()))s")
                        .font(.companionMetric.monospacedDigit())
                        .foregroundStyle(Color.coachCoral)
                        .frame(width: 38, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(zone.displayName)
                            .font(.headline)
                            .foregroundStyle(Color.deepInk)
                        Text(ZoneCareGuidance.explanation(for: zone))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var recommendation: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.forward.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.rinseBlue)
            VStack(alignment: .leading, spacing: 3) {
                Text("Next time")
                    .font(.headline)
                    .foregroundStyle(Color.deepInk)
                Text(recommendationText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.rinseBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var recommendationText: String {
        guard let first = dangerZones.first else {
            return "Use the same steady sweep and remember the inner, outer, and chewing surfaces in every region."
        }
        if dangerZones.count == 1 {
            return "Start with \(first.displayName.lowercased()), then circle back to it during the final 30 seconds."
        }
        return "Start with \(first.displayName.lowercased()), then give every coral area a deliberate pass before the final 30 seconds."
    }
}

struct SessionResultDetailView: View {
    let session: BrushSession

    var body: some View {
        ScrollView {
            SessionResultCard(session: session)
                .companionPageFrame()
        }
        .background(Color.enamelWash.ignoresSafeArea())
        // The card's verdict is this screen's title. A bold system title above
        // it would only say "brush result" a second time, in a typeface the
        // rest of the app doesn't use. The bar stays — it keeps the standard
        // back button and the swipe-back gesture — it just says nothing.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Two clinical-style occlusal arches. Each jaw shows the adult 16-tooth layout
/// while keeping the classifier's honest six-region resolution: five back teeth,
/// six front teeth, five back teeth.
private struct MouthCoverageMap: View {
    let durations: ZoneDurations?
    let usesCoverageThresholds: Bool

    var body: some View {
        GeometryReader { geometry in
            let arches = ArchLayoutCache.arches(for: geometry.size)
            ZStack {
                mouthField

                // Thirty-two crowns, each carrying its own shadow, are thirty-two
                // offscreen passes when composited individually. Rasterising the
                // whole set once costs a single pass instead — and the layer is
                // static, so nothing here has to be re-drawn per frame.
                ZStack {
                    ForEach(arches) { arch in
                        ForEach(arch.teeth) { tooth in
                            let zone = zone(for: tooth.id, jaw: arch.jaw)
                            CoverageTooth(
                                kind: tooth.kind,
                                jaw: arch.jaw,
                                size: tooth.size,
                                color: fill(for: zone),
                                isDanger: isDanger(zone)
                            )
                            .frame(width: tooth.size.width, height: tooth.size.height)
                            .rotationEffect(.degrees(tooth.rotation))
                            .position(tooth.position)
                        }

                        // The classifier measures three regions per jaw, not
                        // sixteen teeth. The breaks say so.
                        ForEach(arch.seams) { seam in
                            Capsule()
                                .fill(Color.deepInk.opacity(0.14))
                                .frame(width: 1.2, height: seam.length)
                                .rotationEffect(.degrees(seam.rotation))
                                .position(seam.position)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .drawingGroup()

                // Text stays outside the rasterised group so it keeps native
                // glyph rendering rather than being baked into a bitmap.
                ForEach(arches) { arch in
                    Text(arch.jaw == .upper ? "UPPER ARCH" : "LOWER ARCH")
                        .position(arch.labelPosition)
                        .accessibilityHidden(true)
                }

                ForEach(BrushZoneLabel.mouthZones) { zone in
                    ZoneTimeBadge(
                        zone: zone,
                        value: zoneValue(for: zone),
                        color: fill(for: zone)
                    )
                    .position(badgePosition(for: zone, in: arches))
                }
            }
            .font(.system(size: 7, weight: .bold, design: .rounded))
            .tracking(1.05)
            .foregroundStyle(Color.rinseBlue.opacity(0.68))
        }
        .accessibilityElement(children: .contain)
    }

    private var mouthField: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(Color.rinseBlue.opacity(0.025))
            .padding(.horizontal, 5)
            .accessibilityHidden(true)
    }

    private func zone(for index: Int, jaw: Jaw) -> BrushZoneLabel {
        let side: MouthSide
        switch index {
        case 0...4: side = .left
        case 5...10: side = .centre
        default: side = .right
        }
        return switch (jaw, side) {
        case (.upper, .left): .upperLeft
        case (.upper, .centre): .upperCentre
        case (.upper, .right): .upperRight
        case (.lower, .left): .lowerLeft
        case (.lower, .centre): .lowerCentre
        case (.lower, .right): .lowerRight
        }
    }

    private func fill(for zone: BrushZoneLabel) -> Color {
        guard let durations else { return Color.rinseBlue.opacity(0.1) }
        let seconds = durations[zone]
        guard usesCoverageThresholds else {
            return Color.rinseBlue.opacity(0.14 + min(1, seconds / 20) * 0.36)
        }
        if seconds < ZoneCoverageStandard.dangerThreshold { return .coachCoral }
        if seconds < ZoneCoverageStandard.targetPerZone { return .achievementGold }
        return .mintFresh
    }

    private func isDanger(_ zone: BrushZoneLabel) -> Bool {
        guard usesCoverageThresholds, let durations else { return false }
        return durations[zone] < ZoneCoverageStandard.dangerThreshold
    }

    private func zoneValue(for zone: BrushZoneLabel) -> String {
        guard let durations else { return "—" }
        return "\(Int(durations[zone].rounded()))s"
    }

    private func badgePosition(for zone: BrushZoneLabel, in arches: [ArchLayout]) -> CGPoint {
        let upper = arches[0]
        let lower = arches[1]
        return switch zone {
        case .upperLeft: upper.badgeAnchor(for: .left)
        case .upperCentre: upper.badgeAnchor(for: .centre)
        case .upperRight: upper.badgeAnchor(for: .right)
        case .lowerLeft: lower.badgeAnchor(for: .left)
        case .lowerCentre: lower.badgeAnchor(for: .centre)
        case .lowerRight: lower.badgeAnchor(for: .right)
        case .transition, .idle: .zero
        }
    }
}

/// Average adult crown dimensions in millimetres, so the arch is spaced by real
/// tooth proportions instead of an even split around a circle.
private struct ToothProfile {
    let kind: ToothKind
    /// Mesiodistal width — the span along the arch.
    let width: CGFloat
    /// Buccolingual depth — the span from cheek side to tongue side.
    let depth: CGFloat

    /// Third molar first, central incisor last.
    private static let upperQuadrant: [ToothProfile] = [
        ToothProfile(kind: .molar, width: 8.5, depth: 10.0),
        ToothProfile(kind: .molar, width: 9.2, depth: 10.8),
        ToothProfile(kind: .molar, width: 10.3, depth: 11.2),
        ToothProfile(kind: .premolar, width: 6.8, depth: 9.2),
        ToothProfile(kind: .premolar, width: 7.1, depth: 9.2),
        ToothProfile(kind: .canine, width: 7.6, depth: 8.1),
        ToothProfile(kind: .incisor, width: 6.6, depth: 6.2),
        ToothProfile(kind: .incisor, width: 8.6, depth: 7.1)
    ]

    private static let lowerQuadrant: [ToothProfile] = [
        ToothProfile(kind: .molar, width: 10.5, depth: 9.5),
        ToothProfile(kind: .molar, width: 10.2, depth: 10.1),
        ToothProfile(kind: .molar, width: 11.2, depth: 10.5),
        ToothProfile(kind: .premolar, width: 7.1, depth: 8.2),
        ToothProfile(kind: .premolar, width: 6.9, depth: 7.7),
        ToothProfile(kind: .canine, width: 6.9, depth: 7.9),
        ToothProfile(kind: .incisor, width: 5.9, depth: 6.4),
        ToothProfile(kind: .incisor, width: 5.3, depth: 6.0)
    ]

    /// One full jaw, right third molar through left third molar.
    static func row(for jaw: Jaw) -> [ToothProfile] {
        let quadrant = jaw == .upper ? upperQuadrant : lowerQuadrant
        return quadrant + quadrant.reversed()
    }
}

/// Places one jaw's teeth along a superellipse arch by arc length, so crowns sit
/// shoulder to shoulder on a smooth horseshoe and each one faces outwards.
private struct ArchLayout: Identifiable {
    struct Tooth: Identifiable {
        let id: Int
        let kind: ToothKind
        let position: CGPoint
        let size: CGSize
        let rotation: Double
    }

    /// A break in the arch where one classifier zone ends and the next begins.
    struct Seam: Identifiable {
        let id: Int
        let position: CGPoint
        let length: CGFloat
        let rotation: Double
    }

    let jaw: Jaw
    let teeth: [Tooth]
    let seams: [Seam]
    let labelPosition: CGPoint

    var id: Int { jaw == .upper ? 0 : 1 }

    private let innerCentre: CGPoint
    private let sideAnchors: [CGPoint]

    /// An exponent above 2 keeps the posterior segments running almost parallel
    /// instead of bowing out into a circle, which is what makes an arch read as
    /// a real horseshoe.
    private static let archExponent: Double = 2.0 / 2.8
    private static let sampleCount = 240
    /// Millimetres of visible separation between neighbouring crowns.
    private static let contactGap: CGFloat = 0.6
    /// A wider break at a zone boundary, so five coral molars read as one
    /// measurement rather than five.
    private static let zoneGap: CGFloat = 3.4
    /// Crown indices a zone boundary falls after, matching `sideAnchors`.
    private static let zoneBoundaries: Set<Int> = [4, 10]

    private static func gap(after index: Int) -> CGFloat {
        zoneBoundaries.contains(index) ? zoneGap : contactGap
    }

    init(jaw: Jaw, in size: CGSize) {
        self.jaw = jaw

        let halfWidth = min(size.width * 0.35, size.height * 0.38)
        let depth = size.height * 0.43
        let centreX = size.width / 2
        let direction: CGFloat = jaw == .upper ? 1 : -1
        let frontY = jaw == .upper ? size.height * 0.035 : size.height * 0.965

        var samples: [CGPoint] = []
        samples.reserveCapacity(Self.sampleCount + 1)
        for step in 0...Self.sampleCount {
            let theta = -Double.pi / 2 + Double.pi * Double(step) / Double(Self.sampleCount)
            let lateral = copysign(pow(abs(sin(theta)), Self.archExponent), sin(theta))
            let backward = 1 - pow(abs(cos(theta)), Self.archExponent)
            samples.append(
                CGPoint(
                    x: centreX + halfWidth * lateral,
                    y: frontY + direction * depth * backward
                )
            )
        }

        var lengths: [CGFloat] = [0]
        lengths.reserveCapacity(samples.count)
        for index in 1..<samples.count {
            let step = hypot(
                samples[index].x - samples[index - 1].x,
                samples[index].y - samples[index - 1].y
            )
            lengths.append(lengths[index - 1] + step)
        }

        let profiles = ToothProfile.row(for: jaw)
        let millimetres = profiles.reduce(0) { $0 + $1.width }
            + (0..<(profiles.count - 1)).reduce(0) { $0 + Self.gap(after: $1) }
        let scale = millimetres > 0 ? lengths[lengths.count - 1] / millimetres : 0

        var placed: [Tooth] = []
        var breaks: [Seam] = []
        placed.reserveCapacity(profiles.count)
        var travelled: CGFloat = 0
        for (index, profile) in profiles.enumerated() {
            let crownWidth = profile.width * scale
            let (point, heading) = Self.sample(
                at: travelled + crownWidth / 2,
                samples: samples,
                lengths: lengths
            )
            placed.append(
                Tooth(
                    id: index,
                    kind: profile.kind,
                    position: point,
                    size: CGSize(width: crownWidth, height: profile.depth * scale),
                    rotation: heading
                )
            )
            travelled += crownWidth
            guard index < profiles.count - 1 else { continue }
            let gap = Self.gap(after: index) * scale
            if Self.zoneBoundaries.contains(index) {
                let (seamPoint, seamHeading) = Self.sample(
                    at: travelled + gap / 2,
                    samples: samples,
                    lengths: lengths
                )
                breaks.append(
                    Seam(
                        id: index,
                        position: seamPoint,
                        length: profile.depth * scale * 1.5,
                        rotation: seamHeading
                    )
                )
            }
            travelled += gap
        }
        teeth = placed
        seams = breaks

        innerCentre = CGPoint(x: centreX, y: frontY + direction * depth * 0.60)
        sideAnchors = [0...4, 5...10, 11...15].map { range in
            let members = placed[range]
            let count = CGFloat(members.count)
            return CGPoint(
                x: members.reduce(0) { $0 + $1.position.x } / count,
                y: members.reduce(0) { $0 + $1.position.y } / count
            )
        }
        labelPosition = CGPoint(x: centreX, y: frontY + direction * depth * 0.88)
    }

    /// Badges float inside the arch rather than on top of the crowns.
    func badgeAnchor(for side: MouthSide) -> CGPoint {
        let anchor: CGPoint
        let pull: CGFloat
        switch side {
        case .left: anchor = sideAnchors[0]; pull = 0.56
        case .centre: anchor = sideAnchors[1]; pull = 0.55
        case .right: anchor = sideAnchors[2]; pull = 0.56
        }
        return CGPoint(
            x: anchor.x + (innerCentre.x - anchor.x) * pull,
            y: anchor.y + (innerCentre.y - anchor.y) * pull
        )
    }

    /// Position plus the tangent heading in degrees at a distance along the arch.
    private static func sample(
        at distance: CGFloat,
        samples: [CGPoint],
        lengths: [CGFloat]
    ) -> (CGPoint, Double) {
        var low = 0
        var high = lengths.count - 1
        while low < high {
            let mid = (low + high) / 2
            if lengths[mid] < distance { low = mid + 1 } else { high = mid }
        }
        let index = min(max(low, 1), samples.count - 2)
        let span = lengths[index] - lengths[index - 1]
        let fraction = span > 0 ? min(1, max(0, (distance - lengths[index - 1]) / span)) : 0
        let previous = samples[index - 1]
        let current = samples[index]
        let point = CGPoint(
            x: previous.x + (current.x - previous.x) * fraction,
            y: previous.y + (current.y - previous.y) * fraction
        )
        let heading = atan2(
            samples[index + 1].y - previous.y,
            samples[index + 1].x - previous.x
        )
        return (point, heading * 180 / .pi)
    }
}

/// Both arches for a given canvas size, built once.
///
/// A layout depends on nothing but the size, but the map's `body` re-runs
/// whenever the durations change or a parent invalidates it. Re-sampling 482
/// points of the superellipse for a size that has not moved was pure waste.
@MainActor
private enum ArchLayoutCache {
    private static var entries: [CGSize: [ArchLayout]] = [:]

    static func arches(for size: CGSize) -> [ArchLayout] {
        if let cached = entries[size] { return cached }
        let built = [ArchLayout(jaw: .upper, in: size), ArchLayout(jaw: .lower, in: size)]
        // A summary map, a detail map and a rotation is the realistic ceiling.
        // Past that the sizes are stale and not worth holding on to.
        if entries.count >= 4 { entries.removeAll() }
        entries[size] = built
        return built
    }
}

private enum ToothKind {
    case molar
    case premolar
    case canine
    case incisor
}

private struct CoverageTooth: View {
    let kind: ToothKind
    let jaw: Jaw
    /// The crown's laid-out size, so the outline is solved once here instead of
    /// once per `Shape` the crown is drawn with.
    let size: CGSize
    let color: Color
    let isDanger: Bool

    var body: some View {
        // A cusped crown is a 56-step superellipse. Drawing it as four separate
        // `ToothCrownShape` values solved that same outline four times over; a
        // `Path` is itself a `Shape`, so one solve serves every layer.
        let rect = CGRect(origin: .zero, size: size)
        let crown = ToothCrownShape(kind: kind).path(in: rect)

        ZStack {
            // The soft aura is worth its offscreen pass only where it carries
            // meaning. At radius 0.5 the non-danger blur was invisible and still
            // cost one pass per crown; the drop shadow already gives those teeth
            // their lift.
            if isDanger {
                crown
                    .fill(color.opacity(0.27))
                    .scaleEffect(1.18)
                    .blur(radius: 1.4)
            }
            crown
                .fill(.white)
                .overlay {
                    crown
                        .fill(color)
                        .scaleEffect(0.84)
                }
                .overlay {
                    crown
                        .stroke(Color.deepInk.opacity(0.13), lineWidth: 1)
                }
            ToothGrooveShape(kind: kind)
                .stroke(
                    Color.deepInk.opacity(0.22),
                    style: StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round)
                )
        }
        // Crowns are drawn cheek-side up; the lower jaw faces the other way.
        .scaleEffect(x: 1, y: jaw == .upper ? 1 : -1)
        .shadow(
            color: isDanger ? Color.coachCoral.opacity(0.32) : Color.deepInk.opacity(0.1),
            radius: isDanger ? 4 : 2,
            y: 1
        )
        .accessibilityHidden(true)
    }
}

/// Occlusal silhouettes: cusped molars and premolars, a pointed canine and a
/// lens-shaped incisor, so the map reads as dental anatomy rather than a string
/// of identical status dots. The cheek side is towards `minY`.
private struct ToothCrownShape: Shape {
    let kind: ToothKind

    func path(in rect: CGRect) -> Path {
        switch kind {
        case .molar: Self.cusped(in: rect, exponent: 3.4, lobes: 4, indent: 0.075)
        case .premolar: Self.cusped(in: rect, exponent: 2.8, lobes: 2, indent: 0.06)
        case .canine: Self.canine(in: rect)
        case .incisor: Self.incisor(in: rect)
        }
    }

    /// A superellipse with the edge midpoints pinched in, which reads as the
    /// developmental grooves between cusps.
    private static func cusped(in rect: CGRect, exponent: Double, lobes: Double, indent: Double) -> Path {
        var path = Path()
        let halfWidth = Double(rect.width) / 2
        let halfHeight = Double(rect.height) / 2
        guard halfWidth > 0, halfHeight > 0 else { return path }
        let steps = 56
        for step in 0..<steps {
            let theta = 2 * Double.pi * Double(step) / Double(steps)
            let cosine = cos(theta)
            let sine = sin(theta)
            let radius = pow(
                pow(abs(cosine) / halfWidth, exponent) + pow(abs(sine) / halfHeight, exponent),
                -1 / exponent
            )
            let pinch = 1 - indent * cos(lobes * theta)
            let point = CGPoint(
                x: rect.midX + radius * cosine * pinch,
                y: rect.midY + radius * sine * pinch
            )
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private static func canine(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.midX + width * x, y: rect.midY + height * y)
        }
        var path = Path()
        path.move(to: point(0, -0.5))
        path.addCurve(to: point(0.47, 0.10), control1: point(0.30, -0.44), control2: point(0.50, -0.16))
        path.addCurve(to: point(0, 0.47), control1: point(0.45, 0.36), control2: point(0.30, 0.50))
        path.addCurve(to: point(-0.47, 0.10), control1: point(-0.30, 0.50), control2: point(-0.45, 0.36))
        path.addCurve(to: point(0, -0.5), control1: point(-0.50, -0.16), control2: point(-0.30, -0.44))
        path.closeSubpath()
        return path
    }

    private static func incisor(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.midX + width * x, y: rect.midY + height * y)
        }
        var path = Path()
        path.move(to: point(-0.44, -0.30))
        path.addCurve(to: point(0.44, -0.30), control1: point(-0.30, -0.52), control2: point(0.30, -0.52))
        path.addCurve(to: point(0.36, 0.44), control1: point(0.52, -0.05), control2: point(0.50, 0.30))
        path.addCurve(to: point(-0.36, 0.44), control1: point(0.18, 0.56), control2: point(-0.18, 0.56))
        path.addCurve(to: point(-0.44, -0.30), control1: point(-0.50, 0.30), control2: point(-0.52, -0.05))
        path.closeSubpath()
        return path
    }
}

private struct ToothGrooveShape: Shape {
    let kind: ToothKind

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.midX + width * x, y: rect.midY + height * y)
        }
        var path = Path()
        switch kind {
        case .molar:
            // Central fossa with the mesiodistal, buccal and distolingual grooves.
            path.move(to: point(-0.36, -0.06))
            path.addQuadCurve(to: point(0.36, -0.10), control: point(0, 0.02))
            path.move(to: point(-0.05, -0.34))
            path.addQuadCurve(to: point(0, 0.02), control: point(0.02, -0.06))
            path.move(to: point(0.10, 0.02))
            path.addLine(to: point(0.20, 0.34))
        case .premolar:
            path.move(to: point(-0.30, -0.04))
            path.addQuadCurve(to: point(0.30, -0.04), control: point(0, 0.06))
        case .canine:
            path.move(to: point(-0.30, 0.26))
            path.addLine(to: point(0, -0.18))
            path.addLine(to: point(0.30, 0.26))
        case .incisor:
            path.move(to: point(-0.32, -0.10))
            path.addQuadCurve(to: point(0.32, -0.10), control: point(0, 0.20))
        }
        return path
    }
}


private struct ZoneTimeBadge: View {
    let zone: BrushZoneLabel
    let value: String
    let color: Color

    var body: some View {
        Text(value)
            .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
            .tracking(0)
            .foregroundStyle(Color.deepInk)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(.white.opacity(0.94), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(color.opacity(0.48), lineWidth: 1)
            }
            .shadow(color: Color.deepInk.opacity(0.06), radius: 3, y: 1)
            .accessibilityLabel("\(zone.displayName), \(value)")
        }
}

private struct CoverageLegend: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { legendItems }
            VStack(alignment: .leading, spacing: 7) { legendItems }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var legendItems: some View {
        item(color: .coachCoral, text: "Under 16s")
        item(color: .achievementGold, text: "16–19s")
        item(color: .mintFresh, text: "20s or more")
    }

    private func item(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text)
        }
    }
}

private enum ZoneCareGuidance {
    static func explanation(for zone: BrushZoneLabel) -> String {
        switch zone {
        case .upperLeft, .upperRight, .lowerLeft, .lowerRight:
            "Back teeth have deep grooves where food and plaque can stay trapped, increasing cavity risk."
        case .upperCentre:
            "Plaque left along the front gumline can irritate gums and make them swollen or prone to bleeding."
        case .lowerCentre:
            "Tartar builds readily around the lower front teeth, especially behind them, and can irritate the gums."
        case .transition, .idle:
            ""
        }
    }
}
