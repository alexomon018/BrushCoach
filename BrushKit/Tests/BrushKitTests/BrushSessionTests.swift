import Foundation
import Testing
@testable import BrushKit

struct BrushSessionTests {
    @Test func wallClockTimelineRecoversAfterADeferredRefresh() {
        let timeline = RoutineTimeline()

        #expect(timeline.snapshot(elapsed: 19.9).currentZoneIndex == 0)
        #expect(timeline.snapshot(elapsed: 61).currentZoneIndex == 3)
        #expect(timeline.snapshot(elapsed: 61).zoneSecondsRemaining == 19)
        #expect(timeline.snapshot(elapsed: 120).isComplete)
        #expect(timeline.snapshot(elapsed: 900).elapsed == 120)
    }

    @Test func assignsMorningAndEveningAndBuildsStatus() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let morning = date(2026, 8, 26, 8, calendar: calendar)
        let evening = date(2026, 8, 26, 21, calendar: calendar)
        let sessions = [session(at: morning), session(at: evening)]

        #expect(RoutinePeriod.period(for: morning, calendar: calendar) == .morning)
        #expect(RoutinePeriod.period(for: evening, calendar: calendar) == .evening)
        #expect(BrushSessionHistory.status(on: morning, sessions: sessions, calendar: calendar).completedCount == 2)
    }

    @Test @MainActor func repositoryUpsertsAndDeletesAtomically() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let repository = LocalSessionRepository(directory: directory)
        var item = session(at: .now)
        try repository.upsert(item)
        item.duration = 118
        try repository.upsert(item)

        #expect(try repository.load().count == 1)
        #expect(try repository.load().first?.duration == 118)
        try repository.delete(id: item.id)
        #expect(try repository.load().isEmpty)
    }


    // MARK: - Streak

    @Test func streakSurvivesAnIncompleteToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date(2026, 8, 26, 9, calendar: calendar)

        // Thirty perfect days behind us, plus this morning's brush.
        var sessions: [BrushSession] = []
        for offset in 1...30 {
            sessions.append(session(at: hour(8, daysBefore: offset, from: now, calendar: calendar)))
            sessions.append(session(at: hour(21, daysBefore: offset, from: now, calendar: calendar)))
        }
        sessions.append(session(at: now))

        // The evening brush has not happened yet; the run must not reset to zero.
        #expect(BrushSessionHistory.currentStreak(sessions: sessions, today: now, calendar: calendar) == 30)

        // Once it lands, today counts.
        sessions.append(session(at: date(2026, 8, 26, 21, calendar: calendar)))
        #expect(BrushSessionHistory.currentStreak(sessions: sessions, today: now, calendar: calendar) == 31)
    }

    @Test func streakBreaksOnAGenuinelyMissedDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date(2026, 8, 26, 9, calendar: calendar)

        var sessions: [BrushSession] = []
        for offset in [1, 2, 4, 5] {
            sessions.append(session(at: hour(8, daysBefore: offset, from: now, calendar: calendar)))
            sessions.append(session(at: hour(21, daysBefore: offset, from: now, calendar: calendar)))
        }
        #expect(BrushSessionHistory.currentStreak(sessions: sessions, today: now, calendar: calendar) == 2)
    }

    // MARK: - Routine day boundary

    @Test func lateNightBrushClosesTheEveningItFinished() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = RoutineDay.default

        let morning = date(2026, 8, 26, 8, calendar: calendar)
        let pastMidnight = date(2026, 8, 27, 0, 15, calendar: calendar)

        // 00:15 belongs to the 26th, as that day's evening — not the 27th's morning.
        #expect(day.period(for: pastMidnight, calendar: calendar) == .evening)
        #expect(day.isDate(pastMidnight, inSameRoutineDayAs: morning, calendar: calendar))

        let status = BrushSessionHistory.status(
            on: morning,
            sessions: [session(at: morning), session(at: pastMidnight)],
            calendar: calendar
        )
        #expect(status.completedCount == 2)
        #expect(status.evening != nil)

        // The next routine day is untouched, so its morning reminder still fires.
        let next = BrushSessionHistory.status(
            on: date(2026, 8, 27, 9, calendar: calendar),
            sessions: [session(at: morning), session(at: pastMidnight)],
            calendar: calendar
        )
        #expect(next.completedCount == 0)
    }

    @Test func dayEndHourIsConfigurable() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let brush = date(2026, 8, 27, 2, calendar: calendar)

        // Rolls over at 03:00 by default, so 02:00 still belongs to the 26th.
        #expect(RoutineDay.default.startOfRoutineDay(for: brush, calendar: calendar)
                == date(2026, 8, 26, 0, calendar: calendar))
        // With a midnight rollover it belongs to the 27th.
        #expect(RoutineDay(endsAtHour: 0).startOfRoutineDay(for: brush, calendar: calendar)
                == date(2026, 8, 27, 0, calendar: calendar))
    }

    // MARK: - Coverage

    @Test func verifiedCoverageIsSeparateFromRoutineCredit() {
        let start = Date.now
        var brush = BrushSession(
            startedAt: start,
            endedAt: start.addingTimeInterval(120),
            duration: 120,
            zonesCompleted: 6,
            verifiedZones: 4,
            source: .watch
        )
        // Motion analysis confirmed only four zones; the routine still counts.
        #expect(brush.completedRoutine)
        #expect(!brush.fullyVerified)

        // No verification at all is distinct from verifying nothing.
        brush.verifiedZones = nil
        #expect(brush.completedRoutine)
        #expect(!brush.fullyVerified)
        brush.verifiedZones = 0
        #expect(brush.completedRoutine)
    }

    @Test func decodesHistoryWrittenBeforeCoverageFieldsExisted() throws {
        // A record written before `plannedZones` and `verifiedZones` existed.
        let legacy = #"[{"id":"7D4C1E2A-0000-4000-8000-000000000001","startedAt":"2026-08-26T08:00:00Z","endedAt":"2026-08-26T08:02:00Z","duration":120,"zonesCompleted":6,"source":"watch","flossed":false,"tongueCleaned":false}]"#

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sessions = try decoder.decode([BrushSession].self, from: Data(legacy.utf8))

        #expect(sessions.count == 1)
        #expect(sessions[0].zonesCompleted == 6)
        #expect(sessions[0].plannedZones == 6)
        #expect(sessions[0].verifiedZones == nil)
        #expect(sessions[0].schemaVersion == BrushSession.currentSchemaVersion)
        #expect(!sessions[0].timeZoneIdentifier.isEmpty)
        #expect(sessions[0].analysisVersion == nil)
        #expect(sessions[0].completedRoutine)
    }

    @Test func decodesPreferencesWrittenBeforeDayEndExisted() throws {
        let legacy = #"{"morningEnabled":true,"morningHour":6,"morningMinute":45,"eveningEnabled":false,"eveningHour":22,"eveningMinute":15,"flossPromptEnabled":false,"tonguePromptEnabled":true}"#

        let preferences = try JSONDecoder().decode(RoutinePreferences.self, from: Data(legacy.utf8))

        // Every existing preference survives; only the new field takes a default.
        #expect(preferences.morningHour == 6)
        #expect(preferences.morningMinute == 45)
        #expect(!preferences.eveningEnabled)
        #expect(preferences.tonguePromptEnabled)
        #expect(preferences.dayEndsAtHour == 3)
    }

    /// Built from the start of the day rather than with `date(bySettingHour:of:)`,
    /// which searches forward and would roll an earlier hour onto the next day.
    private func hour(
        _ hour: Int,
        daysBefore days: Int,
        from reference: Date,
        calendar: Calendar
    ) -> Date {
        let day = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: reference))!
        return calendar.date(byAdding: .hour, value: hour, to: day)!
    }

    private func session(at date: Date) -> BrushSession {
        BrushSession(
            startedAt: date,
            endedAt: date.addingTimeInterval(120),
            duration: 120,
            zonesCompleted: 6,
            source: .watch
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int = 0,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }
}

/// A convenience `session.period` using `RoutineDay.default` used to exist
/// alongside the day-aware call. For anyone who moved their rollover hour the
/// two disagreed, so History could label a brush "Morning" while the same brush
/// counted as that night's evening everywhere else.
struct SessionPeriodRespectsTheConfiguredDayTests {
    @Test
    func aLateNightBrushBelongsToTheEveningOfTheDayItFinished() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        // 04:00, with the routine day rolling over at 05:00.
        let fourAM = calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 4))!
        let session = BrushSession(
            startedAt: fourAM,
            endedAt: fourAM.addingTimeInterval(120),
            duration: 120,
            zonesCompleted: 6,
            source: .watch
        )

        let lateRollover = RoutineDay(endsAtHour: 5)
        #expect(session.period(in: lateRollover, calendar: calendar) == .evening)

        // The old default would have called this the next morning, because 4 is
        // past a 3am rollover and before midday.
        #expect(session.period(in: .default, calendar: calendar) == .morning)
    }
}
