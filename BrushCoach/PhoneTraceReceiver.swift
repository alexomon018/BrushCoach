@preconcurrency import WatchConnectivity
import BrushKit
import Foundation

final class PhoneTraceReceiver: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = PhoneTraceReceiver()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            self.send(preferences: RoutineSettings.shared.preferences)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // WatchConnectivity deletes its temporary file after this callback, so import synchronously.
        guard (try? PhoneTraceStore.importReceivedFile(file.fileURL)) != nil else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .brushCoachTraceInboxChanged, object: nil)
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        switch userInfo["kind"] as? String {
        case "completed-session":
            guard let data = userInfo["session"] as? Data,
                  let brushSession = try? JSONDecoder().decode(BrushSession.self, from: data)
            else { return }
            Task { @MainActor in
                SessionStore.shared.importFromWatch(brushSession)
            }
        case "watch-wrist":
            guard let raw = userInfo["wrist"] as? String, let wrist = WatchWrist(rawValue: raw) else { return }
            Task { @MainActor in
                RoutineSettings.shared.watchWrist = wrist
            }
        default:
            return
        }
    }

    @MainActor
    func send(preferences: RoutinePreferences) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              let data = try? JSONEncoder().encode(preferences)
        else { return }
        try? WCSession.default.updateApplicationContext([
            "kind": "routine-preferences",
            "preferences": data
        ])
    }

    func startSessionOnWatch() -> Bool {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isReachable
        else { return false }
        WCSession.default.sendMessage(["command": "start-session"], replyHandler: nil)
        return true
    }
}
