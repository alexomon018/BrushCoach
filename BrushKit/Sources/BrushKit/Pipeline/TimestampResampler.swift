import Foundation

/// Converts irregular, timestamped input into a fixed-rate stream without assuming Core Motion's dt.
public struct TimestampResampler: Sendable {
    public let sampleRateHz: Double

    private var previous: MotionSample?
    private var nextTimestamp: TimeInterval?

    public init(sampleRateHz: Double = 50) {
        precondition(sampleRateHz > 0)
        self.sampleRateHz = sampleRateHz
    }

    public mutating func append(_ sample: MotionSample) -> [MotionSample] {
        guard let previous, let nextTimestamp else {
            self.previous = sample
            self.nextTimestamp = sample.timestamp + (1 / sampleRateHz)
            return [sample]
        }

        guard sample.timestamp > previous.timestamp else {
            return []
        }

        let interval = 1 / sampleRateHz
        var timestamp = nextTimestamp
        var output: [MotionSample] = []

        while timestamp <= sample.timestamp + interval * 0.001 {
            let fraction = (timestamp - previous.timestamp) / (sample.timestamp - previous.timestamp)
            output.append(previous.interpolated(to: sample, fraction: min(1, max(0, fraction)), timestamp: timestamp))
            timestamp += interval
        }

        self.previous = sample
        self.nextTimestamp = timestamp
        return output
    }

    public mutating func reset() {
        previous = nil
        nextTimestamp = nil
    }
}
