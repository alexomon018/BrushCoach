import Foundation

/// A device-motion sample whose timestamp is the monotonic Core Motion timestamp.
/// The explicit vector and quaternion types keep trace JSON stable across platforms.
public struct MotionSample: Codable, Hashable, Sendable {
    public var timestamp: TimeInterval
    public var userAcceleration: Vector3
    public var rotationRate: Vector3
    public var gravity: Vector3
    public var attitude: Quaternion

    public init(
        timestamp: TimeInterval,
        userAcceleration: Vector3,
        rotationRate: Vector3,
        gravity: Vector3,
        attitude: Quaternion
    ) {
        self.timestamp = timestamp
        self.userAcceleration = userAcceleration
        self.rotationRate = rotationRate
        self.gravity = gravity
        self.attitude = attitude
    }

    public func interpolated(to other: MotionSample, fraction: Double, timestamp: TimeInterval) -> MotionSample {
        MotionSample(
            timestamp: timestamp,
            userAcceleration: userAcceleration.interpolated(to: other.userAcceleration, fraction: fraction),
            rotationRate: rotationRate.interpolated(to: other.rotationRate, fraction: fraction),
            gravity: gravity.interpolated(to: other.gravity, fraction: fraction),
            attitude: attitude.interpolated(to: other.attitude, fraction: fraction)
        )
    }
}

public struct Vector3: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public var magnitude: Double {
        (x * x + y * y + z * z).squareRoot()
    }

    public func interpolated(to other: Vector3, fraction: Double) -> Vector3 {
        Vector3(
            x: x + (other.x - x) * fraction,
            y: y + (other.y - y) * fraction,
            z: z + (other.z - z) * fraction
        )
    }
}

public struct Quaternion: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public var w: Double

    public init(x: Double, y: Double, z: Double, w: Double) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    public func interpolated(to other: Quaternion, fraction: Double) -> Quaternion {
        // Normalized linear interpolation is stable and sufficient at a 20 ms interval.
        let candidate = Quaternion(
            x: x + (other.x - x) * fraction,
            y: y + (other.y - y) * fraction,
            z: z + (other.z - z) * fraction,
            w: w + (other.w - w) * fraction
        )
        let length = (candidate.x * candidate.x + candidate.y * candidate.y
            + candidate.z * candidate.z + candidate.w * candidate.w).squareRoot()
        guard length > 0 else { return self }
        return Quaternion(
            x: candidate.x / length,
            y: candidate.y / length,
            z: candidate.z / length,
            w: candidate.w / length
        )
    }
}
