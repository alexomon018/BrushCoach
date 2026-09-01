import Foundation
import Testing
@testable import BrushKit

struct LocalSessionDatabaseTests {
    @Test @MainActor
    func databaseRoundTripsUpdatesAndDeletesAggregateSessions() throws {
        let directory = temporaryDirectory()
        let database = try LocalSessionDatabase(directory: directory)
        let start = Date(timeIntervalSince1970: 1_787_699_400)
        var session = BrushSession(
            startedAt: start,
            endedAt: start.addingTimeInterval(120),
            timeZoneIdentifier: "Europe/Belgrade",
            duration: 120,
            zonesCompleted: 6,
            plannedZones: 6,
            verifiedZones: 4,
            analysis: SessionAnalysis(
                activeBrushingSeconds: 103,
                fastStrokeSeconds: 8,
                positionChanges: 5,
                longestSinglePositionSeconds: 24,
                medianStrokeRatePerMinute: 176,
                windowCount: 111,
                confidentZoneWindows: 72,
                zoneAgreement: 0.75,
                zoneEstimationAttempted: true,
                coveredSeconds: 119,
                recordingCompleted: true
            ),
            source: .watch,
            flossed: true
        )

        try database.upsert(session)
        let stored = try #require(database.load().first)
        #expect(stored == session)
        #expect(stored.analysisVersion == SessionAnalysis.currentSchemaVersion)
        #expect(stored.timeZoneIdentifier == "Europe/Belgrade")

        session.duration = 118
        session.verifiedZones = 0
        session.analysis = nil
        session.analysisVersion = nil
        try database.upsert(session)

        let updated = try #require(database.load().first)
        #expect(try database.load().count == 1)
        #expect(updated.duration == 118)
        #expect(updated.verifiedZones == 0)
        #expect(updated.analysis == nil)
        #expect(updated.analysisVersion == nil)

        try database.delete(id: session.id)
        #expect(try database.load().isEmpty)
    }

    @Test @MainActor
    func legacyJSONImportsOnceAndDoesNotResurrectADeletion() throws {
        let directory = temporaryDirectory()
        let legacy = LocalSessionRepository(directory: directory)
        let session = sampleSession()
        try legacy.upsert(session)

        var database: LocalSessionDatabase? = try LocalSessionDatabase(directory: directory)
        #expect(try database?.load().map(\.id) == [session.id])
        try database?.delete(id: session.id)
        #expect(try database?.load().isEmpty == true)
        database = nil

        let reopened = try LocalSessionDatabase(directory: directory)
        #expect(try reopened.load().isEmpty)
    }

    @Test @MainActor
    func aNewerFallbackJSONFileIsMergedOnTheNextHealthyLaunch() throws {
        let directory = temporaryDirectory()
        var database: LocalSessionDatabase? = try LocalSessionDatabase(directory: directory)
        let first = sampleSession()
        try database?.upsert(first)
        database = nil

        // Simulate a launch that had to use the JSON fallback and recorded a
        // second session there. A later healthy database launch must recover it.
        let fallback = LocalSessionRepository(directory: directory)
        let second = sampleSession(at: first.startedAt.addingTimeInterval(3_600))
        try fallback.upsert(second)

        let reopened = try LocalSessionDatabase(directory: directory)
        let ids = Set(try reopened.load().map(\.id))
        #expect(ids == [first.id, second.id])
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "BrushCoachDatabaseTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func sampleSession(at start: Date = Date(timeIntervalSince1970: 1_787_699_400)) -> BrushSession {
        BrushSession(
            startedAt: start,
            endedAt: start.addingTimeInterval(120),
            timeZoneIdentifier: "Europe/Belgrade",
            duration: 120,
            zonesCompleted: 6,
            source: .watch
        )
    }
}
