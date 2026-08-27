import BrushKit
import Foundation
import HealthKit

final class HealthKitWriter: @unchecked Sendable {
    private let store = HKHealthStore()
    private let metadataKey = "BrushCoachSessionID"

    private var type: HKCategoryType? {
        HKObjectType.categoryType(forIdentifier: .toothbrushingEvent)
    }

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable(), let type else { return false }
        do {
            try await store.requestAuthorization(toShare: [type], read: [])
            return store.authorizationStatus(for: type) == .sharingAuthorized
        } catch {
            return false
        }
    }

    func replace(_ session: BrushSession) async throws {
        guard let type else { return }
        guard store.authorizationStatus(for: type) == .sharingAuthorized else { return }
        try await delete(sessionID: session.id)
        let sample = HKCategorySample(
            type: type,
            value: HKCategoryValue.notApplicable.rawValue,
            start: session.startedAt,
            end: session.endedAt,
            metadata: [metadataKey: session.id.uuidString]
        )
        try await store.save(sample)
    }

    func delete(sessionID: UUID) async throws {
        guard let type else { return }
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: metadataKey,
            allowedValues: [sessionID.uuidString]
        )
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.deleteObjects(of: type, predicate: predicate) { _, _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
}
