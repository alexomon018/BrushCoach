import BrushKit
import Foundation
import Observation
import WatchKit

/// The watch-side shell around `SessionCoordinator`.
///
/// The timing rules — countdown, pause, ending early — live in
/// BrushKit where they are unit-tested. What is left here is the part that can
/// only exist on a Watch: haptics, extended runtime, Core Motion, and the
/// handedness and calibration state that decide whether analysis runs at all.
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

    /// What motion analysis is seeing right now, or `nil` when it is not running.
    private(set) var liveActivity: MotionActivity?

    @ObservationIgnored private var coordinator = SessionCoordinator()
    @ObservationIgnored private let runtime = ExtendedRuntimeController()
    @ObservationIgnored private let recorder = WatchMotionRecorder()
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var motionTask: Task<Void, Never>?
    @ObservationIgnored private var analyzer = LiveSessionAnalyzer()
    @ObservationIgnored private var didSenseMotion = false
    @ObservationIgnored private var lastStrokeRateNudge: Date?
    @ObservationIgnored private var isStoppingMotionDeliberately = false
    /// True from the moment analysis starts until the session ends, across any
    /// number of pauses. A resume must not restart the sensor for a session
    /// that never had it running in the first place.
    @ObservationIgnored private var isAnalyzingMotion = false
    @ObservationIgnored private var calibrationProfile: PersonalCalibrationProfile?

    /// The dial only renders whole seconds, and this runs for two minutes under
    /// extended runtime on a small battery.
    private static let tickInterval = Duration.milliseconds(250)

    /// Whether the Watch is on the brushing hand. The user can move it to the
    /// other wrist or change their answer between sessions, so this is resolved
    /// again on every `refreshDeviceState()` rather than once at launch.
    private(set) var capability: SensingCapability = .unknown

    /// Whether a usable calibration profile exists. Drives the More menu entry
    /// and whether zone estimates run at all.
    private(set) var hasCalibration = false

    init() {
        refreshDeviceState()
    }

    /// Re-reads the two pieces of state that live outside this process.
    ///
    /// Both used to be computed properties, which meant every render that
    /// touched them decoded `RoutinePreferences` out of `UserDefaults` and read
    /// and decoded the calibration profile off disk — three of each per render
    /// of the More screen. They change when the user recalibrates or answers
    /// the handedness question, so refreshing on appearance and at session
    /// start covers every case that can actually move them.
    func refreshDeviceState() {
        // A load failure and an absent profile are both "no usable calibration"
        // here; the distinction only matters on the calibration screen itself.
        calibrationProfile = try? CalibrationProfileStore.load()
        hasCalibration = calibrationProfile != nil
        capability = HandednessProfile(
            watchWrist: WKInterfaceDevice.current().wristLocation == .left ? .left : .right,
            brushingHand: WatchRoutinePreferences.current.brushingHand
        ).capability
    }

    var isBusy: Bool { coordinator.isBusy }
    var isPaused: Bool { coordinator.isPaused }
    var secondsRemaining: Int { coordinator.sessionSecondsRemaining }
    var progress: Double { coordinator.progress }

    // MARK: - Intent

    func startSession() {
        guard tickTask == nil else { return }
        refreshDeviceState()
        resetLiveReadings()
        apply(coordinator.start(at: .now))
        startTicking()
    }

    func handle(url: URL) {
        guard url.scheme == "brushcoach", url.host == "start" else { return }
        startSession()
    }

    func pause() { apply(coordinator.pause(at: .now)) }
    func resume() { apply(coordinator.resume(at: .now)) }
    func endEarly() { apply(coordinator.endEarly(at: .now)) }
    func discard() { apply(coordinator.discard()) }

    func finishSummary() { acknowledge() }
    func dismissError() { acknowledge() }
    func markFlossed() { updateSummary { $0.flossed = true } }
    func markTongueCleaned() { updateSummary { $0.tongueCleaned = true } }

    private func acknowledge() {
        apply(coordinator.acknowledge())
        resetLiveReadings()
    }

    // MARK: - The tick loop

    /// One loop, wall-clock driven. The coordinator derives every value from the
    /// instant it is handed, so a tick that arrives late — or not at all while
    /// the process is suspended — cannot make the session drift.
    private func startTicking() {
        tickTask = Task { @MainActor [weak self] in
            while let self, coordinator.isBusy {
                do {
                    try await Task.sleep(for: Self.tickInterval)
                } catch {
                    break
                }
                apply(coordinator.tick(at: .now))
            }
            self?.tickTask = nil
        }
    }

    // MARK: - Effects

    private func apply(_ effects: [SessionCoordinator.Effect]) {
        for effect in effects { perform(effect) }
        syncFromCoordinator()
    }

    private func perform(_ effect: SessionCoordinator.Effect) {
        switch effect {
        case .beginExtendedRuntime:
            runtime.begin()
        case .endExtendedRuntime:
            runtime.end()
        case .startMotionAnalysis:
            startMotionAnalysis()
        case .stopMotionAnalysis:
            stopMotionAnalysis()
        case .suspendMotionAnalysis:
            // None of the motion arriving during a pause is this session's
            // brushing, and a window spanning the pause would be interpolated
            // across the gap. Powering the sensor down rather than discarding
            // its samples is what actually saves the battery — and it stops a
            // long pause from spending the recorder's hard ceiling, which is
            // measured in sensor time and does not know the session is held.
            analyzer.suspend()
            suspendMotionCapture()
            liveActivity = nil
        case .countdownTicked:
            WKInterfaceDevice.current().play(.click)
        case .sessionStarted:
            WKInterfaceDevice.current().play(.start)
        case .sessionResumed:
            WKInterfaceDevice.current().play(.start)
            resumeMotionCapture()
        case .sessionPaused:
            WKInterfaceDevice.current().play(.stop)
        case .advancedToZone:
            // Free brushing has no timed zone changes. This legacy coordinator
            // effect is intentionally silent if received from an older plan.
            break
        case .finished(let outcome):
            record(outcome)
        case .failed(let message):
            phase = .failed(message)
            WKInterfaceDevice.current().play(.failure)
        }
    }

    /// Mirrors the pacer's state onto the observable properties the views read.
    /// The two terminal phases are set while handling their effect, because each
    /// carries a payload the coordinator does not have.
    private func syncFromCoordinator() {
        elapsed = coordinator.elapsed
        switch coordinator.phase {
        case .ready: phase = .ready
        case .countdown(let remaining): phase = .countdown(remaining)
        case .brushing: phase = .brushing
        case .paused: phase = .paused
        case .finished, .failed: break
        }
    }

    /// Builds and stores the finished session. The timer's facts arrive in
    /// `outcome`; analysis is attached here and only here, so it stays obvious
    /// that the former never depend on the latter.
    private func record(_ outcome: SessionCoordinator.PacerOutcome) {
        let session = BrushSession(
            startedAt: outcome.startedAt,
            endedAt: outcome.startedAt.addingTimeInterval(outcome.duration),
            duration: outcome.duration,
            zonesCompleted: outcome.zonesCompleted,
            plannedZones: outcome.plannedZones,
            analysis: didSenseMotion ? analyzer.currentAnalysis : nil,
            source: .watch
        )
        _ = try? WatchSessionStore.upsert(session)
        WatchTraceTransfer.shared.enqueue(session)
        phase = .completed(
            SessionSummary(session: session, nextSteps: pendingSteps(), capability: capability)
        )
        WKInterfaceDevice.current().play(.success)
    }

    private func pendingSteps() -> [String] {
        let preferences = WatchRoutinePreferences.current
        var steps: [String] = []
        if preferences.flossPromptEnabled { steps.append("Floss between teeth") }
        if preferences.tonguePromptEnabled { steps.append("Clean your tongue") }
        return steps
    }

    private func updateSummary(_ update: (inout BrushSession) -> Void) {
        guard case .completed(var summary) = phase else { return }
        update(&summary.session)
        _ = try? WatchSessionStore.upsert(summary.session)
        WatchTraceTransfer.shared.enqueue(summary.session)
        phase = .completed(summary)
        WKInterfaceDevice.current().play(.click)
    }

    private func resetLiveReadings() {
        liveActivity = nil
        didSenseMotion = false
        isAnalyzingMotion = false
        lastStrokeRateNudge = nil
        analyzer.reset()
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
        isAnalyzingMotion = true
        beginCapture()
    }

    /// Restarts the sensor after a pause without touching the analyzer: the
    /// seconds it measured before the pause belong to this session and have to
    /// survive it.
    private func resumeMotionCapture() {
        guard isAnalyzingMotion, motionTask == nil else { return }
        beginCapture()
    }

    private func beginCapture() {
        isStoppingMotionDeliberately = false

        motionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // A hard ceiling well past the routine, so an abandoned session can
            // never leave device motion running. It applies per capture stretch;
            // stopping through a pause is what keeps a held session from
            // spending it while nothing is being measured.
            let ceiling = coordinator.timeline.totalDuration + 60
            do {
                _ = try await recorder.recordUntilStopped(
                    maxDuration: ceiling,
                    // Analysis is streamed sample by sample below, so the
                    // finished trace is never read. Keeping it cost about a
                    // megabyte held for the length of the session.
                    retainsSamples: false
                ) { [weak self] sample, _ in
                    guard let self else { return true }
                    // The sensor is stopped on pause, so this only covers the
                    // sample or two already in flight when that happens.
                    guard phase == .brushing else { return false }
                    didSenseMotion = true
                    for insight in analyzer.ingest(sample) {
                        handle(insight)
                    }
                    // Assigning an `@Observable` property notifies on every
                    // write, equal value or not, and the analyzer only emits a
                    // feature window once a second. Writing this per sample
                    // invalidated the whole active screen fifty times for each
                    // value that could actually differ.
                    let activity = analyzer.currentActivity
                    if activity != liveActivity { liveActivity = activity }
                    return false
                }
            } catch is CancellationError {
                // Expected: pausing and ending both cancel the recorder.
            } catch {
                // Core Motion gave up mid-session. Keep what was measured, but
                // never let a truncated recording be read as a whole session.
                if !isStoppingMotionDeliberately { analyzer.markRecordingIncomplete() }
            }
            // Only reached without cancellation when the ceiling was hit; the
            // cancelling paths have already cleared this and may have started a
            // fresh capture that must not be dropped here.
            if !Task.isCancelled { motionTask = nil }
        }
    }

    /// Cancels the capture but keeps the session's analysis alive, so a resume
    /// can pick it back up.
    private func suspendMotionCapture() {
        guard motionTask != nil else { return }
        isStoppingMotionDeliberately = true
        motionTask?.cancel()
        motionTask = nil
        recorder.cancel()
    }

    private func stopMotionAnalysis() {
        guard isAnalyzingMotion else { return }
        suspendMotionCapture()
        isAnalyzingMotion = false
        liveActivity = nil
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
}
