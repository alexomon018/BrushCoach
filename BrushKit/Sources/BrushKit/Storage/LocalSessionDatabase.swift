import Foundation
import SwiftData

/// SQLite-backed, device-local session storage. CloudKit is explicitly disabled;
/// this database never creates an account or sends a record off the device.
@MainActor
public final class LocalSessionDatabase: SessionRepository {
    public let databaseURL: URL

    private let context: ModelContext
    private let legacyRepository: LocalSessionRepository

    public init(
        directory: URL,
        databaseFilename: String = "brushcoach-local.store",
        legacyFilename: String = "brush-sessions.json"
    ) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        databaseURL = directory.appending(path: databaseFilename)
        legacyRepository = LocalSessionRepository(
            directory: directory,
            filename: legacyFilename
        )

        let schema = Schema([
            StoredBrushSession.self,
            LocalStoreState.self
        ])
        let configuration = ModelConfiguration(
            "BrushCoachLocal",
            schema: schema,
            url: databaseURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        context = ModelContext(container)
        context.autosaveEnabled = false

        try importLegacySessionsIfNeeded()
    }

    public func load() throws -> [BrushSession] {
        let descriptor = FetchDescriptor<StoredBrushSession>(
            sortBy: [SortDescriptor(\StoredBrushSession.startedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map(\.session)
    }

    @discardableResult
    public func upsert(_ session: BrushSession) throws -> [BrushSession] {
        do {
            try upsertWithoutSaving(session, now: .now)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return try load()
    }

    @discardableResult
    public func delete(id: UUID) throws -> [BrushSession] {
        do {
            if let record = try record(id: id) {
                context.delete(record)
                try context.save()
            }
        } catch {
            context.rollback()
            throw error
        }
        return try load()
    }

    /// Imports the old JSON array exactly once per version of that file. The
    /// modification timestamp makes recovery safe too: if database startup ever
    /// falls back to JSON and writes newer history, the next healthy launch
    /// merges those records instead of losing them.
    private func importLegacySessionsIfNeeded() throws {
        let fileURL = legacyRepository.fileURL
        guard FileManager.default.fileExists(atPath: fileURL.path()) else { return }

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path())
        let modificationTime = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let state = try migrationState()
        guard state?.lastLegacySessionsModificationTime != modificationTime else { return }

        let now = Date.now
        for session in try legacyRepository.load() {
            try upsertWithoutSaving(session, now: now)
        }

        if let state {
            state.lastLegacySessionsModificationTime = modificationTime
        } else {
            context.insert(LocalStoreState(
                key: LocalStoreState.legacySessionsKey,
                lastLegacySessionsModificationTime: modificationTime
            ))
        }
        try context.save()
    }

    private func upsertWithoutSaving(_ session: BrushSession, now: Date) throws {
        if let existing = try record(id: session.id) {
            existing.apply(session, updatedAt: now)
        } else {
            context.insert(StoredBrushSession(session: session, now: now))
        }
    }

    private func record(id: UUID) throws -> StoredBrushSession? {
        let targetID = id
        var descriptor = FetchDescriptor<StoredBrushSession>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func migrationState() throws -> LocalStoreState? {
        let key = LocalStoreState.legacySessionsKey
        var descriptor = FetchDescriptor<LocalStoreState>(
            predicate: #Predicate { $0.key == key }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

@Model
private final class LocalStoreState {
    static let legacySessionsKey = "legacy-session-json"

    @Attribute(.unique) var key: String
    var lastLegacySessionsModificationTime: Double

    init(key: String, lastLegacySessionsModificationTime: Double) {
        self.key = key
        self.lastLegacySessionsModificationTime = lastLegacySessionsModificationTime
    }
}

/// A deliberately flat record. Aggregate analysis fields stay queryable without
/// retaining the raw motion samples that produced them.
@Model
private final class StoredBrushSession {
    @Attribute(.unique) var id: UUID
    var sessionSchemaVersion: Int
    var analysisSchemaVersion: Int?
    var startedAt: Date
    var endedAt: Date
    var timeZoneIdentifier: String
    var duration: TimeInterval
    var zonesCompleted: Int
    var plannedZones: Int
    var verifiedZones: Int?
    var sourceRawValue: String
    var flossed: Bool
    var tongueCleaned: Bool

    var hasAnalysis: Bool
    var activeBrushingSeconds: TimeInterval
    var fastStrokeSeconds: TimeInterval
    var positionChanges: Int
    var longestSinglePositionSeconds: TimeInterval
    var medianStrokeRatePerMinute: Double
    var windowCount: Int
    var confidentZoneWindows: Int
    var zoneAgreement: Double?
    var zoneEstimationAttempted: Bool
    var coveredSeconds: TimeInterval
    var recordingCompleted: Bool

    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(session: BrushSession, now: Date) {
        id = session.id
        sessionSchemaVersion = session.schemaVersion
        analysisSchemaVersion = session.analysisVersion
        startedAt = session.startedAt
        endedAt = session.endedAt
        timeZoneIdentifier = session.timeZoneIdentifier
        duration = session.duration
        zonesCompleted = session.zonesCompleted
        plannedZones = session.plannedZones
        verifiedZones = session.verifiedZones
        sourceRawValue = session.source.rawValue
        flossed = session.flossed
        tongueCleaned = session.tongueCleaned

        let analysis = session.analysis
        hasAnalysis = analysis != nil
        activeBrushingSeconds = analysis?.activeBrushingSeconds ?? 0
        fastStrokeSeconds = analysis?.fastStrokeSeconds ?? 0
        positionChanges = analysis?.positionChanges ?? 0
        longestSinglePositionSeconds = analysis?.longestSinglePositionSeconds ?? 0
        medianStrokeRatePerMinute = analysis?.medianStrokeRatePerMinute ?? 0
        windowCount = analysis?.windowCount ?? 0
        confidentZoneWindows = analysis?.confidentZoneWindows ?? 0
        zoneAgreement = analysis?.zoneAgreement
        zoneEstimationAttempted = analysis?.zoneEstimationAttempted ?? false
        coveredSeconds = analysis?.coveredSeconds ?? 0
        recordingCompleted = analysis?.recordingCompleted ?? true

        createdAt = now
        updatedAt = now
        deletedAt = nil
    }

    func apply(_ session: BrushSession, updatedAt: Date) {
        sessionSchemaVersion = session.schemaVersion
        analysisSchemaVersion = session.analysisVersion
        startedAt = session.startedAt
        endedAt = session.endedAt
        timeZoneIdentifier = session.timeZoneIdentifier
        duration = session.duration
        zonesCompleted = session.zonesCompleted
        plannedZones = session.plannedZones
        verifiedZones = session.verifiedZones
        sourceRawValue = session.source.rawValue
        flossed = session.flossed
        tongueCleaned = session.tongueCleaned

        let analysis = session.analysis
        hasAnalysis = analysis != nil
        activeBrushingSeconds = analysis?.activeBrushingSeconds ?? 0
        fastStrokeSeconds = analysis?.fastStrokeSeconds ?? 0
        positionChanges = analysis?.positionChanges ?? 0
        longestSinglePositionSeconds = analysis?.longestSinglePositionSeconds ?? 0
        medianStrokeRatePerMinute = analysis?.medianStrokeRatePerMinute ?? 0
        windowCount = analysis?.windowCount ?? 0
        confidentZoneWindows = analysis?.confidentZoneWindows ?? 0
        zoneAgreement = analysis?.zoneAgreement
        zoneEstimationAttempted = analysis?.zoneEstimationAttempted ?? false
        coveredSeconds = analysis?.coveredSeconds ?? 0
        recordingCompleted = analysis?.recordingCompleted ?? true
        self.updatedAt = updatedAt
        deletedAt = nil
    }

    var session: BrushSession {
        let analysis = hasAnalysis ? SessionAnalysis(
            activeBrushingSeconds: activeBrushingSeconds,
            fastStrokeSeconds: fastStrokeSeconds,
            positionChanges: positionChanges,
            longestSinglePositionSeconds: longestSinglePositionSeconds,
            medianStrokeRatePerMinute: medianStrokeRatePerMinute,
            windowCount: windowCount,
            confidentZoneWindows: confidentZoneWindows,
            zoneAgreement: zoneAgreement,
            zoneEstimationAttempted: zoneEstimationAttempted,
            coveredSeconds: coveredSeconds,
            recordingCompleted: recordingCompleted
        ) : nil

        return BrushSession(
            id: id,
            schemaVersion: sessionSchemaVersion,
            startedAt: startedAt,
            endedAt: endedAt,
            timeZoneIdentifier: timeZoneIdentifier,
            duration: duration,
            zonesCompleted: zonesCompleted,
            plannedZones: plannedZones,
            verifiedZones: verifiedZones,
            analysis: analysis,
            analysisVersion: analysisSchemaVersion,
            source: BrushSessionSource(rawValue: sourceRawValue) ?? .manual,
            flossed: flossed,
            tongueCleaned: tongueCleaned
        )
    }
}
