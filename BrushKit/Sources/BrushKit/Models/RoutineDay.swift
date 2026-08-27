import Foundation

/// Defines where one routine day ends and the next begins.
///
/// A calendar day is the wrong boundary for a brushing routine: someone who
/// brushes at 00:15 has finished *tonight's* routine, not started tomorrow's.
/// Attributing that brush to the next calendar day penalises them twice — the
/// previous evening reads as missed, and the next morning reads as already done,
/// which also suppresses its reminder.
public struct RoutineDay: Codable, Hashable, Sendable {
    public static let `default` = RoutineDay()

    /// Hour at which a routine day rolls over. Brushes before this hour belong to
    /// the previous routine day. Clamped to 0..<12 — a rollover at or after noon
    /// would make "morning" unreachable.
    public var endsAtHour: Int

    /// Hour separating the morning slot from the evening slot within a routine day.
    public var middayHour: Int

    public init(endsAtHour: Int = 3, middayHour: Int = 15) {
        self.endsAtHour = min(11, max(0, endsAtHour))
        self.middayHour = min(23, max(self.endsAtHour + 1, middayHour))
    }

    /// The start of the routine day that `date` belongs to.
    public func startOfRoutineDay(for date: Date, calendar: Calendar = .current) -> Date {
        let startOfCalendarDay = calendar.startOfDay(for: date)
        guard calendar.component(.hour, from: date) < endsAtHour else { return startOfCalendarDay }
        return calendar.date(byAdding: .day, value: -1, to: startOfCalendarDay) ?? startOfCalendarDay
    }

    /// An instant safely inside the routine day that begins at `dayStart`.
    ///
    /// `startOfRoutineDay` maps arbitrary instants, so it is not idempotent: given
    /// a day *start* (midnight) it pushes back another day whenever the rollover
    /// hour is after midnight. Anything walking day to day must probe from inside
    /// the day instead. `endsAtHour` is clamped below 12, so midday is always past
    /// the rollover.
    public func middayOfRoutineDay(startingAt dayStart: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .hour, value: 12, to: dayStart) ?? dayStart
    }

    public func isDate(
        _ date: Date,
        inSameRoutineDayAs other: Date,
        calendar: Calendar = .current
    ) -> Bool {
        startOfRoutineDay(for: date, calendar: calendar)
            == startOfRoutineDay(for: other, calendar: calendar)
    }

    /// Which routine slot `date` falls into. A late-night brush is the evening of
    /// the routine day it belongs to, never the next day's morning.
    public func period(for date: Date, calendar: Calendar = .current) -> RoutinePeriod {
        let hour = calendar.component(.hour, from: date)
        if hour < endsAtHour { return .evening }
        return hour < middayHour ? .morning : .evening
    }
}
