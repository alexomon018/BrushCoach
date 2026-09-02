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
                zoneDurations: ZoneDurations(
                    upperLeft: 14,
                    upperCentre: 18,
                    upperRight: 20,
                    lowerLeft: 17,
                    lowerCentre: 16,
                    lowerRight: 18
                ),
                coveredSeconds: 119,
                recordingCompleted: true
            ),
            source: .watch,
            flossed: true
        )

        try database.upsert(session)
        let stored = try #require(database.load().first)
        // `updatedAt` is stamped by the write, so it is the one field that is
        // deliberately not expected to survive a round trip unchanged.
        #expect(stored.withoutWriteStamp == session.withoutWriteStamp)
        #expect(stored.createdAt == session.createdAt)
        #expect(stored.updatedAt >= session.createdAt)
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

    @Test @MainActor
    func rewritingASessionMovesUpdatedAtButNeverCreatedAt() throws {
        let directory = temporaryDirectory()
        let database = try LocalSessionDatabase(directory: directory)
        var session = sampleSession()
        try database.upsert(session)
        let first = try #require(database.load().first)

        session.flossed = true
        try database.upsert(session)
        let second = try #require(database.load().first)

        #expect(second.createdAt == first.createdAt)
        #expect(second.updatedAt >= first.updatedAt)
        #expect(second.flossed)
    }

    /// The Watch stamps `createdAt` when it builds the session. The phone must
    /// keep that instant rather than overwriting it with its own collection time,
    /// or every transferred session looks like it was created on arrival.
    @Test @MainActor
    func aTransferredSessionKeepsTheCreationInstantFromTheWatch() throws {
        let directory = temporaryDirectory()
        let database = try LocalSessionDatabase(directory: directory)
        let createdOnWatch = Date(timeIntervalSince1970: 1_787_000_000)
        var session = sampleSession()
        session.createdAt = createdOnWatch
        session.updatedAt = createdOnWatch

        try database.upsert(session)
        #expect(try database.load().first?.createdAt == createdOnWatch)
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

extension BrushSession {
    /// The record minus the timestamp a write is expected to move, so a round-trip
    /// assertion can still compare everything else field by field.
    var withoutWriteStamp: BrushSession {
        var copy = self
        copy.updatedAt = copy.createdAt
        return copy
    }
}

struct LocalSessionRepositoryRetentionTests {
    /// The Watch rewrites this whole file on every brush, so it keeps a bounded
    /// tail rather than an archive. The newest sessions are the ones that matter:
    /// older ones have already reached the phone.
    @Test @MainActor
    func aRetentionLimitKeepsTheNewestSessionsAndDropsTheRest() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "BrushCoachRetention-\(UUID().uuidString)", directoryHint: .isDirectory)
        let repository = LocalSessionRepository(directory: directory, retentionLimit: 3)
        let base = Date(timeIntervalSince1970: 1_787_000_000)

        for index in 0..<10 {
            let start = base.addingTimeInterval(Double(index) * 3_600)
            try repository.upsert(BrushSession(
                startedAt: start,
                endedAt: start.addingTimeInterval(120),
                duration: 120,
                zonesCompleted: 6,
                source: .watch
            ))
        }

        let stored = try repository.load()
        #expect(stored.count == 3)
        // Sorted newest first, so these are hours 9, 8 and 7.
        #expect(stored.map(\.startedAt) == [
            base.addingTimeInterval(9 * 3_600),
            base.addingTimeInterval(8 * 3_600),
            base.addingTimeInterval(7 * 3_600)
        ])
    }

    @Test @MainActor
    func withoutALimitEverySessionIsKept() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "BrushCoachRetention-\(UUID().uuidString)", directoryHint: .isDirectory)
        let repository = LocalSessionRepository(directory: directory)
        let base = Date(timeIntervalSince1970: 1_787_000_000)

        for index in 0..<10 {
            let start = base.addingTimeInterval(Double(index) * 3_600)
            try repository.upsert(BrushSession(
                startedAt: start,
                endedAt: start.addingTimeInterval(120),
                duration: 120,
                zonesCompleted: 6,
                source: .watch
            ))
        }
        #expect(try repository.load().count == 10)
    }
}

struct BrushSessionTimestampTests {
    /// History written before these fields existed still has to decode. The
    /// brushing instant is the only honest answer available for both.
    @Test
    func aLegacyRecordWithoutTimestampsFallsBackToTheBrushingInstant() throws {
        let json = """
        {
          "id": "8B1D0F5A-0000-4000-8000-000000000001",
          "startedAt": "2026-08-25T23:10:00Z",
          "endedAt": "2026-08-25T23:12:00Z",
          "duration": 120,
          "zonesCompleted": 6,
          "plannedZones": 6,
          "source": "watch"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(BrushSession.self, from: Data(json.utf8))

        #expect(session.createdAt == session.startedAt)
        #expect(session.updatedAt == session.startedAt)
    }

    /// A record that has never been rewritten was last written when it was
    /// created — not at the epoch, which is what a bare `Date()` default would
    /// give a sync layer comparing the two.
    @Test
    func anUnwrittenSessionReportsItsCreationAsItsLastWrite() {
        let created = Date(timeIntervalSince1970: 1_787_000_000)
        let session = BrushSession(
            startedAt: created,
            endedAt: created.addingTimeInterval(120),
            duration: 120,
            zonesCompleted: 6,
            source: .watch,
            createdAt: created
        )
        #expect(session.updatedAt == created)
    }
}
