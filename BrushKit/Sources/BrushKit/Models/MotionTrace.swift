import Foundation

public enum Jaw: String, Codable, CaseIterable, Sendable {
    case upper
    case lower
}

public enum MouthSide: String, Codable, CaseIterable, Sendable {
    case left
    case centre
    case right
}

public enum BrushZoneLabel: String, Codable, CaseIterable, Identifiable, Sendable {
    case upperLeft
    case upperCentre
    case upperRight
    case lowerLeft
    case lowerCentre
    case lowerRight
    case transition
    case idle

    public var id: String { rawValue }

    /// The six regions the calibrated classifier can actually distinguish.
    /// `allCases` also contains capture-only labels (`transition` and `idle`),
    /// which must never appear as teeth on a coverage map.
    public static let mouthZones: [Self] = [
        .upperLeft, .upperCentre, .upperRight,
        .lowerLeft, .lowerCentre, .lowerRight
    ]

    public var displayName: String {
        switch self {
        case .upperLeft: "Upper left"
        case .upperCentre: "Upper centre"
        case .upperRight: "Upper right"
        case .lowerLeft: "Lower left"
        case .lowerCentre: "Lower centre"
        case .lowerRight: "Lower right"
        case .transition: "Transition"
        case .idle: "Idle"
        }
    }

    public var jaw: Jaw? {
        switch self {
        case .upperLeft, .upperCentre, .upperRight: .upper
        case .lowerLeft, .lowerCentre, .lowerRight: .lower
        case .transition, .idle: nil
        }
    }

    public var side: MouthSide? {
        switch self {
        case .upperLeft, .lowerLeft: .left
        case .upperCentre, .lowerCentre: .centre
        case .upperRight, .lowerRight: .right
        case .transition, .idle: nil
        }
    }
}

public enum WatchWrist: String, Codable, CaseIterable, Sendable {
    case left
    case right
}

public struct TraceMetadata: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: UUID
    public var recordedAt: Date
    public var label: BrushZoneLabel
    public var requestedSampleRateHz: Double
    public var requestedDuration: TimeInterval
    public var watchWrist: WatchWrist?
    public var notes: String?

    public init(
        schemaVersion: Int = currentSchemaVersion,
        id: UUID = UUID(),
        recordedAt: Date = Date(),
        label: BrushZoneLabel,
        requestedSampleRateHz: Double = 50,
        requestedDuration: TimeInterval = 10,
        watchWrist: WatchWrist? = nil,
        notes: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.recordedAt = recordedAt
        self.label = label
        self.requestedSampleRateHz = requestedSampleRateHz
        self.requestedDuration = requestedDuration
        self.watchWrist = watchWrist
        self.notes = notes
    }
}

public struct LabelledMotionTrace: Codable, Hashable, Sendable {
    public var metadata: TraceMetadata
    public var samples: [MotionSample]

    public init(metadata: TraceMetadata, samples: [MotionSample]) {
        self.metadata = metadata
        self.samples = samples
    }

    public var actualDuration: TimeInterval {
        guard let first = samples.first, let last = samples.last else { return 0 }
        return max(0, last.timestamp - first.timestamp)
    }

    public var actualSampleRateHz: Double {
        guard samples.count > 1, actualDuration > 0 else { return 0 }
        return Double(samples.count - 1) / actualDuration
    }
}

public enum TraceJSON {
    public static func encoder(prettyPrinted: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
