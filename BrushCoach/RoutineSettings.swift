import BrushKit
import Foundation
import Observation

@MainActor
@Observable
final class RoutineSettings {
    static let shared = RoutineSettings()

    var preferences: RoutinePreferences {
        didSet { persistAndApply() }
    }

    private let key = "routine-preferences-v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(RoutinePreferences.self, from: data) {
            preferences = decoded
        } else {
            preferences = RoutinePreferences()
        }
    }

    func apply() async {
        PhoneTraceReceiver.shared.send(preferences: preferences)
        await ReminderScheduler.shared.refresh(
            preferences: preferences,
            sessions: SessionStore.shared.sessions
        )
    }

    private func persistAndApply() {
        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: key)
        }
        Task { await apply() }
    }
}

