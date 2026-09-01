import BrushKit
import SwiftUI

struct TodayView: View {
    @Bindable var store: SessionStore
    /// False while another tab is showing, so the mascot's looping animations stop.
    let isVisible: Bool

    @State private var launchState = WatchLaunchState.idle

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CompanionMetrics.componentSpacing) {
                    hero
                    routineCard
                    techniqueCard
                }
                .companionPageFrame()
            }
            .background(Color.enamelWash.ignoresSafeArea())
            // The hero card already carries the date, the greeting and the
            // brand. A bar repeating the app name above it is chrome that only
            // costs vertical room and draws a hairline across the card.
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(today, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.rinseBlue)
                        .textCase(.uppercase)
                    Text(greeting)
                        .font(.companionHero)
                        .foregroundStyle(Color.deepInk)
                    Text(dayStatus)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                VStack(spacing: 5) {
                    ToothMascotView(mood: mascotMood, action: mascotAction, isOnScreen: isVisible)
                        .frame(width: 76, height: 78)
                    Text("\(store.streak) DAY STREAK")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.65)
                        .foregroundStyle(Color.deepInk.opacity(0.7))
                }
            }

            DentalArchView(completedZones: store.today.completedCount * 3)
                .frame(height: 100)

            WatchLaunchButton(state: launchState, action: beginWatchHandoff)

            if launchState == .unavailable {
                Label("Open BrushCoach on your Watch, or use its complication.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .companionCard(.feature)
    }

    private var routineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CompanionSectionHeader(title: "TODAY'S ROUTINE", detail: "Two brushes complete your daily rhythm.")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: CompanionMetrics.componentSpacing) {
                    PeriodStatusCard(period: .morning, session: store.today.morning)
                    PeriodStatusCard(period: .evening, session: store.today.evening)
                }
                VStack(spacing: CompanionMetrics.componentSpacing) {
                    PeriodStatusCard(period: .morning, session: store.today.morning)
                    PeriodStatusCard(period: .evening, session: store.today.evening)
                }
            }
        }
    }

    private var techniqueCard: some View {
        HStack(spacing: CompanionMetrics.rowSpacing) {
            Image(systemName: "angle")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.deepInk)
                .frame(width: CompanionMetrics.rowIconSize, height: CompanionMetrics.rowIconSize)
                .background(Color.mintFresh.opacity(0.65), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("Aim for the gumline")
                    .font(.headline)
                Text("Hold a soft-bristled brush around 45° and use gentle, short strokes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .companionCard()
    }

    /// Read once per body evaluation so the greeting, date and mascot mood all
    /// agree, and so `body` stays a pure function of its inputs.
    private var today: Date { store.today.date }

    private var hour: Int { Calendar.current.component(.hour, from: .now) }

    private var greeting: String {
        switch hour {
        case 0..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    private var dayStatus: String {
        switch store.today.completedCount {
        case 0: "Two small minutes to start fresh."
        case 1: "One brush tucked away. One to go."
        default: "Both brushes done. Nicely played."
        }
    }

    private var mascotMood: ToothMood {
        switch store.today.completedCount {
        case 0: .ready
        case 1: .cheery
        default: .proud
        }
    }

    private var mascotAction: ToothAction {
        if store.today.completedCount == 2 { return .success }
        if hour >= 18 { return .bedtime }
        return .idle
    }

    private func beginWatchHandoff() {
        guard launchState == .idle else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
            launchState = .connecting
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(520))
            let sent = PhoneTraceReceiver.shared.startSessionOnWatch()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
                launchState = sent ? .sent : .unavailable
            }
            try? await Task.sleep(for: .seconds(sent ? 1.3 : 2.6))
            withAnimation(.easeInOut(duration: 0.25)) { launchState = .idle }
        }
    }
}

enum WatchLaunchState: Equatable {
    case idle, connecting, sent, unavailable
}

private struct WatchLaunchButton: View {
    let state: WatchLaunchState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .contentTransition(.interpolate)
                Spacer()
                trailing
            }
            .font(.headline)
            .padding(.horizontal, 18)
            .frame(height: CompanionMetrics.controlHeight)
            .foregroundStyle(.white)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(state != .idle)
        .sensoryFeedback(trigger: state) { _, newValue in
            switch newValue {
            case .connecting: .impact(weight: .medium)
            case .sent: .success
            case .unavailable: .error
            case .idle: nil
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if state == .connecting {
            ProgressView().tint(.white)
        } else {
            Image(systemName: state == .idle ? "arrow.up.right" : state == .unavailable ? "exclamationmark" : "checkmark")
                .contentTransition(.symbolEffect(.replace))
        }
    }

    private var icon: String {
        switch state {
        case .idle: "applewatch.side.right"
        case .connecting: "wave.3.right"
        case .sent: "applewatch.radiowaves.left.and.right"
        case .unavailable: "applewatch.slash"
        }
    }

    private var title: String {
        switch state {
        case .idle: "Start two-minute brush"
        case .connecting: "Calling your Watch…"
        case .sent: "Ready on your wrist"
        case .unavailable: "Watch not reachable"
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .idle: .deepInk
        case .connecting: .rinseBlue
        case .sent: .mintDeep
        case .unavailable: .coachCoral
        }
    }
}

private struct PeriodStatusCard: View {
    let period: RoutinePeriod
    let session: BrushSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: period == .morning ? "sun.max.fill" : "moon.stars.fill")
                Spacer()
                Image(systemName: session == nil ? "circle" : "checkmark.circle.fill")
                    .foregroundStyle(session == nil ? Color.secondary : Color.mintDeep)
            }
            .foregroundStyle(Color.deepInk)
            Text(period.displayName)
                .font(.headline)
            Text(session.map { Duration.seconds($0.duration).formatted(.time(pattern: .minuteSecond)) } ?? "Not yet")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .companionCard(.compact)
    }
}
