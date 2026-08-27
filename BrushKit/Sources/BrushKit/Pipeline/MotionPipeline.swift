import Foundation

/// Streaming pipeline: irregular samples → 50 Hz grid → 2 s windows with 50% overlap → features.
public struct MotionPipeline: Sendable {
    public let sampleRateHz: Double
    public let windowDuration: TimeInterval
    public let overlap: Double

    private var resampler: TimestampResampler
    private var window: [MotionSample] = []
    private var samplesSinceEmission = 0
    private var hasEmitted = false

    public init(sampleRateHz: Double = 50, windowDuration: TimeInterval = 2, overlap: Double = 0.5) {
        precondition(sampleRateHz > 0)
        precondition(windowDuration > 0)
        precondition(overlap >= 0 && overlap < 1)
        self.sampleRateHz = sampleRateHz
        self.windowDuration = windowDuration
        self.overlap = overlap
        self.resampler = TimestampResampler(sampleRateHz: sampleRateHz)
    }

    public mutating func append(_ sample: MotionSample) -> [FeatureVector] {
        let fixedSamples = resampler.append(sample)
        var output: [FeatureVector] = []
        let windowCount = max(2, Int((windowDuration * sampleRateHz).rounded()))
        let hopCount = max(1, Int((Double(windowCount) * (1 - overlap)).rounded()))

        for fixedSample in fixedSamples {
            window.append(fixedSample)
            samplesSinceEmission += 1

            if window.count == windowCount && (hasEmitted ? samplesSinceEmission >= hopCount : samplesSinceEmission >= windowCount) {
                output.append(FeatureExtractor(sampleRateHz: sampleRateHz).extract(from: window))
                hasEmitted = true
                samplesSinceEmission = 0
                window.removeFirst(min(hopCount, window.count))
            } else if window.count > windowCount {
                window.removeFirst(window.count - windowCount)
            }
        }
        return output
    }

    public mutating func process(_ samples: [MotionSample]) -> [FeatureVector] {
        samples.flatMap { append($0) }
    }

    public mutating func reset() {
        resampler.reset()
        window.removeAll(keepingCapacity: true)
        samplesSinceEmission = 0
        hasEmitted = false
    }
}
