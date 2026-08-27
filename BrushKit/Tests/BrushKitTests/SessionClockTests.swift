import Foundation
import Testing
@testable import BrushKit

/// The product promise is that a started session survives the wrist going down,
/// the display sleeping, and Sleep Focus. These pin the property that makes that
/// possible: elapsed time is a function of wall-clock instants, never of how often
/// or how regularly the clock is read.
struct SessionClockTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func elapsedIsIndependentOfHowOftenItIsRead() {
        var dense = SessionClock(limit: 120)
        var sparse = SessionClock(limit: 120)
        dense.start(at: start)
        sparse.start(at: start)

        // One reader polls 4x a second; the other is suspended and reads twice.
        for tick in stride(from: 0.0, through: 90.0, by: 0.25) {
            _ = dense.elapsed(at: start.addingTimeInterval(tick))
        }
        _ = sparse.elapsed(at: start.addingTimeInterval(3))

        let end = start.addingTimeInterval(90)
        #expect(dense.elapsed(at: end) == sparse.elapsed(at: end))
        #expect(dense.elapsed(at: end) == 90)
    }

    @Test func aSuspendedProcessDoesNotLoseTime() {
        var clock = SessionClock(limit: 120)
        clock.start(at: start)

        // Wrist down for 45 seconds: no reads happen at all in that window.
        #expect(clock.elapsed(at: start.addingTimeInterval(10)) == 10)
        #expect(clock.elapsed(at: start.addingTimeInterval(55)) == 55)
        #expect(clock.isComplete(at: start.addingTimeInterval(120)))
    }

    @Test func elapsedNeverExceedsTheSessionLength() {
        var clock = SessionClock(limit: 120)
        clock.start(at: start)
        // The app was closed and reopened fifteen minutes later.
        #expect(clock.elapsed(at: start.addingTimeInterval(900)) == 120)
    }

    @Test func pausingHoldsTheClockAndResumingContinuesIt() {
        var clock = SessionClock(limit: 120)
        clock.start(at: start)

        clock.pause(at: start.addingTimeInterval(30))
        #expect(!clock.isRunning)
        // Ten minutes paused must not advance the session.
        #expect(clock.elapsed(at: start.addingTimeInterval(630)) == 30)

        clock.resume(at: start.addingTimeInterval(630))
        #expect(clock.isRunning)
        #expect(clock.elapsed(at: start.addingTimeInterval(650)) == 50)
    }

    @Test func repeatedPausesAccumulateExactly() {
        var clock = SessionClock(limit: 120)
        clock.start(at: start)
        var cursor = start

        // Six 10-second bursts separated by 30-second pauses.
        for _ in 0..<6 {
            cursor = cursor.addingTimeInterval(10)
            clock.pause(at: cursor)
            cursor = cursor.addingTimeInterval(30)
            clock.resume(at: cursor)
        }
        #expect(clock.elapsed(at: cursor) == 60)
    }

    @Test func redundantPauseAndResumeAreIgnored() {
        var clock = SessionClock(limit: 120)
        clock.start(at: start)
        clock.pause(at: start.addingTimeInterval(10))
        clock.pause(at: start.addingTimeInterval(20))
        #expect(clock.elapsed(at: start.addingTimeInterval(30)) == 10)

        clock.resume(at: start.addingTimeInterval(30))
        clock.resume(at: start.addingTimeInterval(40))
        #expect(clock.elapsed(at: start.addingTimeInterval(40)) == 20)
    }

    @Test func clockDrivesTheSameZonesAsTheTimeline() {
        let timeline = RoutineTimeline()
        var clock = SessionClock(limit: timeline.totalDuration)
        clock.start(at: start)

        // Paused across a zone boundary: the boundary shifts with the pause.
        clock.pause(at: start.addingTimeInterval(15))
        clock.resume(at: start.addingTimeInterval(300))

        let atZoneOne = start.addingTimeInterval(300 + 4)
        #expect(timeline.snapshot(elapsed: clock.elapsed(at: atZoneOne)).currentZoneIndex == 0)

        let atZoneTwo = start.addingTimeInterval(300 + 6)
        #expect(timeline.snapshot(elapsed: clock.elapsed(at: atZoneTwo)).currentZoneIndex == 1)
    }
}
