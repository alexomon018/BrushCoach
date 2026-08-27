import Foundation

public struct FeatureVector: Codable, Hashable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var windowStart: TimeInterval
    public var windowEnd: TimeInterval
    public var names: [String]
    public var values: [Double]

    public init(
        schemaVersion: Int = FeatureVector.schemaVersion,
        windowStart: TimeInterval,
        windowEnd: TimeInterval,
        names: [String],
        values: [Double]
    ) {
        precondition(names.count == values.count, "Feature names and values must stay aligned")
        self.schemaVersion = schemaVersion
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.names = names
        self.values = values
    }

    public subscript(name: String) -> Double? {
        guard let index = names.firstIndex(of: name) else { return nil }
        return values[index]
    }
}
