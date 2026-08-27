import Foundation

public enum MotionActivity: String, Codable, Sendable {
    case brushing
    case transition
    case idle
}

public struct ClassificationResult: Codable, Hashable, Sendable {
    public var activity: MotionActivity
    public var zone: BrushZoneLabel?
    public var side: MouthSide?
    public var jaw: Jaw?
    public var confidence: Double

    public init(
        activity: MotionActivity,
        zone: BrushZoneLabel?,
        side: MouthSide?,
        jaw: Jaw?,
        confidence: Double
    ) {
        self.activity = activity
        self.zone = zone
        self.side = side
        self.jaw = jaw
        self.confidence = min(1, max(0, confidence))
    }
}

public protocol ZoneClassifier: Sendable {
    func classify(_ features: FeatureVector, scheduledZone: BrushZoneLabel) -> ClassificationResult
}

/// Phase 0/1 fallback. It reports the plan, explicitly at zero confidence.
public struct PacerOnlyClassifier: ZoneClassifier {
    public init() {}

    public func classify(_ features: FeatureVector, scheduledZone: BrushZoneLabel) -> ClassificationResult {
        ClassificationResult(
            activity: .brushing,
            zone: scheduledZone,
            side: scheduledZone.side,
            jaw: scheduledZone.jaw,
            confidence: 0
        )
    }
}
