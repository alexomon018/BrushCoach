import SwiftUI

@main
struct BrushCoachApp: App {
    private let environment = AppEnvironment.shared

    init() {
        environment.activate()
    }

    var body: some Scene {
        WindowGroup {
            ConsumerRootView(
                sessions: environment.sessions,
                settings: environment.settings
            )
        }
    }
}
