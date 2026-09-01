import BrushKit
import Foundation
import Observation

@MainActor
@Observable
final class RoutineSettings {
    var preferences: RoutinePreferences {
        didSet { persistAndApply() }
    }

    /// Reported by the Watch, which is the only device that can read it.
    /// `nil` until a paired Watch has connected at least once.
    var watchWrist: WatchWrist? {
        didSet {
            UserDefaults.standard.set(watchWrist?.rawValue, forKey: wristKey)
        }
    }

    @ObservationIgnored private let reminders: any ReminderScheduling
    @ObservationIgnored private let watch: any WatchLinking
    /// Reminder scheduling needs to know which brushes already happened.
    /// Supplied as a closure so this store does not have to know that
    /// `SessionStore` exists.
    @ObservationIgnored private let sessions: @MainActor () -> [BrushSession]

    private let key = "routine-preferences-v1"
    private let wristKey = "watch-wrist-v1"

    init(
        reminders: any ReminderScheduling,
        watch: any WatchLinking,
        sessions: @escaping @MainActor () -> [BrushSession]
    ) {
        self.reminders = reminders
        self.watch = watch
        self.sessions = sessions
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(RoutinePreferences.self, from: data) {
            preferences = decoded
        } else {
            preferences = RoutinePreferences()
        }
        watchWrist = UserDefaults.standard.string(forKey: wristKey).flatMap(WatchWrist.init(rawValue:))
    }

    func apply() async {
        watch.send(preferences: preferences)
        await reminders.refresh(preferences: preferences, sessions: sessions())
    }

    private func persistAndApply() {
        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: key)
        }
        Task { await apply() }
    }
}
