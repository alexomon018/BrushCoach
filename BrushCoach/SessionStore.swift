import BrushKit
import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
    static let shared = SessionStore()

    private(set) var sessions: [BrushSession] = []
    private(set) var lastError: String?

    @ObservationIgnored private let repository: LocalSessionRepository
    @ObservationIgnored private let health = HealthKitWriter()
    @ObservationIgnored private var healthEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "health-writing-enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "health-writing-enabled") }
    }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: "BrushCoach", directoryHint: .isDirectory)
        repository = LocalSessionRepository(directory: base)
        reload()
    }

    func reload() {
        do {
            sessions = try repository.load()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
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
                if writeHealth && healthEnabled { try? await health.replace(session) }
                await ReminderScheduler.shared.refresh(
                    preferences: RoutineSettings.shared.preferences,
                    sessions: sessions
                )
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func delete(_ session: BrushSession) {
        do {
            sessions = try repository.delete(id: session.id)
            lastError = nil
            Task {
                try? await health.delete(sessionID: session.id)
                await ReminderScheduler.shared.refresh(
                    preferences: RoutineSettings.shared.preferences,
                    sessions: sessions
                )
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    var isHealthAuthorized: Bool { health.isAuthorized }

    func requestHealthAccess() async -> Bool {
        let allowed = await health.requestAuthorization()
        healthEnabled = allowed
        if allowed {
            for session in sessions { try? await health.replace(session) }
        }
        return allowed
    }

    /// The day boundary the user configured, so late-night brushing is credited
    /// to the day it finished rather than the one it started.
    var routineDay: RoutineDay { RoutineSettings.shared.preferences.routineDay }

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
