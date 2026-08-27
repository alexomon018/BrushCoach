import Foundation

public struct PersonalZonePrototype: Codable, Hashable, Sendable {
    public var zone: BrushZoneLabel
    public var centre: [Double]
    public var windowCount: Int

    public init(zone: BrushZoneLabel, centre: [Double], windowCount: Int) {
        self.zone = zone
        self.centre = centre
        self.windowCount = windowCount
    }
}

public struct PersonalCalibrationProfile: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: UUID
    public var createdAt: Date
    public var watchWrist: WatchWrist
    public var featureSchemaVersion: Int
    public var zoneFeatureNames: [String]
    public var zoneFeatureScales: [Double]
    public var zoneFeatureWeights: [Double]
    public var zonePrototypes: [PersonalZonePrototype]
    public var activityFeatureNames: [String]
    public var activityFeatureScales: [Double]
    public var idleCentre: [Double]
    public var brushingCentre: [Double]
    /// Apparent calibration accuracy against the captured windows. This is a
    /// separability signal, not a claim about future real-world accuracy.
    public var calibrationQuality: Double

    public init(
        schemaVersion: Int = currentSchemaVersion,
        id: UUID = UUID(),
        createdAt: Date = Date(),
        watchWrist: WatchWrist,
        featureSchemaVersion: Int = FeatureVector.schemaVersion,
        zoneFeatureNames: [String],
        zoneFeatureScales: [Double],
        zoneFeatureWeights: [Double],
        zonePrototypes: [PersonalZonePrototype],
        activityFeatureNames: [String],
        activityFeatureScales: [Double],
        idleCentre: [Double],
        brushingCentre: [Double],
        calibrationQuality: Double
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.createdAt = createdAt
        self.watchWrist = watchWrist
        self.featureSchemaVersion = featureSchemaVersion
        self.zoneFeatureNames = zoneFeatureNames
        self.zoneFeatureScales = zoneFeatureScales
        self.zoneFeatureWeights = zoneFeatureWeights
        self.zonePrototypes = zonePrototypes
        self.activityFeatureNames = activityFeatureNames
        self.activityFeatureScales = activityFeatureScales
        self.idleCentre = idleCentre
        self.brushingCentre = brushingCentre
        self.calibrationQuality = min(1, max(0, calibrationQuality))
    }
}

public enum PersonalCalibrationError: LocalizedError, Equatable {
    case missingIdleWindows
    case missingZone(BrushZoneLabel)
    case incompatibleFeatures

    public var errorDescription: String? {
        switch self {
        case .missingIdleWindows:
            "The stillness baseline did not contain enough motion data."
        case .missingZone(let zone):
            "The calibration for \(zone.displayName) did not contain enough motion data."
        case .incompatibleFeatures:
            "The recorded motion features are incompatible with this version of BrushCoach."
        }
    }
}

/// Builds a compact, user-specific classifier from one guided brushing session.
/// It deliberately uses interpretable statistics rather than training a neural
/// network on a single person's highly correlated windows.
public struct PersonalCalibrationBuilder: Sendable {
    public static let requiredZones: [BrushZoneLabel] = [
        .upperRight, .upperCentre, .upperLeft,
        .lowerLeft, .lowerCentre, .lowerRight
    ]

    /// Device-relative posture and motion features. Absolute attitude
    /// quaternions are excluded because their yaw reference can change between
    /// Core Motion sessions.
    public static let zoneFeatureNames = [
        "gravity_x_mean", "gravity_x_std",
        "gravity_y_mean", "gravity_y_std",
        "gravity_z_mean", "gravity_z_std",
        "accel_x_std", "accel_x_rms",
        "accel_y_std", "accel_y_rms",
        "accel_z_std", "accel_z_rms",
        "rotation_x_std", "rotation_x_rms",
        "rotation_y_std", "rotation_y_rms",
        "rotation_z_std", "rotation_z_rms",
        "accel_magnitude_std", "accel_magnitude_rms",
        "rotation_magnitude_std", "rotation_magnitude_rms"
    ]

    public static let activityFeatureNames = [
        "accel_magnitude_std", "accel_magnitude_rms", "accel_magnitude_max",
        "rotation_magnitude_std", "rotation_magnitude_rms", "rotation_magnitude_max",
        "accel_dominant_frequency_hz", "accel_spectral_energy",
        "accel_zero_crossing_rate", "jerk_magnitude_rms"
    ]

    public init() {}

    public func build(
        watchWrist: WatchWrist,
        idleWindows: [FeatureVector],
        zoneWindows: [BrushZoneLabel: [FeatureVector]]
    ) throws -> PersonalCalibrationProfile {
        guard idleWindows.count >= 2 else { throw PersonalCalibrationError.missingIdleWindows }

        let requiredZones = Self.requiredZones
        for zone in requiredZones {
            guard (zoneWindows[zone]?.count ?? 0) >= 2 else {
                throw PersonalCalibrationError.missingZone(zone)
            }
        }

        let allZoneWindows = requiredZones.flatMap { zoneWindows[$0] ?? [] }
        guard let first = (idleWindows + allZoneWindows).first,
              first.schemaVersion == FeatureVector.schemaVersion,
              Self.zoneFeatureNames.allSatisfy({ first[$0] != nil }),
              Self.activityFeatureNames.allSatisfy({ first[$0] != nil }) else {
            throw PersonalCalibrationError.incompatibleFeatures
        }

        let zoneRows = try rows(from: allZoneWindows, names: Self.zoneFeatureNames)
        let zoneScales = scales(for: zoneRows)
        let zonePrototypes = try requiredZones.map { zone in
            let windows = zoneWindows[zone] ?? []
            let rows = try rows(from: windows, names: Self.zoneFeatureNames)
            return PersonalZonePrototype(zone: zone, centre: mean(of: rows), windowCount: rows.count)
        }
        let zoneWeights = discriminativeWeights(
            rowsByZone: try requiredZones.map { zone in
                try rows(from: zoneWindows[zone] ?? [], names: Self.zoneFeatureNames)
            },
            prototypes: zonePrototypes.map(\.centre),
            scales: zoneScales
        )

        let idleRows = try rows(from: idleWindows, names: Self.activityFeatureNames)
        let brushingRows = try rows(from: allZoneWindows, names: Self.activityFeatureNames)
        let activityScales = scales(for: idleRows + brushingRows)
        let idleCentre = mean(of: idleRows)
        let brushingCentre = mean(of: brushingRows)

        let quality = apparentQuality(
            requiredZones: requiredZones,
            zoneWindows: zoneWindows,
            names: Self.zoneFeatureNames,
            scales: zoneScales,
            weights: zoneWeights,
            prototypes: zonePrototypes
        )

        return PersonalCalibrationProfile(
            watchWrist: watchWrist,
            zoneFeatureNames: Self.zoneFeatureNames,
            zoneFeatureScales: zoneScales,
            zoneFeatureWeights: zoneWeights,
            zonePrototypes: zonePrototypes,
            activityFeatureNames: Self.activityFeatureNames,
            activityFeatureScales: activityScales,
            idleCentre: idleCentre,
            brushingCentre: brushingCentre,
            calibrationQuality: quality
        )
    }

    private func rows(from windows: [FeatureVector], names: [String]) throws -> [[Double]] {
        try windows.map { window in
            guard window.schemaVersion == FeatureVector.schemaVersion else {
                throw PersonalCalibrationError.incompatibleFeatures
            }
            return try names.map { name in
                guard let value = window[name], value.isFinite else {
                    throw PersonalCalibrationError.incompatibleFeatures
                }
                return value
            }
        }
    }

    private func mean(of rows: [[Double]]) -> [Double] {
        guard let width = rows.first?.count, !rows.isEmpty else { return [] }
        return (0..<width).map { column in
            rows.reduce(0) { $0 + $1[column] } / Double(rows.count)
        }
    }

    private func scales(for rows: [[Double]]) -> [Double] {
        let centre = mean(of: rows)
        guard !centre.isEmpty else { return [] }
        return centre.indices.map { column in
            let variance = rows.reduce(0) { partial, row in
                let difference = row[column] - centre[column]
                return partial + difference * difference
            } / Double(max(1, rows.count))
            // Prevent a nearly constant feature from dominating distance due
            // to floating-point noise.
            return max(variance.squareRoot(), abs(centre[column]) * 0.02, 0.001)
        }
    }

    private func discriminativeWeights(
        rowsByZone: [[[Double]]],
        prototypes: [[Double]],
        scales: [Double]
    ) -> [Double] {
        guard let width = prototypes.first?.count else { return [] }
        let globalCentre = mean(of: prototypes)
        let rawWeights = (0..<width).map { column in
            let between = prototypes.reduce(0) { partial, prototype in
                let difference = prototype[column] - globalCentre[column]
                return partial + difference * difference
            } / Double(max(1, prototypes.count))
            let withinValues = zip(rowsByZone, prototypes).flatMap { rows, prototype in
                rows.map { row in
                    let difference = row[column] - prototype[column]
                    return difference * difference
                }
            }
            let within = withinValues.reduce(0, +) / Double(max(1, withinValues.count))
            let floor = scales[column] * scales[column] * 0.01
            return min(12, max(0.05, between / max(within, floor)))
        }
        let average = rawWeights.reduce(0, +) / Double(max(1, rawWeights.count))
        return rawWeights.map { $0 / max(average, 0.001) }
    }

    private func apparentQuality(
        requiredZones: [BrushZoneLabel],
        zoneWindows: [BrushZoneLabel: [FeatureVector]],
        names: [String],
        scales: [Double],
        weights: [Double],
        prototypes: [PersonalZonePrototype]
    ) -> Double {
        var correct = 0
        var total = 0
        for zone in requiredZones {
            for window in zoneWindows[zone] ?? [] {
                guard let row = try? rows(from: [window], names: names).first else { continue }
                let prediction = prototypes.min { lhs, rhs in
                    Self.distance(row, lhs.centre, scales: scales, weights: weights)
                        < Self.distance(row, rhs.centre, scales: scales, weights: weights)
                }?.zone
                correct += prediction == zone ? 1 : 0
                total += 1
            }
        }
        return total == 0 ? 0 : Double(correct) / Double(total)
    }

    fileprivate static func distance(
        _ values: [Double],
        _ centre: [Double],
        scales: [Double],
        weights: [Double]? = nil
    ) -> Double {
        guard values.count == centre.count, values.count == scales.count else {
            return .infinity
        }
        var weightedSquares = 0.0
        var weightTotal = 0.0
        for index in values.indices {
            let weight = weights?[index] ?? 1
            let standardized = (values[index] - centre[index]) / max(scales[index], 0.001)
            weightedSquares += weight * standardized * standardized
            weightTotal += weight
        }
        return (weightedSquares / max(weightTotal, 0.001)).squareRoot()
    }
}

public struct PersonalZoneClassifier: ZoneClassifier {
    public let profile: PersonalCalibrationProfile

    public init(profile: PersonalCalibrationProfile) {
        self.profile = profile
    }

    public func classify(_ features: FeatureVector, scheduledZone: BrushZoneLabel) -> ClassificationResult {
        guard features.schemaVersion == profile.featureSchemaVersion,
              let activityValues = values(in: features, named: profile.activityFeatureNames),
              let zoneValues = values(in: features, named: profile.zoneFeatureNames) else {
            return PacerOnlyClassifier().classify(features, scheduledZone: scheduledZone)
        }

        let idleDistance = PersonalCalibrationBuilder.distance(
            activityValues,
            profile.idleCentre,
            scales: profile.activityFeatureScales
        )
        let brushingDistance = PersonalCalibrationBuilder.distance(
            activityValues,
            profile.brushingCentre,
            scales: profile.activityFeatureScales
        )
        let activityMargin = normalizedMargin(first: min(idleDistance, brushingDistance), second: max(idleDistance, brushingDistance))

        if activityMargin < 0.08 {
            return ClassificationResult(activity: .transition, zone: nil, side: nil, jaw: nil, confidence: activityMargin)
        }
        if idleDistance < brushingDistance {
            return ClassificationResult(activity: .idle, zone: nil, side: nil, jaw: nil, confidence: activityMargin)
        }

        let candidates = profile.zonePrototypes.map { prototype in
            (
                prototype,
                PersonalCalibrationBuilder.distance(
                    zoneValues,
                    prototype.centre,
                    scales: profile.zoneFeatureScales,
                    weights: profile.zoneFeatureWeights
                )
            )
        }.sorted { $0.1 < $1.1 }

        guard let best = candidates.first else {
            return ClassificationResult(activity: .brushing, zone: nil, side: nil, jaw: nil, confidence: 0)
        }
        let secondDistance = candidates.dropFirst().first?.1 ?? best.1 + 1
        let zoneMargin = normalizedMargin(first: best.1, second: secondDistance)
        let fit = 1 / (1 + best.1)
        let confidence = min(activityMargin, min(1, zoneMargin * 2) * min(1, fit * 1.5))
        let zone = best.0.zone
        return ClassificationResult(
            activity: .brushing,
            zone: zone,
            side: zone.side,
            jaw: zone.jaw,
            confidence: confidence
        )
    }

    private func values(in features: FeatureVector, named names: [String]) -> [Double]? {
        var output: [Double] = []
        output.reserveCapacity(names.count)
        for name in names {
            guard let value = features[name], value.isFinite else { return nil }
            output.append(value)
        }
        return output
    }

    private func normalizedMargin(first: Double, second: Double) -> Double {
        guard first.isFinite, second.isFinite else { return 0 }
        return min(1, max(0, (second - first) / max(second, 0.001)))
    }
}

/// Majority/weighted-vote smoothing for the UI. The session engine still sees
/// every activity decision so it can pause conservatively.
public struct PredictionSmoother: Sendable {
    public let capacity: Int
    private var recent: [ClassificationResult] = []

    public init(capacity: Int = 3) {
        self.capacity = max(1, capacity)
    }

    public mutating func ingest(_ result: ClassificationResult) -> ClassificationResult {
        recent.append(result)
        if recent.count > capacity { recent.removeFirst(recent.count - capacity) }

        let activity = majorityActivity()
        guard activity == .brushing else {
            let confidence = recent.filter { $0.activity == activity }.map(\.confidence).average
            return ClassificationResult(activity: activity, zone: nil, side: nil, jaw: nil, confidence: confidence)
        }

        var votes: [BrushZoneLabel: Double] = [:]
        for prediction in recent where prediction.activity == .brushing {
            guard let zone = prediction.zone else { continue }
            votes[zone, default: 0] += max(0.01, prediction.confidence)
        }
        guard let winner = votes.max(by: { $0.value < $1.value }) else {
            return ClassificationResult(activity: .brushing, zone: nil, side: nil, jaw: nil, confidence: 0)
        }
        let total = votes.values.reduce(0, +)
        let confidence = total > 0 ? winner.value / total : 0
        return ClassificationResult(
            activity: .brushing,
            zone: winner.key,
            side: winner.key.side,
            jaw: winner.key.jaw,
            confidence: confidence
        )
    }

    public mutating func reset() {
        recent.removeAll(keepingCapacity: true)
    }

    private func majorityActivity() -> MotionActivity {
        var votes: [MotionActivity: Double] = [:]
        for prediction in recent {
            votes[prediction.activity, default: 0] += max(0.1, prediction.confidence)
        }
        return votes.max(by: { $0.value < $1.value })?.key ?? .transition
    }
}

private extension Array where Element == Double {
    var average: Double {
        isEmpty ? 0 : reduce(0, +) / Double(count)
    }
}
