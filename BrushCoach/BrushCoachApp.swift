import SwiftUI

@main
struct BrushCoachApp: App {
    init() {
        PhoneTraceReceiver.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ConsumerRootView()
        }
    }
}
