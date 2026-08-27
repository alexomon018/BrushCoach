import Foundation

public struct LocalSessionRepository: Sendable {
    public let fileURL: URL

    public init(directory: URL, filename: String = "brush-sessions.json") {
        fileURL = directory.appending(path: filename)
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
        sessions.removeAll { $0.id == session.id }
        sessions.append(session)
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
        let sorted = sessions.sorted { $0.startedAt > $1.startedAt }
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

