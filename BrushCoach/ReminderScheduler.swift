import BrushKit
import Foundation
import UserNotifications

actor ReminderScheduler {
    static let shared = ReminderScheduler()

    private let center = UNUserNotificationCenter.current()
    private let prefix = "brushcoach-routine-"

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// The answer as it stands right now, including one given during onboarding
    /// or revoked later in Settings, so the Routine tab can show what is true
    /// instead of staying blank until someone taps it.
    func isAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    func refresh(preferences: RoutinePreferences, sessions: [BrushSession]) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        let calendar = Calendar.current
        let routineDay = preferences.routineDay
        let today = calendar.startOfDay(for: .now)
        for dayOffset in 0..<14 {
            guard let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            // Probe from inside the routine day: `status` re-normalises whatever
            // instant it is given, and midnight sits before the rollover hour.
            let day = routineDay.middayOfRoutineDay(startingAt: dayStart, calendar: calendar)
            await schedule(
                .morning,
                on: day,
                hour: preferences.morningHour,
                minute: preferences.morningMinute,
                enabled: preferences.morningEnabled,
                sessions: sessions,
                calendar: calendar,
                day: routineDay
            )
            await schedule(
                .evening,
                on: day,
                hour: preferences.eveningHour,
                minute: preferences.eveningMinute,
                enabled: preferences.eveningEnabled,
                sessions: sessions,
                calendar: calendar,
                day: routineDay
            )
        }
    }

    private func schedule(
        _ period: RoutinePeriod,
        on day: Date,
        hour: Int,
        minute: Int,
        enabled: Bool,
        sessions: [BrushSession],
        calendar: Calendar,
        day routineDay: RoutineDay
    ) async {
        guard enabled else { return }
        let status = BrushSessionHistory.status(
            on: day, sessions: sessions, calendar: calendar, day: routineDay
        )
        guard (period == .morning ? status.morning : status.evening) == nil else { return }

        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        guard let fireDate = calendar.date(from: components), fireDate > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = period == .morning ? "Start fresh" : "Close the day clean"
        content.body = "Two minutes of free brushing. Your Watch is ready."
        content.sound = .default
        content.userInfo = ["route": "start"]

        let stamp = ISO8601DateFormatter().string(from: day).prefix(10)
        let request = UNNotificationRequest(
            identifier: "\(prefix)\(stamp)-\(period.rawValue)",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try? await center.add(request)
    }
}
