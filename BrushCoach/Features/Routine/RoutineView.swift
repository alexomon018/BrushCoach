import BrushKit
import SwiftUI

struct RoutineView: View {
    @Bindable var store: SessionStore
    @Bindable var settings: RoutineSettings
    @State private var notificationStatus = ""
    @State private var healthStatus = ""
    @State private var successFeedback = 0
    @State private var errorFeedback = 0

    private static let notificationsReady = "Notifications are ready."
    private static let healthConnected = "Apple Health is connected."

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CompanionMetrics.sectionSpacing) {
                    RoutineRailCard(preferences: settings.preferences, today: store.today)
                        .staggeredReveal(index: 0)

                    CompanionSection(title: "TWICE DAILY", detail: "A reminder pauses after that brush is complete.") {
                        VStack(spacing: CompanionMetrics.componentSpacing) {
                            PeriodScheduleCard(
                                period: .morning,
                                enabled: $settings.preferences.morningEnabled,
                                time: morningTime,
                                completed: store.today.morning != nil
                            )

                            PeriodScheduleCard(
                                period: .evening,
                                enabled: $settings.preferences.eveningEnabled,
                                time: eveningTime,
                                completed: store.today.evening != nil
                            )
                        }
                    }
                    .staggeredReveal(index: 1)

                    CompanionSection(title: "FINISH THE ROUTINE", detail: "Choose the prompts that help without adding noise.") {
                        promptsCard
                    }
                    .staggeredReveal(index: 2)

                    CompanionSection(title: "WHEN THE DAY ENDS", detail: "A late-night brush closes the day it finished.") {
                        dayEndCard
                    }
                    .staggeredReveal(index: 3)

                    CompanionSection(title: "STROKE CHECKING", detail: "Available only when the Watch is on your brushing hand.") {
                        strokeCheckingCard
                    }
                    .staggeredReveal(index: 4)

                    CompanionSection(title: "CONNECTIONS", detail: "Optional services that support your routine.") {
                        connectionsCard
                    }
                    .staggeredReveal(index: 5)
                }
                .companionPageFrame()
                .revealGroup()
            }
            .background(Color.enamelWash.ignoresSafeArea())
            .navigationTitle("Routine")
            .navigationBarTitleDisplayMode(.large)
        }
        .sensoryFeedback(.success, trigger: successFeedback)
        .sensoryFeedback(.error, trigger: errorFeedback)
    }

    /// States the capability plainly, including when it is absent. Telling
    /// someone their strokes cannot be read is far better than reporting that
    /// they did not brush.
    private var strokeCheckingCard: some View {
        let handedness = HandednessProfile(
            watchWrist: settings.watchWrist,
            brushingHand: settings.preferences.brushingHand
        )
        let capability = handedness.capability
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: capability.canSenseMotion ? "checkmark.seal.fill" : "info.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(capability.canSenseMotion ? Color.mintDeep : Color.rinseBlue)
                    .frame(width: CompanionMetrics.rowIconSize, height: CompanionMetrics.rowIconSize)
                    .background(
                        (capability.canSenseMotion ? Color.mintDeep : Color.rinseBlue).opacity(0.12),
                        in: Circle()
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(capability.shortLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.deepInk)
                    Text(capability.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 9) {
                Text("BRUSHING HAND")
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
                Picker("Brushing hand", selection: brushingHand) {
                    Text("Not set").tag(BrushingHand?.none)
                    ForEach(BrushingHand.allCases, id: \.self) { hand in
                        Text(hand.displayName).tag(BrushingHand?.some(hand))
                    }
                }
                .pickerStyle(.segmented)

                if let wrist = settings.watchWrist {
                    Text("Your Watch reports it is on your \(wrist == .left ? "left" : "right") wrist.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    // Offered, never forced. Some people will happily switch
                    // wrists to get stroke checking; most will not, and the app
                    // works either way.
                    if handedness.couldEnableBySwitchingWrist {
                        Label(
                            "Wear your Watch on your other wrist while brushing to turn stroke checking on.",
                            systemImage: "arrow.left.arrow.right"
                        )
                        .font(.caption2)
                        .foregroundStyle(Color.rinseBlue)
                    }
                } else {
                    Text("Open BrushCoach on your Watch once so it can report which wrist it is on.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .companionCard()
    }

    private var brushingHand: Binding<BrushingHand?> {
        Binding(
            get: { settings.preferences.brushingHand },
            set: { settings.preferences.brushingHand = $0 }
        )
    }

    private var promptsCard: some View {
        VStack(spacing: 0) {
            PromptToggleRow(
                title: "Floss",
                detail: "A quick prompt after brushing",
                systemImage: "scribble.variable",
                tint: .sketchLavender,
                isOn: $settings.preferences.flossPromptEnabled
            )
            Divider().padding(.leading, 58)
            PromptToggleRow(
                title: "Clean your tongue",
                detail: "Keep the final step visible",
                systemImage: "sparkles",
                tint: .achievementGold,
                isOn: $settings.preferences.tonguePromptEnabled
            )
        }
        .companionCard()
    }

    private var dayEndCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: CompanionMetrics.rowSpacing) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.sketchLavender)
                    .frame(width: CompanionMetrics.rowIconSize, height: CompanionMetrics.rowIconSize)
                    .background(Color.sketchLavender.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Day rolls over at")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.deepInk)
                    Text("Brushing before this counts toward the night before.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Day rolls over at", selection: $settings.preferences.dayEndsAtHour) {
                    ForEach(0..<12, id: \.self) { hour in
                        Text(hourLabel(hour)).tag(hour)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Color.rinseBlue)
            }
        }
        .companionCard()
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(from: DateComponents(hour: hour)) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    private var connectionsCard: some View {
        VStack(spacing: CompanionMetrics.componentSpacing) {
            ConnectionActionCard(
                title: "Notifications",
                detail: notificationStatus.isEmpty ? "Timely reminders for unfinished brushes" : notificationStatus,
                systemImage: notificationStatus == Self.notificationsReady ? "checkmark.circle.fill" : "bell.badge.fill",
                tint: notificationStatus == Self.notificationsReady ? .mintDeep : .rinseBlue,
                action: requestNotifications
            )

            ConnectionActionCard(
                title: "Apple Health",
                detail: healthStatus.isEmpty ? "Save completed brushing sessions" : healthStatus,
                systemImage: healthStatus == Self.healthConnected ? "checkmark.circle.fill" : "heart.fill",
                tint: healthStatus == Self.healthConnected ? .mintDeep : .coachCoral,
                action: requestHealthAccess
            )
        }
    }

    private func requestNotifications() {
        Task {
            let allowed = await ReminderScheduler.shared.requestAuthorization()
            withAnimation(.snappy) {
                notificationStatus = allowed ? Self.notificationsReady : "Enable notifications in Settings."
            }
            if allowed { successFeedback += 1 } else { errorFeedback += 1 }
            await settings.apply()
        }
    }

    private func requestHealthAccess() {
        Task {
            let allowed = await store.requestHealthAccess()
            withAnimation(.snappy) {
                healthStatus = allowed ? Self.healthConnected : "Health access was not granted."
            }
            if allowed { successFeedback += 1 } else { errorFeedback += 1 }
        }
    }

    private var morningTime: Binding<Date> {
        timeBinding(hour: settings.preferences.morningHour, minute: settings.preferences.morningMinute) { hour, minute in
            settings.preferences.morningHour = hour
            settings.preferences.morningMinute = minute
        }
    }

    private var eveningTime: Binding<Date> {
        timeBinding(hour: settings.preferences.eveningHour, minute: settings.preferences.eveningMinute) { hour, minute in
            settings.preferences.eveningHour = hour
            settings.preferences.eveningMinute = minute
        }
    }

    private func timeBinding(hour: Int, minute: Int, update: @escaping (Int, Int) -> Void) -> Binding<Date> {
        Binding {
            Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: hour, minute: minute)) ?? .now
        } set: { value in
            update(Calendar.current.component(.hour, from: value), Calendar.current.component(.minute, from: value))
        }
    }
}

private struct RoutineRailCard: View {
    let preferences: RoutinePreferences
    let today: RoutineDayStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("YOUR DAILY ARC")
                    .font(.caption2.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(Color.rinseBlue)
                Text(routineTitle)
                    .font(.companionFeatureTitle)
                    .foregroundStyle(Color.deepInk)
            }

            HStack(spacing: 10) {
                railNode(
                    period: .morning,
                    time: formattedTime(hour: preferences.morningHour, minute: preferences.morningMinute),
                    enabled: preferences.morningEnabled,
                    completed: today.morning != nil
                )
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.rinseBlue.opacity(0.22), Color.sketchLavender.opacity(0.28)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 5)
                railNode(
                    period: .evening,
                    time: formattedTime(hour: preferences.eveningHour, minute: preferences.eveningMinute),
                    enabled: preferences.eveningEnabled,
                    completed: today.evening != nil
                )
            }
        }
        .companionCard(.feature)
    }

    private var routineTitle: String {
        switch today.completedCount {
        case 0: "Two moments, one routine"
        case 1: "Halfway through today"
        default: "Today's arc is complete"
        }
    }

    private func railNode(period: RoutinePeriod, time: String, enabled: Bool, completed: Bool) -> some View {
        VStack(spacing: 7) {
            Image(systemName: completed ? "checkmark" : period == .morning ? "sun.max.fill" : "moon.stars.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(completed ? Color.deepInk : enabled ? nodeTint(period) : Color.secondary)
                .frame(width: 44, height: 44)
                .background(completed ? Color.mintFresh : nodeTint(period).opacity(enabled ? 0.13 : 0.06), in: Circle())
                .contentTransition(.symbolEffect(.replace))
            Text(time)
                .font(.system(.caption, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(enabled ? Color.deepInk : Color.secondary)
        }
    }

    private func nodeTint(_ period: RoutinePeriod) -> Color {
        period == .morning ? .rinseBlue : .sketchLavender
    }

    private func formattedTime(hour: Int, minute: Int) -> String {
        let date = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private struct PeriodScheduleCard: View {
    let period: RoutinePeriod
    @Binding var enabled: Bool
    @Binding var time: Date
    let completed: Bool

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: CompanionMetrics.rowSpacing) {
                Image(systemName: period == .morning ? "sun.max.fill" : "moon.stars.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: CompanionMetrics.rowIconSize, height: CompanionMetrics.rowIconSize)
                    .background(tint.opacity(0.12), in: Circle())
                    .symbolEffect(.pulse, value: enabled)
                VStack(alignment: .leading, spacing: 3) {
                    Text(period.displayName)
                        .font(.headline)
                        .foregroundStyle(Color.deepInk)
                    Text(completed ? "Completed today" : enabled ? "Reminder is ready" : "Reminder is paused")
                        .font(.caption)
                        .foregroundStyle(completed ? Color.mintDeep : .secondary)
                }
                Spacer()
                Toggle("", isOn: $enabled)
                    .labelsHidden()
                    .tint(Color.mintDeep)
            }

            if enabled {
                Divider().opacity(0.6)
                HStack {
                    Text("Reminder time")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    DatePicker("Reminder time", selection: $time, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
                // A plain move/fade keeps this to a layout change; `blurReplace`
                // would rasterize the whole shadowed card for every frame.
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .companionCard()
        .animation(.snappy(duration: 0.34), value: enabled)
        .sensoryFeedback(.selection, trigger: enabled)
    }

    private var tint: Color { period == .morning ? .rinseBlue : .sketchLavender }
}

private struct ConnectionActionCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: CompanionMetrics.rowSpacing) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: CompanionMetrics.rowIconSize, height: CompanionMetrics.rowIconSize)
                    .background(tint.opacity(0.12), in: Circle())
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(Color.deepInk)
                    Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .companionCard()
        }
        .buttonStyle(TactileCardButtonStyle())
    }
}
