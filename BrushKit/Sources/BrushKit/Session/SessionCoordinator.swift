import Foundation

/// The session state machine: countdown, fixed-duration timing, pause, resume, and the two
/// ways a session can end.
///
/// This is deliberately a plain value type driven by explicit instants rather
/// than by `Task.sleep`, timers, or notifications. Every transition is a function
/// of the state and a `Date`, so the whole machine — including the paths that
/// only happen when someone pauses at a zone boundary or ends a session one
/// second before it completes — can be exercised without a Watch, a run loop, or
/// waiting in real time.
///
/// It cannot see motion analysis. `PacerOutcome` carries only what the pacer
/// itself observed, which is what makes "analysis never decides whether the
/// session counted" a property of the types rather than a rule to remember.
public struct SessionCoordinator: Sendable {
    /// What the pacer is doing. Terminal states carry the reason.
    public enum Phase: Equatable, Sendable {
        case ready
        /// Whole seconds still to go before brushing starts.
        case countdown(Int)
        case brushing
        case paused
        case finished(PacerOutcome)
        case failed(String)
    }

    /// What the pacer observed, and the only input a `BrushSession`'s routine
    /// credit is allowed to depend on.
    public struct PacerOutcome: Equatable, Sendable {
        public let startedAt: Date
        public let duration: TimeInterval
        public let zonesCompleted: Int
        public let plannedZones: Int
        /// Whether the routine ran to the end, as opposed to being ended early
        /// with some zones already banked.
        public let ranToCompletion: Bool

        public init(
            startedAt: Date,
            duration: TimeInterval,
            zonesCompleted: Int,
            plannedZones: Int,
            ranToCompletion: Bool
        ) {
            self.startedAt = startedAt
            self.duration = duration
            self.zonesCompleted = zonesCompleted
            self.plannedZones = plannedZones
            self.ranToCompletion = ranToCompletion
        }
    }

    /// Something the host has to do that this type deliberately cannot: play a
    /// haptic, hold an extended runtime session, drive Core Motion.
    ///
    /// These are intents, not device calls.
    public enum Effect: Equatable, Sendable {
        case beginExtendedRuntime
        case endExtendedRuntime
        case startMotionAnalysis
        case stopMotionAnalysis
        /// Paused, not stopped: motion keeps arriving but none of it is this
        /// session's brushing, and a window spanning the gap would be
        /// interpolated across it.
        case suspendMotionAnalysis
        case countdownTicked(secondsRemaining: Int)
        case sessionStarted
        case sessionPaused
        case sessionResumed
        /// Retained for source compatibility with older hosts. Free-brushing
        /// sessions no longer emit zone-advance effects.
        case advancedToZone(index: Int)
        case finished(PacerOutcome)
        case failed(String)
    }

    public static let countdownSeconds = 3

    public private(set) var phase: Phase = .ready
    public private(set) var elapsed: TimeInterval = 0
    public private(set) var currentZoneIndex = 0

    public let timeline: RoutineTimeline

    private var clock: SessionClock
    private var countdownStartedAt: Date?
    private var sessionStartedAt: Date?

    public init(timeline: RoutineTimeline = RoutineTimeline()) {
        self.timeline = timeline
        clock = SessionClock(limit: timeline.totalDuration)
    }

    // MARK: - Derived state

    public var isBusy: Bool {
        switch phase {
        case .countdown, .brushing, .paused: true
        default: false
        }
    }

    public var isPaused: Bool { phase == .paused }

    public var progress: Double {
        guard timeline.totalDuration > 0 else { return 0 }
        return min(1, elapsed / timeline.totalDuration)
    }

    public var zoneSecondsRemaining: Int {
        timeline.snapshot(elapsed: elapsed).zoneSecondsRemaining
    }

    /// Whole seconds remaining in the single free-brushing session. Unlike the
    /// legacy `zoneSecondsRemaining`, this never resets at 20-second boundaries.
    public var sessionSecondsRemaining: Int {
        Int(ceil(max(0, timeline.totalDuration - elapsed)))
    }

    /// The zone the pacer is prompting, as distinct from wherever a classifier
    /// thinks the brush actually is.
    public var scheduledZone: BrushZoneLabel {
        timeline.plan.zones[min(currentZoneIndex, timeline.plan.zones.count - 1)]
    }

    // MARK: - Transitions

    public mutating func start(at instant: Date) -> [Effect] {
        guard !isBusy else { return [] }
        clearRunState()
        countdownStartedAt = instant
        phase = .countdown(Self.countdownSeconds)
        return [.beginExtendedRuntime, .countdownTicked(secondsRemaining: Self.countdownSeconds)]
    }

    /// Advances the machine to `instant`. Safe to call at any rate, including
    /// not at all for a while: every value is derived from wall-clock deltas, so
    /// a tick that arrives late, early, or never cannot make the session drift.
    public mutating func tick(at instant: Date) -> [Effect] {
        switch phase {
        case .countdown(let showing):
            return tickCountdown(at: instant, showing: showing)
        case .brushing:
            return tickBrushing(at: instant)
        case .ready, .paused, .finished, .failed:
            return []
        }
    }

    private mutating func tickCountdown(at instant: Date, showing: Int) -> [Effect] {
        guard let startedAt = countdownStartedAt else { return [] }
        let gone = max(0, instant.timeIntervalSince(startedAt))
        let remaining = Self.countdownSeconds - Int(gone)

        guard remaining > 0 else { return beginBrushing(at: instant) }
        guard remaining != showing else { return [] }
        phase = .countdown(remaining)
        return [.countdownTicked(secondsRemaining: remaining)]
    }

    /// The session clock starts when the countdown is *observed* to have run out,
    /// not at the instant it theoretically did. If the app was suspended through
    /// the countdown, backdating the start would credit seconds nobody spent
    /// brushing — the one thing this app refuses to do.
    private mutating func beginBrushing(at instant: Date) -> [Effect] {
        countdownStartedAt = nil
        sessionStartedAt = instant
        clock.start(at: instant)
        phase = .brushing
        currentZoneIndex = 0
        elapsed = 0
        return [.sessionStarted, .startMotionAnalysis]
    }

    private mutating func tickBrushing(at instant: Date) -> [Effect] {
        let snapshot = timeline.snapshot(elapsed: clock.elapsed(at: instant))
        elapsed = snapshot.elapsed

        var effects: [Effect] = []
        if snapshot.currentZoneIndex > currentZoneIndex {
            currentZoneIndex = snapshot.currentZoneIndex
        }
        guard snapshot.isComplete else { return effects }

        guard let startedAt = sessionStartedAt else { return effects }
        let outcome = PacerOutcome(
            startedAt: startedAt,
            duration: timeline.totalDuration,
            zonesCompleted: timeline.plan.zones.count,
            plannedZones: timeline.plan.zones.count,
            ranToCompletion: true
        )
        effects.append(contentsOf: settle(on: outcome))
        return effects
    }

    public mutating func pause(at instant: Date) -> [Effect] {
        guard phase == .brushing else { return [] }
        clock.pause(at: instant)
        elapsed = clock.elapsed(at: instant)
        phase = .paused
        return [.suspendMotionAnalysis, .sessionPaused]
    }

    public mutating func resume(at instant: Date) -> [Effect] {
        guard phase == .paused else { return [] }
        clock.resume(at: instant)
        phase = .brushing
        return [.sessionResumed]
    }

    /// Ends the session early, keeping its elapsed time.
    /// Discarding a nearly complete brush is the failure users resent most.
    ///
    /// The legacy 20-second completion segments keep the existing minimum useful
    /// early-session threshold without becoming zone guidance in the UI.
    public mutating func endEarly(at instant: Date) -> [Effect] {
        guard isBusy else { return [] }
        clock.stop(at: instant)
        let banked = clock.elapsed(at: instant)
        let snapshot = timeline.snapshot(elapsed: banked)

        guard let startedAt = sessionStartedAt, snapshot.zonesCompleted > 0 else {
            return discard()
        }
        elapsed = banked
        return settle(on: PacerOutcome(
            startedAt: startedAt,
            duration: banked,
            zonesCompleted: snapshot.zonesCompleted,
            plannedZones: timeline.plan.zones.count,
            ranToCompletion: false
        ))
    }

    /// Abandons the session without recording anything.
    public mutating func discard() -> [Effect] {
        let wasBusy = isBusy
        phase = .ready
        clearRunState()
        return wasBusy ? [.stopMotionAnalysis, .endExtendedRuntime] : []
    }

    /// Reports that the host could not run the session at all.
    public mutating func fail(_ message: String) -> [Effect] {
        clearRunState()
        phase = .failed(message)
        return [.stopMotionAnalysis, .endExtendedRuntime, .failed(message)]
    }

    /// Returns to the ready screen from a terminal phase.
    public mutating func acknowledge() -> [Effect] {
        switch phase {
        case .finished, .failed:
            phase = .ready
            clearRunState()
            return []
        default:
            return []
        }
    }

    private mutating func settle(on outcome: PacerOutcome) -> [Effect] {
        phase = .finished(outcome)
        countdownStartedAt = nil
        sessionStartedAt = nil
        return [.stopMotionAnalysis, .endExtendedRuntime, .finished(outcome)]
    }

    private mutating func clearRunState() {
        elapsed = 0
        currentZoneIndex = 0
        clock.reset()
        countdownStartedAt = nil
        sessionStartedAt = nil
    }
}
