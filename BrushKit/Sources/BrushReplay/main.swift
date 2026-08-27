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

        let paths = arguments.filter { !$0.hasPrefix("--") }
        guard !paths.isEmpty else {
            printUsage()
            return
        }

        if arguments.contains("--separability") {
            try separability(paths: paths)
            return
        }

        var hadFailure = false
        for path in paths {
            do {
                try replay(path: path)
            } catch {
                hadFailure = true
                FileHandle.standardError.write(Data("brush-replay: \(path): \(error)\n".utf8))
            }
        }
        if hadFailure { throw Exit.failure }
    }

    // MARK: - Replay

    private static func replay(path: String) throws {
        let url = URL(fileURLWithPath: path)
        let trace = try load(url)

        var pipeline = MotionPipeline()
        let windows = pipeline.process(trace.samples)

        var analyzer = LiveSessionAnalyzer()
        _ = analyzer.ingest(trace.samples)
        let analysis = analyzer.currentAnalysis

        print("\(url.lastPathComponent)")
        print("  label: \(trace.metadata.label.displayName)")
        print("  raw: \(trace.samples.count) samples, \(format(trace.actualDuration)) s, \(format(trace.actualSampleRateHz)) Hz actual")
        print("  pipeline: \(windows.count) feature windows, schema v\(FeatureVector.schemaVersion)")
        if let first = windows.first {
            let frequency = first["accel_dominant_frequency_hz"] ?? 0
            let energy = first["accel_spectral_energy"] ?? 0
            print("  first window: dominant \(format(frequency)) Hz, energy \(format(energy)), \(first.values.count) features")
        }
        print("  analysis: \(format(analysis.activeBrushingSeconds)) s active, \(format(analysis.fastStrokeSeconds)) s fast")
        print("            \(analysis.positionChanges) position changes, longest hold \(format(analysis.longestSinglePositionSeconds)) s")
        print("            median \(format(analysis.medianStrokeRatePerMinute)) strokes/min\(analysis.isInconclusive ? "  (INCONCLUSIVE)" : "")")
    }

    // MARK: - Separability

    /// Answers the one question that decides whether the verification tier is
    /// real: on your own recorded traces, does idle separate from brushing?
    ///
    /// Everything downstream — real brushing time, stroke coaching, the paid
    /// tier — rests on this. It is deliberately reported as measured numbers and
    /// a best achievable threshold rather than a pass/fail, because the answer
    /// is a distribution, not a verdict.
    private static func separability(paths: [String]) throws {
        var idle: [Scored] = []
        var brushing: [Scored] = []
        var transition: [Scored] = []
        var skipped = 0

        let detector = ActivityDetector()

        for path in paths {
            let url = URL(fileURLWithPath: path)
            guard let trace = try? load(url) else {
                skipped += 1
                FileHandle.standardError.write(Data("brush-replay: skipped unreadable \(url.lastPathComponent)\n".utf8))
                continue
            }
            var pipeline = MotionPipeline()
            let windows = pipeline.process(trace.samples)
            let scored = windows.map { window -> Scored in
                let score = detector.score(window)
                return Scored(energy: score.energy, strokeRate: score.strokeRatePerMinute, isRhythmic: score.isRhythmic)
            }

            switch trace.metadata.label {
            case .idle: idle += scored
            case .transition: transition += scored
            default: brushing += scored
            }
        }

        print("Separability report")
        print("  traces read: \(paths.count - skipped)\(skipped > 0 ? " (\(skipped) skipped)" : "")")
        print("")

        guard !idle.isEmpty, !brushing.isEmpty else {
            print("  Not enough labelled data. Record traces labelled Idle *and* at least one")
            print("  mouth zone, then run this again. Zone labels all count as brushing here.")
            return
        }

        report("idle", idle)
        report("brushing", brushing)
        if !transition.isEmpty { report("transition", transition) }
        print("")

        let best = bestThreshold(idle: idle.map(\.energy), brushing: brushing.map(\.energy))
        let shipped = ActivityDetectorConfiguration()
        let shippedAccuracy = accuracy(
            threshold: shipped.enterBrushingEnergy,
            idle: idle.map(\.energy),
            brushing: brushing.map(\.energy)
        )

        let rhythmSensitivity = fraction(brushing, \.isRhythmic)
        let rhythmFalsePositive = fraction(idle, \.isRhythmic)
        let fullBest = fullRuleAccuracy(threshold: best.threshold, idle: idle, brushing: brushing)
        let fullShipped = fullRuleAccuracy(threshold: shipped.enterBrushingEnergy, idle: idle, brushing: brushing)

        print("  Energy threshold, in isolation")
        print("    best separating value: \(format(best.threshold, places: 4)) → \(percent(best.accuracy)) of windows correct")
        print("    shipped default (\(format(shipped.enterBrushingEnergy, places: 4))): \(percent(shippedAccuracy)) correct")
        print("")
        print("  Rhythm gate (\(format(shipped.minimumStrokeFrequencyHz))–\(format(shipped.maximumStrokeFrequencyHz)) Hz)")
        print("    brushing windows judged rhythmic: \(percent(rhythmSensitivity))")
        print("    idle windows judged rhythmic:     \(percent(rhythmFalsePositive))")
        print("")
        print("  Full detector (energy AND rhythm) — this is what the app runs")
        print("    at best energy value:  \(percent(fullBest))")
        print("    at shipped default:    \(percent(fullShipped))")
        print("")

        // The verdict is based on the combined rule, never on energy alone.
        // Energy can separate perfectly while the rhythm gate rejects every
        // brushing window, which would score well here and detect nothing on
        // the wrist.
        let verdict: String
        if rhythmSensitivity < 0.5 {
            verdict = """
            Blocked by the rhythm gate. Energy separates at \(percent(best.accuracy)), but only \(percent(rhythmSensitivity)) of             brushing windows register a stroke inside \(format(shipped.minimumStrokeFrequencyHz))–\(format(shipped.maximumStrokeFrequencyHz)) Hz,             so the app would detect almost nothing. Widen the band in ActivityDetectorConfiguration and re-run before changing anything else.
            """
        } else if fullBest >= 0.9 {
            verdict = "Strong. Brushing time is worth shipping; consider tuning the default to the best energy value above."
        } else if fullBest >= 0.75 {
            verdict = "Workable but noisy. Ship it only with visible uncertainty, and record more varied traces first."
        } else {
            verdict = "Weak. Do not ship a verification tier on this data. Record more traces, and check the Watch was on the brushing hand."
        }
        print("  Verdict: \(verdict)")
    }

    private struct Scored {
        let energy: Double
        let strokeRate: Double
        let isRhythmic: Bool
    }

    private static func report(_ name: String, _ values: [Scored]) {
        let energies = values.map(\.energy).sorted()
        print("  \(name): \(values.count) windows")
        print("    energy   median \(format(percentile(energies, 0.5), places: 4))   p10 \(format(percentile(energies, 0.1), places: 4))   p90 \(format(percentile(energies, 0.9), places: 4))")
        let rates = values.filter(\.isRhythmic).map(\.strokeRate).sorted()
        if rates.isEmpty {
            print("    strokes  no rhythmic windows")
        } else {
            print("    strokes  median \(format(percentile(rates, 0.5))) /min")
        }
    }

    /// Sweeps every midpoint between observed values and keeps the split that
    /// classifies the most windows correctly.
    private static func bestThreshold(idle: [Double], brushing: [Double]) -> (threshold: Double, accuracy: Double) {
        let observed = Set(idle + brushing).sorted()
        guard let lowest = observed.first, let highest = observed.last else { return (0, 0) }

        // Midpoints between observed values, plus the two degenerate splits:
        // below everything (call it all brushing) and above everything (call it
        // all idle). When one class dominates, a degenerate split really is the
        // most accurate one, and omitting it reports a "best" that is not.
        var candidates: [Double] = [lowest - 1, highest + 1]
        for (index, value) in observed.enumerated() where index + 1 < observed.count {
            candidates.append((value + observed[index + 1]) / 2)
        }

        var best = (threshold: candidates[0], accuracy: -1.0)
        for threshold in candidates {
            let score = accuracy(threshold: threshold, idle: idle, brushing: brushing)
            if score > best.accuracy { best = (threshold, score) }
        }
        return best
    }

    /// Accuracy of the rule the app actually runs: energy over the threshold
    /// **and** an oscillation inside the stroke band. Energy alone is what the
    /// sweep optimises, but it is not what ships.
    private static func fullRuleAccuracy(
        threshold: Double,
        idle: [Scored],
        brushing: [Scored]
    ) -> Double {
        let correct = idle.filter { !($0.energy >= threshold && $0.isRhythmic) }.count
            + brushing.filter { $0.energy >= threshold && $0.isRhythmic }.count
        let total = idle.count + brushing.count
        return total == 0 ? 0 : Double(correct) / Double(total)
    }

    private static func accuracy(threshold: Double, idle: [Double], brushing: [Double]) -> Double {
        let correct = idle.filter { $0 < threshold }.count + brushing.filter { $0 >= threshold }.count
        let total = idle.count + brushing.count
        return total == 0 ? 0 : Double(correct) / Double(total)
    }

    private static func fraction(_ values: [Scored], _ keyPath: KeyPath<Scored, Bool>) -> Double {
        guard !values.isEmpty else { return 0 }
        return Double(values.filter { $0[keyPath: keyPath] }.count) / Double(values.count)
    }

    private static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = Int((Double(sorted.count - 1) * fraction).rounded())
        return sorted[min(sorted.count - 1, max(0, index))]
    }

    // MARK: - Helpers

    private static func load(_ url: URL) throws -> LabelledMotionTrace {
        try TraceJSON.decoder().decode(LabelledMotionTrace.self, from: Data(contentsOf: url))
    }

    private static func format(_ value: Double, places: Int = 2) -> String {
        value.formatted(.number.precision(.fractionLength(places)))
    }

    private static func percent(_ value: Double) -> String {
        (value * 100).formatted(.number.precision(.fractionLength(1))) + "%"
    }

    private static func printUsage() {
        print("""
        Usage: brush-replay [--separability] TRACE.json [TRACE.json ...]

        Replays labelled watch traces through BrushKit's timestamp-aware 50 Hz
        MotionPipeline and LiveSessionAnalyzer.

          --separability   Pool the traces by label and report whether idle
                           separates from brushing, the best achievable energy
                           threshold, and how the shipped default compares.
                           Needs traces labelled Idle and at least one zone.

        No trace data leaves this machine.
        """)
    }

    private enum Exit: Error { case failure }
}
