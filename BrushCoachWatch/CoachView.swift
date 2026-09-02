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
                ReadyView(tracksZones: model.hasCalibration, start: model.startSession)
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
        .navigationBarBackButtonHidden(model.isBusy)
        .toolbar {
            if case .ready = model.phase {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        WatchMoreView(model: model)
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
            Text("Finishing saves the time and coverage recorded so far.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .brushCoachStartSessionRequested)) { _ in
            model.startSession()
        }
        // Handedness can be answered on the phone and calibration can be run
        // from the More screen, so both are re-read when this screen comes back
        // into view rather than on every render.
        .onAppear { model.refreshDeviceState() }
    }
}

private struct ReadyView: View {
    let tracksZones: Bool
    let start: () -> Void

    /// A scroll view rather than a `ViewThatFits` pair: on the smallest watches
    /// neither variant really fitted, so the arch and the subtitle were clipped
    /// against each other instead of the screen simply scrolling.
    var body: some View {
        ScrollView {
            VStack(spacing: WatchMetrics.componentSpacing) {
                WatchDentalArch(completed: 0, active: nil)
                    .frame(height: 38)
                    .accessibilityHidden(true)

                VStack(spacing: 3) {
                    Text("Two minutes, your way")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(tracksZones ? "Six areas tracked automatically" : "Brush freely at your own pace")
                        .font(.caption2)
                        .foregroundStyle(Color.watchMint)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: start) {
                    Label("Start brushing", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .watchPrimaryControl(tint: .watchMint, foreground: .watchInk)
                .accessibilityHint("Starts a two-minute free-brushing session")

                Text("Soft bristles · gentle pressure")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.56))
                    .multilineTextAlignment(.center)
            }
            .watchPageFrame(bottom: 12)
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
        .watchPageFrame(bottom: 0)
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
                pauseButton
                if !compact { hint }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .watchPageFrame(bottom: 0)
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
                Text(model.secondsRemaining.formatted())
                    .font(.system(size: compact ? 42 : 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.75)
                Text("KEEP BRUSHING")
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
        return "\(state)\(model.secondsRemaining) seconds remaining"
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
        .watchSecondaryControl(tint: tint)
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

    /// The summary grows with whatever the session produced — metrics, coverage,
    /// a sensing note, a next step — so it scrolls rather than trying to squeeze
    /// every combination onto one screen.
    var body: some View {
        ScrollView {
            content
                .watchPageFrame(bottom: 12)
        }
    }

    private var content: some View {
        VStack(spacing: 8) {
            Image(systemName: summary.session.completedRoutine
                  ? "checkmark.circle.fill" : "circle.lefthalf.filled")
                .font(.system(size: 38))
                .foregroundStyle(Color.watchMint)

            Text(summary.session.completedRoutine ? "Brush complete" : "Session saved")
                .font(.system(.headline, design: .rounded, weight: .bold))

            HStack(spacing: 16) {
                metric(formattedDuration, "TIME")
                if let brushed = formattedBrushingTime {
                    metric(brushed, "BRUSHED")
                }
            }

            if let coverageNote {
                Text(coverageNote)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.watchBlue)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let note = sensingNote {
                Text(note)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.watchBlue)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
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
                .watchSecondaryControl(tint: .watchMint)
            }

            Button("Done", action: model.finishSummary)
                .watchPrimaryControl(tint: .watchBlue)
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

    private var coverageNote: String? {
        guard summary.capability == .available else { return nil }
        guard let analysis = summary.session.analysis else { return nil }
        guard analysis.zoneEstimationAttempted else {
            return "Calibrate zones to unlock your iPhone mouth map."
        }
        guard analysis.hasUsableZoneCoverage(forSessionLasting: summary.session.duration) else {
            return "Not enough confident zone time for a reliable mouth map."
        }
        let count = analysis.underBrushedZones.count
        return count == 0
            ? "Balanced coverage · see the mouth map on iPhone"
            : "\(count) area\(count == 1 ? "" : "s") need more time · see iPhone"
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
                .watchPrimaryControl(tint: .watchBlue)
        }
        .watchPageFrame(bottom: 0)
    }
}

private struct WatchMoreView: View {
    @Bindable var model: CoachViewModel

    var body: some View {
        List {
            Section("Zone mapping") {
                NavigationLink {
                    CalibrationView()
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.hasCalibration ? "Recalibrate" : "Calibrate zones")
                        Text(model.hasCalibration ? "Ready for mouth maps" : "About 3 minutes")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!model.capability.canSenseMotion)
                if !model.capability.canSenseMotion {
                    Text(model.capability.explanation)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            Section("Developer") {
                NavigationLink("Motion capture") { RecordingView() }
            }
        }
        .navigationTitle("More")
        .scrollContentBackground(.hidden)
        .background(Color.watchInk.ignoresSafeArea())
        .tint(Color.watchMint)
        // Picks up a profile written by the calibration screen this pushed to.
        .onAppear { model.refreshDeviceState() }
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
