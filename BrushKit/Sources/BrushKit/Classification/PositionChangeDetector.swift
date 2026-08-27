import Foundation

/// Detects that the wrist moved to a new posture, without claiming to know
/// which part of the mouth it moved to.
///
/// This is deliberately a change-point detector rather than a classifier. Naming
/// a mouth region from a wrist IMU is the problem the literature says is
/// unreliable — errors cluster within the same side because the movements are
/// so alike. Detecting *that* the posture changed at the twenty-second mark
/// avoids that failure entirely: there is no label to get wrong. "You spent
/// eighty seconds without changing position" is also more actionable than a
/// low-confidence guess at a zone name.
///
/// The signal is the gravity vector, which gives wrist orientation directly and
/// needs no calibration and no absolute heading — unlike the attitude
/// quaternion, whose yaw reference can change between Core Motion sessions.
public struct PositionChangeDetector: Sendable {
    /// Angle the wrist must turn from the settled posture to count as a move.
    public let changeThresholdRadians: Double
    /// How long a new posture must hold before it is accepted, so a single
    /// window of wobble is not a position change.
    public let settleDuration: TimeInterval

    private var anchor: Vector3?
    private var anchorSince: TimeInterval?
    private var candidate: Vector3?
    private var candidateSince: TimeInterval?
    private(set) public var changeCount = 0

    public init(changeThresholdDegrees: Double = 25, settleDuration: TimeInterval = 2) {
        self.changeThresholdRadians = changeThresholdDegrees * .pi / 180
        self.settleDuration = max(0, settleDuration)
    }

    /// Seconds the wrist has held its current settled posture, or `nil` before
    /// the first posture settles.
    public func secondsInCurrentPosition(at timestamp: TimeInterval) -> TimeInterval? {
        guard let anchorSince else { return nil }
        return max(0, timestamp - anchorSince)
    }

    @discardableResult
    public mutating func ingest(_ features: FeatureVector) -> Bool {
        guard let direction = normalizedGravity(in: features) else { return false }
        let timestamp = features.windowEnd

        guard let anchor else {
            self.anchor = direction
            anchorSince = timestamp
            return false
        }

        if angle(anchor, direction) <= changeThresholdRadians {
            // Still in the settled posture; any pending candidate was a wobble.
            candidate = nil
            candidateSince = nil
            return false
        }

        guard let existing = candidate, let since = candidateSince else {
            candidate = direction
            candidateSince = timestamp
            return false
        }

        // The candidate has to stay put too, or a sweep through an intermediate
        // orientation would register as arriving somewhere.
        guard angle(existing, direction) <= changeThresholdRadians else {
            candidate = direction
            candidateSince = timestamp
            return false
        }

        guard timestamp - since >= settleDuration else { return false }

        self.anchor = direction
        anchorSince = timestamp
        candidate = nil
        candidateSince = nil
        changeCount += 1
        return true
    }

    public mutating func reset() {
        anchor = nil
        anchorSince = nil
        candidate = nil
        candidateSince = nil
        changeCount = 0
    }

    private func normalizedGravity(in features: FeatureVector) -> Vector3? {
        guard let x = features["gravity_x_mean"],
              let y = features["gravity_y_mean"],
              let z = features["gravity_z_mean"],
              x.isFinite, y.isFinite, z.isFinite else { return nil }
        let vector = Vector3(x: x, y: y, z: z)
        let magnitude = vector.magnitude
        guard magnitude > 0.001 else { return nil }
        return Vector3(x: x / magnitude, y: y / magnitude, z: z / magnitude)
    }

    private func angle(_ lhs: Vector3, _ rhs: Vector3) -> Double {
        let dot = min(1, max(-1, lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z))
        return acos(dot)
    }
}
