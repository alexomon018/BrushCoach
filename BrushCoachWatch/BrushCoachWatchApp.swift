import SwiftUI

@main
struct BrushCoachWatchApp: App {
    @State private var model = CoachViewModel()
    @State private var handledLaunchArguments = false

    init() {
        WatchTraceTransfer.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                CoachView(model: model)
            }
            .onOpenURL { model.handle(url: $0) }
            .task {
                guard !handledLaunchArguments else { return }
                handledLaunchArguments = true
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-startSession") {
                    model.startSession()
                }
                #endif
            }
        }
    }
}
