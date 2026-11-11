import XCTest
import YixiPolicy

final class CountdownTests: XCTestCase {
    func testDeadlineAndExpiry() {
        var countdown = Countdown()
        countdown.start(duration: 60, at: 100)
        XCTAssertEqual(countdown.remaining(at: 125), 35)
        XCTAssertEqual(countdown.remaining(at: 160), 0)
        XCTAssertEqual(countdown.remaining(at: 200), 0)
    }

    func testResumeAfterSleepPreservesRemainingDuration() {
        var countdown = Countdown()
        countdown.start(duration: 60, at: 100)
        let remaining = countdown.remaining(at: 120)
        countdown.start(duration: remaining, at: 500)
        XCTAssertEqual(countdown.remaining(at: 510), 30)
    }

    func testNegativeDurationExpiresImmediately() {
        var countdown = Countdown()
        countdown.start(duration: -1, at: 10)
        XCTAssertEqual(countdown.remaining(at: 10), 0)
    }
}
