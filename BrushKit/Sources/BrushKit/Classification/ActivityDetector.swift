import Foundation

/// Thresholds for `ActivityDetector`.
///
/// **These defaults are provisional.** They were chosen from the physics of the
/// signal — `userAcceleration` is in g, `rotationRate` in rad/s — and not from
/// recorded brushing. Run `brush-replay --separability` over real labelled
/// traces before trusting them, and treat any value here as a hypothesis until
/// that has been done.
public struct ActivityDetectorConfiguration: Codable, Hashable, Sendable {
    /// Motion energy required to enter the brushing state.
    public var enterBrushingEnergy: Double
    /// Motion energy below which the brushing state is left. Deliberately lower
    /// than `enterBrushingEnergy`: the gap is the hysteresis that stops the
    /// state flickering between windows on an ordinary pause mid-stroke.
    public var leaveBrushingEnergy: Double
    /// Plausible band for a brushing stroke. A hand reaching for a towel carries
    /// energy but no sustained oscillation, which is what separates it from
    /// brushing far more reliably than amplitude alone.
    public var minimumStrokeFrequencyHz: Double
    public var maximumStrokeFrequencyHz: Double
    /// Spectral energy floor. Below this the dominant frequency is noise picking
    /// a bin, not a real oscillation.
    public var minimumSpectralEnergy: Double
    /// Rotation contribution to the energy score, relative to acceleration.
    /// Wrist rotation carries much of a brushing stroke, but in different units.
    public var rotationWeight: Double

    public init(
        enterBrushingEnergy: Double = 0.080,
        leaveBrushingEnergy: Double = 0.040,
        minimumStrokeFrequencyHz: Double = 1.0,
        maximumStrokeFrequencyHz: Double = 6.5,
        minimumSpectralEnergy: Double = 0.0015,
        rotationWeight: Double = 0.05
    ) {
        self.enterBrushingEnergy = enterBrushingEnergy
        self.leaveBrushingEnergy = leaveBrushingEnergy
        self.minimumStrokeFrequencyHz = minimumStrokeFrequencyHz
        self.maximumStrokeFrequencyHz = maximumStrokeFrequencyHz
        self.minimumSpectralEnergy = minimumSpectralEnergy
        self.rotationWeight = rotationWeight
    }
}

public struct ActivityReading: Equatable, Sendable {
    public let activity: MotionActivity
    /// Combined acceleration/rotation energy for this window.
    public let energy: Double
    /// Dominant oscillation of the strongest acceleration axis, in strokes per
    /// minute. Zero when no oscillation was found.
    public let strokeRatePerMinute: Double
    /// Whether the oscillation fell inside the plausible brushing band.
    public let isRhythmic: Bool
    public let windowStart: TimeInterval
    public let windowEnd: TimeInterval

    public init(
        activity: MotionActivity,
        energy: Double,
        strokeRatePerMinute: Double,
        isRhythmic: Bool,
        windowStart: TimeInterval,
        windowEnd: TimeInterval
    ) {
        self.activity = activity
        self.energy = energy
        self.strokeRatePerMinute = strokeRatePerMinute
        self.isRhythmic = isRhythmic
        self.windowStart = windowStart
        self.windowEnd = windowEnd
    }
}

/// Decides brushing / transition / idle from one feature window, with no
/// per-user calibration.
///
/// This exists instead of `PersonalZoneClassifier` for the first shipping
/// verification layer for one reason: it answers a two-way question rather than
/// a six-way one. Published wrist-IMU work is consistently pessimistic about
/// naming a mouth region from the wrist, and consistently silent about whether
/// the wrist is moving rhythmically at all — which is the far easier question,
/// and the one that turns "you ran a two-minute timer" into "you brushed for
/// ninety-four seconds".
public struct ActivityDetector: Sendable {
    public let configuration: ActivityDetectorConfiguration
    private var isBrushing = false

    public init(configuration: ActivityDetectorConfiguration = ActivityDetectorConfiguration()) {
        self.configuration = configuration
    }

    /// Scores a window without consuming it, so replay tooling can sweep
    /// thresholds over a fixed set of features.
    public func score(_ features: FeatureVector) -> (energy: Double, strokeRatePerMinute: Double, isRhythmic: Bool) {
        let accelerationEnergy = features["accel_magnitude_std"] ?? 0
        let rotationEnergy = features["rotation_magnitude_std"] ?? 0
        let energy = accelerationEnergy + rotationEnergy * configuration.rotationWeight

        let frequency = features["accel_dominant_frequency_hz"] ?? 0
        let spectralEnergy = features["accel_spectral_energy"] ?? 0
        let isRhythmic = frequency >= configuration.minimumStrokeFrequencyHz
            && frequency <= configuration.maximumStrokeFrequencyHz
            && spectralEnergy >= configuration.minimumSpectralEnergy

        return (energy, frequency * 60, isRhythmic)
    }

    public mutating func ingest(_ features: FeatureVector) -> ActivityReading {
        let scored = score(features)
        let activity = nextActivity(energy: scored.energy, isRhythmic: scored.isRhythmic)

        return ActivityReading(
            activity: activity,
            energy: scored.energy,
            strokeRatePerMinute: scored.strokeRatePerMinute,
            isRhythmic: scored.isRhythmic,
            windowStart: features.windowStart,
            windowEnd: features.windowEnd
        )
    }

    private mutating func nextActivity(energy: Double, isRhythmic: Bool) -> MotionActivity {
        if isBrushing {
            // Leaving brushing needs the energy to actually drop, not merely for
            // one window to lose its rhythm — people pause mid-stroke constantly.
            if energy < configuration.leaveBrushingEnergy {
                isBrushing = false
                return .idle
            }
            return isRhythmic ? .brushing : .transition
        }

        if energy >= configuration.enterBrushingEnergy && isRhythmic {
            isBrushing = true
            return .brushing
        }
        return energy >= configuration.enterBrushingEnergy ? .transition : .idle
    }

    public mutating func reset() {
        isBrushing = false
    }
}
