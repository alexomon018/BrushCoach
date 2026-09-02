import BrushKit
import SwiftUI

struct TodayView: View {
    @Bindable var store: SessionStore
    /// Kept in the root contract so older tab-state restoration remains stable.
    let isVisible: Bool

    @State private var launchState = WatchLaunchState.idle

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CompanionMetrics.componentSpacing) {
                    pageHeader

                    if let message = store.lastError {
                        StorageNotice(
                            message: message,
                            isDegradedRatherThanFailed: store.isUsingFallbackStorage
                        )
                    }

                    if let latestSession {
                        NavigationLink {
                            SessionResultDetailView(session: latestSession)
                        } label: {
                            SessionResultCard(session: latestSession, presentation: .summary)
                        }
                        .buttonStyle(TactileCardButtonStyle())
                        .accessibilityHint("Shows the full coverage breakdown.")
                    } else {
                        EmptyResultCard()
                    }

                    WatchLaunchButton(state: launchState, action: beginWatchHandoff)

                    CompanionSectionHeader(
                        title: "TODAY",
                        detail: "Two brushes complete your daily routine."
                    )
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
                .companionPageFrame()
            }
            .background(Color.enamelWash.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var latestSession: BrushSession? { store.sessions.first }

    private var pageHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Your latest brush")
                .font(.companionHero)
                .foregroundStyle(Color.deepInk)
            Spacer(minLength: 0)
            StreakPill(days: store.streak)
        }
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

/// The streak as one glanceable object rather than a number stacked on a caption.
/// Zero still shows, muted: the moment the mechanic most needs starting is the
/// wrong moment for it to disappear.
private struct StreakPill: View {
    let days: Int

    private var isActive: Bool { days > 0 }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isActive ? Color.coachCoral : Color.deepInk.opacity(0.42))
            Text(days.formatted())
                .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(isActive ? Color.deepInk : Color.deepInk.opacity(0.45))
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(
            isActive ? Color.achievementGold.opacity(0.18) : Color.deepInk.opacity(0.05),
            in: Capsule()
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(days == 1 ? "1 day streak" : "\(days) day streak")
    }
}

private struct EmptyResultCard: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "mouth.fill")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(Color.rinseBlue)
                .frame(width: 82, height: 82)
                .background(Color.rinseBlue.opacity(0.1), in: Circle())
            VStack(spacing: 5) {
                Text("Your mouth map starts here")
                    .font(.companionFeatureTitle)
                    .foregroundStyle(Color.deepInk)
                    .multilineTextAlignment(.center)
                Text("Finish a two-minute Watch session to see which areas got enough attention.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .companionCard(.feature)
    }
}

enum WatchLaunchState: Equatable {
    case idle, connecting, sent, unavailable
}

private struct WatchLaunchButton: View {
    let state: WatchLaunchState
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
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

            if state == .unavailable {
                Label("Open BrushCoach on your Watch, or use its complication.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.move(edge: .top).combined(with: .opacity))
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
        HStack(spacing: 12) {
            Image(systemName: period == .morning ? "sun.max.fill" : "moon.stars.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(period == .morning ? Color.rinseBlue : Color.sketchLavender)
                .frame(width: 38, height: 38)
                .background(
                    (period == .morning ? Color.rinseBlue : Color.sketchLavender).opacity(0.1),
                    in: Circle()
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(period.displayName).font(.headline)
                Text(session.map { Duration.seconds($0.duration).formatted(.time(pattern: .minuteSecond)) } ?? "Not yet")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: session == nil ? "circle" : "checkmark.circle.fill")
                .foregroundStyle(session == nil ? Color.secondary : Color.mintDeep)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .companionCard(.compact)
    }
}
