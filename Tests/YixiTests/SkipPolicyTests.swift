import XCTest
import YixiPolicy

final class SkipPolicyTests: XCTestCase {
    func testClampRejectsNegativeAndHugeValues() {
        XCTAssertEqual(SkipPolicy.clamp(-3), 0)
        XCTAssertEqual(SkipPolicy.clamp(0), 0)
        XCTAssertEqual(SkipPolicy.clamp(4), 4)
        XCTAssertEqual(SkipPolicy.clamp(99), SkipPolicy.threshold)
    }

    func testStoredHugeValueBecomesBlockedButFinite() {
        let policy = SkipPolicy(stored: 1_000)
        XCTAssertEqual(policy.consecutiveSkipCount, SkipPolicy.threshold)
        XCTAssertTrue(policy.isSkipBlocked)
    }

    func testFourSkipsThenBlocked() {
        var policy = SkipPolicy(stored: 0)
        XCTAssertFalse(policy.isSkipBlocked)

        for i in 1...3 {
            policy.recordSkip()
            XCTAssertEqual(policy.consecutiveSkipCount, i)
            XCTAssertFalse(policy.isSkipBlocked, "第 \(i) 次跳过后仍不应强制止息")
        }

        policy.recordSkip()
        XCTAssertEqual(policy.consecutiveSkipCount, 4)
        XCTAssertTrue(policy.isSkipBlocked, "连跳四次后下一次应强制止息")
    }

    func testRecordSkipDoesNotExceedThreshold() {
        var policy = SkipPolicy(stored: 4)
        policy.recordSkip()
        XCTAssertEqual(policy.consecutiveSkipCount, SkipPolicy.threshold)
        XCTAssertTrue(policy.isSkipBlocked)
    }

    func testResetClearsBlock() {
        var policy = SkipPolicy(stored: 4)
        XCTAssertTrue(policy.isSkipBlocked)
        policy.reset()
        XCTAssertEqual(policy.consecutiveSkipCount, 0)
        XCTAssertFalse(policy.isSkipBlocked)
    }
}
