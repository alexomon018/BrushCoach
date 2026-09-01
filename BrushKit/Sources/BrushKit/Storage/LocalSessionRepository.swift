import Foundation

/// The original JSON repository. It remains available as the migration source
/// and as a last-resort fallback if the local database cannot open.
public struct LocalSessionRepository: SessionRepository, Sendable {
    public let fileURL: URL

    /// Most recent sessions to keep on disk, or `nil` to keep every one.
    ///
    /// The whole array is rewritten on every upsert, so an unbounded file makes
    /// each brush cost more than the last. The phone keeps everything in the
    /// database; the Watch passes its sessions on and only needs a short tail,
    /// so it caps this. See `WatchSessionStore`.
    public let retentionLimit: Int?

    public init(
        directory: URL,
        filename: String = "brush-sessions.json",
        retentionLimit: Int? = nil
    ) {
        fileURL = directory.appending(path: filename)
        self.retentionLimit = retentionLimit.map { max(1, $0) }
    }

    public func load() throws -> [BrushSession] {
        guard FileManager.default.fileExists(atPath: fileURL.path()) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try Self.decoder.decode([BrushSession].self, from: data)
            .sorted { $0.startedAt > $1.startedAt }
    }

    @discardableResult
    public func upsert(_ session: BrushSession) throws -> [BrushSession] {
        var sessions = try load()
        var stamped = session
        // Rewriting a record keeps the moment it was first created; only the
        // write time moves. A later sync layer orders by `updatedAt`.
        if let existing = sessions.first(where: { $0.id == session.id }) {
            stamped.createdAt = existing.createdAt
        }
        stamped.updatedAt = .now
        sessions.removeAll { $0.id == session.id }
        sessions.append(stamped)
        return try save(sessions)
    }

    @discardableResult
    public func delete(id: UUID) throws -> [BrushSession] {
        var sessions = try load()
        sessions.removeAll { $0.id == id }
        return try save(sessions)
    }

    @discardableResult
    public func save(_ sessions: [BrushSession]) throws -> [BrushSession] {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var sorted = sessions.sorted { $0.startedAt > $1.startedAt }
        if let retentionLimit, sorted.count > retentionLimit {
            sorted = Array(sorted.prefix(retentionLimit))
        }
        let data = try Self.encoder.encode(sorted)
        try data.write(to: fileURL, options: .atomic)
        return sorted
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
