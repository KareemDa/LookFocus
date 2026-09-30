import XCTest
import FocusCore

final class WorkSetupTests: XCTestCase {
    func testOnlyTheSavedWorkMonitorAllowsCameraUse() {
        let policy = WorkSetupPolicy(monitorID: "work-monitor")
        XCTAssertFalse(policy.allowsTracking(connectedMonitorIDs: ["mac-display"]))
        XCTAssertFalse(policy.allowsTracking(connectedMonitorIDs: ["mac-display", "home-monitor"]))
        XCTAssertTrue(policy.allowsTracking(connectedMonitorIDs: ["mac-display", "work-monitor"]))
    }
    func testReconnectPreservesTrackingIntentButManualPauseCancelsIt() {
        var policy = WorkSetupPolicy(monitorID: "work-monitor")
        policy.requestTracking()
        XCTAssertFalse(policy.allowsTracking(connectedMonitorIDs: ["mac-display"]))
        XCTAssertTrue(policy.trackingRequested)
        XCTAssertTrue(policy.allowsTracking(connectedMonitorIDs: ["work-monitor"]))
        XCTAssertTrue(policy.trackingRequested)
        policy.pause()
        XCTAssertFalse(policy.trackingRequested)
        XCTAssertTrue(policy.allowsTracking(connectedMonitorIDs: ["work-monitor"]))
        XCTAssertFalse(policy.trackingRequested)
    }
    func testLaunchStaysPausedAndDisablingRestrictionAllowsHomeUse() {
        var policy = WorkSetupPolicy(monitorID: "work-monitor")
        XCTAssertFalse(policy.trackingRequested)
        policy.monitorID = nil
        XCTAssertTrue(policy.allowsTracking(connectedMonitorIDs: ["mac-display"]))
        XCTAssertFalse(policy.trackingRequested)
    }
    func testStableScreenIdentityPreservesSamplesAndOlderRecordsDecode() throws {
        var target = FocusTarget(name: "Work", displayID: 3, pose: Pose(yaw: 0.8, pitch: 0))
        target.additionalPoses = [Pose(yaw: 0.7, pitch: 0.1)]
        let oldData = try JSONEncoder().encode(target)
        XCTAssertNil(try JSONDecoder().decode(FocusTarget.self, from: oldData).displayUUID)
        target.displayUUID = "work-monitor"
        let restored = try JSONDecoder().decode(FocusTarget.self, from: JSONEncoder().encode(target))
        XCTAssertEqual(restored.displayUUID, "work-monitor")
        XCTAssertEqual(restored.id, target.id)
        XCTAssertEqual(restored.additionalPoses, target.additionalPoses)
        XCTAssertEqual(restored.sampleCount, 2)
    }
}
