import Testing
import Foundation
@testable import BrushKit

@Suite("Handedness")
struct HandednessTests {
    @Test func matchedWristAndHandEnablesSensing() {
        let profile = HandednessProfile(watchWrist: .right, brushingHand: .right)
        #expect(profile.capability == .available)
        #expect(profile.capability.canSenseMotion)
        #expect(!profile.couldEnableBySwitchingWrist)
    }

    @Test func theCommonCaseIsTheOneThatCannotSense() {
        // Watch on the non-dominant wrist, brushing with the dominant hand.
        let profile = HandednessProfile(watchWrist: .left, brushingHand: .right)
        #expect(!profile.capability.canSenseMotion)
        #expect(profile.couldEnableBySwitchingWrist)
        #expect(profile.capability == .wrongWrist(watchWrist: .left, brushingHand: .right))
    }

    @Test func anUnansweredQuestionIsNotTreatedAsAMatch() {
        #expect(HandednessProfile(watchWrist: .left, brushingHand: nil).capability == .unknown)
        #expect(HandednessProfile(watchWrist: nil, brushingHand: .left).capability == .unknown)
        #expect(!HandednessProfile().capability.canSenseMotion)
    }

    @Test func everyCapabilityExplainsItselfInPlainLanguage() {
        for capability: SensingCapability in [
            .available,
            .wrongWrist(watchWrist: .left, brushingHand: .right),
            .unknown
        ] {
            #expect(!capability.explanation.isEmpty)
            #expect(!capability.shortLabel.isEmpty)
        }
    }
}

@Suite("Activity detection")
struct ActivityDetectorTests {
    @Test func aStillWristReadsAsIdle() {
        var detector = ActivityDetector()
        var pipeline = MotionPipeline()
        let reading = windows(&pipeline, seconds: 6) { _ in
            MotionFixture.still()
        }.map { detector.ingest($0) }

        #expect(!reading.isEmpty)
        #expect(reading.allSatisfy { $0.activity == .idle })
    }

    @Test func aRhythmicStrokeReadsAsBrushing() {
        var detector = ActivityDetector()
        var pipeline = MotionPipeline()
        let readings = windows(&pipeline, seconds: 6) { time in
            MotionFixture.stroke(at: time, frequencyHz: 3, amplitude: 0.32)
        }.map { detector.ingest($0) }

        #expect(!readings.isEmpty)
        #expect(readings.allSatisfy { $0.activity == .brushing })
        // 3 Hz is 180 strokes per minute.
        let rate = readings[0].strokeRatePerMinute
        #expect(abs(rate - 180) < 12)
    }

    /// Energy alone would call this brushing. The rhythm gate is what stops a
    /// hand reaching for a towel from counting.
    @Test func energeticButUnrhythmicMotionIsNotBrushing() {
        var detector = ActivityDetector()
        var pipeline = MotionPipeline()
        var generator = SeededGenerator(seed: 99)
        let readings = windows(&pipeline, seconds: 6) { _ in
            MotionFixture.jitter(using: &generator, amplitude: 0.5)
        }.map { detector.ingest($0) }

        #expect(!readings.isEmpty)
        #expect(readings.allSatisfy { $0.activity != .brushing })
    }

    @Test func hysteresisKeepsABriefPauseFromDroppingOutOfBrushing() {
        var detector = ActivityDetector()
        let brushing = FeatureFixture.vector(energy: 0.30, frequencyHz: 3, spectralEnergy: 0.4)
        #expect(detector.ingest(brushing).activity == .brushing)

        // Energy dips below the entry threshold but stays above the exit one.
        let dip = FeatureFixture.vector(energy: 0.06, frequencyHz: 3, spectralEnergy: 0.2)
        #expect(detector.ingest(dip).activity == .brushing)

        let stop = FeatureFixture.vector(energy: 0.005, frequencyHz: 0.2, spectralEnergy: 0.0001)
        #expect(detector.ingest(stop).activity == .idle)
    }

    @Test func scoringDoesNotMutateStateSoThresholdsCanBeSwept() {
        let detector = ActivityDetector()
        let vector = FeatureFixture.vector(energy: 0.3, frequencyHz: 3, spectralEnergy: 0.4)
        let first = detector.score(vector)
        let second = detector.score(vector)
        #expect(first.energy == second.energy)
        #expect(first.isRhythmic && second.isRhythmic)
    }
}

@Suite("Position change detection")
struct PositionChangeDetectorTests {
    @Test func holdingOnePostureRegistersNoChanges() {
        var detector = PositionChangeDetector()
        for index in 0..<10 {
            detector.ingest(FeatureFixture.gravity(x: 0, y: -1, z: 0, windowEnd: Double(index)))
        }
        #expect(detector.changeCount == 0)
    }

    @Test func aSustainedTurnCountsOnceNotOncePerWindow() {
        var detector = PositionChangeDetector(changeThresholdDegrees: 25, settleDuration: 2)
        for index in 0..<4 {
            detector.ingest(FeatureFixture.gravity(x: 0, y: -1, z: 0, windowEnd: Double(index)))
        }
        // Roughly 90° away, then held.
        for index in 4..<12 {
            detector.ingest(FeatureFixture.gravity(x: -1, y: 0, z: 0, windowEnd: Double(index)))
        }
        #expect(detector.changeCount == 1)
    }

    @Test func aSingleWindowOfWobbleIsNotAPositionChange() {
        var detector = PositionChangeDetector(changeThresholdDegrees: 25, settleDuration: 2)
        for index in 0..<4 {
            detector.ingest(FeatureFixture.gravity(x: 0, y: -1, z: 0, windowEnd: Double(index)))
        }
        detector.ingest(FeatureFixture.gravity(x: -1, y: 0, z: 0, windowEnd: 4))
        for index in 5..<10 {
            detector.ingest(FeatureFixture.gravity(x: 0, y: -1, z: 0, windowEnd: Double(index)))
        }
        #expect(detector.changeCount == 0)
    }

    @Test func timeInPositionTracksTheSettledPosture() {
        var detector = PositionChangeDetector()
        detector.ingest(FeatureFixture.gravity(x: 0, y: -1, z: 0, windowEnd: 10))
        #expect(detector.secondsInCurrentPosition(at: 40) == 30)
    }
}

@Suite("Live session analysis")
struct LiveSessionAnalyzerTests {
    @Test func brushingSecondsCountHopsNotOverlappingWindows() {
        var analyzer = LiveSessionAnalyzer()
        let samples = MotionFixture.series(seconds: 20) { time in
            MotionFixture.stroke(at: time, frequencyHz: 3, amplitude: 0.32)
        }
        _ = analyzer.ingest(samples)
        let analysis = analyzer.currentAnalysis

        // 50%-overlapping windows would double-count to ~40 s if hops were
        // ignored. Allow slack for the pipeline's warm-up window.
        #expect(analysis.activeBrushingSeconds > 14)
        #expect(analysis.activeBrushingSeconds <= 20)
    }

    @Test func aStillSessionRecordsNoBrushingButIsStillReported() {
        var analyzer = LiveSessionAnalyzer()
        _ = analyzer.ingest(MotionFixture.series(seconds: 20) { _ in MotionFixture.still() })
        let analysis = analyzer.currentAnalysis

        #expect(analysis.activeBrushingSeconds == 0)
        #expect(analysis.windowCount > 3)
        #expect(!analysis.isInconclusive)
    }

    @Test func tooFewWindowsIsInconclusiveRatherThanZero() {
        var analyzer = LiveSessionAnalyzer()
        _ = analyzer.ingest(MotionFixture.series(seconds: 3) { _ in MotionFixture.still() })
        #expect(analyzer.currentAnalysis.isInconclusive)
    }

    @Test func fastStrokesAreFlagged() {
        var analyzer = LiveSessionAnalyzer()
        // 5 Hz is 300 strokes per minute, past the 240 ceiling.
        let insights = analyzer.ingest(MotionFixture.series(seconds: 12) { time in
            MotionFixture.stroke(at: time, frequencyHz: 5, amplitude: 0.32)
        })
        let flagged = insights.contains { insight in
            if case .strokeRateHigh = insight { return true }
            return false
        }
        #expect(flagged)
        #expect(analyzer.currentAnalysis.fastStrokeSeconds > 0)
    }

    @Test func resetClearsEverySignal() {
        var analyzer = LiveSessionAnalyzer()
        _ = analyzer.ingest(MotionFixture.series(seconds: 12) { time in
            MotionFixture.stroke(at: time, frequencyHz: 3, amplitude: 0.32)
        })
        #expect(analyzer.currentAnalysis.windowCount > 0)
        analyzer.reset()
        #expect(analyzer.currentAnalysis == SessionAnalysis())
        #expect(analyzer.currentActivity == .idle)
    }
}

@Suite("Session analysis and routine credit")
struct SessionAnalysisCreditTests {
    /// The whole point of keeping analysis separate: a session where sensing
    /// found nothing must still count as a completed routine.
    @Test func failedAnalysisNeverRemovesRoutineCredit() {
        let session = BrushSession(
            startedAt: .now,
            endedAt: .now.addingTimeInterval(120),
            duration: 120,
            zonesCompleted: 6,
            analysis: SessionAnalysis(activeBrushingSeconds: 0, windowCount: 0),
            source: .watch
        )
        #expect(session.completedRoutine)
        #expect(session.activeBrushingSeconds == nil)
    }

    @Test func absentAnalysisReadsAsUnknownNotZero() {
        let session = BrushSession(
            startedAt: .now,
            endedAt: .now.addingTimeInterval(120),
            duration: 120,
            zonesCompleted: 6,
            source: .watch
        )
        #expect(session.analysis == nil)
        #expect(session.activeBrushingSeconds == nil)
        #expect(session.completedRoutine)
    }

    @Test func aUsableReadingSurfacesItsBrushingTime() {
        let session = BrushSession(
            startedAt: .now,
            endedAt: .now.addingTimeInterval(120),
            duration: 120,
            zonesCompleted: 6,
            analysis: SessionAnalysis(activeBrushingSeconds: 94, windowCount: 60),
            source: .watch
        )
        #expect(session.activeBrushingSeconds == 94)
    }

    @Test func historyWrittenBeforeAnalysisExistedStillDecodes() throws {
        let json = """
        [{"startedAt":"2026-01-04T08:00:00Z","duration":120,"zonesCompleted":6,"source":"watch"}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sessions = try decoder.decode([BrushSession].self, from: Data(json.utf8))
        #expect(sessions.count == 1)
        #expect(sessions[0].analysis == nil)
        #expect(sessions[0].completedRoutine)
    }

    @Test func preferencesWrittenBeforeHandednessExistedStillDecode() throws {
        let json = #"{"morningEnabled":true,"morningHour":6,"morningMinute":0}"#
        let preferences = try JSONDecoder().decode(RoutinePreferences.self, from: Data(json.utf8))
        #expect(preferences.brushingHand == nil)
        #expect(preferences.morningHour == 6)
        #expect(preferences.eveningEnabled)
    }
}

// MARK: - Fixtures

private enum MotionFixture {
    static func still() -> (Vector3, Vector3) {
        (Vector3(x: 0, y: 0, z: 0), Vector3(x: 0, y: 0, z: 0))
    }

    static func stroke(at time: TimeInterval, frequencyHz: Double, amplitude: Double) -> (Vector3, Vector3) {
        let phase = 2 * Double.pi * frequencyHz * time
        return (
            Vector3(x: amplitude * sin(phase), y: amplitude * 0.3 * sin(phase), z: 0),
            Vector3(x: amplitude * 4 * cos(phase), y: 0, z: 0)
        )
    }

    static func jitter(using generator: inout SeededGenerator, amplitude: Double) -> (Vector3, Vector3) {
        (
            Vector3(
                x: generator.nextUnit() * amplitude,
                y: generator.nextUnit() * amplitude,
                z: generator.nextUnit() * amplitude
            ),
            Vector3(x: generator.nextUnit() * amplitude, y: 0, z: 0)
        )
    }

    static func series(
        seconds: TimeInterval,
        rateHz: Double = 50,
        _ build: (TimeInterval) -> (Vector3, Vector3)
    ) -> [MotionSample] {
        let count = Int(seconds * rateHz)
        return (0..<count).map { index in
            let time = Double(index) / rateHz
            let (acceleration, rotation) = build(time)
            return MotionSample(
                timestamp: time,
                userAcceleration: acceleration,
                rotationRate: rotation,
                gravity: Vector3(x: 0, y: -1, z: 0),
                attitude: Quaternion(x: 0, y: 0, z: 0, w: 1)
            )
        }
    }
}

private func windows(
    _ pipeline: inout MotionPipeline,
    seconds: TimeInterval,
    _ build: (TimeInterval) -> (Vector3, Vector3)
) -> [FeatureVector] {
    pipeline.process(MotionFixture.series(seconds: seconds, build))
}

private enum FeatureFixture {
    /// A minimal feature vector carrying only what the detectors read, so a test
    /// can pin one signal without simulating a whole waveform.
    static func vector(
        energy: Double,
        frequencyHz: Double,
        spectralEnergy: Double,
        windowEnd: TimeInterval = 0
    ) -> FeatureVector {
        FeatureVector(
            windowStart: max(0, windowEnd - 2),
            windowEnd: windowEnd,
            names: [
                "accel_magnitude_std", "rotation_magnitude_std",
                "accel_dominant_frequency_hz", "accel_spectral_energy",
                "gravity_x_mean", "gravity_y_mean", "gravity_z_mean"
            ],
            values: [energy, 0, frequencyHz, spectralEnergy, 0, -1, 0]
        )
    }

    static func gravity(x: Double, y: Double, z: Double, windowEnd: TimeInterval) -> FeatureVector {
        FeatureVector(
            windowStart: max(0, windowEnd - 2),
            windowEnd: windowEnd,
            names: [
                "accel_magnitude_std", "rotation_magnitude_std",
                "accel_dominant_frequency_hz", "accel_spectral_energy",
                "gravity_x_mean", "gravity_y_mean", "gravity_z_mean"
            ],
            values: [0, 0, 0, 0, x, y, z]
        )
    }
}

/// Deterministic pseudo-random source, so the "energetic but unrhythmic" test
/// cannot pass or fail depending on the day.
private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 6_364_136_223_846_793_005 &+ 1 }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    /// Uniform in [-1, 1].
    mutating func nextUnit() -> Double {
        Double(next() % 2_000_001) / 1_000_000 - 1
    }
}
