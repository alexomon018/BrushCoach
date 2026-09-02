import SwiftUI

struct ConsumerRootView: View {
    enum AppTab: Hashable { case brush, history, settings }

    @AppStorage("hasSeenConsumerOnboarding") private var hasSeenOnboarding = false
    @State private var sessions: SessionStore
    @State private var routine: RoutineSettings
    @State private var selectedTab = AppTab.brush

    init(sessions: SessionStore, settings: RoutineSettings) {
        _sessions = State(initialValue: sessions)
        _routine = State(initialValue: settings)
    }

    var body: some View {
        Group {
            if hasSeenOnboarding {
                tabs
            } else {
                OnboardingView(settings: routine) { hasSeenOnboarding = true }
            }
        }
        .preferredColorScheme(hasSeenOnboarding ? .light : .dark)
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            TodayView(store: sessions, isVisible: selectedTab == .brush)
                .tabItem { Label("Brush", systemImage: selectedTab == .brush ? "mouth.fill" : "mouth") }
                .tag(AppTab.brush)
            HistoryView(store: sessions)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(AppTab.history)
            RoutineView(store: sessions, settings: routine)
                .tabItem { Label("Settings", systemImage: selectedTab == .settings ? "gearshape.fill" : "gearshape") }
                .tag(AppTab.settings)
        }
        .tint(Color.rinseBlue)
        .sensoryFeedback(.selection, trigger: selectedTab)
        .task { await routine.apply() }
    }
}
