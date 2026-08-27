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

    /// Reported by the Watch, which is the only device that can read it.
    /// `nil` until a paired Watch has connected at least once.
    var watchWrist: WatchWrist? {
        didSet {
            UserDefaults.standard.set(watchWrist?.rawValue, forKey: wristKey)
        }
    }

    private let key = "routine-preferences-v1"
    private let wristKey = "watch-wrist-v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(RoutinePreferences.self, from: data) {
            preferences = decoded
        } else {
            preferences = RoutinePreferences()
        }
        watchWrist = UserDefaults.standard.string(forKey: wristKey).flatMap(WatchWrist.init(rawValue:))
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

