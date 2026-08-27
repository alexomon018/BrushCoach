import Foundation

/// The zone sequence and per-zone duration a session follows.
public struct SessionPlan: Codable, Hashable, Sendable {
    public var zones: [BrushZoneLabel]
    public var secondsPerZone: TimeInterval

    public init(
        zones: [BrushZoneLabel] = [.upperRight, .upperCentre, .upperLeft, .lowerLeft, .lowerCentre, .lowerRight],
        secondsPerZone: TimeInterval = 20
    ) {
        precondition(!zones.isEmpty)
        precondition(secondsPerZone > 0)
        self.zones = zones
        self.secondsPerZone = secondsPerZone
    }
}

public struct RoutineTimelineSnapshot: Equatable, Sendable {
    public let elapsed: TimeInterval
    public let currentZoneIndex: Int
    public let zonesCompleted: Int
    public let zoneSecondsRemaining: Int
    public let isComplete: Bool
}

/// Converts elapsed wall-clock time into routine state. UI refresh frequency and
/// motion-sample delivery never affect the result.
public struct RoutineTimeline: Sendable {
    public let plan: SessionPlan

    public init(plan: SessionPlan = SessionPlan()) {
        self.plan = plan
    }

    public var totalDuration: TimeInterval {
        Double(plan.zones.count) * plan.secondsPerZone
    }

    public func snapshot(elapsed rawElapsed: TimeInterval) -> RoutineTimelineSnapshot {
        let elapsed = min(totalDuration, max(0, rawElapsed))
        let complete = elapsed >= totalDuration
        let completed = complete ? plan.zones.count : Int(elapsed / plan.secondsPerZone)
        let current = min(plan.zones.count - 1, completed)
        let remaining: Int
        if complete {
            remaining = 0
        } else {
            remaining = Int(ceil(plan.secondsPerZone - elapsed.truncatingRemainder(dividingBy: plan.secondsPerZone)))
        }
        return RoutineTimelineSnapshot(
            elapsed: elapsed,
            currentZoneIndex: current,
            zonesCompleted: completed,
            zoneSecondsRemaining: remaining,
            isComplete: complete
        )
    }
}

