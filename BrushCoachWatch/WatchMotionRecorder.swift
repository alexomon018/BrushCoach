@preconcurrency import CoreMotion
import BrushKit
import Foundation

@MainActor
final class WatchMotionRecorder {
    enum RecordingError: LocalizedError {
        case deviceMotionUnavailable
        case noSamples
        case motionFailure(String)

        var errorDescription: String? {
            switch self {
            case .deviceMotionUnavailable: "Motion sensing is unavailable on this watch."
            case .noSamples: "No motion samples arrived. Try recording again."
            case .motionFailure(let message): "Motion recording stopped: \(message)"
            }
        }
    }

    private let manager = CMMotionManager()
    private var samples: [MotionSample] = []
    /// Counted separately from `samples`, which stays empty when the caller does
    /// not need the trace. "No motion arrived" must stay distinguishable from
    /// "motion arrived and was deliberately not kept".
    private var receivedCount = 0
    private var retainsSamples = true
    private var firstTimestamp: TimeInterval?
    private var continuation: CheckedContinuation<[MotionSample], Error>?
    private var timeoutTask: Task<Void, Never>?
    private var sampleHandler: ((MotionSample, TimeInterval) -> Bool)?

    func record(
        duration: TimeInterval,
        onSample: @escaping @MainActor (MotionSample, TimeInterval) -> Void
    ) async throws -> [MotionSample] {
        try await capture(maxDuration: duration) { sample, elapsed in
            onSample(sample, elapsed)
            return false
        }
    }

    /// Records until the callback reports completion, with a hard deadline so
    /// a paused or abandoned brushing session cannot keep sensing forever.
    ///
    /// `retainsSamples` is for callers that need the finished trace — a
    /// calibration capture does, a coaching session does not. Analysis is
    /// streamed sample by sample through `onSample`, so keeping the array as
    /// well meant holding roughly a megabyte for two minutes to throw it away.
    func recordUntilStopped(
        maxDuration: TimeInterval,
        retainsSamples: Bool = true,
        onSample: @escaping @MainActor (MotionSample, TimeInterval) -> Bool
    ) async throws -> [MotionSample] {
        try await capture(maxDuration: maxDuration, retainsSamples: retainsSamples, onSample: onSample)
    }

    private func capture(
        maxDuration: TimeInterval,
        retainsSamples: Bool = true,
        onSample: @escaping @MainActor (MotionSample, TimeInterval) -> Bool
    ) async throws -> [MotionSample] {
        guard manager.isDeviceMotionAvailable else { throw RecordingError.deviceMotionUnavailable }
        cancel()
        self.retainsSamples = retainsSamples
        if retainsSamples { samples.reserveCapacity(Int(maxDuration * 50) + 20) }
        sampleHandler = onSample
        manager.deviceMotionUpdateInterval = 1.0 / 50.0

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let error {
                        self.finish(throwing: RecordingError.motionFailure(error.localizedDescription))
                        return
                    }
                    guard let motion else { return }
                    self.receive(motion, duration: maxDuration)
                }
            }

            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(maxDuration + 2))
                guard !Task.isCancelled else { return }
                self?.finishAtDeadline()
            }
        }
    }

    func cancel() {
        manager.stopDeviceMotionUpdates()
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(throwing: CancellationError())
        continuation = nil
        samples.removeAll(keepingCapacity: true)
        receivedCount = 0
        firstTimestamp = nil
        sampleHandler = nil
    }

    private func receive(_ motion: CMDeviceMotion, duration: TimeInterval) {
        let sample = MotionSample(
            timestamp: motion.timestamp,
            userAcceleration: Vector3(
                x: motion.userAcceleration.x,
                y: motion.userAcceleration.y,
                z: motion.userAcceleration.z
            ),
            rotationRate: Vector3(
                x: motion.rotationRate.x,
                y: motion.rotationRate.y,
                z: motion.rotationRate.z
            ),
            gravity: Vector3(x: motion.gravity.x, y: motion.gravity.y, z: motion.gravity.z),
            attitude: Quaternion(
                x: motion.attitude.quaternion.x,
                y: motion.attitude.quaternion.y,
                z: motion.attitude.quaternion.z,
                w: motion.attitude.quaternion.w
            )
        )
        let start = firstTimestamp ?? sample.timestamp
        firstTimestamp = start
        let elapsed = sample.timestamp - start
        receivedCount += 1
        if retainsSamples { samples.append(sample) }
        let requestedStop = sampleHandler?(sample, elapsed) ?? false
        if requestedStop || elapsed >= duration { finish(with: samples) }
    }

    private func finishAtDeadline() {
        if receivedCount == 0 { finish(throwing: RecordingError.noSamples) }
        else { finish(with: samples) }
    }

    private func finish(with result: [MotionSample]) {
        manager.stopDeviceMotionUpdates()
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(returning: result)
        continuation = nil
        samples = []
        receivedCount = 0
        firstTimestamp = nil
        sampleHandler = nil
    }

    private func finish(throwing error: Error) {
        manager.stopDeviceMotionUpdates()
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(throwing: error)
        continuation = nil
        samples = []
        receivedCount = 0
        firstTimestamp = nil
        sampleHandler = nil
    }
}
