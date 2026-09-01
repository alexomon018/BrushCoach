import Foundation

/// The storage boundary used by the app-facing session store.
///
/// Keeping persistence behind this protocol lets the local database replace the
/// original JSON file without leaking SwiftData into views or domain models.
@MainActor
public protocol SessionRepository {
    func load() throws -> [BrushSession]

    @discardableResult
    func upsert(_ session: BrushSession) throws -> [BrushSession]

    @discardableResult
    func delete(id: UUID) throws -> [BrushSession]
}
