import XCTest
import FocusCore

final class BatteryIdleTests: XCTestCase {
    func testIdleThresholdAndInputRecovery() {
        XCTAssertFalse(BatteryIdlePolicy.shouldPause(enabled: true, idleSeconds: 119.9))
        XCTAssertTrue(BatteryIdlePolicy.shouldPause(enabled: true, idleSeconds: 120))
        XCTAssertTrue(BatteryIdlePolicy.shouldPause(enabled: true, idleSeconds: 300))
        XCTAssertFalse(BatteryIdlePolicy.shouldPause(enabled: true, idleSeconds: 0))
        XCTAssertFalse(BatteryIdlePolicy.shouldPause(enabled: false, idleSeconds: 300))
    }
}
