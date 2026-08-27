import BrushKit
import Foundation

struct TraceFile: Identifiable, Hashable, Sendable {
    let url: URL
    let trace: LabelledMotionTrace

    var id: UUID { trace.metadata.id }
}

enum PhoneTraceStore {
    static let appGroupIdentifier = "group.com.aleksamitic.BrushCoach"

    enum StorageError: LocalizedError {
        case containerUnavailable

        var errorDescription: String? {
            "The local trace container is unavailable."
        }
    }

    static func traceDirectory() throws -> URL {
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
        return directory
    }

    static func importReceivedFile(_ temporaryURL: URL) throws -> URL {
        let data = try Data(contentsOf: temporaryURL)
        let trace = try TraceJSON.decoder().decode(LabelledMotionTrace.self, from: data)
        let destination = try traceDirectory()
            .appending(path: "trace-\(trace.metadata.id.uuidString.lowercased()).json")
        if FileManager.default.fileExists(atPath: destination.path()) {
            try FileManager.default.removeItem(at: destination)
        }
        try data.write(to: destination, options: .atomic)
        return destination
    }

    static func list() throws -> [TraceFile] {
        let directory = try traceDirectory()
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let trace = try? TraceJSON.decoder().decode(LabelledMotionTrace.self, from: data)
                else { return nil }
                return TraceFile(url: url, trace: trace)
            }
            .sorted { $0.trace.metadata.recordedAt > $1.trace.metadata.recordedAt }
    }
}

extension Notification.Name {
    static let brushCoachTraceInboxChanged = Notification.Name("BrushCoachTraceInboxChanged")
}
