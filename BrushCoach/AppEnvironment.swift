import BrushKit
import Foundation

/// The composition root: the single place that knows which concrete services the
/// running app uses and how they refer to each other.
///
/// Reminder scheduling needs both the configured times and the sessions already
/// recorded, so something has to hold both. Confining that to one type keeps the
/// stores themselves free of each other — each declares a capability it needs
/// and is handed one, which is what makes either constructible in isolation.
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let sessions: SessionStore
    let settings: RoutineSettings
    private let watchLink: PhoneTraceReceiver

    private init() {
        let reminders = ReminderScheduler.shared
        let watchLink = PhoneTraceReceiver.shared
        self.watchLink = watchLink

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: "BrushCoach", directoryHint: .isDirectory)

        let repository: any SessionRepository
        let startupError: String?
        let usingFallback: Bool
        do {
            repository = try LocalSessionDatabase(directory: base)
            startupError = nil
            usingFallback = false
        } catch {
            // Brushing must still work if the database cannot open. The JSON
            // repository is also the source that a later healthy launch merges.
            repository = LocalSessionRepository(directory: base)
            startupError = """
            Your history is in backup storage because the database wouldn't open. \
            Brushing still records normally. \(error.localizedDescription)
            """
            usingFallback = true
        }

        // Each store is handed a closure for the half it does not own. They are
        // read lazily, so neither store has to exist when the other is built.
        let sessionsBox = Box<SessionStore>()
        let settingsBox = Box<RoutineSettings>()

        let sessions = SessionStore(
            repository: repository,
            health: HealthKitWriter(),
            reminders: reminders,
            preferences: { settingsBox.value?.preferences ?? RoutinePreferences() },
            startupError: startupError,
            isUsingFallbackStorage: usingFallback
        )
        let settings = RoutineSettings(
            reminders: reminders,
            watch: watchLink,
            sessions: { sessionsBox.value?.sessions ?? [] }
        )
        sessionsBox.value = sessions
        settingsBox.value = settings

        self.sessions = sessions
        self.settings = settings

        watchLink.connect(sessions: sessions, settings: settings)
    }

    func activate() {
        watchLink.activate()

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demoSession") {
            UserDefaults.standard.set(true, forKey: "hasSeenConsumerOnboarding")
            sessions.upsert(Self.demoSession(), writeHealth: false)
        }
        #endif
    }

    #if DEBUG
    /// A simulator-only result that exercises every state of the mouth map.
    /// Launching with `-demoSession` makes design review possible without
    /// pretending Core Motion is available in Simulator or altering release
    /// behavior. A stable ID means repeated launches update one demo record
    /// instead of filling History with fixtures.
    private static func demoSession(now: Date = .now) -> BrushSession {
        let duration: TimeInterval = ZoneCoverageStandard.sessionDuration
        return BrushSession(
            id: UUID(uuidString: "B7A4C18C-3C7E-4C52-97E7-93A6D87ED3E1")!,
            startedAt: now.addingTimeInterval(-duration),
            endedAt: now,
            duration: duration,
            zonesCompleted: 6,
            plannedZones: 6,
            analysis: SessionAnalysis(
                activeBrushingSeconds: 108,
                fastStrokeSeconds: 4,
                positionChanges: 8,
                longestSinglePositionSeconds: 24,
                medianStrokeRatePerMinute: 156,
                windowCount: 119,
                confidentZoneWindows: 100,
                zoneEstimationAttempted: true,
                zoneDurations: ZoneDurations(
                    upperLeft: 23,
                    upperCentre: 20,
                    upperRight: 11,
                    lowerLeft: 18,
                    lowerCentre: 7,
                    lowerRight: 21
                ),
                coveredSeconds: duration,
                recordingCompleted: true
            ),
            source: .watch
        )
    }
    #endif
}

/// A one-slot holder so the two stores can be handed references to each other
/// after both exist, without either taking a hard dependency on the other's type.
///
/// Weak on purpose. Each store captures the box holding the *other* store, so a
/// strong slot would make the pair retain each other through their closures.
/// `AppEnvironment` owns both, which is what keeps them alive.
@MainActor
private final class Box<Value: AnyObject> {
    weak var value: Value?
}
