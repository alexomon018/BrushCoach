import BrushKit
import Foundation
import Observation
import WatchKit

@MainActor
@Observable
final class CoachViewModel {
    struct SessionSummary: Equatable {
        var session: BrushSession
        var nextSteps: [String]
        var capability: SensingCapability
    }

    enum Phase: Equatable {
        case ready
        case countdown(Int)
        case brushing
        case paused
        case completed(SessionSummary)
        case failed(String)
    }

    private(set) var phase: Phase = .ready
    private(set) var elapsed: TimeInterval = 0
    private(set) var currentZoneIndex = 0

    /// What motion analysis is seeing right now, or `nil` when it is not running.
    private(set) var liveActivity: MotionActivity?
    private(set) var liveBrushingSeconds: TimeInterval = 0
    /// Latest confident zone estimate. `nil` whenever there is no calibration
    /// profile, or the estimate is not confident enough to show.
    private(set) var liveZone: BrushZoneLabel?

    @ObservationIgnored private let runtime = ExtendedRuntimeController()
    @ObservationIgnored private let recorder = WatchMotionRecorder()
    @ObservationIgnored private var workTask: Task<Void, Never>?
    @ObservationIgnored private var motionTask: Task<Void, Never>?
    @ObservationIgnored private var analyzer = LiveSessionAnalyzer()
    @ObservationIgnored private var didSenseMotion = false
    @ObservationIgnored private var lastStrokeRateNudge: Date?
    @ObservationIgnored private var isStoppingMotionDeliberately = false
    @ObservationIgnored private let timeline = RoutineTimeline()
    /// Elapsed time is derived from wall-clock instants, never accumulated from
    /// ticks, so a suspended process cannot make the session drift. See
    /// `SessionClockTests` for the properties this relies on.
    @ObservationIgnored private lazy var clock = SessionClock(limit: timeline.totalDuration)
    @ObservationIgnored private var sessionStartedAt: Date?

    /// Resolved fresh each time: the user can move the Watch to the other wrist
    /// or change their answer between sessions.
    var capability: SensingCapability {
        HandednessProfile(
            watchWrist: WKInterfaceDevice.current().wristLocation == .left ? .left : .right,
            brushingHand: WatchRoutinePreferences.current.brushingHand
        ).capability
    }

    /// Whether a usable calibration profile exists. Drives the More menu entry
    /// and whether zone estimates run at all.
    var hasCalibration: Bool { calibrationProfile != nil }

    /// A load failure and an absent profile are both "no usable calibration"
    /// here; the distinction only matters on the calibration screen itself.
    private var calibrationProfile: PersonalCalibrationProfile? {
        try? CalibrationProfileStore.load()
    }

    var isBusy: Bool {
        switch phase {
        case .countdown, .brushing, .paused: true
        default: false
        }
    }

    var isPaused: Bool { phase == .paused }

    var zoneSecondsRemaining: Int {
        timeline.snapshot(elapsed: elapsed).zoneSecondsRemaining
    }

    var progress: Double { min(1, elapsed / timeline.totalDuration) }

    var zoneName: String {
        ["Upper right", "Upper centre", "Upper left", "Lower left", "Lower centre", "Lower right"][currentZoneIndex]
    }

    /// The zone the pacer is currently prompting, as distinct from `liveZone`,
    /// which is where the classifier thinks the brush actually is.
    var scheduledZone: BrushZoneLabel { timeline.plan.zones[currentZoneIndex] }

    func startSession() {
        guard workTask == nil else { return }
        clearRunState()
        workTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await runSession()
            } catch is CancellationError {
                // `endEarly` cancels the task *and* records a partial session, so
                // only fall back to `.ready` if nothing terminal was set already.
                if isBusy { phase = .ready }
            } catch {
                phase = .failed(error.localizedDescription)
                WKInterfaceDevice.current().play(.failure)
            }
            stopMotionAnalysis()
            runtime.end()
            workTask = nil
        }
    }

    func handle(url: URL) {
        guard url.scheme == "brushcoach", url.host == "start" else { return }
        startSession()
    }

    func pause() {
        guard phase == .brushing else { return }
        clock.pause(at: .now)
        elapsed = clock.elapsed(at: .now)
        phase = .paused
        // Motion keeps arriving while paused; none of it is this session's
        // brushing, and a window spanning the pause would be interpolated
        // across the gap.
        analyzer.suspend()
        liveActivity = nil
        liveZone = nil
        WKInterfaceDevice.current().play(.stop)
    }

    func resume() {
        guard phase == .paused else { return }
        clock.resume(at: .now)
        phase = .brushing
        WKInterfaceDevice.current().play(.start)
    }

    /// Ends the session early, keeping credit for the zones already brushed.
    /// Discarding a nearly complete brush is the failure users resent most.
    func endEarly() {
        let now = Date.now
        clock.stop(at: now)
        let banked = clock.elapsed(at: now)
        workTask?.cancel()
        stopMotionAnalysis()
        runtime.end()

        let snapshot = timeline.snapshot(elapsed: banked)
        guard let startedAt = sessionStartedAt, snapshot.zonesCompleted > 0 else {
            reset()
            return
        }
        finish(
            startedAt: startedAt,
            duration: banked,
            zonesCompleted: snapshot.zonesCompleted
        )
    }

    /// Abandons the session without recording anything.
    func discard() {
        workTask?.cancel()
        stopMotionAnalysis()
        runtime.end()
        reset()
    }

    private func reset() {
        phase = .ready
        clearRunState()
    }

    private func clearRunState() {
        elapsed = 0
        currentZoneIndex = 0
        clock.reset()
        sessionStartedAt = nil
        liveActivity = nil
        liveBrushingSeconds = 0
        liveZone = nil
        didSenseMotion = false
        lastStrokeRateNudge = nil
        analyzer.reset()
    }

    private func pendingSteps() -> [String] {
        let preferences = WatchRoutinePreferences.current
        var steps: [String] = []
        if preferences.flossPromptEnabled { steps.append("Floss between teeth") }
        if preferences.tonguePromptEnabled { steps.append("Clean your tongue") }
        return steps
    }

    func finishSummary() { reset() }
    func dismissError() { reset() }
    func markFlossed() { updateSummary { $0.flossed = true } }
    func markTongueCleaned() { updateSummary { $0.tongueCleaned = true } }

    private func runSession() async throws {
        runtime.begin()
        for count in stride(from: 3, through: 1, by: -1) {
            phase = .countdown(count)
            WKInterfaceDevice.current().play(.click)
            try await Task.sleep(for: .seconds(1))
        }

        let startedAt = Date.now
        sessionStartedAt = startedAt
        clock.start(at: startedAt)
        phase = .brushing
        WKInterfaceDevice.current().play(.start)
        startMotionAnalysis()

        while true {
            try Task.checkCancellation()
            guard phase != .paused else {
                try await Task.sleep(for: .milliseconds(250))
                continue
            }
            let snapshot = timeline.snapshot(elapsed: clock.elapsed(at: .now))
            elapsed = snapshot.elapsed
            let newIndex = snapshot.currentZoneIndex
            if newIndex > currentZoneIndex {
                currentZoneIndex = newIndex
                // A prominent tap: the wrist is moving and often out of sight.
                WKInterfaceDevice.current().play(.notification)
            }
            if snapshot.isComplete { break }
            // 4 Hz. The dial only renders whole seconds, and this runs for two
            // minutes under extended runtime on a small battery.
            try await Task.sleep(for: .milliseconds(250))
        }

        stopMotionAnalysis()
        let zones = timeline.plan.zones.count
        finish(
            startedAt: startedAt,
            duration: timeline.totalDuration,
            zonesCompleted: zones
        )
    }

    /// Builds and stores the finished session. Pacer facts and analysis facts are
    /// assembled in one place so it stays obvious that the former never depend
    /// on the latter.
    private func finish(startedAt: Date, duration: TimeInterval, zonesCompleted: Int) {
        let session = BrushSession(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(duration),
            duration: duration,
            zonesCompleted: zonesCompleted,
            plannedZones: timeline.plan.zones.count,
            analysis: didSenseMotion ? analyzer.currentAnalysis : nil,
            source: .watch
        )
        try? WatchSessionStore.upsert(session)
        WatchTraceTransfer.shared.enqueue(session)
        phase = .completed(
            SessionSummary(session: session, nextSteps: pendingSteps(), capability: capability)
        )
        WKInterfaceDevice.current().play(.success)
        clearRunState()
    }

    // MARK: - Motion analysis

    /// Runs the recorder beside the pacer rather than driving it. The pacer stays
    /// pure wall-clock, so a sensing failure can slow nothing down and stop
    /// nothing — it only means the summary has less to say.
    private func startMotionAnalysis() {
        guard capability.canSenseMotion, motionTask == nil else { return }
        // Rebuilt per session: the profile can be created, replaced, or cleared
        // between sessions, and a stale classifier is worse than none.
        analyzer = LiveSessionAnalyzer(profile: calibrationProfile)
        isStoppingMotionDeliberately = false

        motionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // A hard ceiling well past the routine, so an abandoned session can
            // never leave device motion running.
            let ceiling = timeline.totalDuration + 60
            do {
                _ = try await recorder.recordUntilStopped(maxDuration: ceiling) { [weak self] sample, _ in
                    guard let self else { return true }
                    // Paused: the pacer is not counting, so neither does analysis.
                    guard phase == .brushing else { return false }
                    didSenseMotion = true
                    let scheduled = timeline.plan.zones[currentZoneIndex]
                    for insight in analyzer.ingest(sample, scheduledZone: scheduled) {
                        handle(insight)
                    }
                    liveActivity = analyzer.currentActivity
                    liveZone = analyzer.currentZone
                    liveBrushingSeconds = analyzer.currentAnalysis.activeBrushingSeconds
                    return false
                }
            } catch is CancellationError {
                // Expected: `stopMotionAnalysis` cancels the recorder when the
                // session ends normally.
            } catch {
                // Core Motion gave up mid-session. Keep what was measured, but
                // never let a truncated recording be read as a whole session.
                if !isStoppingMotionDeliberately { analyzer.markRecordingIncomplete() }
            }
        }
    }

    private func stopMotionAnalysis() {
        guard motionTask != nil else { return }
        isStoppingMotionDeliberately = true
        motionTask?.cancel()
        motionTask = nil
        recorder.cancel()
        liveActivity = nil
        liveZone = nil
    }

    private func handle(_ insight: SessionInsight) {
        switch insight {
        case .strokeRateHigh(let rate):
            nudgeForFastStrokes(rate: rate)
        case .heldOnePositionTooLong:
            // The wrist is moving and usually out of sight; this has to be felt.
            WKInterfaceDevice.current().play(.retry)
        case .activityChanged, .positionChanged, .zoneEstimated:
            // Zone estimates are shown, never felt. A haptic per estimate would
            // fire every second and would be wrong often enough to mislead.
            break
        }
    }

    /// Throttled hard. A fast-stroke window recurs every second while the user is
    /// scrubbing, and a haptic every second is noise the user learns to ignore.
    private func nudgeForFastStrokes(rate: Double) {
        let now = Date.now
        if let last = lastStrokeRateNudge, now.timeIntervalSince(last) < 15 { return }
        lastStrokeRateNudge = now
        WKInterfaceDevice.current().play(.directionDown)
    }

    private func updateSummary(_ update: (inout BrushSession) -> Void) {
        guard case .completed(var summary) = phase else { return }
        update(&summary.session)
        _ = try? WatchSessionStore.upsert(summary.session)
        WatchTraceTransfer.shared.enqueue(summary.session)
        phase = .completed(summary)
        WKInterfaceDevice.current().play(.click)
    }
}
