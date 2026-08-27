import Foundation

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

public struct SessionEngineConfiguration: Codable, Hashable, Sendable {
    public var plan: SessionPlan
    public var verificationEnabled: Bool
    public var stallThreshold: TimeInterval
    public var highStrokeRatePerMinute: Double

    public init(
        plan: SessionPlan = SessionPlan(),
        verificationEnabled: Bool = false,
        stallThreshold: TimeInterval = 3,
        highStrokeRatePerMinute: Double = 240
    ) {
        self.plan = plan
        self.verificationEnabled = verificationEnabled
        self.stallThreshold = stallThreshold
        self.highStrokeRatePerMinute = highStrokeRatePerMinute
    }
}

public enum SessionEvent: Hashable, Sendable {
    case windowClassified(ClassificationResult, strokeRatePerMinute: Double)
    case zoneAdvanced(from: BrushZoneLabel, to: BrushZoneLabel)
    case stalled
    case resumed
    case strokeRateHigh(ratePerMinute: Double)
    case completed
}

/// A deterministic state machine. It depends only on timestamped samples and a classifier.
public struct SessionEngine: Sendable {
    public let configuration: SessionEngineConfiguration

    private var pipeline: MotionPipeline
    private let classifier: any ZoneClassifier
    private var currentZoneIndex = 0
    private var countedTimeInZone: TimeInterval = 0
    private var lastTimestamp: TimeInterval?
    private var latestActivity: MotionActivity = .transition
    private var idleDuration: TimeInterval = 0
    private var isStalled = false
    private var isComplete = false
    private var countedDuration: TimeInterval = 0

    public init(
        configuration: SessionEngineConfiguration = SessionEngineConfiguration(),
        classifier: any ZoneClassifier = PacerOnlyClassifier(),
        pipeline: MotionPipeline = MotionPipeline()
    ) {
        self.configuration = configuration
        self.classifier = classifier
        self.pipeline = pipeline
    }

    public var currentZone: BrushZoneLabel {
        configuration.plan.zones[currentZoneIndex]
    }

    public var secondsInCurrentZone: TimeInterval { countedTimeInZone }

    public var activeDuration: TimeInterval { countedDuration }

    public var completed: Bool { isComplete }

    public var stalled: Bool { isStalled }

    public mutating func ingest(_ sample: MotionSample) -> [SessionEvent] {
        guard !isComplete else { return [] }
        var events: [SessionEvent] = []

        if let lastTimestamp {
            let delta = max(0, min(sample.timestamp - lastTimestamp, 0.25))
            updateTiming(by: delta, events: &events)
        }
        lastTimestamp = sample.timestamp

        for features in pipeline.append(sample) {
            let classification = classifier.classify(features, scheduledZone: currentZone)
            let previousActivity = latestActivity
            latestActivity = classification.activity
            let strokeRate = (features["accel_dominant_frequency_hz"] ?? 0) * 60
            events.append(.windowClassified(classification, strokeRatePerMinute: strokeRate))

            if configuration.verificationEnabled,
               previousActivity == .idle,
               latestActivity == .brushing,
               isStalled {
                isStalled = false
                idleDuration = 0
                events.append(.resumed)
            }

            if latestActivity == .brushing, strokeRate > configuration.highStrokeRatePerMinute {
                events.append(.strokeRateHigh(ratePerMinute: strokeRate))
            }
        }
        return events
    }

    public mutating func ingest(_ samples: [MotionSample]) -> [SessionEvent] {
        samples.flatMap { ingest($0) }
    }

    private mutating func updateTiming(by delta: TimeInterval, events: inout [SessionEvent]) {
        let shouldCount = !configuration.verificationEnabled || latestActivity == .brushing
        if shouldCount {
            countedTimeInZone += delta
            countedDuration += delta
            if !configuration.verificationEnabled {
                idleDuration = 0
            }
        } else if latestActivity == .idle {
            idleDuration += delta
            if !isStalled, idleDuration >= configuration.stallThreshold {
                isStalled = true
                events.append(.stalled)
            }
        }

        while countedTimeInZone >= configuration.plan.secondsPerZone, !isComplete {
            countedTimeInZone -= configuration.plan.secondsPerZone
            let previousZone = currentZone
            if currentZoneIndex == configuration.plan.zones.count - 1 {
                isComplete = true
                events.append(.completed)
            } else {
                currentZoneIndex += 1
                events.append(.zoneAdvanced(from: previousZone, to: currentZone))
            }
        }
    }
}
