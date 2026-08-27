import BrushKit
import Foundation

enum WatchTraceStore {
    static let appGroupIdentifier = "group.com.aleksamitic.BrushCoach"

    enum StorageError: LocalizedError {
        case containerUnavailable

        var errorDescription: String? {
            "The local trace container is unavailable."
        }
    }

    static func save(_ trace: LabelledMotionTrace) throws -> URL {
        let container: URL
        if let appGroupContainer = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            container = appGroupContainer
        } else if let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            // Free Personal Teams cannot provision App Groups. WatchConnectivity
            // still bridges the two devices while each side stores traces locally.
            container = applicationSupport
        } else {
            throw StorageError.containerUnavailable
        }
        let directory = container.appending(path: "Traces", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: "trace-\(trace.metadata.id.uuidString.lowercased()).json")
        let data = try TraceJSON.encoder(prettyPrinted: false).encode(trace)
        try data.write(to: destination, options: .atomic)
        return destination
    }
}
