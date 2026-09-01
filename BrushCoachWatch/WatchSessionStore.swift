import BrushKit
import Foundation

@MainActor
enum WatchSessionStore {
    /// Roughly a month of twice-daily brushing.
    ///
    /// The Watch is a staging area, not the archive: every session is handed to
    /// the phone over WatchConnectivity, which keeps the durable history. What
    /// stays here only has to cover the window where the phone has not collected
    /// yet. Without a cap the whole file is re-encoded on every brush, forever,
    /// on the most storage- and battery-constrained device in the system.
    static let retainedSessions = 60

    private static var repository: LocalSessionRepository {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: "BrushCoach", directoryHint: .isDirectory)
        return LocalSessionRepository(directory: base, retentionLimit: retainedSessions)
    }

    @discardableResult
    static func upsert(_ session: BrushSession) throws -> [BrushSession] {
        try repository.upsert(session)
    }
}

enum WatchRoutinePreferences {
    private static let key = "routine-preferences-v1"

    static var current: RoutinePreferences {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let value = try? JSONDecoder().decode(RoutinePreferences.self, from: data)
            else { return RoutinePreferences() }
            return value
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key)
        }
    }
}

extension Notification.Name {
    static let brushCoachStartSessionRequested = Notification.Name("BrushCoachStartSessionRequested")
}
