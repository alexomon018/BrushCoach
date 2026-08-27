import Foundation

public struct FeatureExtractor: Sendable {
    public let sampleRateHz: Double

    public init(sampleRateHz: Double = 50) {
        self.sampleRateHz = sampleRateHz
    }

    public func extract(from samples: [MotionSample]) -> FeatureVector {
        precondition(!samples.isEmpty)

        var names: [String] = []
        var values: [Double] = []

        appendVectorStatistics(samples.map(\.userAcceleration), prefix: "accel", names: &names, values: &values)
        appendVectorStatistics(samples.map(\.rotationRate), prefix: "rotation", names: &names, values: &values)
        appendVectorStatistics(samples.map(\.gravity), prefix: "gravity", names: &names, values: &values)

        appendStatistics(samples.map(\.userAcceleration.magnitude), prefix: "accel_magnitude", names: &names, values: &values)
        appendStatistics(samples.map(\.rotationRate.magnitude), prefix: "rotation_magnitude", names: &names, values: &values)
        appendStatistics(samples.map(\.gravity.magnitude), prefix: "gravity_magnitude", names: &names, values: &values)

        let accelerationAxes = [
            samples.map(\.userAcceleration.x),
            samples.map(\.userAcceleration.y),
            samples.map(\.userAcceleration.z)
        ]
        // Preserve the oscillation's sign. A magnitude-only spectrum doubles a symmetric stroke frequency.
        let strokeSignal = accelerationAxes.max {
            Statistics($0).variance < Statistics($1).variance
        } ?? accelerationAxes[0]
        let spectrum = spectralFeatures(strokeSignal)
        names += ["accel_dominant_frequency_hz", "accel_spectral_energy", "accel_zero_crossing_rate"]
        values += [spectrum.dominantFrequency, spectrum.energy, zeroCrossingRate(strokeSignal)]

        appendQuaternionStatistics(samples.map(\.attitude), names: &names, values: &values)

        let jerk = zip(samples, samples.dropFirst()).map { previous, current in
            let dt = current.timestamp - previous.timestamp
            guard dt > 0 else { return Vector3(x: 0, y: 0, z: 0) }
            return Vector3(
                x: (current.userAcceleration.x - previous.userAcceleration.x) / dt,
                y: (current.userAcceleration.y - previous.userAcceleration.y) / dt,
                z: (current.userAcceleration.z - previous.userAcceleration.z) / dt
            )
        }
        if jerk.isEmpty {
            appendVectorStatistics([Vector3(x: 0, y: 0, z: 0)], prefix: "jerk", names: &names, values: &values)
            appendStatistics([0], prefix: "jerk_magnitude", names: &names, values: &values)
        } else {
            appendVectorStatistics(jerk, prefix: "jerk", names: &names, values: &values)
            appendStatistics(jerk.map(\.magnitude), prefix: "jerk_magnitude", names: &names, values: &values)
        }

        return FeatureVector(
            windowStart: samples[0].timestamp,
            windowEnd: samples[samples.count - 1].timestamp,
            names: names,
            values: values
        )
    }

    private func appendVectorStatistics(
        _ vectors: [Vector3],
        prefix: String,
        names: inout [String],
        values: inout [Double]
    ) {
        appendStatistics(vectors.map(\.x), prefix: "\(prefix)_x", names: &names, values: &values)
        appendStatistics(vectors.map(\.y), prefix: "\(prefix)_y", names: &names, values: &values)
        appendStatistics(vectors.map(\.z), prefix: "\(prefix)_z", names: &names, values: &values)
    }

    private func appendStatistics(
        _ input: [Double],
        prefix: String,
        names: inout [String],
        values: inout [Double]
    ) {
        let statistics = Statistics(input)
        names += ["\(prefix)_mean", "\(prefix)_std", "\(prefix)_rms", "\(prefix)_min", "\(prefix)_max"]
        values += [statistics.mean, statistics.standardDeviation, statistics.rms, statistics.minimum, statistics.maximum]
    }

    private func appendQuaternionStatistics(
        _ quaternions: [Quaternion],
        names: inout [String],
        values: inout [Double]
    ) {
        let axes: [(String, [Double])] = [
            ("x", quaternions.map(\.x)),
            ("y", quaternions.map(\.y)),
            ("z", quaternions.map(\.z)),
            ("w", quaternions.map(\.w))
        ]
        for (axis, input) in axes {
            let statistics = Statistics(input)
            names += ["attitude_\(axis)_mean", "attitude_\(axis)_variance"]
            values += [statistics.mean, statistics.variance]
        }
    }

    private func spectralFeatures(_ input: [Double]) -> (dominantFrequency: Double, energy: Double) {
        guard input.count > 1 else { return (0, 0) }
        let mean = input.reduce(0, +) / Double(input.count)
        let centred = input.map { $0 - mean }
        let half = input.count / 2
        var dominantBin = 0
        var dominantPower = 0.0
        var totalPower = 0.0

        // A 100-sample window makes this dependency-free DFT inexpensive and deterministic.
        for bin in 1...half {
            var real = 0.0
            var imaginary = 0.0
            for (index, value) in centred.enumerated() {
                let angle = -2 * Double.pi * Double(bin * index) / Double(input.count)
                real += value * cos(angle)
                imaginary += value * sin(angle)
            }
            let power = (real * real + imaginary * imaginary) / Double(input.count)
            totalPower += power
            if power > dominantPower {
                dominantPower = power
                dominantBin = bin
            }
        }

        return (Double(dominantBin) * sampleRateHz / Double(input.count), totalPower)
    }

    private func zeroCrossingRate(_ input: [Double]) -> Double {
        guard input.count > 1 else { return 0 }
        let mean = input.reduce(0, +) / Double(input.count)
        let centred = input.map { $0 - mean }
        let crossings = zip(centred, centred.dropFirst()).reduce(0) { partial, pair in
            partial + ((pair.0 >= 0) != (pair.1 >= 0) ? 1 : 0)
        }
        return Double(crossings) / Double(input.count - 1)
    }
}

private struct Statistics {
    let mean: Double
    let variance: Double
    let standardDeviation: Double
    let rms: Double
    let minimum: Double
    let maximum: Double

    init(_ values: [Double]) {
        guard !values.isEmpty else {
            mean = 0
            variance = 0
            standardDeviation = 0
            rms = 0
            minimum = 0
            maximum = 0
            return
        }
        let calculatedMean = values.reduce(0, +) / Double(values.count)
        mean = calculatedMean
        variance = values.reduce(0) { $0 + ($1 - calculatedMean) * ($1 - calculatedMean) } / Double(values.count)
        standardDeviation = variance.squareRoot()
        rms = (values.reduce(0) { $0 + $1 * $1 } / Double(values.count)).squareRoot()
        minimum = values.min() ?? 0
        maximum = values.max() ?? 0
    }
}
