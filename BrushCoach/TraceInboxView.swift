import BrushKit
import SwiftUI

struct TraceInboxView: View {
    @State private var traces: [TraceFile] = []
    @State private var errorMessage: String?
    @State private var shareURLs: [URL] = []
    @State private var showingShareSheet = false

    var body: some View {
        Group {
            if traces.isEmpty {
                emptyState
            } else {
                traceList
            }
        }
        .background(Color.enamelWash.ignoresSafeArea())
        .navigationTitle("Trace inbox")
        .toolbar {
            if !traces.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Export all", systemImage: "square.and.arrow.up") {
                        shareURLs = traces.map(\.url)
                        showingShareSheet = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ActivitySheet(items: shareURLs)
                .presentationDetents([.medium, .large])
        }
        .task { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .brushCoachTraceInboxChanged)) { _ in
            reload()
        }
        .tint(Color.rinseBlue)
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.rinseBlue)
                    .frame(width: 72, height: 72)
                    .background(Color.rinseBlue.opacity(0.12), in: Circle())

                VStack(spacing: 6) {
                    Text("No traces yet")
                        .font(.companionFeatureTitle)
                        .foregroundStyle(Color.deepInk)
                    Text(errorMessage ?? "Record a labelled 10-second sample on Apple Watch. It will appear here when transferred.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button("Check again") { reload() }
                    .buttonStyle(CompanionPrimaryButtonStyle())
            }
            .companionCard(.feature)
            .companionPageFrame(top: 24)
        }
    }

    private var traceList: some View {
        ScrollView {
            LazyVStack(spacing: CompanionMetrics.sectionSpacing) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "lock.shield.fill")
                        .font(.title2)
                        .foregroundStyle(Color.rinseBlue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("On-device dataset")
                            .font(.headline)
                        Text("Raw motion stays in this private app container until you choose to export it.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .companionCard()

                CompanionSection(title: "RECORDINGS", detail: "Share individual captures or export the complete set.") {
                    LazyVStack(spacing: CompanionMetrics.componentSpacing) {
                        ForEach(traces) { file in
                            TraceRow(file: file)
                        }
                    }
                }
            }
            .companionPageFrame()
        }
    }

    private func reload() {
        do {
            traces = try PhoneTraceStore.list()
            errorMessage = nil
        } catch {
            traces = []
            errorMessage = error.localizedDescription
        }
    }
}

private struct TraceRow: View {
    let file: TraceFile

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 3) {
                Text(file.trace.metadata.label.jaw == .upper ? "U" : file.trace.metadata.label.jaw == .lower ? "L" : "·")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Text(sideAbbreviation)
                    .font(.caption2.monospaced())
            }
            .foregroundStyle(Color.rinseBlue)
            .frame(width: CompanionMetrics.rowIconSize, height: CompanionMetrics.rowIconSize)
            .background(Color.rinseBlue.opacity(0.11), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(file.trace.metadata.label.displayName)
                    .font(.headline)
                Text(file.trace.metadata.recordedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(file.trace.samples.count) samples · \(file.trace.actualSampleRateHz.formatted(.number.precision(.fractionLength(1)))) Hz")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ShareLink(item: file.url) {
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                    .accessibilityLabel("Export \(file.trace.metadata.label.displayName) trace")
            }
            .buttonStyle(.borderless)
        }
        .companionCard(.compact)
    }

    private var sideAbbreviation: String {
        switch file.trace.metadata.label.side {
        case .left: "LT"
        case .centre: "CT"
        case .right: "RT"
        case nil: file.trace.metadata.label == .idle ? "ID" : "TR"
        }
    }
}
