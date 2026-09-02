import Foundation

/// Stable, schema-friendly storage for the classifier's six mouth regions.
/// Fixed fields keep future trend queries simple and avoid leaking capture-only
/// labels such as `idle` into a session result.
public struct ZoneDurations: Codable, Hashable, Sendable {
    public var upperLeft: TimeInterval
    public var upperCentre: TimeInterval
    public var upperRight: TimeInterval
    public var lowerLeft: TimeInterval
    public var lowerCentre: TimeInterval
    public var lowerRight: TimeInterval

    public init(
        upperLeft: TimeInterval = 0,
        upperCentre: TimeInterval = 0,
        upperRight: TimeInterval = 0,
        lowerLeft: TimeInterval = 0,
        lowerCentre: TimeInterval = 0,
        lowerRight: TimeInterval = 0
    ) {
        self.upperLeft = max(0, upperLeft)
        self.upperCentre = max(0, upperCentre)
        self.upperRight = max(0, upperRight)
        self.lowerLeft = max(0, lowerLeft)
        self.lowerCentre = max(0, lowerCentre)
        self.lowerRight = max(0, lowerRight)
    }

    public subscript(zone: BrushZoneLabel) -> TimeInterval {
        get {
            switch zone {
            case .upperLeft: upperLeft
            case .upperCentre: upperCentre
            case .upperRight: upperRight
            case .lowerLeft: lowerLeft
            case .lowerCentre: lowerCentre
            case .lowerRight: lowerRight
            case .transition, .idle: 0
            }
        }
        set {
            let value = max(0, newValue)
            switch zone {
            case .upperLeft: upperLeft = value
            case .upperCentre: upperCentre = value
            case .upperRight: upperRight = value
            case .lowerLeft: lowerLeft = value
            case .lowerCentre: lowerCentre = value
            case .lowerRight: lowerRight = value
            case .transition, .idle: break
            }
        }
    }

    public var total: TimeInterval {
        BrushZoneLabel.mouthZones.reduce(0) { $0 + self[$1] }
    }
}

/// The fixed two-minute routine gives every one of the six classifier regions
/// an equal 20-second target. A danger area is deliberately a little below that
/// target so a one-window boundary wobble does not turn into a warning.
public enum ZoneCoverageStandard {
    public static let sessionDuration: TimeInterval = 120
    public static let targetPerZone: TimeInterval = 20
    public static let dangerThreshold: TimeInterval = 16
    public static let minimumClassifiedSeconds: TimeInterval = 72
}

/// What motion analysis observed during one session.
///
/// Every field is an observation, not a verdict. Nothing here decides whether
/// the session counted — `BrushSession.completedRoutine` still depends only on
/// the pacer, so a failed or absent reading can never take away a streak.
public struct SessionAnalysis: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 2

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

    /// Brushing windows whose zone estimate cleared the confidence threshold.
    /// Zero when no calibration profile was loaded.
    public var confidentZoneWindows: Int

    /// Legacy/offline calibration metric: the fraction of confident estimates
    /// matching a supplied reference label. Free-brushing sessions do not pass
    /// a prompt, so this remains `nil` for new user sessions.
    public var zoneAgreement: Double?

    /// Whether a calibration profile was loaded and zone estimation actually
    /// ran. Distinguishes "not calibrated" from "calibrated but never
    /// confident" — which are the same zero to a reader, and completely
    /// different things to diagnose.
    public var zoneEstimationAttempted: Bool

    /// Confident, dwell-filtered brushing time attributed to each of the six
    /// classifier regions. Time with no reliable label remains unassigned.
    public var zoneDurations: ZoneDurations

    /// Wall-clock span the analysed windows actually covered. A recorder that
    /// dies ten seconds into a two-minute session still produces windows, and
    /// without this its handful of seconds would be reported as the whole
    /// session's brushing time.
    public var coveredSeconds: TimeInterval

    /// Whether motion recording ran to the end of the session. False after a
    /// Core Motion failure, which must not be presented as a finished reading.
    public var recordingCompleted: Bool

    public init(
        activeBrushingSeconds: TimeInterval = 0,
        fastStrokeSeconds: TimeInterval = 0,
        positionChanges: Int = 0,
        longestSinglePositionSeconds: TimeInterval = 0,
        medianStrokeRatePerMinute: Double = 0,
        windowCount: Int = 0,
        confidentZoneWindows: Int = 0,
        zoneAgreement: Double? = nil,
        zoneEstimationAttempted: Bool = false,
        zoneDurations: ZoneDurations = ZoneDurations(),
        coveredSeconds: TimeInterval = 0,
        recordingCompleted: Bool = true
    ) {
        self.activeBrushingSeconds = max(0, activeBrushingSeconds)
        self.fastStrokeSeconds = max(0, fastStrokeSeconds)
        self.positionChanges = max(0, positionChanges)
        self.longestSinglePositionSeconds = max(0, longestSinglePositionSeconds)
        self.medianStrokeRatePerMinute = max(0, medianStrokeRatePerMinute)
        self.windowCount = max(0, windowCount)
        self.confidentZoneWindows = max(0, confidentZoneWindows)
        self.zoneAgreement = zoneAgreement.map { min(1, max(0, $0)) }
        self.zoneEstimationAttempted = zoneEstimationAttempted
        self.zoneDurations = zoneDurations
        self.coveredSeconds = max(0, coveredSeconds)
        self.recordingCompleted = recordingCompleted
    }

    /// Field-by-field decoding keeps sessions written by analysis schema v1
    /// readable; those records simply have no per-zone timing data.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            activeBrushingSeconds: try container.decodeIfPresent(TimeInterval.self, forKey: .activeBrushingSeconds) ?? 0,
            fastStrokeSeconds: try container.decodeIfPresent(TimeInterval.self, forKey: .fastStrokeSeconds) ?? 0,
            positionChanges: try container.decodeIfPresent(Int.self, forKey: .positionChanges) ?? 0,
            longestSinglePositionSeconds: try container.decodeIfPresent(TimeInterval.self, forKey: .longestSinglePositionSeconds) ?? 0,
            medianStrokeRatePerMinute: try container.decodeIfPresent(Double.self, forKey: .medianStrokeRatePerMinute) ?? 0,
            windowCount: try container.decodeIfPresent(Int.self, forKey: .windowCount) ?? 0,
            confidentZoneWindows: try container.decodeIfPresent(Int.self, forKey: .confidentZoneWindows) ?? 0,
            zoneAgreement: try container.decodeIfPresent(Double.self, forKey: .zoneAgreement),
            zoneEstimationAttempted: try container.decodeIfPresent(Bool.self, forKey: .zoneEstimationAttempted) ?? false,
            zoneDurations: try container.decodeIfPresent(ZoneDurations.self, forKey: .zoneDurations) ?? ZoneDurations(),
            coveredSeconds: try container.decodeIfPresent(TimeInterval.self, forKey: .coveredSeconds) ?? 0,
            recordingCompleted: try container.decodeIfPresent(Bool.self, forKey: .recordingCompleted) ?? true
        )
    }

    /// True when too little motion arrived to say anything at all. Report this
    /// as "couldn't check", never as "you didn't brush".
    public var isInconclusive: Bool { windowCount < 3 }

    /// Fraction of a session of `duration` that analysis actually observed.
    public func coverage(ofSessionLasting duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, coveredSeconds / duration)
    }

    /// Whether this reading can stand as a statement about the whole session.
    ///
    /// A truncated recording is the dangerous case: it looks like a normal
    /// result and silently under-reports brushing time by however much of the
    /// session it missed.
    public func isInconclusive(forSessionLasting duration: TimeInterval) -> Bool {
        isInconclusive || !recordingCompleted || coverage(ofSessionLasting: duration) < 0.8
    }

    /// Danger feedback is withheld when zone estimation was absent, truncated,
    /// or too uncertain to cover most of the routine. An incomplete reading is
    /// information about the sensor, not evidence that six areas were neglected.
    public func hasUsableZoneCoverage(forSessionLasting duration: TimeInterval) -> Bool {
        zoneEstimationAttempted
            && !isInconclusive(forSessionLasting: duration)
            && zoneDurations.total >= ZoneCoverageStandard.minimumClassifiedSeconds
    }

    public var underBrushedZones: [BrushZoneLabel] {
        BrushZoneLabel.mouthZones
            .filter { zoneDurations[$0] < ZoneCoverageStandard.dangerThreshold }
            .sorted { zoneDurations[$0] < zoneDurations[$1] }
    }
}

public enum SessionInsight: Hashable, Sendable {
    case activityChanged(MotionActivity)
    /// A zone estimate that cleared the confidence threshold. Never emitted
    /// without a calibration profile, and never emitted below the threshold —
    /// a low-confidence guess is worse than silence.
    case zoneEstimated(BrushZoneLabel, confidence: Double)
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
    /// Zone estimates below this are discarded rather than shown.
    ///
    /// The trade-off is real in both directions: too low and a confidently wrong
    /// zone teaches users to distrust the app; too high and the feature never
    /// fires, which teaches its author nothing. This default deliberately errs
    /// toward firing during the experimental period, and `SessionAnalysis`
    /// records whether estimation ran at all so a silent session can be told
    /// apart from an uncalibrated one.
    public var zoneConfidenceThreshold: Double
    /// A smoothed label must repeat on two successive one-second hops before
    /// its buffered time is accepted. This removes one-off zone flashes without
    /// throwing away the start of a real dwell.
    public var minimumZoneDwellWindows: Int

    public init(
        activity: ActivityDetectorConfiguration = ActivityDetectorConfiguration(),
        highStrokeRatePerMinute: Double = 240,
        singlePositionNudgeSeconds: TimeInterval = 28,
        positionChangeThresholdDegrees: Double = 25,
        zoneConfidenceThreshold: Double = 0.35,
        minimumZoneDwellWindows: Int = 2
    ) {
        self.activity = activity
        self.highStrokeRatePerMinute = highStrokeRatePerMinute
        self.singlePositionNudgeSeconds = singlePositionNudgeSeconds
        self.positionChangeThresholdDegrees = positionChangeThresholdDegrees
        self.zoneConfidenceThreshold = zoneConfidenceThreshold
        self.minimumZoneDwellWindows = max(1, minimumZoneDwellWindows)
    }
}

/// Buffers a possible zone switch until it persists, then backfills the time
/// that established the dwell. `interrupt` deliberately leaves uncertain time
/// unassigned instead of guessing that the previous zone continued.
public struct ZoneDwellAccumulator: Hashable, Sendable {
    public let minimumConsecutiveWindows: Int
    public private(set) var durations = ZoneDurations()

    private var stableZone: BrushZoneLabel?
    private var candidateZone: BrushZoneLabel?
    private var candidateWindows = 0
    private var candidateSeconds: TimeInterval = 0

    public init(minimumConsecutiveWindows: Int = 2) {
        self.minimumConsecutiveWindows = max(1, minimumConsecutiveWindows)
    }

    public mutating func ingest(zone: BrushZoneLabel, elapsed: TimeInterval) {
        guard BrushZoneLabel.mouthZones.contains(zone), elapsed > 0 else { return }

        if stableZone == zone {
            durations[zone] += elapsed
            return
        }

        if candidateZone == zone {
            candidateWindows += 1
            candidateSeconds += elapsed
        } else {
            candidateZone = zone
            candidateWindows = 1
            candidateSeconds = elapsed
        }

        guard candidateWindows >= minimumConsecutiveWindows else { return }
        stableZone = zone
        durations[zone] += candidateSeconds
        clearCandidate()
    }

    public mutating func interrupt() {
        stableZone = nil
        clearCandidate()
    }

    public mutating func reset() {
        durations = ZoneDurations()
        interrupt()
    }

    private mutating func clearCandidate() {
        candidateZone = nil
        candidateWindows = 0
        candidateSeconds = 0
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
    private var firstWindowStart: TimeInterval?
    /// Brushing seconds accumulated in the current posture. Distinct from the
    /// detector's wall-clock hold: standing still for a minute is not "held one
    /// position while brushing", and must not trip the nudge.
    private var brushingSecondsInPosition: TimeInterval = 0

    private let zoneClassifier: PersonalZoneClassifier?
    private var smoother = PredictionSmoother(capacity: 3)
    private var zoneDwell: ZoneDwellAccumulator
    private var zoneMatches = 0
    private var latestZone: BrushZoneLabel?

    public init(
        configuration: LiveSessionAnalyzerConfiguration = LiveSessionAnalyzerConfiguration(),
        profile: PersonalCalibrationProfile? = nil,
        pipeline: MotionPipeline = MotionPipeline()
    ) {
        self.configuration = configuration
        self.pipeline = pipeline
        self.activity = ActivityDetector(configuration: configuration.activity)
        self.position = PositionChangeDetector(
            changeThresholdDegrees: configuration.positionChangeThresholdDegrees
        )
        self.zoneClassifier = profile.map(PersonalZoneClassifier.init(profile:))
        self.zoneDwell = ZoneDwellAccumulator(
            minimumConsecutiveWindows: configuration.minimumZoneDwellWindows
        )
        self.analysis.zoneEstimationAttempted = profile != nil
    }

    public var currentActivity: MotionActivity { latestActivity }

    /// The most recent zone estimate that cleared the confidence threshold, or
    /// `nil` when there is no profile or nothing confident to show.
    public var currentZone: BrushZoneLabel? { latestZone }

    public var isEstimatingZones: Bool { zoneClassifier != nil }

    public var currentAnalysis: SessionAnalysis {
        var output = analysis
        output.medianStrokeRatePerMinute = median(of: strokeRates)
        return output
    }

    public mutating func ingest(_ sample: MotionSample) -> [SessionInsight] {
        ingest(sample, scheduledZone: nil)
    }

    /// `scheduledZone` is retained for calibration tests and offline agreement
    /// scoring. The free-brushing Watch path calls `ingest(_:)` without one; a
    /// reference label never influences the estimate itself.
    public mutating func ingest(
        _ sample: MotionSample,
        scheduledZone: BrushZoneLabel?
    ) -> [SessionInsight] {
        var insights: [SessionInsight] = []

        for features in pipeline.append(sample) {
            analysis.windowCount += 1
            if firstWindowStart == nil { firstWindowStart = features.windowStart }
            analysis.coveredSeconds = max(0, features.windowEnd - (firstWindowStart ?? features.windowStart))

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
                if let insight = estimateZone(
                    features,
                    elapsed: elapsed,
                    scheduledZone: scheduledZone
                ) {
                    insights.append(insight)
                }
                if reading.strokeRatePerMinute > configuration.highStrokeRatePerMinute {
                    analysis.fastStrokeSeconds += elapsed
                    insights.append(.strokeRateHigh(ratePerMinute: reading.strokeRatePerMinute))
                }
            }

            if reading.activity != .brushing {
                smoother.reset()
                zoneDwell.interrupt()
                latestZone = nil
            }

            if position.ingest(features) {
                analysis.positionChanges = position.changeCount
                nudgedForCurrentPosition = false
                brushingSecondsInPosition = 0
                insights.append(.positionChanged(total: position.changeCount))
            }

            // Counted from brushing windows only, so a long idle stretch in one
            // posture neither inflates the summary nor fires the nudge.
            if reading.activity == .brushing {
                brushingSecondsInPosition += elapsed
                analysis.longestSinglePositionSeconds = max(
                    analysis.longestSinglePositionSeconds,
                    brushingSecondsInPosition
                )
                if !nudgedForCurrentPosition,
                   brushingSecondsInPosition >= configuration.singlePositionNudgeSeconds {
                    nudgedForCurrentPosition = true
                    insights.append(.heldOnePositionTooLong(seconds: brushingSecondsInPosition))
                }
            }
        }

        return insights
    }

    public mutating func ingest(
        _ samples: [MotionSample],
        scheduledZone: BrushZoneLabel? = nil
    ) -> [SessionInsight] {
        samples.flatMap { ingest($0, scheduledZone: scheduledZone) }
    }

    /// Runs the calibrated classifier, smooths across three windows, and reports
    /// only what clears the confidence threshold. Below it the estimate is
    /// dropped entirely rather than shown with a caveat: on a small watch face
    /// nobody reads the caveat.
    private mutating func estimateZone(
        _ features: FeatureVector,
        elapsed: TimeInterval,
        scheduledZone: BrushZoneLabel?
    ) -> SessionInsight? {
        guard let zoneClassifier else { return nil }
        let smoothed = smoother.ingest(zoneClassifier.classify(features))
        guard smoothed.activity == .brushing,
              let zone = smoothed.zone,
              smoothed.confidence >= configuration.zoneConfidenceThreshold else {
            zoneDwell.interrupt()
            latestZone = nil
            return nil
        }
        latestZone = zone
        analysis.confidentZoneWindows += 1
        zoneDwell.ingest(zone: zone, elapsed: elapsed)
        analysis.zoneDurations = zoneDwell.durations
        if let prompted = scheduledZone {
            if zone == prompted { zoneMatches += 1 }
            analysis.zoneAgreement = Double(zoneMatches) / Double(analysis.confidentZoneWindows)
        }
        return .zoneEstimated(zone, confidence: smoothed.confidence)
    }

    /// Drops the partial window and stops accounting, without discarding what
    /// has been measured. Used while the session is paused: samples that arrive
    /// during a pause are not brushing, and a window spanning the pause would be
    /// interpolated across the gap.
    public mutating func suspend() {
        pipeline.reset()
        smoother.reset()
        latestActivity = .idle
        latestZone = nil
        previousWindowEnd = nil
    }

    /// Records that motion recording ended before the session did. The reading
    /// is kept — partial data is still worth showing — but it can no longer
    /// claim to describe the whole session.
    public mutating func markRecordingIncomplete() {
        analysis.recordingCompleted = false
    }

    public mutating func reset() {
        pipeline.reset()
        activity.reset()
        position.reset()
        latestActivity = .idle
        previousWindowEnd = nil
        strokeRates.removeAll(keepingCapacity: true)
        nudgedForCurrentPosition = false
        analysis = SessionAnalysis(zoneEstimationAttempted: zoneClassifier != nil)
        smoother.reset()
        zoneDwell.reset()
        zoneMatches = 0
        latestZone = nil
        firstWindowStart = nil
        brushingSecondsInPosition = 0
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
