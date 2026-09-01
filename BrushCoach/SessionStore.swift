import BrushKit
import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [BrushSession] = []

    /// The last persistence failure, or `nil` when the last write succeeded.
    ///
    /// This is shown to the user. An app that says "couldn't check" about motion
    /// analysis should not go quiet about failing to save a brush.
    private(set) var lastError: String?

    /// True when the database would not open and history is being kept in the
    /// JSON fallback instead. Sessions are still recorded; the next healthy
    /// launch merges them back.
    private(set) var isUsingFallbackStorage = false

    @ObservationIgnored private let repository: any SessionRepository
    @ObservationIgnored private let health: any HealthWriting
    @ObservationIgnored private let reminders: any ReminderScheduling
    /// Reminder scheduling needs the configured times. Supplied as a closure so
    /// this store does not have to know that `RoutineSettings` exists.
    @ObservationIgnored private let preferences: @MainActor () -> RoutinePreferences

    @ObservationIgnored private var healthEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "health-writing-enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "health-writing-enabled") }
    }

    init(
        repository: any SessionRepository,
        health: any HealthWriting,
        reminders: any ReminderScheduling,
        preferences: @escaping @MainActor () -> RoutinePreferences,
        startupError: String? = nil,
        isUsingFallbackStorage: Bool = false
    ) {
        self.repository = repository
        self.health = health
        self.reminders = reminders
        self.preferences = preferences
        self.isUsingFallbackStorage = isUsingFallbackStorage
        reload()
        if lastError == nil { lastError = startupError }
    }

    func reload() {
        do {
            sessions = try repository.load()
            lastError = nil
        } catch {
            lastError = "Couldn't read your brushing history. \(error.localizedDescription)"
        }
    }

    func importFromWatch(_ session: BrushSession) {
        let isNew = !sessions.contains { $0.id == session.id }
        upsert(session, writeHealth: isNew)
    }

    func upsert(_ session: BrushSession, writeHealth: Bool = true) {
        do {
            sessions = try repository.upsert(session)
            lastError = nil
            Task {
                if writeHealth && healthEnabled { await writeToHealth(session) }
                await refreshReminders()
            }
        } catch {
            lastError = "Couldn't save that brush. \(error.localizedDescription)"
        }
    }

    func delete(_ session: BrushSession) {
        do {
            sessions = try repository.delete(id: session.id)
            lastError = nil
            Task {
                do {
                    try await health.delete(sessionID: session.id)
                } catch {
                    // The brush is gone from BrushCoach either way; only the
                    // Health copy is stale, and saying so beats silence.
                    lastError = "Removed here, but Apple Health still has a copy. \(error.localizedDescription)"
                }
                await refreshReminders()
            }
        } catch {
            lastError = "Couldn't delete that brush. \(error.localizedDescription)"
        }
    }

    var isHealthAuthorized: Bool { health.isAuthorized }

    func requestHealthAccess() async -> Bool {
        let allowed = await health.requestAuthorization()
        healthEnabled = allowed
        if allowed {
            for session in sessions { await writeToHealth(session) }
        }
        return allowed
    }

    /// Reads the history and preferences at the moment it runs, never a snapshot
    /// taken when the write happened.
    ///
    /// A Watch reconnecting can deliver a backlog, so several of these can be in
    /// flight at once with no ordering guarantee between them. Whichever runs
    /// last must still see the full history — a stale snapshot would schedule a
    /// reminder for a brush that has already been recorded.
    private func refreshReminders() async {
        await reminders.refresh(preferences: preferences(), sessions: sessions)
    }

    private func writeToHealth(_ session: BrushSession) async {
        do {
            try await health.replace(session)
        } catch {
            lastError = "Saved here, but Apple Health didn't accept it. \(error.localizedDescription)"
        }
    }

    /// The day boundary the user configured, so late-night brushing is credited
    /// to the day it finished rather than the one it started.
    var routineDay: RoutineDay { preferences().routineDay }

    var today: RoutineDayStatus {
        BrushSessionHistory.status(on: .now, sessions: sessions, day: routineDay)
    }

    var streak: Int {
        BrushSessionHistory.currentStreak(sessions: sessions, day: routineDay)
    }

    func status(on date: Date) -> RoutineDayStatus {
        BrushSessionHistory.status(on: date, sessions: sessions, day: routineDay)
    }
}
