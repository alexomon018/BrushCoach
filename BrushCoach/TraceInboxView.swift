import BrushKit
import SwiftUI

struct TraceInboxView: View {
    @State private var traces: [TraceFile] = []
    @State private var errorMessage: String?
    @State private var shareURLs: [URL] = []
    @State private var showingShareSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if traces.isEmpty {
                    emptyState
                } else {
                    traceList
                }
            }
            .background(Color.traceEnamelWash)
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
        }
        .tint(Color.traceRinseBlue)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No traces yet", systemImage: "waveform.path.ecg")
        } description: {
            Text(errorMessage ?? "Record a labelled 10-second sample on Apple Watch. It will appear here when transferred.")
        } actions: {
            Button("Check again") { reload() }
        }
    }

    private var traceList: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "lock.shield.fill")
                        .font(.title2)
                        .foregroundStyle(Color.traceRinseBlue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("On-device dataset")
                            .font(.headline)
                        Text("Raw motion stays in this private app container until you choose to export it.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Recordings") {
                ForEach(traces) { file in
                    TraceRow(file: file)
                }
            }
        }
        .scrollContentBackground(.hidden)
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
            .foregroundStyle(Color.traceRinseBlue)
            .frame(width: 38, height: 46)
            .background(Color.traceRinseBlue.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))

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
        .padding(.vertical, 5)
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

private extension Color {
    static let traceEnamelWash = Color(red: 0.945, green: 0.975, blue: 0.985)
    static let traceRinseBlue = Color(red: 0.03, green: 0.48, blue: 0.72)
}
