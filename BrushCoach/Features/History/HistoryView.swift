import BrushKit
import SwiftUI

struct HistoryView: View {
    @Bindable var store: SessionStore
    @State private var editing: BrushSession?
    @State private var adding: BrushSession?
    @State private var editFeedback = 0
    @State private var deleteFeedback = 0
    @State private var pendingDelete: BrushSession?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: CompanionMetrics.componentSpacing) {
                    // History is the screen where a save failure actually costs
                    // the user something, so it is stated here too.
                    if let message = store.lastError {
                        StorageNotice(
                            message: message,
                            isDegradedRatherThanFailed: store.isUsingFallbackStorage
                        )
                    }

                    WeekRhythmCard(statuses: weekStatuses, streak: store.streak)
                        .staggeredReveal(index: 0)

                    if store.sessions.isEmpty {
                        EmptyHistoryCard()
                            .staggeredReveal(index: 1)
                    } else {
                        sessionListHeader
                            .staggeredReveal(index: 1)
                        sessionList
                    }
                }
                .companionPageFrame()
                .revealGroup()
            }
            .background(Color.enamelWash.ignoresSafeArea())
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add brush", systemImage: "plus") {
                        adding = EditSessionView.manualDraft()
                    }
                }
            }
            .sheet(item: $adding) { draft in
                EditSessionView(session: draft, isNew: true) { session in
                    store.upsert(session)
                    adding = nil
                } onDelete: {
                    adding = nil
                }
            }
            .confirmationDialog(
                "Delete this brush?",
                isPresented: .init(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                presenting: pendingDelete
            ) { session in
                Button("Delete", role: .destructive) {
                    deleteFeedback += 1
                    withAnimation(.snappy) { store.delete(session) }
                    pendingDelete = nil
                }
            }
            .sheet(item: $editing) { session in
                EditSessionView(session: session) { updated in
                    store.upsert(updated)
                    editing = nil
                } onDelete: {
                    deleteFeedback += 1
                    store.delete(session)
                    editing = nil
                }
            }
        }
        .sensoryFeedback(.selection, trigger: editFeedback)
        .sensoryFeedback(.warning, trigger: deleteFeedback)
    }

    private var sessionListHeader: some View {
        HStack {
            Text("RECENT BRUSHES")
                .font(.caption2.weight(.bold))
                .tracking(1.35)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(store.sessions.count) total")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.rinseBlue)
        }
    }

    private var sessionList: some View {
        ForEach(Array(store.sessions.enumerated()), id: \.element.id) { index, session in
            HistorySessionCard(
                session: session,
                routineDay: store.routineDay,
                edit: {
                    editFeedback += 1
                    editing = session
                },
                delete: { pendingDelete = session }
            )
            .staggeredReveal(index: min(index + 2, 8))
            .transition(.opacity)
        }
    }

    private var weekStatuses: [RoutineDayStatus] {
        let calendar = Calendar.current
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: .now) else { return nil }
            return store.status(on: date)
        }
    }
}

private struct WeekRhythmCard: View {
    let statuses: [RoutineDayStatus]
    let streak: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("YOUR RHYTHM")
                        .font(.caption2.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(Color.rinseBlue)
                    Text(weekTitle)
                        .font(.companionFeatureTitle)
                        .foregroundStyle(Color.deepInk)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(streak.formatted())
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("DAY STREAK")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 9) {
                ForEach(statuses, id: \.date) { status in
                    dayColumn(status)
                }
            }
        }
        .companionCard(.feature)
    }

    private func dayColumn(_ status: RoutineDayStatus) -> some View {
        let isToday = Calendar.current.isDateInToday(status.date)
        return VStack(spacing: 8) {
            VStack(spacing: 4) {
                rhythmMark(completed: status.morning != nil)
                rhythmMark(completed: status.evening != nil)
            }
            Text(status.date, format: .dateTime.weekday(.narrow))
                .font(.caption2.weight(isToday ? .bold : .medium))
                .foregroundStyle(isToday ? Color.deepInk : Color.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var weekTitle: String {
        let completed = statuses.reduce(0) { $0 + $1.completedCount }
        return switch completed {
        case 0: "Begin with one brush"
        case 1..<7: "A routine is forming"
        case 7..<14: "Consistency looks good"
        default: "A complete clean week"
        }
    }

    private func rhythmMark(completed: Bool) -> some View {
        Capsule()
            .fill(completed ? Color.mintDeep : Color.rinseBlue.opacity(0.1))
            .frame(height: 8)
            .overlay {
                if completed { Capsule().strokeBorder(.white.opacity(0.72), lineWidth: 1) }
            }
    }
}

private struct EmptyHistoryCard: View {
    var body: some View {
        VStack(spacing: 18) {
            DentalArchView(completedZones: 0)
                .frame(height: 82)
            VStack(spacing: 6) {
                Text("Your rhythm starts here")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(Color.deepInk)
                Text("Finish a guided Watch session and its details will appear here automatically.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .companionCard(.feature)
    }
}

private struct HistorySessionCard: View {
    let session: BrushSession
    let routineDay: RoutineDay
    let edit: () -> Void
    let delete: () -> Void

    private var period: RoutinePeriod { session.period(in: routineDay) }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: edit) {
                HStack(spacing: 14) {
                    Image(systemName: period == .morning ? "sun.max.fill" : "moon.stars.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(period == .morning ? Color.rinseBlue : Color.sketchLavender)
                        .frame(width: CompanionMetrics.rowIconSize, height: CompanionMetrics.rowIconSize)
                        .background(iconBackground, in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(period.displayName)
                            .font(.headline)
                            .foregroundStyle(Color.deepInk)
                        HStack(spacing: 5) {
                            Text(session.startedAt, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                            if session.source == .manual {
                                Text("· Added by hand")
                                    .foregroundStyle(Color.rinseBlue)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(Duration.seconds(session.duration), format: .time(pattern: .minuteSecond))
                            .font(.companionMetric.monospacedDigit())
                            .foregroundStyle(Color.deepInk)
                        Label(
                            "\(session.zonesCompleted)/\(session.plannedZones)",
                            systemImage: "circle.hexagongrid.fill"
                        )
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(session.completedRoutine ? Color.mintDeep : .secondary)
                    }
                }
            }
            .buttonStyle(TactileCardButtonStyle())

            Menu {
                Button("Edit", systemImage: "pencil", action: edit)
                Button("Delete", systemImage: "trash", role: .destructive, action: delete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 44)
            }
        }
        .companionCard(.compact)
    }

    private var iconBackground: Color {
        period == .morning ? Color.rinseBlue.opacity(0.12) : Color.sketchLavender.opacity(0.12)
    }
}
