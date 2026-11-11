import Foundation

/// A deadline measured on a monotonic clock. Sleep is handled by the caller.
public struct Countdown: Sendable {
    private var end: TimeInterval = 0

    public init() {}

    public mutating func start(duration: TimeInterval, at now: TimeInterval) {
        end = now + max(0, duration)
    }

    public func remaining(at now: TimeInterval) -> TimeInterval {
        max(0, end - now)
    }
}
