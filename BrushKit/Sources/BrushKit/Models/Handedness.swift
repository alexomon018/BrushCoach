import Foundation

public enum BrushingHand: String, Codable, CaseIterable, Hashable, Sendable {
    case left
    case right

    public var displayName: String {
        switch self {
        case .left: "Left hand"
        case .right: "Right hand"
        }
    }
}

extension WatchWrist {
    public var displayName: String {
        switch self {
        case .left: "Left wrist"
        case .right: "Right wrist"
        }
    }

    /// The brushing hand this wrist would have to match for the Watch to see
    /// brushing motion at all.
    public var matchingHand: BrushingHand {
        switch self {
        case .left: .left
        case .right: .right
        }
    }
}

/// Why BrushCoach can or cannot read motion during a session.
///
/// Most people wear the Watch on the non-dominant wrist and brush with the
/// dominant hand. When those differ the Watch is on an arm that barely moves,
/// and no amount of signal processing recovers a brushing stroke that was never
/// recorded. Treating that as a first-class, user-visible state is deliberate:
/// the alternative is telling someone they did not brush when they did.
public enum SensingCapability: Equatable, Sendable {
    /// The Watch is on the brushing hand. Motion analysis can run.
    case available
    /// The Watch is on the other wrist. Pacing works; analysis cannot.
    case wrongWrist(watchWrist: WatchWrist, brushingHand: BrushingHand)
    /// The user has not told us which hand holds the brush yet.
    case unknown

    public var canSenseMotion: Bool { self == .available }

    /// Plain-language explanation, written for the person rather than the log.
    public var explanation: String {
        switch self {
        case .available:
            "Your Watch is on your brushing hand, so BrushCoach can check your strokes."
        case .wrongWrist(let wrist, let hand):
            "Your Watch is on your \(wrist == .left ? "left" : "right") wrist and you brush with your \(hand == .left ? "left" : "right") hand, so BrushCoach can't check your strokes. It will still pace your session."
        case .unknown:
            "Tell BrushCoach which hand holds your toothbrush and it can check your strokes."
        }
    }

    public var shortLabel: String {
        switch self {
        case .available: "Checking strokes"
        case .wrongWrist: "Pacing only"
        case .unknown: "Set up sensing"
        }
    }
}

/// Resolves the Watch's own wrist reading against the hand the user says holds
/// the brush. The Watch already knows its wrist
/// (`WKInterfaceDevice.current().wristLocation`), so onboarding only ever has to
/// ask one question.
public struct HandednessProfile: Codable, Hashable, Sendable {
    public var watchWrist: WatchWrist?
    public var brushingHand: BrushingHand?

    public init(watchWrist: WatchWrist? = nil, brushingHand: BrushingHand? = nil) {
        self.watchWrist = watchWrist
        self.brushingHand = brushingHand
    }

    public var capability: SensingCapability {
        guard let watchWrist, let brushingHand else { return .unknown }
        return watchWrist.matchingHand == brushingHand
            ? .available
            : .wrongWrist(watchWrist: watchWrist, brushingHand: brushingHand)
    }

    /// Whether the user could gain analysis simply by moving the Watch across.
    /// Worth offering; never worth forcing.
    public var couldEnableBySwitchingWrist: Bool {
        if case .wrongWrist = capability { return true }
        return false
    }
}
