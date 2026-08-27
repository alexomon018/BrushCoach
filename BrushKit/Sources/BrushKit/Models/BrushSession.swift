import Foundation

public enum RoutinePeriod: String, Codable, CaseIterable, Hashable, Sendable {
    case morning
    case evening

    public var displayName: String { rawValue.capitalized }

    public static func period(
        for date: Date,
        calendar: Calendar = .current,
        day: RoutineDay = .default
    ) -> Self {
        day.period(for: date, calendar: calendar)
    }
}

public enum BrushSessionSource: String, Codable, Hashable, Sendable {
    case watch
    case phone
    case manual
}

public struct BrushSession: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var duration: TimeInterval
    /// Zones the pacer advanced through. This is what "completed a two-minute
    /// brush" means, and it is never withheld because motion analysis failed.
    public var zonesCompleted: Int

    /// How many zones the plan called for. Stored per session so that changing
    /// the plan later cannot retroactively misreport old sessions.
    public var plannedZones: Int

    /// Zones confirmed by motion analysis, or `nil` when no verification ran.
    /// Deliberately distinct from `0`, which means verification ran and confirmed
    /// nothing. Never used to gate routine credit.
    public var verifiedZones: Int?

    public var source: BrushSessionSource
    public var flossed: Bool
    public var tongueCleaned: Bool

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        duration: TimeInterval,
        zonesCompleted: Int,
        plannedZones: Int = 6,
        verifiedZones: Int? = nil,
        source: BrushSessionSource,
        flossed: Bool = false,
        tongueCleaned: Bool = false
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = max(0, duration)
        let planned = max(1, plannedZones)
        self.plannedZones = planned
        self.zonesCompleted = min(planned, max(0, zonesCompleted))
        self.verifiedZones = verifiedZones.map { min(planned, max(0, $0)) }
        self.source = source
        self.flossed = flossed
        self.tongueCleaned = tongueCleaned
    }

    /// Decoded field-by-field so that adding a field never invalidates history
    /// already written to disk. `LocalSessionRepository` decodes the whole array,
    /// so one unreadable session would take every other session with it.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let startedAt = try container.decode(Date.self, forKey: .startedAt)
        let duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        let planned = try container.decodeIfPresent(Int.self, forKey: .plannedZones) ?? 6
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            startedAt: startedAt,
            endedAt: try container.decodeIfPresent(Date.self, forKey: .endedAt)
                ?? startedAt.addingTimeInterval(duration),
            duration: duration,
            zonesCompleted: try container.decodeIfPresent(Int.self, forKey: .zonesCompleted) ?? 0,
            plannedZones: planned,
            verifiedZones: try container.decodeIfPresent(Int.self, forKey: .verifiedZones),
            source: try container.decodeIfPresent(BrushSessionSource.self, forKey: .source) ?? .manual,
            flossed: try container.decodeIfPresent(Bool.self, forKey: .flossed) ?? false,
            tongueCleaned: try container.decodeIfPresent(Bool.self, forKey: .tongueCleaned) ?? false
        )
    }

    public var period: RoutinePeriod { RoutinePeriod.period(for: startedAt) }

    public func period(in day: RoutineDay, calendar: Calendar = .current) -> RoutinePeriod {
        day.period(for: startedAt, calendar: calendar)
    }

    /// Whether this counts as a finished routine. Depends only on the pacer.
    public var completedRoutine: Bool { duration >= 110 && zonesCompleted >= plannedZones }

    /// True when motion analysis ran and confirmed every planned zone.
    public var fullyVerified: Bool { verifiedZones.map { $0 >= plannedZones } ?? false }
}

public struct RoutinePreferences: Codable, Equatable, Sendable {
    public var morningEnabled: Bool
    public var morningHour: Int
    public var morningMinute: Int
    public var eveningEnabled: Bool
    public var eveningHour: Int
    public var eveningMinute: Int
    public var flossPromptEnabled: Bool
    public var tonguePromptEnabled: Bool

    /// Hour at which the routine day rolls over, so late-night brushing counts
    /// toward the day it finished rather than the one it started.
    public var dayEndsAtHour: Int

    public var routineDay: RoutineDay { RoutineDay(endsAtHour: dayEndsAtHour) }

    public init(
        morningEnabled: Bool = true,
        morningHour: Int = 7,
        morningMinute: Int = 30,
        eveningEnabled: Bool = true,
        eveningHour: Int = 21,
        eveningMinute: Int = 30,
        flossPromptEnabled: Bool = true,
        tonguePromptEnabled: Bool = false,
        dayEndsAtHour: Int = 3
    ) {
        self.morningEnabled = morningEnabled
        self.morningHour = morningHour
        self.morningMinute = morningMinute
        self.eveningEnabled = eveningEnabled
        self.eveningHour = eveningHour
        self.eveningMinute = eveningMinute
        self.flossPromptEnabled = flossPromptEnabled
        self.tonguePromptEnabled = tonguePromptEnabled
        self.dayEndsAtHour = min(11, max(0, dayEndsAtHour))
    }

    /// Field-by-field so a stored blob written before a field existed still
    /// decodes. `RoutineSettings` falls back to defaults on any decode failure,
    /// which would silently discard every other preference the user had set.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = RoutinePreferences()
        self.init(
            morningEnabled: try container.decodeIfPresent(Bool.self, forKey: .morningEnabled) ?? fallback.morningEnabled,
            morningHour: try container.decodeIfPresent(Int.self, forKey: .morningHour) ?? fallback.morningHour,
            morningMinute: try container.decodeIfPresent(Int.self, forKey: .morningMinute) ?? fallback.morningMinute,
            eveningEnabled: try container.decodeIfPresent(Bool.self, forKey: .eveningEnabled) ?? fallback.eveningEnabled,
            eveningHour: try container.decodeIfPresent(Int.self, forKey: .eveningHour) ?? fallback.eveningHour,
            eveningMinute: try container.decodeIfPresent(Int.self, forKey: .eveningMinute) ?? fallback.eveningMinute,
            flossPromptEnabled: try container.decodeIfPresent(Bool.self, forKey: .flossPromptEnabled) ?? fallback.flossPromptEnabled,
            tonguePromptEnabled: try container.decodeIfPresent(Bool.self, forKey: .tonguePromptEnabled) ?? fallback.tonguePromptEnabled,
            dayEndsAtHour: try container.decodeIfPresent(Int.self, forKey: .dayEndsAtHour) ?? fallback.dayEndsAtHour
        )
    }
}

public struct RoutineDayStatus: Equatable, Sendable {
    public let date: Date
    public let morning: BrushSession?
    public let evening: BrushSession?

    public var completedCount: Int { [morning, evening].compactMap { $0 }.count }
}

public enum BrushSessionHistory {
    public static func status(
        on date: Date,
        sessions: [BrushSession],
        calendar: Calendar = .current,
        day: RoutineDay = .default
    ) -> RoutineDayStatus {
        let sameDay = sessions.filter {
            day.isDate($0.startedAt, inSameRoutineDayAs: date, calendar: calendar)
        }
        func latest(_ period: RoutinePeriod) -> BrushSession? {
            sameDay
                .filter { $0.period(in: day, calendar: calendar) == period }
                .max { $0.startedAt < $1.startedAt }
        }
        return RoutineDayStatus(
            date: day.startOfRoutineDay(for: date, calendar: calendar),
            morning: latest(.morning),
            evening: latest(.evening)
        )
    }

    /// Consecutive complete routine days, counting back from today.
    ///
    /// Today is in progress until its evening brush lands, so an incomplete today
    /// does not end the run — it simply does not count yet. Breaking the streak at
    /// midnight would zero it out every morning for someone brushing perfectly.
    public static func currentStreak(
        sessions: [BrushSession],
        today: Date = .now,
        calendar: Calendar = .current,
        day: RoutineDay = .default
    ) -> Int {
        var cursor = day.startOfRoutineDay(for: today, calendar: calendar)
        var streak = 0

        func isComplete(_ dayStart: Date) -> Bool {
            status(
                on: day.middayOfRoutineDay(startingAt: dayStart, calendar: calendar),
                sessions: sessions,
                calendar: calendar,
                day: day
            ).completedCount == 2
        }

        if isComplete(cursor) { streak += 1 }

        while let previous = calendar.date(byAdding: .day, value: -1, to: cursor) {
            cursor = previous
            guard isComplete(cursor) else { break }
            streak += 1
        }
        return streak
    }
}

