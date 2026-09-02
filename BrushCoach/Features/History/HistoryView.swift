import BrushKit
import SwiftUI

struct HistoryView: View {
    @Bindable var store: SessionStore
    @State private var editing: BrushSession?
    @State private var deleteFeedback = 0
    @State private var pendingDelete: BrushSession?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: CompanionMetrics.componentSpacing) {
                    if let message = store.lastError {
                        StorageNotice(
                            message: message,
                            isDegradedRatherThanFailed: store.isUsingFallbackStorage
                        )
                    }

                    if store.sessions.isEmpty {
                        EmptyHistoryCard()
                    } else {
                        sessionListHeader
                        ForEach(store.sessions) { session in
                            HistorySessionCard(
                                session: session,
                                routineDay: store.routineDay,
                                edit: { editing = session },
                                delete: { pendingDelete = session }
                            )
                        }
                    }
                }
                .companionPageFrame()
            }
            .background(Color.enamelWash.ignoresSafeArea())
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
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
        .sensoryFeedback(.warning, trigger: deleteFeedback)
    }

    private var sessionListHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SAVED BRUSHES")
                .font(.companionEyebrow)
                .tracking(1.35)
                .foregroundStyle(Color.rinseBlue)
            Text("Every result stays available for future trends.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EmptyHistoryCard: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(Color.rinseBlue)
            Text("No saved brushes yet")
                .font(.companionFeatureTitle)
                .foregroundStyle(Color.deepInk)
            Text("Your Watch sessions and mouth maps will stay here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .companionCard(.feature)
    }
}

private struct HistorySessionCard: View {
    let session: BrushSession
    let routineDay: RoutineDay
    let edit: () -> Void
    let delete: () -> Void

    private var period: RoutinePeriod { session.period(in: routineDay) }
    private var dangerCount: Int? {
        guard let analysis = session.analysis,
              analysis.hasUsableZoneCoverage(forSessionLasting: session.duration)
        else { return nil }
        return analysis.underBrushedZones.count
    }

    var body: some View {
        HStack(spacing: 10) {
            NavigationLink {
                SessionResultDetailView(session: session)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: period == .morning ? "sun.max.fill" : "moon.stars.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(period == .morning ? Color.rinseBlue : Color.sketchLavender)
                        .frame(width: CompanionMetrics.rowIconSize, height: CompanionMetrics.rowIconSize)
                        .background(iconBackground, in: Circle())

                    // The coverage badge sits under the date rather than beside
                    // the duration, so it never has to wrap in a narrow row.
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(period.displayName)
                                .font(.headline)
                                .foregroundStyle(Color.deepInk)
                            Spacer(minLength: 0)
                            Text(Duration.seconds(session.duration), format: .time(pattern: .minuteSecond))
                                .font(.companionMetric.monospacedDigit())
                                .foregroundStyle(Color.deepInk)
                        }
                        Text(session.startedAt, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        coverageBadge
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, 2)
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
                    .frame(width: 30, height: 44)
            }
        }
        .companionCard(.compact)
    }

    private var coverageBadge: some View {
        let style = coverage
        return Label(style.text, systemImage: style.icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(style.tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(style.tint.opacity(0.12), in: Capsule())
    }

    private var coverage: (text: String, icon: String, tint: Color) {
        guard let dangerCount else { return ("No mouth map", "map", Color.rinseBlue) }
        if dangerCount == 0 { return ("Balanced coverage", "checkmark.circle.fill", Color.mintDeep) }
        return (dangerCount == 1 ? "1 area to revisit" : "\(dangerCount) areas to revisit", "scope", Color.coachCoral)
    }

    private var iconBackground: Color {
        period == .morning ? Color.rinseBlue.opacity(0.12) : Color.sketchLavender.opacity(0.12)
    }
}
