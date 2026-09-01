import SwiftUI

struct ConsumerRootView: View {
    enum AppTab: Hashable { case today, history, routine, more }

    @AppStorage("hasSeenConsumerOnboarding") private var hasSeenOnboarding = false
    @State private var sessions: SessionStore
    @State private var routine: RoutineSettings
    @State private var selectedTab = AppTab.today

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
            // `isVisible` stops the mascot's looping animations while another tab
            // is showing. A TabView keeps every tab's views alive, so without this
            // the mascot holds the render loop open and every other screen scrolls
            // against a frame budget it has already spent.
            TodayView(store: sessions, isVisible: selectedTab == .today)
                .tabItem { Label("Today", systemImage: selectedTab == .today ? "sun.max.fill" : "sun.max") }
                .tag(AppTab.today)
            HistoryView(store: sessions)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(AppTab.history)
            RoutineView(store: sessions, settings: routine)
                .tabItem { Label("Routine", systemImage: selectedTab == .routine ? "bell.badge.fill" : "bell.badge") }
                .tag(AppTab.routine)
            MoreView()
                .tabItem { Label("More", systemImage: selectedTab == .more ? "ellipsis.circle.fill" : "ellipsis.circle") }
                .tag(AppTab.more)
        }
        .tint(Color.rinseBlue)
        .sensoryFeedback(.selection, trigger: selectedTab)
        .task { await routine.apply() }
    }
}
