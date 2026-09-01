import BrushKit
import Foundation

/// The collaborators the two stores need, named as capabilities rather than as
/// each other.
///
/// `SessionStore` and `RoutineSettings` genuinely both feed reminder scheduling:
/// a reminder depends on the configured times *and* on whether that brush has
/// already happened. Previously each reached into the other's singleton to get
/// the missing half, so neither could be constructed — or tested — alone.
///
/// These protocols move that knot to one place. A store now declares what it
/// needs; `AppEnvironment` is the only thing that knows the concrete instances
/// and closes the loop between them.

protocol HealthWriting: Sendable {
    var isAuthorized: Bool { get }
    func requestAuthorization() async -> Bool
    func replace(_ session: BrushSession) async throws
    func delete(sessionID: UUID) async throws
}

protocol ReminderScheduling: Sendable {
    func refresh(preferences: RoutinePreferences, sessions: [BrushSession]) async
    func isAuthorized() async -> Bool
    func requestAuthorization() async -> Bool
}

/// The Watch half of the pair, from the phone's side.
protocol WatchLinking: Sendable {
    @MainActor func send(preferences: RoutinePreferences)
}

extension HealthKitWriter: HealthWriting {}
extension ReminderScheduler: ReminderScheduling {}
extension PhoneTraceReceiver: WatchLinking {}
