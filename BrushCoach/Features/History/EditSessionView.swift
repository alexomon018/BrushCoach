import BrushKit
import SwiftUI

struct EditSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: BrushSession
    @State private var saveFeedback = 0
    @State private var deleteFeedback = 0
    private let isNew: Bool
    let onSave: (BrushSession) -> Void
    let onDelete: () -> Void

    init(
        session: BrushSession,
        isNew: Bool = false,
        onSave: @escaping (BrushSession) -> Void,
        onDelete: @escaping () -> Void
    ) {
        _draft = State(initialValue: session)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    /// A brush the user is logging by hand, defaulted to a full routine just now.
    /// Manual credit has to be as good as tracked credit, or a flat battery costs
    /// someone their streak.
    static func manualDraft(at date: Date = .now) -> BrushSession {
        BrushSession(
            startedAt: date,
            endedAt: date.addingTimeInterval(120),
            duration: 120,
            zonesCompleted: 6,
            source: .manual
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CompanionMetrics.sectionSpacing) {
                    detailsCard
                        .staggeredReveal(index: 0)

                    CompanionSection(title: "AFTER BRUSHING", detail: "Keep the session record accurate.") {
                        promptsCard
                    }
                        .staggeredReveal(index: 1)

                    if !isNew {
                        deleteButton
                            .staggeredReveal(index: 2)
                    }
                }
                .companionPageFrame()
                .revealGroup()
            }
            .background(Color.enamelWash.ignoresSafeArea())
            .navigationTitle(isNew ? "Add brush" : "Edit brush")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save", action: save).fontWeight(.semibold)
                }
            }
        }
        .sensoryFeedback(.success, trigger: saveFeedback)
        .sensoryFeedback(.warning, trigger: deleteFeedback)
    }

    private var detailsCard: some View {
        VStack(spacing: 16) {
            DatePicker("Started", selection: $draft.startedAt)
                .font(.subheadline.weight(.semibold))
            Divider()
            Stepper(value: $draft.duration, in: 5...300, step: 5) {
                editorMetric(
                    title: "Duration",
                    value: Duration.seconds(draft.duration).formatted(.time(pattern: .minuteSecond)),
                    systemImage: "timer"
                )
            }
            Divider()
            Stepper(value: $draft.zonesCompleted, in: 0...6) {
                editorMetric(
                    title: "Zones",
                    value: "\(draft.zonesCompleted) of 6",
                    systemImage: "circle.hexagongrid.fill"
                )
            }
        }
        .companionCard()
    }

    private var promptsCard: some View {
        VStack(spacing: 0) {
            PromptToggleRow(
                title: "Flossed",
                detail: "Included in this routine",
                systemImage: "scribble.variable",
                tint: .sketchLavender,
                isOn: $draft.flossed
            )
            Divider().padding(.leading, 58)
            PromptToggleRow(
                title: "Cleaned tongue",
                detail: "Included in this routine",
                systemImage: "sparkles",
                tint: .achievementGold,
                isOn: $draft.tongueCleaned
            )
        }
        .companionCard()
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            deleteFeedback += 1
            onDelete()
        } label: {
            Label("Delete session", systemImage: "trash")
                .font(.headline)
                .foregroundStyle(Color.coachCoral)
                .frame(maxWidth: .infinity)
                .frame(height: CompanionMetrics.controlHeight)
                .background(Color.coachCoral.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(TactileCardButtonStyle())
    }

    private func save() {
        saveFeedback += 1
        draft.endedAt = draft.startedAt.addingTimeInterval(draft.duration)
        onSave(draft)
    }

    private func editorMetric(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: CompanionMetrics.rowSpacing) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.rinseBlue)
                .frame(width: CompanionMetrics.rowIconSize, height: CompanionMetrics.rowIconSize)
                .background(Color.rinseBlue.opacity(0.1), in: Circle())
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .bold).monospacedDigit())
                .contentTransition(.numericText())
        }
    }
}
