import BrushKit
import Foundation
import Observation
import WatchKit

/// Drives one guided calibration run.
///
/// Motion is recorded continuously for the whole run and the collector's stage
/// is switched underneath it, rather than starting and stopping Core Motion per
/// zone. Restarting device motion drops the first samples every time, and six
/// restarts would quietly bias every zone prototype toward its own tail.
@MainActor
@Observable
final class CalibrationViewModel {
    enum Phase: Equatable {
        case intro
        case baseline(secondsRemaining: Int)
        case reposition(zoneIndex: Int, secondsRemaining: Int)
        case capturing(zoneIndex: Int, secondsRemaining: Int)
        case building
        case complete(quality: Double)
        case failed(String)
    }

    private(set) var phase: Phase = .intro
    /// Windows banked for the stage in progress, so a stage collecting nothing
    /// is visible while it happens rather than at the end.
    private(set) var stageWindows = 0

    @ObservationIgnored private let plan = CalibrationPlan()
    @ObservationIgnored private var collector = CalibrationCollector()
    @ObservationIgnored private let recorder = WatchMotionRecorder()
    @ObservationIgnored private let runtime = ExtendedRuntimeController()
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var motionTask: Task<Void, Never>?

    var isRunning: Bool {
        switch phase {
        case .intro, .complete, .failed: false
        default: true
        }
    }

    var estimatedMinutes: Int { max(1, Int((plan.totalDuration / 60).rounded())) }

    var zoneNames: [String] { plan.zones.map(\.displayName) }

    func start() {
        guard runTask == nil else { return }
        collector.reset()
        runtime.begin()
        startRecording()

        runTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await run()
            } catch is CancellationError {
                // Cancelled by the user; `cancel()` has already set the phase.
            } catch {
                phase = .failed(error.localizedDescription)
                WKInterfaceDevice.current().play(.failure)
            }
            stopRecording()
            runtime.end()
            runTask = nil
        }
    }

    func cancel() {
        runTask?.cancel()
        runTask = nil
        stopRecording()
        runtime.end()
        collector.reset()
        phase = .intro
        stageWindows = 0
    }

    func dismiss() {
        phase = .intro
        stageWindows = 0
    }

    private func run() async throws {
        try await hold(
            for: plan.baselineDuration,
            stage: .baseline
        ) { .baseline(secondsRemaining: $0) }

        for index in plan.zones.indices {
            WKInterfaceDevice.current().play(.notification)
            try await hold(
                for: plan.repositionDuration,
                stage: nil
            ) { .reposition(zoneIndex: index, secondsRemaining: $0) }

            WKInterfaceDevice.current().play(.start)
            try await hold(
                for: plan.zoneDuration,
                stage: .zone(index)
            ) { .capturing(zoneIndex: index, secondsRemaining: $0) }
        }

        phase = .building
        stopRecording()

        let wrist: WatchWrist = WKInterfaceDevice.current().wristLocation == .left ? .left : .right
        let profile = try collector.build(watchWrist: wrist)
        // Only now does the new profile replace the old one. A run that fails to
        // build leaves whatever was working before untouched.
        try CalibrationProfileStore.save(profile)
        phase = .complete(quality: profile.calibrationQuality)
        WKInterfaceDevice.current().play(.success)
    }

    /// Holds one stage for a wall-clock duration, updating the countdown as it
    /// goes. Wall-clock rather than tick-counting for the same reason the pacer
    /// is: a suspended process must not stretch a twenty-second capture.
    private func hold(
        for duration: TimeInterval,
        stage: CalibrationStage?,
        phase build: (Int) -> Phase
    ) async throws {
        if let stage {
            collector.begin(stage)
        } else {
            collector.pause()
        }
        stageWindows = 0

        let deadline = Date.now.addingTimeInterval(duration)
        while true {
            try Task.checkCancellation()
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            phase = build(Int(ceil(remaining)))
            if let stage { stageWindows = collector.windowCount(for: stage) }
            try await Task.sleep(for: .milliseconds(200))
        }
        if let stage { stageWindows = collector.windowCount(for: stage) }
    }

    private func startRecording() {
        guard motionTask == nil else { return }
        motionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            _ = try? await recorder.recordUntilStopped(maxDuration: plan.totalDuration + 60) { [weak self] sample, _ in
                guard let self else { return true }
                collector.ingest(sample)
                return false
            }
        }
    }

    private func stopRecording() {
        guard motionTask != nil else { return }
        motionTask?.cancel()
        motionTask = nil
        recorder.cancel()
    }
}
