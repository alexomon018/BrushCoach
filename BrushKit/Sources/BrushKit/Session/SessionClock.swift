import Foundation

/// Tracks elapsed session time from wall-clock instants.
///
/// The session must stay accurate while the display sleeps, the wrist is lowered,
/// and Sleep Focus is active — which means elapsed time can never be accumulated
/// from timer ticks. Ticks stop when the process is suspended; wall-clock
/// differences do not. Every reading here is derived from `Date` deltas, so a tick
/// that arrives late, early, or not at all cannot make the session drift.
public struct SessionClock: Equatable, Sendable {
    /// Time banked by previously completed run segments.
    private var banked: TimeInterval = 0
    /// When the current run segment began, or `nil` while paused or stopped.
    private var segmentStart: Date?

    public let limit: TimeInterval

    public init(limit: TimeInterval) {
        self.limit = max(0, limit)
    }

    public var isRunning: Bool { segmentStart != nil }

    public mutating func start(at instant: Date) {
        banked = 0
        segmentStart = instant
    }

    public mutating func pause(at instant: Date) {
        guard let start = segmentStart else { return }
        banked = min(limit, banked + max(0, instant.timeIntervalSince(start)))
        segmentStart = nil
    }

    public mutating func resume(at instant: Date) {
        guard segmentStart == nil else { return }
        segmentStart = instant
    }

    public mutating func stop(at instant: Date) {
        pause(at: instant)
    }

    public mutating func reset() {
        banked = 0
        segmentStart = nil
    }

    public func elapsed(at instant: Date) -> TimeInterval {
        guard let start = segmentStart else { return banked }
        return min(limit, banked + max(0, instant.timeIntervalSince(start)))
    }

    public func isComplete(at instant: Date) -> Bool {
        elapsed(at: instant) >= limit
    }
}
