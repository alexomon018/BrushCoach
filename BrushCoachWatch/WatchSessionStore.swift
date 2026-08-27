import BrushKit
import Foundation

enum WatchSessionStore {
    private static var repository: LocalSessionRepository {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: "BrushCoach", directoryHint: .isDirectory)
        return LocalSessionRepository(directory: base)
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

