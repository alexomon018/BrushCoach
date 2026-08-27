import SwiftUI

struct CoachView: View {
    @Bindable var model: CoachViewModel
    @State private var showingEndOptions = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.watchInk, .watchInk, .watchBlue.opacity(0.17)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            switch model.phase {
            case .ready:
                ReadyView(start: model.startSession)
            case .countdown(let count):
                CountdownView(count: count)
            case .brushing, .paused:
                ActiveBrushView(model: model)
            case .completed(let summary):
                CompletionView(model: model, summary: summary)
            case .failed(let message):
                FailureView(message: message, dismiss: model.dismissError)
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarBackButtonHidden(model.isBusy)
        .toolbar {
            if case .ready = model.phase {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        WatchMoreView()
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More")
                }
            } else if model.isBusy {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingEndOptions = true } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("End session")
                }
            }
        }
        .confirmationDialog("End this session?", isPresented: $showingEndOptions) {
            Button("Finish here") { model.endEarly() }
            Button("Discard", role: .destructive) { model.discard() }
            Button("Keep brushing", role: .cancel) {}
        } message: {
            Text("Finishing keeps credit for the zones you have brushed.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .brushCoachStartSessionRequested)) { _ in
            model.startSession()
        }
    }

    private var navigationTitle: String {
        switch model.phase {
        case .ready: "BrushCoach"
        case .brushing: "Zone \(model.currentZoneIndex + 1) of 6"
        case .paused: "Paused"
        case .countdown: ""
        case .completed: "Complete"
        case .failed: "Session stopped"
        }
    }
}

private struct ReadyView: View {
    let start: () -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            content(compact: false)
            content(compact: true)
        }
        .padding(.horizontal, 8)
    }

    private func content(compact: Bool) -> some View {
        VStack(spacing: compact ? 6 : 9) {
            WatchDentalArch(completed: 0, active: nil)
                .frame(height: compact ? 42 : 54)
                .accessibilityHidden(true)

            VStack(spacing: 2) {
                Text("Ready for two")
                    .font(.system(compact ? .headline : .title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text("Six 20-sec zones")
                    .font(.caption2)
                    .foregroundStyle(Color.watchMint)
            }

            Button(action: start) {
                Label("Start brushing", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.watchMint)
            .foregroundStyle(Color.watchInk)
            .accessibilityHint("Starts a two-minute guided session")

            if !compact {
                Text("Soft bristles · gentle pressure")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.56))
            }
        }
    }
}

private struct CountdownView: View {
    let count: Int

    var body: some View {
        VStack(spacing: 5) {
            Spacer(minLength: 0)
            Text(count.formatted())
                .font(.system(size: 72, weight: .black, design: .rounded))
                .foregroundStyle(Color.watchMint)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.7)
            Text("Get your brush ready")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }
}

private struct ActiveBrushView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: CoachViewModel

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 180
            let dialSize = min(geometry.size.width * 0.62, geometry.size.height * (compact ? 0.58 : 0.55))

            VStack(spacing: compact ? 3 : 7) {
                Spacer(minLength: 0)
                dial(size: dialSize, compact: compact)
                ZoneRail(completed: model.currentZoneIndex, active: model.currentZoneIndex)
                pauseButton
                if !compact { hint }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 9)
        }
    }

    private func dial(size: CGFloat, compact: Bool) -> some View {
        let lineWidth: CGFloat = compact ? 7 : 9
        return ZStack {
            Circle().stroke(.white.opacity(0.11), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: model.progress)
                .stroke(Color.watchMint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 0.26), value: model.progress)
            VStack(spacing: -2) {
                Text(model.zoneSecondsRemaining.formatted())
                    .font(.system(size: compact ? 42 : 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.75)
                Text(model.zoneName)
                    .font(.system(size: compact ? 9 : 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
        }
        .frame(width: size, height: size)
        .opacity(model.isPaused ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dialAccessibilityLabel)
    }

    private var dialAccessibilityLabel: String {
        let state = model.isPaused ? "Paused. " : ""
        return "\(state)\(model.zoneName), \(model.zoneSecondsRemaining) seconds remaining"
    }

    private var pauseButton: some View {
        let paused = model.isPaused
        let title: String = paused ? "Resume" : "Pause"
        let icon: String = paused ? "play.fill" : "pause.fill"
        let tint: Color = paused ? .watchMint : .watchBlue
        return Button {
            if paused { model.resume() } else { model.pause() }
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(tint)
    }

    /// The screen is barely looked at mid-session, so this line stays quiet and
    /// never scolds. Idle is stated as a fact, not an accusation, and the timer
    /// keeps running either way.
    private var hint: some View {
        let text: String
        let tint: Color
        if model.isPaused {
            text = "Timer held · nothing lost"
            tint = .watchBlue
        } else if model.liveActivity == .idle {
            text = "Not brushing right now"
            tint = .watchCoral
        } else {
            text = "45° to the gumline · gentle strokes"
            tint = .watchBlue
        }
        return Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(tint)
            .lineLimit(1)
    }
}

private struct CompletionView: View {
    @Bindable var model: CoachViewModel
    let summary: CoachViewModel.SessionSummary

    var body: some View {
        ViewThatFits(in: .vertical) {
            content(compact: false)
            content(compact: true)
        }
        .padding(.horizontal, 8)
    }

    private func content(compact: Bool) -> some View {
        VStack(spacing: compact ? 5 : 8) {
            Image(systemName: summary.session.completedRoutine
                  ? "checkmark.circle.fill" : "circle.lefthalf.filled")
                .font(.system(size: compact ? 28 : 38))
                .foregroundStyle(Color.watchMint)

            Text(summary.session.completedRoutine ? "Clean sweep" : "Partly done")
                .font(.system(.headline, design: .rounded, weight: .bold))

            HStack(spacing: compact ? 11 : 16) {
                metric(formattedDuration, "TIME")
                metric("\(summary.session.zonesCompleted)/\(summary.session.plannedZones)", "ZONES")
                if let brushed = formattedBrushingTime {
                    metric(brushed, "BRUSHED")
                }
            }

            if let note = sensingNote {
                Text(note)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.watchBlue)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            if let step = nextPendingStep {
                Button {
                    if step.contains("Floss") { model.markFlossed() }
                    else { model.markTongueCleaned() }
                } label: {
                    Label(step, systemImage: "arrow.right.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color.watchMint)
            }

            Button("Done", action: model.finishSummary)
                .buttonStyle(.borderedProminent)
                .tint(Color.watchBlue)
                .frame(maxWidth: .infinity)
        }
    }

    private var formattedDuration: String {
        Duration.seconds(summary.session.duration).formatted(.time(pattern: .minuteSecond))
    }

    /// Only shown when analysis actually produced a usable reading. An
    /// inconclusive session must not render as "0:00 brushed".
    private var formattedBrushingTime: String? {
        guard let seconds = summary.session.activeBrushingSeconds else { return nil }
        return Duration.seconds(seconds.rounded()).formatted(.time(pattern: .minuteSecond))
    }

    /// Explains a missing brushing time rather than leaving a silent gap.
    private var sensingNote: String? {
        guard formattedBrushingTime == nil else { return nil }
        switch summary.capability {
        case .available:
            return summary.session.analysis == nil
                ? nil
                : "Not enough motion to check your strokes this time."
        case .wrongWrist:
            return "Watch is on your other wrist, so strokes weren't checked."
        case .unknown:
            return "Set your brushing hand in the iPhone app to check strokes."
        }
    }

    private var nextPendingStep: String? {
        summary.nextSteps.first { step in
            step.contains("Floss") ? !summary.session.flossed : !summary.session.tongueCleaned
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
        }
    }
}

private struct FailureView: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(Color.watchCoral)
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Button("Back", action: dismiss)
                .buttonStyle(.borderedProminent)
                .tint(Color.watchBlue)
        }
        .padding(.horizontal, 10)
    }
}

private struct WatchMoreView: View {
    var body: some View {
        List {
            Section("Technique") {
                Label("Fluoride toothpaste", systemImage: "drop.fill")
                Label("Soft bristles", systemImage: "leaf.fill")
                Label("Gentle pressure", systemImage: "hand.raised.fill")
                Label("45° to gumline", systemImage: "angle")
            }
            Section("Developer") {
                NavigationLink("Motion capture") { RecordingView() }
            }
        }
        .navigationTitle("More")
    }
}

private struct ZoneRail: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let completed: Int
    let active: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<6, id: \.self) { index in
                Capsule()
                    .fill(index < completed ? Color.watchMint : index == active ? Color.watchBlue : .white.opacity(0.14))
                    .frame(height: index == active ? 8 : 6)
                    .scaleEffect(index == active ? 1 : 0.88)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.65), value: active)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zone \(active + 1) of 6")
    }
}

private struct WatchDentalArch: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    let completed: Int
    let active: Int?

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<6, id: \.self) { index in
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(fill(index))
                    .frame(height: height(index))
                    .scaleEffect(y: revealed ? 1 : 0.2, anchor: .bottom)
                    .opacity(revealed ? 1 : 0)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.7).delay(Double(index) * 0.06),
                        value: revealed
                    )
            }
        }
        .onAppear { revealed = true }
    }

    private func height(_ index: Int) -> CGFloat {
        switch index { case 0, 5: 26; case 1, 4: 38; default: 50 }
    }

    private func fill(_ index: Int) -> Color {
        if index < completed { return .watchMint }
        if index == active { return .watchBlue }
        return .white.opacity(0.13)
    }
}

private extension Color {
    static let watchInk = Color(red: 0.027, green: 0.102, blue: 0.141)
    static let watchBlue = Color(red: 0.23, green: 0.69, blue: 0.86)
    static let watchMint = Color(red: 0.498, green: 0.878, blue: 0.765)
    static let watchCoral = Color(red: 0.98, green: 0.41, blue: 0.37)
}
