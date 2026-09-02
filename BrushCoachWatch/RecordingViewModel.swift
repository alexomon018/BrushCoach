import BrushKit
import Foundation
import Observation
import WatchKit

@MainActor
@Observable
final class RecordingViewModel {
    // Phase 0 capture vocabulary: click = countdown, start = capture live,
    // success = saved/queued, failure = capture or storage error.
    enum Phase: Equatable {
        case idle
        case countdown(Int)
        case recording
        case saved(Int)
        case failed(String)
    }

    var selectedLabel: BrushZoneLabel = .upperRight
    /// Length of the capture currently running (or the last one). The view reads
    /// this rather than its own setting so changing the setting mid-capture can
    /// never desync the progress bar from what is actually being recorded.
    private(set) var duration: TimeInterval = RecordingViewModel.defaultDuration
    private(set) var phase: Phase = .idle
    private(set) var sampleCount = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var waveform: [Double] = []

    @ObservationIgnored private let recorder = WatchMotionRecorder()
    @ObservationIgnored private let runtime = ExtendedRuntimeController()
    @ObservationIgnored private var captureTask: Task<Void, Never>?

    /// Capture state is accumulated here and published to the observable
    /// properties on a timer. Writing all three per sample re-evaluated the
    /// recording view 150 times a second for a 70-point sparkline.
    @ObservationIgnored private var capturedSamples = 0
    @ObservationIgnored private var capturedWaveform: [Double] = []
    @ObservationIgnored private var lastPublish: TimeInterval = -.infinity

    /// Ten updates a second is already past what the eye resolves on a sparkline
    /// this size, and it is a fifth of the sensor rate.
    private static let publishInterval: TimeInterval = 0.1

    /// Capture lengths offered on the watch. Ten seconds is enough for a single
    /// labelled zone burst; the longer options exist because a natural brushing
    /// stroke pattern needs more than one burst to be representative.
    static let durationOptions: [Int] = [10, 20, 30, 60]
    static let defaultDuration: TimeInterval = 20

    var isBusy: Bool {
        if case .countdown = phase { return true }
        if case .recording = phase { return true }
        return false
    }

    var canRecordAgain: Bool {
        if case .saved = phase { return true }
        if case .failed = phase { return true }
        return false
    }

    func begin(duration: TimeInterval, watchWrist: WatchWrist?) {
        guard captureTask == nil else { return }
        self.duration = duration
        phase = .countdown(3)
        resetCaptureState()
        runtime.begin()

        captureTask = Task { [weak self] in
            guard let self else { return }
            for count in stride(from: 3, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                phase = .countdown(count)
                WKInterfaceDevice.current().play(.click)
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }

            phase = .recording
            WKInterfaceDevice.current().play(.start)
            do {
                let samples = try await recorder.record(duration: duration) { [weak self] sample, recordingElapsed in
                    guard let self else { return }
                    capturedSamples += 1
                    capturedWaveform.append(sample.userAcceleration.magnitude)
                    if capturedWaveform.count > 70 {
                        capturedWaveform.removeFirst(capturedWaveform.count - 70)
                    }
                    // The last sample always publishes, so the finished capture
                    // never shows a count short of what it recorded.
                    let isFinalSample = recordingElapsed >= duration
                    guard isFinalSample || recordingElapsed - lastPublish >= Self.publishInterval
                    else { return }
                    lastPublish = recordingElapsed
                    sampleCount = capturedSamples
                    elapsed = min(duration, recordingElapsed)
                    waveform = capturedWaveform
                }
                guard !Task.isCancelled else { return }

                let trace = LabelledMotionTrace(
                    metadata: TraceMetadata(label: selectedLabel, watchWrist: watchWrist),
                    samples: samples
                )
                let url = try WatchTraceStore.save(trace)
                WatchTraceTransfer.shared.enqueue(url)
                phase = .saved(samples.count)
                WKInterfaceDevice.current().play(.success)
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error.localizedDescription)
                WKInterfaceDevice.current().play(.failure)
            }
            runtime.end()
            captureTask = nil
        }
    }

    func cancel() {
        captureTask?.cancel()
        captureTask = nil
        recorder.cancel()
        runtime.end()
        phase = .idle
        resetCaptureState()
    }

    private func resetCaptureState() {
        sampleCount = 0
        elapsed = 0
        waveform = []
        capturedSamples = 0
        capturedWaveform = []
        lastPublish = -.infinity
    }
}
