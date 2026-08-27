import Foundation

/// What motion analysis observed during one session.
///
/// Every field is an observation, not a verdict. Nothing here decides whether
/// the session counted — `BrushSession.completedRoutine` still depends only on
/// the pacer, so a failed or absent reading can never take away a streak.
public struct SessionAnalysis: Codable, Hashable, Sendable {
    /// Seconds the wrist was actually moving in a brushing rhythm. This is the
    /// number worth showing: most people's "two minutes" includes wetting the
    /// brush, rinsing, and standing still.
    public var activeBrushingSeconds: TimeInterval
    /// Seconds spent brushing faster than the configured stroke-rate ceiling.
    public var fastStrokeSeconds: TimeInterval
    /// Distinct wrist postures the session moved through. Not mouth zones — see
    /// `PositionChangeDetector`.
    public var positionChanges: Int
    /// Longest stretch held in one posture while brushing.
    public var longestSinglePositionSeconds: TimeInterval
    public var medianStrokeRatePerMinute: Double
    /// Feature windows the analysis actually saw. Near zero means the recorder
    /// never delivered usable motion, which is a different thing from "did not
    /// brush" and must be reported differently.
    public var windowCount: Int

    public init(
        activeBrushingSeconds: TimeInterval = 0,
        fastStrokeSeconds: TimeInterval = 0,
        positionChanges: Int = 0,
        longestSinglePositionSeconds: TimeInterval = 0,
        medianStrokeRatePerMinute: Double = 0,
        windowCount: Int = 0
    ) {
        self.activeBrushingSeconds = max(0, activeBrushingSeconds)
        self.fastStrokeSeconds = max(0, fastStrokeSeconds)
        self.positionChanges = max(0, positionChanges)
        self.longestSinglePositionSeconds = max(0, longestSinglePositionSeconds)
        self.medianStrokeRatePerMinute = max(0, medianStrokeRatePerMinute)
        self.windowCount = max(0, windowCount)
    }

    /// True when too little motion arrived to say anything. Report this as
    /// "couldn't check", never as "you didn't brush".
    public var isInconclusive: Bool { windowCount < 3 }
}

public enum SessionInsight: Hashable, Sendable {
    case activityChanged(MotionActivity)
    case positionChanged(total: Int)
    case strokeRateHigh(ratePerMinute: Double)
    case heldOnePositionTooLong(seconds: TimeInterval)
}

public struct LiveSessionAnalyzerConfiguration: Hashable, Sendable {
    public var activity: ActivityDetectorConfiguration
    public var highStrokeRatePerMinute: Double
    /// How long the wrist may stay in one posture while brushing before it is
    /// worth a nudge. Slightly longer than a zone so ordinary pacing never
    /// trips it.
    public var singlePositionNudgeSeconds: TimeInterval
    public var positionChangeThresholdDegrees: Double

    public init(
        activity: ActivityDetectorConfiguration = ActivityDetectorConfiguration(),
        highStrokeRatePerMinute: Double = 240,
        singlePositionNudgeSeconds: TimeInterval = 28,
        positionChangeThresholdDegrees: Double = 25
    ) {
        self.activity = activity
        self.highStrokeRatePerMinute = highStrokeRatePerMinute
        self.singlePositionNudgeSeconds = singlePositionNudgeSeconds
        self.positionChangeThresholdDegrees = positionChangeThresholdDegrees
    }
}

/// Drives the pipeline, activity detection, and position-change detection over a
/// live session, accumulating a `SessionAnalysis` as it goes.
///
/// Deliberately separate from the pacer: `SessionClock` and `RoutineTimeline`
/// own timing and zone scheduling, this owns observation. Keeping them apart is
/// what lets the pacer stay pure wall-clock while analysis runs beside it, and
/// it means an analysis bug can never desynchronise the timer.
public struct LiveSessionAnalyzer: Sendable {
    public let configuration: LiveSessionAnalyzerConfiguration

    private var pipeline: MotionPipeline
    private var activity: ActivityDetector
    private var position: PositionChangeDetector

    private var latestActivity: MotionActivity = .idle
    private var previousWindowEnd: TimeInterval?
    private var strokeRates: [Double] = []
    private var nudgedForCurrentPosition = false
    private var analysis = SessionAnalysis()

    public init(
        configuration: LiveSessionAnalyzerConfiguration = LiveSessionAnalyzerConfiguration(),
        pipeline: MotionPipeline = MotionPipeline()
    ) {
        self.configuration = configuration
        self.pipeline = pipeline
        self.activity = ActivityDetector(configuration: configuration.activity)
        self.position = PositionChangeDetector(
            changeThresholdDegrees: configuration.positionChangeThresholdDegrees
        )
    }

    public var currentActivity: MotionActivity { latestActivity }

    public var currentAnalysis: SessionAnalysis {
        var output = analysis
        output.medianStrokeRatePerMinute = median(of: strokeRates)
        return output
    }

    public mutating func ingest(_ sample: MotionSample) -> [SessionInsight] {
        var insights: [SessionInsight] = []

        for features in pipeline.append(sample) {
            analysis.windowCount += 1

            // Attribute the hop, not the window, so 50%-overlapping windows do
            // not double-count the seconds they share.
            let elapsed: TimeInterval
            if let previousWindowEnd {
                elapsed = max(0, features.windowEnd - previousWindowEnd)
            } else {
                elapsed = max(0, features.windowEnd - features.windowStart)
            }
            previousWindowEnd = features.windowEnd

            let reading = activity.ingest(features)
            if reading.activity != latestActivity {
                latestActivity = reading.activity
                insights.append(.activityChanged(reading.activity))
            }

            if reading.activity == .brushing {
                analysis.activeBrushingSeconds += elapsed
                strokeRates.append(reading.strokeRatePerMinute)
                if reading.strokeRatePerMinute > configuration.highStrokeRatePerMinute {
                    analysis.fastStrokeSeconds += elapsed
                    insights.append(.strokeRateHigh(ratePerMinute: reading.strokeRatePerMinute))
                }
            }

            if position.ingest(features) {
                analysis.positionChanges = position.changeCount
                nudgedForCurrentPosition = false
                insights.append(.positionChanged(total: position.changeCount))
            }

            if let held = position.secondsInCurrentPosition(at: features.windowEnd) {
                analysis.longestSinglePositionSeconds = max(analysis.longestSinglePositionSeconds, held)
                if reading.activity == .brushing,
                   !nudgedForCurrentPosition,
                   held >= configuration.singlePositionNudgeSeconds {
                    nudgedForCurrentPosition = true
                    insights.append(.heldOnePositionTooLong(seconds: held))
                }
            }
        }

        return insights
    }

    public mutating func ingest(_ samples: [MotionSample]) -> [SessionInsight] {
        samples.flatMap { ingest($0) }
    }

    public mutating func reset() {
        pipeline.reset()
        activity.reset()
        position.reset()
        latestActivity = .idle
        previousWindowEnd = nil
        strokeRates.removeAll(keepingCapacity: true)
        nudgedForCurrentPosition = false
        analysis = SessionAnalysis()
    }

    private func median(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}
