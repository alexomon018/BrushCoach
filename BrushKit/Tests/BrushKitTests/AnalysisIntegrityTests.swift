import Testing
import Foundation
@testable import BrushKit

/// Regressions for defects where analysis looked fine and was quietly wrong.
/// Each of these produced a plausible-looking summary, which is what made them
/// worth pinning.
@Suite("Analysis integrity")
struct AnalysisIntegrityTests {

    // MARK: - Truncated recordings

    @Test func aRecordingThatDiedEarlyCannotSpeakForTheWholeSession() {
        var analyzer = LiveSessionAnalyzer()
        // Core Motion delivered twelve seconds of a two-minute session.
        _ = analyzer.ingest(IntegrityFixture.brushing(seconds: 12, from: 0))
        analyzer.markRecordingIncomplete()

        let analysis = analyzer.currentAnalysis
        #expect(analysis.activeBrushingSeconds > 0)
        // Enough windows to look conclusive on its own terms...
        #expect(!analysis.isInconclusive)
        // ...but not enough to describe a 120-second session.
        #expect(analysis.isInconclusive(forSessionLasting: 120))
    }

    @Test func aShortRecordingIsInconclusiveEvenWithoutAnError() {
        var analyzer = LiveSessionAnalyzer()
        _ = analyzer.ingest(IntegrityFixture.brushing(seconds: 12, from: 0))
        let analysis = analyzer.currentAnalysis

        #expect(analysis.recordingCompleted)
        #expect(analysis.coverage(ofSessionLasting: 120) < 0.2)
        #expect(analysis.isInconclusive(forSessionLasting: 120))
    }

    @Test func aFullRecordingStandsForTheSession() {
        var analyzer = LiveSessionAnalyzer()
        _ = analyzer.ingest(IntegrityFixture.brushing(seconds: 120, from: 0))
        let analysis = analyzer.currentAnalysis

        #expect(analysis.coverage(ofSessionLasting: 120) > 0.9)
        #expect(!analysis.isInconclusive(forSessionLasting: 120))
    }

    @Test func aTruncatedSessionReportsNoBrushingTimeRatherThanAWrongOne() {
        var analyzer = LiveSessionAnalyzer()
        _ = analyzer.ingest(IntegrityFixture.brushing(seconds: 12, from: 0))
        analyzer.markRecordingIncomplete()

        let session = BrushSession(
            startedAt: .now,
            endedAt: .now.addingTimeInterval(120),
            duration: 120,
            zonesCompleted: 6,
            analysis: analyzer.currentAnalysis,
            source: .watch
        )
        // Ten seconds must never be presented as this session's brushing total.
        #expect(session.activeBrushingSeconds == nil)
        // And the routine still counts, as always.
        #expect(session.completedRoutine)
    }

    // MARK: - Pause

    @Test func suspendingKeepsWhatWasMeasuredAndStopsCounting() {
        var analyzer = LiveSessionAnalyzer()
        _ = analyzer.ingest(IntegrityFixture.brushing(seconds: 20, from: 0))
        let brushedBefore = analyzer.currentAnalysis.activeBrushingSeconds
        #expect(brushedBefore > 0)

        analyzer.suspend()
        #expect(analyzer.currentAnalysis.activeBrushingSeconds == brushedBefore)
        #expect(analyzer.currentZone == nil)
    }

    /// The window straddling a pause would otherwise be interpolated across the
    /// gap, inventing motion that never happened.
    @Test func aWindowCannotSpanAPause() {
        var analyzer = LiveSessionAnalyzer()
        _ = analyzer.ingest(IntegrityFixture.brushing(seconds: 20, from: 0))
        let coveredBefore = analyzer.currentAnalysis.coveredSeconds
        analyzer.suspend()

        // Resume 60 seconds later, as if the user had paused that long.
        _ = analyzer.ingest(IntegrityFixture.brushing(seconds: 2, from: 80))
        let analysis = analyzer.currentAnalysis
        // Two seconds is under one window, so nothing new can have been emitted
        // and the pause cannot have been counted as brushing.
        #expect(analysis.activeBrushingSeconds < coveredBefore + 3)
    }

    // MARK: - Position holding

    /// Standing still in one posture is not "held one position while brushing".
    @Test func idleTimeDoesNotCountTowardHoldingAPosition() {
        var analyzer = LiveSessionAnalyzer()
        _ = analyzer.ingest(IntegrityFixture.still(seconds: 40, from: 0))
        let analysis = analyzer.currentAnalysis

        #expect(analysis.activeBrushingSeconds == 0)
        #expect(analysis.longestSinglePositionSeconds == 0)
    }

    @Test func idleTimeDoesNotTriggerThePositionNudgeEarly() {
        var analyzer = LiveSessionAnalyzer()
        // Forty idle seconds in one posture, then a short brush. Wall-clock hold
        // is well past the nudge threshold; brushing time in that posture is not.
        _ = analyzer.ingest(IntegrityFixture.still(seconds: 40, from: 0))
        let insights = analyzer.ingest(IntegrityFixture.brushing(seconds: 6, from: 40))

        let nudged = insights.contains { insight in
            if case .heldOnePositionTooLong = insight { return true }
            return false
        }
        #expect(!nudged)
    }

    @Test func sustainedBrushingInOnePositionStillNudges() {
        var analyzer = LiveSessionAnalyzer(
            configuration: LiveSessionAnalyzerConfiguration(singlePositionNudgeSeconds: 10)
        )
        let insights = analyzer.ingest(IntegrityFixture.brushing(seconds: 30, from: 0))
        let nudged = insights.contains { insight in
            if case .heldOnePositionTooLong = insight { return true }
            return false
        }
        #expect(nudged)
        #expect(analyzer.currentAnalysis.longestSinglePositionSeconds >= 10)
    }
}

// MARK: - Fixtures

private enum IntegrityFixture {
    static func brushing(seconds: TimeInterval, from start: TimeInterval) -> [MotionSample] {
        series(seconds: seconds, from: start) { time in
            let phase = 2 * Double.pi * 3 * time
            return (
                Vector3(x: 0.32 * sin(phase), y: 0.1 * sin(phase), z: 0),
                Vector3(x: 1.3 * cos(phase), y: 0, z: 0)
            )
        }
    }

    static func still(seconds: TimeInterval, from start: TimeInterval) -> [MotionSample] {
        series(seconds: seconds, from: start) { _ in
            (Vector3(x: 0, y: 0, z: 0), Vector3(x: 0, y: 0, z: 0))
        }
    }

    private static func series(
        seconds: TimeInterval,
        from start: TimeInterval,
        rateHz: Double = 50,
        _ build: (TimeInterval) -> (Vector3, Vector3)
    ) -> [MotionSample] {
        let count = Int(seconds * rateHz)
        return (0..<count).map { index in
            let offset = Double(index) / rateHz
            let (acceleration, rotation) = build(offset)
            return MotionSample(
                timestamp: start + offset,
                userAcceleration: acceleration,
                rotationRate: rotation,
                gravity: Vector3(x: 0, y: -1, z: 0),
                attitude: Quaternion(x: 0, y: 0, z: 0, w: 1)
            )
        }
    }
}
