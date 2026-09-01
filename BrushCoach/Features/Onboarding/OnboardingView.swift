import BrushKit
import SwiftUI

struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var page = 0
    @State private var settings: RoutineSettings
    /// Blocks the footer while the notification prompt is on screen, so a second
    /// tap cannot finish onboarding before the answer comes back.
    @State private var isWorking = false
    let complete: () -> Void

    init(settings: RoutineSettings, complete: @escaping () -> Void) {
        _settings = State(initialValue: settings)
        self.complete = complete
    }

    private static let pages: [OnboardingPage] = [
        OnboardingPage(
            kind: .message,
            icon: "timer",
            eyebrow: "THE ROUTINE",
            title: "Two minutes. Twice daily.",
            body: "Six zones keep the full mouth moving, with a clear haptic every 20 seconds.",
            mood: .ready,
            action: .idle
        ),
        OnboardingPage(
            kind: .message,
            icon: "angle",
            eyebrow: "THE TECHNIQUE",
            title: "Meet the gumline gently.",
            body: "Use fluoride toothpaste and a soft-bristled brush. Hold it around 45° and move in short, gentle strokes.",
            mood: .cheery,
            action: .brushing
        ),
        OnboardingPage(
            kind: .message,
            icon: "applewatch",
            eyebrow: "THE COACH",
            title: "Lower your wrist. Keep brushing.",
            body: "The Watch session follows real elapsed time, even when the display sleeps. Your history stays local and can be written to Apple Health.",
            mood: .proud,
            action: .protection
        ),
        OnboardingPage(
            kind: .handedness,
            icon: "hand.raised.fill",
            eyebrow: "ONE QUESTION",
            title: "Which hand holds the brush?",
            body: "Your Watch already knows which wrist it's on. If that's your brushing hand, BrushCoach can check your strokes — if not, it will say so instead of guessing.",
            mood: .cheery,
            action: .brushing
        ),
        OnboardingPage(
            kind: .schedule,
            icon: "clock.fill",
            eyebrow: "YOUR TWO MOMENTS",
            title: "When do you brush?",
            body: "Set the times that already fit your day. You can move them whenever they stop fitting.",
            mood: .ready,
            action: .idle
        ),
        OnboardingPage(
            kind: .reminders,
            icon: "bell.badge.fill",
            eyebrow: "LAST STEP",
            title: "A nudge, only when it's missing.",
            body: "BrushCoach reminds you at those two times — and stays quiet for a brush you have already finished.",
            mood: .proud,
            action: .success
        )
    ]

    private var current: OnboardingPage { Self.pages[page] }

    private var canAdvance: Bool {
        current.kind != .handedness || settings.preferences.brushingHand != nil
    }

    var body: some View {
        ZStack {
            onboardingBackground

            VStack(spacing: 18) {
                progressHeader

                ScrollView {
                    pageContent
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)

                footer
            }
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, horizontalSizeClass == .regular ? 28 : 24)
            .padding(.vertical, 16)
        }
        // The app runs light, but this screen is full-bleed `deepInk`. Without
        // this the system controls on the schedule page render for a light
        // background and disappear into it.
        .environment(\.colorScheme, .dark)
    }

    private var onboardingBackground: some View {
        ZStack {
            Color.deepInk
            RadialGradient(
                colors: [Color.rinseBlue.opacity(0.2), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 390
            )
            LinearGradient(
                colors: [.clear, Color.mintFresh.opacity(0.055)],
                startPoint: .center,
                endPoint: .bottomLeading
            )
        }
        .ignoresSafeArea()
    }

    private var primaryTitle: String {
        switch current.kind {
        case .handedness:
            settings.preferences.brushingHand == nil ? "Choose a hand" : "Continue"
        case .reminders:
            "Turn on reminders"
        default:
            "Continue"
        }
    }

    /// The way past a step without answering it. Both steps that have one are
    /// recoverable from the Routine tab, so neither is worth a dead end here.
    private var secondaryTitle: String? {
        switch current.kind {
        case .handedness: "Set this later"
        case .reminders: "Not now"
        default: nil
        }
    }

    private var progressHeader: some View {
        VStack(spacing: 12) {
            HStack {
                if page > 0 {
                    Button(action: goBack) {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.weight(.bold))
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                    .accessibilityLabel("Previous step")
                } else {
                    Label("BRUSHCOACH", systemImage: "sparkles")
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(Color.mintFresh)
                }

                Spacer()

                Text("\(page + 1) OF \(Self.pages.count)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.56))
            }
            .frame(height: 34)

            HStack(spacing: 7) {
                ForEach(Self.pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index <= page ? Color.mintFresh : .white.opacity(0.14))
                        .frame(height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(page + 1) of \(Self.pages.count)")
        }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            Button(primaryTitle, action: advance)
                .buttonStyle(CompanionPrimaryButtonStyle())
                .disabled(!canAdvance || isWorking)
                .accessibilityHint(current.kind == .handedness && !canAdvance ? "Choose your brushing hand first" : "")
            if let secondaryTitle {
                Button(secondaryTitle, action: skip)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .disabled(isWorking)
            }
        }
    }

    private var pageContent: some View {
        VStack(spacing: 20) {
            ToothMascotView(mood: current.mood, action: current.action, darkBackdrop: true)
                .frame(width: current.isCompact ? 96 : 132,
                       height: current.isCompact ? 102 : 140)
            if current.kind == .message {
                Image(systemName: current.icon)
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(Color.mintFresh)
            }
            VStack(spacing: 11) {
                Text(current.eyebrow)
                    .font(.companionEyebrow)
                    .tracking(1.4)
                    .foregroundStyle(Color.rinseBlue)
                Text(current.title)
                    .font(.system(size: current.isCompact ? 32 : 36,
                                  weight: .semibold, design: .serif))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                Text(current.body)
                    .font(current.isCompact ? .subheadline : .body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.68))
                    .lineSpacing(3)
            }
            switch current.kind {
            case .handedness: handChoice
            case .schedule: scheduleChoice
            case .message, .reminders: EmptyView()
            }
        }
        .id(page)
        .transition(reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }

    private var handChoice: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ForEach(BrushingHand.allCases, id: \.self) { hand in
                    HandChoiceButton(
                        hand: hand,
                        isSelected: settings.preferences.brushingHand == hand
                    ) {
                        withAnimation(.snappy(duration: 0.28)) {
                            settings.preferences.brushingHand = hand
                        }
                    }
                }
            }

            Label("You can change this later in Routine", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.52))
        }
        .padding(.top, 4)
    }

    /// Pre-filled with the defaults, so accepting the whole schedule is one tap.
    private var scheduleChoice: some View {
        VStack(spacing: 10) {
            OnboardingScheduleRow(
                period: .morning,
                enabled: $settings.preferences.morningEnabled,
                time: morningTime
            )
            OnboardingScheduleRow(
                period: .evening,
                enabled: $settings.preferences.eveningEnabled,
                time: eveningTime
            )
        }
        .padding(.top, 4)
    }

    private func advance() {
        guard canAdvance, !isWorking else { return }
        guard current.kind != .reminders else {
            isWorking = true
            Task { @MainActor in
                _ = await ReminderScheduler.shared.requestAuthorization()
                // Authorization alone schedules nothing: `refresh` bails out
                // while unauthorized, so the routine has to be applied again
                // once the answer is in.
                await settings.apply()
                isWorking = false
                complete()
            }
            return
        }
        withAnimation(.spring(response: 0.52, dampingFraction: 0.84)) { page += 1 }
    }

    private func skip() {
        guard !isWorking else { return }
        guard current.kind != .reminders else {
            complete()
            return
        }
        withAnimation(.spring(response: 0.52, dampingFraction: 0.84)) { page += 1 }
    }

    private func goBack() {
        guard page > 0, !isWorking else { return }
        withAnimation(.spring(response: 0.52, dampingFraction: 0.84)) { page -= 1 }
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

private struct OnboardingScheduleRow: View {
    let period: RoutinePeriod
    @Binding var enabled: Bool
    @Binding var time: Date

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: period == .morning ? "sun.max.fill" : "moon.stars.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(enabled ? Color.mintFresh : .white.opacity(0.35))
                .frame(width: 38, height: 38)
                .background(.white.opacity(enabled ? 0.12 : 0.05), in: Circle())
            Text(period.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(enabled ? .white : .white.opacity(0.45))
            Spacer(minLength: 4)
            if enabled {
                DatePicker("\(period.displayName) reminder time", selection: $time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
            Toggle("\(period.displayName) reminder", isOn: $enabled)
                .labelsHidden()
                .tint(Color.mintDeep)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.065))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.13), lineWidth: 1)
        }
        .animation(.snappy(duration: 0.28), value: enabled)
        .sensoryFeedback(.selection, trigger: enabled)
    }
}

private struct HandChoiceButton: View {
    let hand: BrushingHand
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 25, weight: .medium))
                        .scaleEffect(x: hand == .left ? -1 : 1)
                        .frame(width: 48, height: 48)
                        .background(isSelected ? .white.opacity(0.25) : .white.opacity(0.07), in: Circle())

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 17, weight: .bold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.deepInk, Color.mintFresh)
                            .offset(x: 5, y: -3)
                    }
                }

                Text(hand.displayName)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .foregroundStyle(isSelected ? Color.deepInk : .white)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? Color.mintFresh : .white.opacity(0.07))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isSelected ? .clear : .white.opacity(0.13), lineWidth: 1)
            }
        }
        .buttonStyle(TactileCardButtonStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct OnboardingPage {
    enum Kind { case message, handedness, schedule, reminders }

    let kind: Kind
    let icon: String
    let eyebrow: String
    let title: String
    let body: String
    let mood: ToothMood
    let action: ToothAction

    /// Pages carrying controls give the type less room so the controls fit
    /// without the layout having to scroll.
    var isCompact: Bool { kind != .message }
}
