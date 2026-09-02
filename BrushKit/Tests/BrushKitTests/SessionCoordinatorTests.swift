import Foundation
import Testing
@testable import BrushKit

/// The pacer state machine used to live inside the watch view model, where none
/// of it could be exercised without a Watch. These are the paths that matter and
/// that a hand test would never reliably reach.
@Suite("Session pacing")
struct SessionCoordinatorTests {
    private let start = Date(timeIntervalSince1970: 1_787_000_000)

    // MARK: - Countdown

    @Test
    func aSessionCountsDownBeforeItStartsBrushing() {
        var coordinator = SessionCoordinator()
        let effects = coordinator.start(at: start)

        #expect(coordinator.phase == .countdown(3))
        #expect(effects == [.beginExtendedRuntime, .countdownTicked(secondsRemaining: 3)])

        #expect(coordinator.tick(at: start.addingTimeInterval(1)) == [.countdownTicked(secondsRemaining: 2)])
        #expect(coordinator.phase == .countdown(2))
        #expect(coordinator.tick(at: start.addingTimeInterval(2)) == [.countdownTicked(secondsRemaining: 1)])
        #expect(coordinator.phase != .brushing)

        let began = coordinator.tick(at: start.addingTimeInterval(3))
        #expect(began == [.sessionStarted, .startMotionAnalysis])
        #expect(coordinator.phase == .brushing)
    }

    /// Ticks arrive at 4 Hz, so most of them fall inside the same whole second.
    /// Re-announcing the same number would fire a haptic four times a second.
    @Test
    func repeatedTicksWithinOneSecondAnnounceNothingNew() {
        var coordinator = SessionCoordinator()
        _ = coordinator.start(at: start)

        #expect(coordinator.tick(at: start.addingTimeInterval(0.25)).isEmpty)
        #expect(coordinator.tick(at: start.addingTimeInterval(0.5)).isEmpty)
        #expect(coordinator.tick(at: start.addingTimeInterval(0.75)).isEmpty)
        #expect(coordinator.phase == .countdown(3))
    }

    /// If the app is suspended through the countdown, the session must not begin
    /// already part-way through. Crediting unbrushed seconds is the one failure
    /// this app refuses.
    @Test
    func aCountdownSleptThroughStartsTheSessionAtZero() {
        var coordinator = SessionCoordinator()
        _ = coordinator.start(at: start)

        _ = coordinator.tick(at: start.addingTimeInterval(45))
        #expect(coordinator.phase == .brushing)
        #expect(coordinator.elapsed == 0)

        // And the routine still runs its full length from that moment.
        _ = coordinator.tick(at: start.addingTimeInterval(45 + 119))
        #expect(coordinator.phase == .brushing)
    }

    // MARK: - Zones

    @Test
    func freeBrushingDoesNotAnnounceTwentySecondBoundaries() {
        var coordinator = brushingCoordinator()
        let brushingBegan = start.addingTimeInterval(3)
        var announced: [Int] = []

        // 4 Hz for the whole routine, as the watch runs it.
        for step in stride(from: 0.0, through: 120.0, by: 0.25) {
            for effect in coordinator.tick(at: brushingBegan.addingTimeInterval(step)) {
                if case .advancedToZone(let index) = effect { announced.append(index) }
            }
        }
        #expect(announced.isEmpty)
        #expect(coordinator.currentZoneIndex == 5)
    }

    @Test
    func overallCountdownNeverResetsAtLegacySegmentBoundaries() {
        var coordinator = brushingCoordinator()
        let brushingBegan = start.addingTimeInterval(3)

        _ = coordinator.tick(at: brushingBegan.addingTimeInterval(19))
        #expect(coordinator.sessionSecondsRemaining == 101)
        _ = coordinator.tick(at: brushingBegan.addingTimeInterval(21))
        #expect(coordinator.sessionSecondsRemaining == 99)
    }

    @Test
    func aCompletedRoutineReportsEveryZoneAndRanToCompletion() {
        var coordinator = brushingCoordinator()
        let brushingBegan = start.addingTimeInterval(3)

        let effects = coordinator.tick(at: brushingBegan.addingTimeInterval(120))
        let outcome = try? #require(finishedOutcome(in: effects))

        #expect(outcome?.zonesCompleted == 6)
        #expect(outcome?.plannedZones == 6)
        #expect(outcome?.duration == 120)
        #expect(outcome?.ranToCompletion == true)
        #expect(effects.contains(.stopMotionAnalysis))
        #expect(effects.contains(.endExtendedRuntime))
    }

    /// The session is over. Further ticks must not re-fire the finish effects or
    /// hand the host a second session to persist.
    @Test
    func tickingPastCompletionChangesNothing() {
        var coordinator = brushingCoordinator()
        let brushingBegan = start.addingTimeInterval(3)
        _ = coordinator.tick(at: brushingBegan.addingTimeInterval(120))
        let settled = coordinator.phase

        #expect(coordinator.tick(at: brushingBegan.addingTimeInterval(200)).isEmpty)
        #expect(coordinator.phase == settled)
    }

    // MARK: - Pause and resume

    @Test
    func pausedTimeIsNotCountedAsBrushing() {
        var coordinator = brushingCoordinator()
        let brushingBegan = start.addingTimeInterval(3)

        _ = coordinator.tick(at: brushingBegan.addingTimeInterval(30))
        #expect(coordinator.pause(at: brushingBegan.addingTimeInterval(30)) == [.suspendMotionAnalysis, .sessionPaused])

        // Five minutes on the counter, none of it brushing.
        _ = coordinator.resume(at: brushingBegan.addingTimeInterval(330))
        _ = coordinator.tick(at: brushingBegan.addingTimeInterval(340))

        #expect(abs(coordinator.elapsed - 40) < 0.001)
        #expect(coordinator.phase == .brushing)
    }

    @Test
    func ticksArrivingWhilePausedDoNotAdvanceTheSession() {
        var coordinator = brushingCoordinator()
        let brushingBegan = start.addingTimeInterval(3)
        _ = coordinator.tick(at: brushingBegan.addingTimeInterval(30))
        _ = coordinator.pause(at: brushingBegan.addingTimeInterval(30))

        #expect(coordinator.tick(at: brushingBegan.addingTimeInterval(90)).isEmpty)
        #expect(abs(coordinator.elapsed - 30) < 0.001)
    }

    @Test
    func pausingWhenNotBrushingIsIgnored() {
        var coordinator = SessionCoordinator()
        #expect(coordinator.pause(at: start).isEmpty)
        _ = coordinator.start(at: start)
        #expect(coordinator.pause(at: start).isEmpty)
        #expect(coordinator.phase == .countdown(3))
    }

    /// The internal compatibility segment may advance across a pause, but free
    /// brushing must not emit a user-facing zone-change effect.
    @Test
    func resumingAfterAZoneBoundaryLandsInTheRightZone() {
        var coordinator = brushingCoordinator()
        let brushingBegan = start.addingTimeInterval(3)

        _ = coordinator.tick(at: brushingBegan.addingTimeInterval(19))
        _ = coordinator.pause(at: brushingBegan.addingTimeInterval(19))
        #expect(coordinator.currentZoneIndex == 0)

        _ = coordinator.resume(at: brushingBegan.addingTimeInterval(600))
        let effects = coordinator.tick(at: brushingBegan.addingTimeInterval(602))
        #expect(effects.isEmpty)
        #expect(coordinator.currentZoneIndex == 1)
    }

    // MARK: - Ending early

    @Test
    func endingEarlyKeepsCreditForWholeZonesAlreadyBrushed() {
        var coordinator = brushingCoordinator()
        let brushingBegan = start.addingTimeInterval(3)
        _ = coordinator.tick(at: brushingBegan.addingTimeInterval(65))

        let effects = coordinator.endEarly(at: brushingBegan.addingTimeInterval(65))
        let outcome = try? #require(finishedOutcome(in: effects))

        #expect(outcome?.zonesCompleted == 3)
        #expect(outcome?.plannedZones == 6)
        #expect(outcome?.ranToCompletion == false)
        #expect((outcome?.duration).map { abs($0 - 65) < 0.001 } == true)
    }

    /// Nothing whole was brushed, so there is nothing honest to record.
    @Test
    func endingEarlyBeforeTheFirstZoneRecordsNothing() {
        var coordinator = brushingCoordinator()
        let brushingBegan = start.addingTimeInterval(3)
        _ = coordinator.tick(at: brushingBegan.addingTimeInterval(12))

        let effects = coordinator.endEarly(at: brushingBegan.addingTimeInterval(12))
        #expect(finishedOutcome(in: effects) == nil)
        #expect(coordinator.phase == .ready)
        #expect(effects == [.stopMotionAnalysis, .endExtendedRuntime])
    }

    @Test
    func endingEarlyWhilePausedStillBanksTheZonesAlreadyBrushed() {
        var coordinator = brushingCoordinator()
        let brushingBegan = start.addingTimeInterval(3)
        _ = coordinator.tick(at: brushingBegan.addingTimeInterval(45))
        _ = coordinator.pause(at: brushingBegan.addingTimeInterval(45))

        // Ended from the paused screen a long while later: the banked time is
        // what was brushed, not the time spent sitting on the pause screen.
        let effects = coordinator.endEarly(at: brushingBegan.addingTimeInterval(900))
        let outcome = try? #require(finishedOutcome(in: effects))
        #expect(outcome?.zonesCompleted == 2)
        #expect((outcome?.duration).map { abs($0 - 45) < 0.001 } == true)
    }

    @Test
    func endingEarlyDuringTheCountdownRecordsNothing() {
        var coordinator = SessionCoordinator()
        _ = coordinator.start(at: start)

        let effects = coordinator.endEarly(at: start.addingTimeInterval(1))
        #expect(finishedOutcome(in: effects) == nil)
        #expect(coordinator.phase == .ready)
    }

    // MARK: - Discard, failure, restart

    @Test
    func discardingReleasesTheRuntimeAndRecordsNothing() {
        var coordinator = brushingCoordinator()
        let effects = coordinator.discard()

        #expect(effects == [.stopMotionAnalysis, .endExtendedRuntime])
        #expect(coordinator.phase == .ready)
        #expect(coordinator.elapsed == 0)
        #expect(coordinator.currentZoneIndex == 0)
    }

    @Test
    func aFailureIsTerminalUntilAcknowledged() {
        var coordinator = brushingCoordinator()
        let effects = coordinator.fail("Core Motion unavailable")

        #expect(effects.contains(.failed("Core Motion unavailable")))
        #expect(coordinator.phase == .failed("Core Motion unavailable"))
        #expect(coordinator.tick(at: start.addingTimeInterval(500)).isEmpty)

        _ = coordinator.acknowledge()
        #expect(coordinator.phase == .ready)
    }

    @Test
    func startingIsIgnoredWhileASessionIsAlreadyRunning() {
        var coordinator = brushingCoordinator()
        let before = coordinator.phase
        #expect(coordinator.start(at: start.addingTimeInterval(10)).isEmpty)
        #expect(coordinator.phase == before)
    }

    /// Every session begins from a clean slate, so a second brush cannot inherit
    /// the first one's elapsed time or zone.
    @Test
    func aSecondSessionStartsFromZero() {
        var coordinator = brushingCoordinator()
        let brushingBegan = start.addingTimeInterval(3)
        _ = coordinator.tick(at: brushingBegan.addingTimeInterval(120))
        _ = coordinator.acknowledge()

        let restart = brushingBegan.addingTimeInterval(600)
        _ = coordinator.start(at: restart)
        _ = coordinator.tick(at: restart.addingTimeInterval(3))

        #expect(coordinator.elapsed == 0)
        #expect(coordinator.currentZoneIndex == 0)
        #expect(coordinator.phase == .brushing)
    }

    // MARK: - Helpers

    private func brushingCoordinator() -> SessionCoordinator {
        var coordinator = SessionCoordinator()
        _ = coordinator.start(at: start)
        _ = coordinator.tick(at: start.addingTimeInterval(3))
        return coordinator
    }

    private func finishedOutcome(in effects: [SessionCoordinator.Effect]) -> SessionCoordinator.PacerOutcome? {
        for effect in effects {
            if case .finished(let outcome) = effect { return outcome }
        }
        return nil
    }
}
