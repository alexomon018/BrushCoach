@preconcurrency import WatchConnectivity
import BrushKit
import Foundation

final class WatchTraceTransfer: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchTraceTransfer()

    private let lock = NSLock()
    private var pending: [URL] = []

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func enqueue(_ url: URL) {
        guard WCSession.isSupported() else { return }
        lock.lock()
        pending.append(url)
        lock.unlock()
        flushIfReady()
    }

    func enqueue(_ session: BrushSession) {
        guard WCSession.isSupported(), let data = try? JSONEncoder().encode(session) else { return }
        WCSession.default.transferUserInfo(["kind": "completed-session", "session": data])
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        flushIfReady()
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard applicationContext["kind"] as? String == "routine-preferences",
              let data = applicationContext["preferences"] as? Data,
              let preferences = try? JSONDecoder().decode(RoutinePreferences.self, from: data)
        else { return }
        WatchRoutinePreferences.current = preferences
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard message["command"] as? String == "start-session" else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .brushCoachStartSessionRequested, object: nil)
        }
    }

    private func flushIfReady() {
        let session = WCSession.default
        guard session.activationState == .activated else {
            activate()
            return
        }
        lock.lock()
        let files = pending
        pending.removeAll()
        lock.unlock()
        for file in files {
            session.transferFile(file, metadata: ["kind": "labelled-motion-trace"])
        }
    }
}
