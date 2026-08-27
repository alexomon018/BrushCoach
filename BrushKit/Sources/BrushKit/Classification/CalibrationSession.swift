import Foundation

/// The shape of a guided calibration: a stillness baseline, then each zone in
/// turn. Kept separate from the UI so the flow can be tested without a watch.
public struct CalibrationPlan: Hashable, Sendable {
    public let baselineDuration: TimeInterval
    public let zoneDuration: TimeInterval
    /// Time to reposition the brush between zones. Motion here is discarded —
    /// it is neither idle nor a clean example of the next zone.
    public let repositionDuration: TimeInterval
    public let zones: [BrushZoneLabel]

    public init(
        baselineDuration: TimeInterval = 6,
        zoneDuration: TimeInterval = 20,
        repositionDuration: TimeInterval = 4,
        zones: [BrushZoneLabel] = PersonalCalibrationBuilder.requiredZones
    ) {
        precondition(!zones.isEmpty)
        self.baselineDuration = baselineDuration
        self.zoneDuration = zoneDuration
        self.repositionDuration = repositionDuration
        self.zones = zones
    }

    /// Roughly how long the whole thing takes, for an honest up-front estimate.
    public var totalDuration: TimeInterval {
        baselineDuration + Double(zones.count) * (zoneDuration + repositionDuration)
    }

    public var stages: [CalibrationStage] {
        [.baseline] + zones.indices.map { CalibrationStage.zone($0) }
    }
}

public enum CalibrationStage: Hashable, Sendable {
    case baseline
    case zone(Int)

    public func zoneLabel(in plan: CalibrationPlan) -> BrushZoneLabel? {
        guard case .zone(let index) = self, plan.zones.indices.contains(index) else { return nil }
        return plan.zones[index]
    }
}

/// Accumulates feature windows per calibration stage, then builds a profile.
///
/// The pipeline is reset at every stage boundary so a window can never straddle
/// two stages — a window half idle and half brushing would poison both
/// prototypes it contributed to.
public struct CalibrationCollector: Sendable {
    public let plan: CalibrationPlan

    private var pipeline: MotionPipeline
    private var stage: CalibrationStage?
    private var baselineWindows: [FeatureVector] = []
    private var zoneWindows: [BrushZoneLabel: [FeatureVector]] = [:]

    public init(plan: CalibrationPlan = CalibrationPlan(), pipeline: MotionPipeline = MotionPipeline()) {
        self.plan = plan
        self.pipeline = pipeline
    }

    public var currentStage: CalibrationStage? { stage }

    /// Windows captured so far for the stage in progress. The UI shows this so a
    /// stage that is collecting nothing is visible while it happens, not after.
    public func windowCount(for stage: CalibrationStage) -> Int {
        switch stage {
        case .baseline: baselineWindows.count
        case .zone(let index):
            plan.zones.indices.contains(index) ? (zoneWindows[plan.zones[index]]?.count ?? 0) : 0
        }
    }

    public mutating func begin(_ stage: CalibrationStage) {
        pipeline.reset()
        self.stage = stage
    }

    /// Stops collecting without discarding what has been captured. Used during
    /// the reposition gap between zones.
    public mutating func pause() {
        pipeline.reset()
        stage = nil
    }

    public mutating func ingest(_ sample: MotionSample) {
        guard let stage else { return }
        let windows = pipeline.append(sample)
        guard !windows.isEmpty else { return }
        switch stage {
        case .baseline:
            baselineWindows += windows
        case .zone(let index):
            guard plan.zones.indices.contains(index) else { return }
            zoneWindows[plan.zones[index], default: []] += windows
        }
    }

    public mutating func ingest(_ samples: [MotionSample]) {
        for sample in samples { ingest(sample) }
    }

    public func build(watchWrist: WatchWrist) throws -> PersonalCalibrationProfile {
        try PersonalCalibrationBuilder().build(
            watchWrist: watchWrist,
            idleWindows: baselineWindows,
            zoneWindows: zoneWindows
        )
    }

    public mutating func reset() {
        pipeline.reset()
        stage = nil
        baselineWindows.removeAll(keepingCapacity: true)
        zoneWindows.removeAll(keepingCapacity: true)
    }
}
