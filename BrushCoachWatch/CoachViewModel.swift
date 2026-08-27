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

    @ObservationIgnored private let runtime = ExtendedRuntimeController()
    @ObservationIgnored private var workTask: Task<Void, Never>?
    @ObservationIgnored private let timeline = RoutineTimeline()
    /// Elapsed time is derived from wall-clock instants, never accumulated from
    /// ticks, so a suspended process cannot make the session drift. See
    /// `SessionClockTests` for the properties this relies on.
    @ObservationIgnored private lazy var clock = SessionClock(limit: timeline.totalDuration)
    @ObservationIgnored private var sessionStartedAt: Date?

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

    var totalSecondsRemaining: Int { max(0, Int(ceil(timeline.totalDuration - elapsed))) }
    var progress: Double { min(1, elapsed / timeline.totalDuration) }

    var zoneName: String {
        ["Upper right", "Upper centre", "Upper left", "Lower left", "Lower centre", "Lower right"][currentZoneIndex]
    }

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
        runtime.end()

        let snapshot = timeline.snapshot(elapsed: banked)
        guard let startedAt = sessionStartedAt, snapshot.zonesCompleted > 0 else {
            reset()
            return
        }
        let session = BrushSession(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(banked),
            duration: banked,
            zonesCompleted: snapshot.zonesCompleted,
            plannedZones: timeline.plan.zones.count,
            source: .watch
        )
        try? WatchSessionStore.upsert(session)
        WatchTraceTransfer.shared.enqueue(session)
        phase = .completed(SessionSummary(session: session, nextSteps: pendingSteps()))
        WKInterfaceDevice.current().play(.success)
        clearRunState()
    }

    /// Abandons the session without recording anything.
    func discard() {
        workTask?.cancel()
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

        let zones = timeline.plan.zones.count
        let session = BrushSession(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(timeline.totalDuration),
            duration: timeline.totalDuration,
            zonesCompleted: zones,
            plannedZones: zones,
            source: .watch
        )
        try WatchSessionStore.upsert(session)
        WatchTraceTransfer.shared.enqueue(session)
        phase = .completed(SessionSummary(session: session, nextSteps: pendingSteps()))
        WKInterfaceDevice.current().play(.success)
        clearRunState()
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
