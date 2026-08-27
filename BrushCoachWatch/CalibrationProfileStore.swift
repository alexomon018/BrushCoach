import BrushKit
import Foundation

enum CalibrationProfileStore {
    enum StoreError: LocalizedError {
        case containerUnavailable
        case unsupportedProfile

        var errorDescription: String? {
            switch self {
            case .containerUnavailable:
                "BrushCoach could not access its local profile storage."
            case .unsupportedProfile:
                "The saved calibration belongs to a different version of BrushCoach. Please recalibrate."
            }
        }
    }

    static func load() throws -> PersonalCalibrationProfile? {
        let url = try profileURL(createDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let profile = try JSONDecoder.brushCoach.decode(PersonalCalibrationProfile.self, from: data)
        guard profile.schemaVersion == PersonalCalibrationProfile.currentSchemaVersion,
              profile.featureSchemaVersion == FeatureVector.schemaVersion else {
            throw StoreError.unsupportedProfile
        }
        return profile
    }

    static func save(_ profile: PersonalCalibrationProfile) throws {
        let url = try profileURL(createDirectory: true)
        let data = try JSONEncoder.brushCoach.encode(profile)
        try data.write(to: url, options: .atomic)
    }

    private static func profileURL(createDirectory: Bool) throws -> URL {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw StoreError.containerUnavailable
        }
        let directory = applicationSupport.appending(path: "PersonalCalibration", directoryHint: .isDirectory)
        if createDirectory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appending(path: "profile.json")
    }
}

private extension JSONEncoder {
    static var brushCoach: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var brushCoach: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
