import Foundation

/// 连续「仍行」跳过的计数与强制止息判定（纯逻辑，便于单测）。
public struct SkipPolicy: Equatable, Sendable {
    /// 连续跳过满此次数后，下一次休息不可跳过。
    public static let threshold = 4

    public private(set) var consecutiveSkipCount: Int

    public init(stored: Int) {
        consecutiveSkipCount = Self.clamp(stored)
    }

    /// 当前休息是否应禁止跳过 / 延期 / 暂停逃离。
    public var isSkipBlocked: Bool { consecutiveSkipCount >= Self.threshold }

    public mutating func recordSkip() {
        consecutiveSkipCount = Self.clamp(consecutiveSkipCount + 1)
    }

    public mutating func reset() {
        consecutiveSkipCount = 0
    }

    /// 损坏或异常大的持久化值钳到阈值，避免永久无法跳过。
    public static func clamp(_ value: Int) -> Int {
        min(threshold, max(0, value))
    }
}
