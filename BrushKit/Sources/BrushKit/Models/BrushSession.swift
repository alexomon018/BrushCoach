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
    public static let currentSchemaVersion = 1

    public var id: UUID
    public var schemaVersion: Int
    public var startedAt: Date
    public var endedAt: Date
    /// Captured when the session is created so a future export or sync does not
    /// reinterpret a brush after the user travels to another timezone.
    public var timeZoneIdentifier: String
    public var duration: TimeInterval
    /// Legacy 20-second completion segments. New free-brushing sessions still
    /// fill all six only when the fixed timer reaches the end; these are not
    /// classifier observations and are never shown as mouth coverage.
    public var zonesCompleted: Int

    /// Legacy completion-segment count retained for stored-session compatibility.
    public var plannedZones: Int

    /// Legacy aggregate verification count, or `nil` when no verification ran.
    /// New sessions use `analysis.zoneDurations` for region-level results.
    /// Deliberately distinct from `0`, which means verification ran and confirmed
    /// nothing. Never used to gate routine credit.
    public var verifiedZones: Int?

    /// What motion analysis observed, or `nil` when it did not run — because the
    /// Watch was on the wrong wrist, the user has not answered the handedness
    /// question, or sensing failed. Never used to gate routine credit.
    public var analysis: SessionAnalysis?
    public var analysisVersion: Int?

    public var source: BrushSessionSource
    public var flossed: Bool
    public var tongueCleaned: Bool

    /// When this record first came into existence, on whichever device created
    /// it. Distinct from `startedAt`, which is when the brushing began: a
    /// session entered by hand a week later shares neither.
    public var createdAt: Date

    /// When this record was last written to storage. The repository stamps it on
    /// every upsert, so it is the ordering key a later sync layer needs to decide
    /// which of two copies of the same `id` is newer.
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        schemaVersion: Int = currentSchemaVersion,
        startedAt: Date,
        endedAt: Date,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        duration: TimeInterval,
        zonesCompleted: Int,
        plannedZones: Int = 6,
        verifiedZones: Int? = nil,
        analysis: SessionAnalysis? = nil,
        analysisVersion: Int? = nil,
        source: BrushSessionSource,
        flossed: Bool = false,
        tongueCleaned: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.schemaVersion = max(1, schemaVersion)
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.duration = max(0, duration)
        let planned = max(1, plannedZones)
        self.plannedZones = planned
        self.zonesCompleted = min(planned, max(0, zonesCompleted))
        self.verifiedZones = verifiedZones.map { min(planned, max(0, $0)) }
        self.analysis = analysis
        self.analysisVersion = analysis.map { _ in
            analysisVersion ?? SessionAnalysis.currentSchemaVersion
        }
        self.source = source
        self.flossed = flossed
        self.tongueCleaned = tongueCleaned
        self.createdAt = createdAt
        // A record that has never been rewritten was last written when it was
        // created; `nil` here must not read as the epoch.
        self.updatedAt = max(updatedAt ?? createdAt, createdAt)
    }

    /// Decoded field-by-field so that both transferred Watch records and the
    /// legacy JSON history remain compatible as the durable schema evolves.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let startedAt = try container.decode(Date.self, forKey: .startedAt)
        let duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        let planned = try container.decodeIfPresent(Int.self, forKey: .plannedZones) ?? 6
        let analysis = try container.decodeIfPresent(SessionAnalysis.self, forKey: .analysis)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            schemaVersion: try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
                ?? Self.currentSchemaVersion,
            startedAt: startedAt,
            endedAt: try container.decodeIfPresent(Date.self, forKey: .endedAt)
                ?? startedAt.addingTimeInterval(duration),
            timeZoneIdentifier: try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
                ?? TimeZone.current.identifier,
            duration: duration,
            zonesCompleted: try container.decodeIfPresent(Int.self, forKey: .zonesCompleted) ?? 0,
            plannedZones: planned,
            verifiedZones: try container.decodeIfPresent(Int.self, forKey: .verifiedZones),
            analysis: analysis,
            analysisVersion: try container.decodeIfPresent(Int.self, forKey: .analysisVersion),
            source: try container.decodeIfPresent(BrushSessionSource.self, forKey: .source) ?? .manual,
            flossed: try container.decodeIfPresent(Bool.self, forKey: .flossed) ?? false,
            tongueCleaned: try container.decodeIfPresent(Bool.self, forKey: .tongueCleaned) ?? false,
            // Records written before these fields existed: the best available
            // answer for both is when the brushing happened.
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? startedAt,
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        )
    }

    /// Which routine slot this brush belongs to.
    ///
    /// The routine day is required rather than defaulted. A convenience property
    /// using `RoutineDay.default` used to exist, and silently disagreed with the
    /// rest of the app for anyone who moved their rollover hour: with a 5am
    /// rollover a 4am brush is that night's evening, but the default read it as
    /// the next morning. Every other call site already threads the configured day
    /// through, so the default was the only way to get a wrong answer.
    public func period(in day: RoutineDay, calendar: Calendar = .current) -> RoutinePeriod {
        day.period(for: startedAt, calendar: calendar)
    }

    /// Whether this counts as a finished routine. Depends only on timer facts.
    public var completedRoutine: Bool { duration >= 110 && zonesCompleted >= plannedZones }

    /// True when motion analysis ran and confirmed every planned zone.
    public var fullyVerified: Bool { verifiedZones.map { $0 >= plannedZones } ?? false }

    /// Seconds of real brushing, when analysis produced a usable reading.
    /// `nil` covers both "analysis did not run" and "analysis saw too little to
    /// say" — the summary must not present either as zero seconds brushed.
    public var activeBrushingSeconds: TimeInterval? {
        guard let analysis, !analysis.isInconclusive(forSessionLasting: duration) else { return nil }
        return analysis.activeBrushingSeconds
    }
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

    /// Which hand holds the toothbrush. The Watch reads its own wrist, so this
    /// is the only half of the handedness question a person ever has to answer.
    /// `nil` until they do.
    public var brushingHand: BrushingHand?

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
        brushingHand: BrushingHand? = nil,
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
        self.brushingHand = brushingHand
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
            brushingHand: try container.decodeIfPresent(BrushingHand.self, forKey: .brushingHand),
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
