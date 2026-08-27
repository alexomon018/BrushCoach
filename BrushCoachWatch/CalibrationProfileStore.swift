import BrushKit
import Foundation

/// Stores the one calibration profile this watch has, on this watch only.
///
/// The profile is a compact statistical description of how one person moves
/// while brushing. It never leaves the device and is never transferred to the
/// phone.
enum CalibrationProfileStore {
    enum StoreError: LocalizedError {
        case containerUnavailable
        case unsupportedProfile

        var errorDescription: String? {
            switch self {
            case .containerUnavailable:
                "BrushCoach could not reach its local storage."
            case .unsupportedProfile:
                "This calibration was saved by a different version of BrushCoach. Please calibrate again."
            }
        }
    }

    /// Returns `nil` when there is no profile, and throws only when one exists
    /// but cannot be used — the caller must be able to tell "never calibrated"
    /// from "calibration is stale".
    static func load() throws -> PersonalCalibrationProfile? {
        let url = try profileURL(createDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let profile = try JSONDecoder.brushCoach.decode(
            PersonalCalibrationProfile.self,
            from: Data(contentsOf: url)
        )
        guard profile.schemaVersion == PersonalCalibrationProfile.currentSchemaVersion,
              profile.featureSchemaVersion == FeatureVector.schemaVersion else {
            throw StoreError.unsupportedProfile
        }
        return profile
    }

    /// Written atomically, and only after a calibration completes, so a failed
    /// or abandoned run can never replace a working profile.
    static func save(_ profile: PersonalCalibrationProfile) throws {
        let url = try profileURL(createDirectory: true)
        try JSONEncoder.brushCoach.encode(profile).write(to: url, options: .atomic)
    }

    static func clear() throws {
        let url = try profileURL(createDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
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
