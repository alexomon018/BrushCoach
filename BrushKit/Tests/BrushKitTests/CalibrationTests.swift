import Testing
import Foundation
@testable import BrushKit

@Suite("Calibration collection")
struct CalibrationCollectorTests {
    @Test func aFullRunBuildsAProfileForEveryZone() throws {
        var collector = CalibrationCollector()
        collector.begin(.baseline)
        collector.ingest(CalibrationFixture.still(seconds: 8, from: 0))

        var start: TimeInterval = 8
        for index in CalibrationCollector().plan.zones.indices {
            collector.begin(.zone(index))
            collector.ingest(CalibrationFixture.zoneMotion(index: index, seconds: 8, from: start))
            start += 8
        }

        let profile = try collector.build(watchWrist: .right)
        #expect(profile.zonePrototypes.count == 6)
        #expect(profile.watchWrist == .right)
        #expect(profile.featureSchemaVersion == FeatureVector.schemaVersion)
        #expect(profile.calibrationQuality > 0)
    }

    @Test func aMissingZoneFailsInsteadOfBuildingAPartialProfile() {
        var collector = CalibrationCollector()
        collector.begin(.baseline)
        collector.ingest(CalibrationFixture.still(seconds: 8, from: 0))
        collector.begin(.zone(0))
        collector.ingest(CalibrationFixture.zoneMotion(index: 0, seconds: 8, from: 8))

        #expect(throws: PersonalCalibrationError.self) {
            try collector.build(watchWrist: .left)
        }
    }

    @Test func aMissingBaselineFailsToo() {
        var collector = CalibrationCollector()
        var start: TimeInterval = 0
        for index in CalibrationCollector().plan.zones.indices {
            collector.begin(.zone(index))
            collector.ingest(CalibrationFixture.zoneMotion(index: index, seconds: 8, from: start))
            start += 8
        }
        #expect(throws: PersonalCalibrationError.missingIdleWindows) {
            try collector.build(watchWrist: .left)
        }
    }

    /// A window straddling two stages is half idle and half brushing, and would
    /// poison both prototypes it landed in.
    @Test func pausingBetweenStagesDiscardsTheStraddlingWindow() {
        var collector = CalibrationCollector()
        collector.begin(.zone(0))
        collector.ingest(CalibrationFixture.zoneMotion(index: 0, seconds: 3, from: 0))
        let afterFirst = collector.windowCount(for: .zone(0))

        collector.pause()
        collector.ingest(CalibrationFixture.zoneMotion(index: 0, seconds: 3, from: 3))
        #expect(collector.windowCount(for: .zone(0)) == afterFirst)

        collector.begin(.zone(1))
        collector.ingest(CalibrationFixture.zoneMotion(index: 1, seconds: 3, from: 6))
        #expect(collector.windowCount(for: .zone(1)) > 0)
    }

    @Test func resetClearsEverythingCollected() {
        var collector = CalibrationCollector()
        collector.begin(.baseline)
        collector.ingest(CalibrationFixture.still(seconds: 8, from: 0))
        #expect(collector.windowCount(for: .baseline) > 0)
        collector.reset()
        #expect(collector.windowCount(for: .baseline) == 0)
        #expect(collector.currentStage == nil)
    }

    @Test func thePlanReportsAnHonestDuration() {
        let plan = CalibrationPlan()
        // Baseline plus six zones of capture and reposition.
        #expect(plan.totalDuration == plan.baselineDuration + 6 * (plan.zoneDuration + plan.repositionDuration))
        #expect(plan.stages.count == 7)
        #expect(CalibrationStage.zone(2).zoneLabel(in: plan) == plan.zones[2])
        #expect(CalibrationStage.baseline.zoneLabel(in: plan) == nil)
    }
}

@Suite("Zone estimation in a live session")
struct LiveZoneEstimationTests {
    private func trainedProfile() throws -> PersonalCalibrationProfile {
        var collector = CalibrationCollector()
        collector.begin(.baseline)
        collector.ingest(CalibrationFixture.still(seconds: 8, from: 0))
        var start: TimeInterval = 8
        for index in collector.plan.zones.indices {
            collector.begin(.zone(index))
            collector.ingest(CalibrationFixture.zoneMotion(index: index, seconds: 8, from: start))
            start += 8
        }
        return try collector.build(watchWrist: .right)
    }

    @Test func withoutAProfileNoZoneIsEverEstimated() {
        var analyzer = LiveSessionAnalyzer()
        let insights = analyzer.ingest(
            CalibrationFixture.zoneMotion(index: 0, seconds: 12, from: 0),
            scheduledZone: .upperRight
        )
        #expect(!analyzer.isEstimatingZones)
        #expect(analyzer.currentZone == nil)
        #expect(analyzer.currentAnalysis.zoneAgreement == nil)
        #expect(!insights.contains { if case .zoneEstimated = $0 { true } else { false } })
    }

    @Test func withAProfileTheMatchingZoneIsRecognised() throws {
        let profile = try trainedProfile()
        var analyzer = LiveSessionAnalyzer(profile: profile)
        #expect(analyzer.isEstimatingZones)

        let zone = profile.zonePrototypes[0].zone
        _ = analyzer.ingest(
            CalibrationFixture.zoneMotion(index: 0, seconds: 14, from: 0),
            scheduledZone: zone
        )
        let analysis = analyzer.currentAnalysis
        #expect(analysis.confidentZoneWindows > 0)
        #expect((analysis.zoneAgreement ?? 0) > 0.5)
    }

    @Test func freeBrushingAccumulatesZoneTimeWithoutAPrompt() throws {
        let profile = try trainedProfile()
        var analyzer = LiveSessionAnalyzer(profile: profile)

        _ = analyzer.ingest(
            CalibrationFixture.zoneMotion(index: 0, seconds: 14, from: 0)
        )

        let analysis = analyzer.currentAnalysis
        #expect(analysis.confidentZoneWindows > 0)
        #expect(analysis.zoneDurations.total > 0)
        #expect(analysis.zoneAgreement == nil)
    }

    /// Agreement must never be inferred from the prompt. Feeding one zone's
    /// motion while prompting a different zone has to lower agreement.
    @Test func agreementFallsWhenMotionDoesNotMatchThePrompt() throws {
        let profile = try trainedProfile()
        var matching = LiveSessionAnalyzer(profile: profile)
        _ = matching.ingest(
            CalibrationFixture.zoneMotion(index: 0, seconds: 14, from: 0),
            scheduledZone: profile.zonePrototypes[0].zone
        )

        var mismatched = LiveSessionAnalyzer(profile: profile)
        _ = mismatched.ingest(
            CalibrationFixture.zoneMotion(index: 0, seconds: 14, from: 0),
            scheduledZone: profile.zonePrototypes[3].zone
        )

        let matched = matching.currentAnalysis.zoneAgreement ?? 0
        let crossed = mismatched.currentAnalysis.zoneAgreement ?? 0
        #expect(matched > crossed)
    }

    @Test func aHighThresholdSuppressesEstimatesEntirely() throws {
        let profile = try trainedProfile()
        var analyzer = LiveSessionAnalyzer(
            configuration: LiveSessionAnalyzerConfiguration(zoneConfidenceThreshold: 1.0),
            profile: profile
        )
        _ = analyzer.ingest(
            CalibrationFixture.zoneMotion(index: 0, seconds: 14, from: 0),
            scheduledZone: profile.zonePrototypes[0].zone
        )
        #expect(analyzer.currentAnalysis.confidentZoneWindows == 0)
        #expect(analyzer.currentZone == nil)
    }

    /// Zone estimation is an observation, never a gate.
    @Test func zoneEstimatesNeverAffectRoutineCredit() throws {
        let profile = try trainedProfile()
        var analyzer = LiveSessionAnalyzer(profile: profile)
        _ = analyzer.ingest(
            CalibrationFixture.zoneMotion(index: 0, seconds: 14, from: 0),
            scheduledZone: profile.zonePrototypes[3].zone
        )
        let session = BrushSession(
            startedAt: .now,
            endedAt: .now.addingTimeInterval(120),
            duration: 120,
            zonesCompleted: 6,
            analysis: analyzer.currentAnalysis,
            source: .watch
        )
        #expect(session.completedRoutine)
    }

    @Test func resetClearsZoneStateBetweenSessions() throws {
        let profile = try trainedProfile()
        var analyzer = LiveSessionAnalyzer(profile: profile)
        _ = analyzer.ingest(
            CalibrationFixture.zoneMotion(index: 0, seconds: 14, from: 0),
            scheduledZone: profile.zonePrototypes[0].zone
        )
        analyzer.reset()
        #expect(analyzer.currentZone == nil)
        #expect(analyzer.currentAnalysis.confidentZoneWindows == 0)
        #expect(analyzer.currentAnalysis.zoneAgreement == nil)
    }
}

@Suite("Zone dwell aggregation")
struct ZoneDwellAggregationTests {
    @Test func aSingleFlashIsNotCounted() {
        var accumulator = ZoneDwellAccumulator(minimumConsecutiveWindows: 2)
        accumulator.ingest(zone: .upperLeft, elapsed: 1)
        accumulator.ingest(zone: .upperRight, elapsed: 1)

        #expect(accumulator.durations.total == 0)
    }

    @Test func aConfirmedDwellBackfillsItsBufferedTime() {
        var accumulator = ZoneDwellAccumulator(minimumConsecutiveWindows: 2)
        accumulator.ingest(zone: .lowerCentre, elapsed: 2)
        accumulator.ingest(zone: .lowerCentre, elapsed: 1)
        accumulator.ingest(zone: .lowerCentre, elapsed: 1)

        #expect(accumulator.durations.lowerCentre == 4)
    }

    @Test func uncertaintyBreaksADwellInsteadOfExtendingTheOldZone() {
        var accumulator = ZoneDwellAccumulator(minimumConsecutiveWindows: 2)
        accumulator.ingest(zone: .upperCentre, elapsed: 1)
        accumulator.ingest(zone: .upperCentre, elapsed: 1)
        accumulator.interrupt()
        accumulator.ingest(zone: .upperCentre, elapsed: 1)

        #expect(accumulator.durations.upperCentre == 2)
    }
}

// MARK: - Fixtures

private enum CalibrationFixture {
    static func still(seconds: TimeInterval, from start: TimeInterval) -> [MotionSample] {
        series(seconds: seconds, from: start) { _ in
            (Vector3(x: 0, y: 0, z: 0), Vector3(x: 0, y: 0, z: 0), Vector3(x: 0, y: -1, z: 0))
        }
    }

    /// Each index gets a distinct wrist orientation and stroke frequency, which
    /// is what a real set of six zones would look like if it were separable.
    static func zoneMotion(index: Int, seconds: TimeInterval, from start: TimeInterval) -> [MotionSample] {
        let gravities: [Vector3] = [
            Vector3(x: 0, y: -1, z: 0),
            Vector3(x: -0.7, y: -0.7, z: 0),
            Vector3(x: -1, y: 0, z: 0),
            Vector3(x: 0, y: 0, z: -1),
            Vector3(x: 0.7, y: -0.7, z: 0),
            Vector3(x: 1, y: 0, z: 0)
        ]
        let gravity = gravities[index % gravities.count]
        let frequency = 2.5 + Double(index) * 0.4
        let amplitude = 0.28 + Double(index) * 0.02
        return series(seconds: seconds, from: start) { time in
            let phase = 2 * Double.pi * frequency * time
            return (
                Vector3(x: amplitude * sin(phase), y: amplitude * 0.4 * cos(phase), z: 0),
                Vector3(x: amplitude * 5 * cos(phase), y: amplitude * cos(phase), z: 0),
                gravity
            )
        }
    }

    private static func series(
        seconds: TimeInterval,
        from start: TimeInterval,
        rateHz: Double = 50,
        _ build: (TimeInterval) -> (Vector3, Vector3, Vector3)
    ) -> [MotionSample] {
        let count = Int(seconds * rateHz)
        return (0..<count).map { index in
            let offset = Double(index) / rateHz
            let (acceleration, rotation, gravity) = build(offset)
            return MotionSample(
                timestamp: start + offset,
                userAcceleration: acceleration,
                rotationRate: rotation,
                gravity: gravity,
                attitude: Quaternion(x: 0, y: 0, z: 0, w: 1)
            )
        }
    }
}
