import XCTest
@testable import BrushKit

final class MotionPipelineTests: XCTestCase {
    func testResamplerUsesTimestampsInsteadOfAssumingUniformInput() {
        var resampler = TimestampResampler(sampleRateHz: 50)
        let timestamps = stride(from: 0.0, through: 1.0, by: 0.031).map { $0 }
        let output = timestamps.flatMap { resampler.append(sample(at: $0, accelerationX: $0)) }

        XCTAssertLessThanOrEqual(abs(output.count - 50), 1)
        for pair in zip(output, output.dropFirst()) {
            XCTAssertEqual(pair.1.timestamp - pair.0.timestamp, 0.02, accuracy: 0.000_001)
        }
    }

    func testFeatureExtractorFindsThreeHertzStrokeSignal() {
        let samples = (0..<100).map { index in
            let timestamp = Double(index) / 50
            return sample(at: timestamp, accelerationX: sin(2 * .pi * 3 * timestamp))
        }

        let features = FeatureExtractor().extract(from: samples)

        XCTAssertEqual(features.schemaVersion, 1)
        XCTAssertEqual(features.values.count, 91)
        XCTAssertEqual(features.names.count, features.values.count)
        XCTAssertEqual(try XCTUnwrap(features["accel_dominant_frequency_hz"]), 3, accuracy: 0.001)
        XCTAssertTrue(features.values.allSatisfy(\.isFinite))
    }

    func testPipelineCreatesOverlappingTwoSecondWindows() {
        var pipeline = MotionPipeline()
        let samples = (0...150).map { index in
            let jitter = index.isMultiple(of: 3) ? 0.001 : -0.001
            return sample(at: max(0, Double(index) / 50 + jitter), accelerationX: Double(index) / 150)
        }

        let windows = pipeline.process(samples)

        XCTAssertEqual(windows.count, 2)
        guard windows.count == 2 else { return }
        XCTAssertEqual(windows[0].windowStart, 0, accuracy: 0.001)
        XCTAssertEqual(windows[1].windowStart, 1, accuracy: 0.021)
    }

    func testFixtureReplaysThroughPipelineAndAnalyzer() throws {
        let fixtureURL = try XCTUnwrap(Bundle.module.url(forResource: "short-trace", withExtension: "json", subdirectory: "Fixtures"))
        let trace = try TraceJSON.decoder().decode(
            LabelledMotionTrace.self,
            from: Data(contentsOf: fixtureURL)
        )
        var pipeline = MotionPipeline(sampleRateHz: 5, windowDuration: 2, overlap: 0.5)
        XCTAssertEqual(pipeline.process(trace.samples).count, 1)

        // Recorded JSON has to survive a round trip into the analysis path, not
        // just into the feature pipeline.
        var analyzer = LiveSessionAnalyzer()
        _ = analyzer.ingest(trace.samples)
        let analysis = analyzer.currentAnalysis
        XCTAssertGreaterThan(analysis.windowCount, 0)
        // Two seconds of trace cannot support a conclusion, and the analyzer
        // must say so rather than reporting zero.
        XCTAssertTrue(analysis.isInconclusive)
    }

    func testPersonalCalibrationRecognizesIdleAndAZone() throws {
        let zones = PersonalCalibrationBuilder.requiredZones
        let idle = (0..<4).map { index in
            syntheticFeatures(zoneValue: 0, activityValue: 0.02 + Double(index) * 0.002)
        }
        let zoneWindows = Dictionary(uniqueKeysWithValues: zones.enumerated().map { index, zone in
            let value = Double(index + 1)
            let windows = (0..<8).map { sampleIndex in
                syntheticFeatures(
                    zoneValue: value + Double(sampleIndex) * 0.01,
                    activityValue: 2 + Double(sampleIndex) * 0.01
                )
            }
            return (zone, windows)
        })

        let profile = try PersonalCalibrationBuilder().build(
            watchWrist: .left,
            idleWindows: idle,
            zoneWindows: zoneWindows
        )
        let classifier = PersonalZoneClassifier(profile: profile)

        let brushing = classifier.classify(
            syntheticFeatures(zoneValue: 3.03, activityValue: 2.03),
            scheduledZone: .upperRight
        )
        XCTAssertEqual(brushing.activity, .brushing)
        XCTAssertEqual(brushing.zone, zones[2])
        XCTAssertGreaterThan(brushing.confidence, 0)

        let still = classifier.classify(
            syntheticFeatures(zoneValue: 0, activityValue: 0.021),
            scheduledZone: .upperRight
        )
        XCTAssertEqual(still.activity, .idle)
        XCTAssertNil(still.zone)
        XCTAssertGreaterThan(profile.calibrationQuality, 0.9)
    }

    func testPredictionSmootherUsesARecentMajority() {
        var smoother = PredictionSmoother(capacity: 3)
        let left = ClassificationResult(
            activity: .brushing,
            zone: .upperLeft,
            side: .left,
            jaw: .upper,
            confidence: 0.8
        )
        let right = ClassificationResult(
            activity: .brushing,
            zone: .upperRight,
            side: .right,
            jaw: .upper,
            confidence: 0.3
        )

        _ = smoother.ingest(left)
        _ = smoother.ingest(right)
        let result = smoother.ingest(left)

        XCTAssertEqual(result.activity, .brushing)
        XCTAssertEqual(result.zone, .upperLeft)
        // The majority wins, but smoothing must not manufacture more certainty
        // than the winning windows actually had.
        XCTAssertGreaterThan(result.confidence, 0.5)
        XCTAssertLessThanOrEqual(result.confidence, 0.8)
    }

    /// Vote share alone would call three unanimous coin-flips a certainty.
    func testUnanimousButUnsurePredictionsStayUnsure() {
        var smoother = PredictionSmoother(capacity: 3)
        let unsure = ClassificationResult(
            activity: .brushing,
            zone: .lowerLeft,
            side: .left,
            jaw: .lower,
            confidence: 0.12
        )

        _ = smoother.ingest(unsure)
        _ = smoother.ingest(unsure)
        let result = smoother.ingest(unsure)

        XCTAssertEqual(result.zone, .lowerLeft)
        XCTAssertLessThanOrEqual(result.confidence, 0.15)
    }

    private func sample(at timestamp: TimeInterval, accelerationX: Double) -> MotionSample {
        MotionSample(
            timestamp: timestamp,
            userAcceleration: Vector3(x: accelerationX, y: 0, z: 0),
            rotationRate: Vector3(x: 0, y: 0, z: 0),
            gravity: Vector3(x: 0, y: -1, z: 0),
            attitude: Quaternion(x: 0, y: 0, z: 0, w: 1)
        )
    }

    private func syntheticFeatures(zoneValue: Double, activityValue: Double) -> FeatureVector {
        var names: [String] = []
        for name in PersonalCalibrationBuilder.zoneFeatureNames + PersonalCalibrationBuilder.activityFeatureNames
        where !names.contains(name) {
            names.append(name)
        }
        let zoneNames = Set(PersonalCalibrationBuilder.zoneFeatureNames)
        let activityNames = Set(PersonalCalibrationBuilder.activityFeatureNames)
        let values = names.map { name in
            if zoneNames.contains(name), !activityNames.contains(name) { return zoneValue }
            if activityNames.contains(name), !zoneNames.contains(name) { return activityValue }
            if zoneNames.contains(name), activityNames.contains(name) {
                return zoneValue + activityValue
            }
            return 0
        }
        return FeatureVector(windowStart: 0, windowEnd: 2, names: names, values: values)
    }
}
