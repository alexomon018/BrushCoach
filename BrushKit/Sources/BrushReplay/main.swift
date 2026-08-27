import BrushKit
import Foundation

@main
struct BrushReplayCommand {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard !arguments.isEmpty, !arguments.contains("--help") else {
            printUsage()
            return
        }

        var hadFailure = false
        for path in arguments where !path.hasPrefix("--") {
            do {
                try replay(path: path)
            } catch {
                hadFailure = true
                FileHandle.standardError.write(Data("brush-replay: \(path): \(error)\n".utf8))
            }
        }
        if hadFailure { throw Exit.failure }
    }

    private static func replay(path: String) throws {
        let url = URL(fileURLWithPath: path)
        let trace = try TraceJSON.decoder().decode(LabelledMotionTrace.self, from: Data(contentsOf: url))

        var pipeline = MotionPipeline()
        let windows = pipeline.process(trace.samples)

        let plan = SessionPlan(zones: [.upperRight, .upperCentre, .upperLeft, .lowerLeft, .lowerCentre, .lowerRight], secondsPerZone: 20)
        var engine = SessionEngine(configuration: SessionEngineConfiguration(plan: plan))
        let events = engine.ingest(trace.samples)

        print("\(url.lastPathComponent)")
        print("  label: \(trace.metadata.label.displayName)")
        print("  raw: \(trace.samples.count) samples, \(format(trace.actualDuration)) s, \(format(trace.actualSampleRateHz)) Hz actual")
        print("  pipeline: \(windows.count) feature windows, schema v\(FeatureVector.schemaVersion)")
        if let first = windows.first {
            let frequency = first["accel_dominant_frequency_hz"] ?? 0
            let energy = first["accel_spectral_energy"] ?? 0
            print("  first window: dominant \(format(frequency)) Hz, energy \(format(energy)), \(first.values.count) features")
        }
        let classifications = events.reduce(0) { count, event in
            if case .windowClassified = event { count + 1 } else { count }
        }
        print("  engine: \(events.count) events (\(classifications) classified windows)")
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    private static func printUsage() {
        print("""
        Usage: brush-replay TRACE.json [TRACE.json ...]

        Replays labelled watch traces through BrushKit's timestamp-aware 50 Hz
        MotionPipeline and pure SessionEngine. No trace data leaves this machine.
        """)
    }

    private enum Exit: Error { case failure }
}
