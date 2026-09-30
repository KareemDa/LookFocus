import XCTest
@testable import FocusCore

final class FocusPolicyTests: XCTestCase {
    let left = FocusTarget(name: "Left", displayID: 1, pose: Pose(yaw: -0.35, pitch: 0))
    let right = FocusTarget(name: "Right", displayID: 2, pose: Pose(yaw: 0.35, pitch: 0))
    func testRequiresContinuousDwellAndAllowsReturnTrip() {
        var policy = FocusPolicy()
        let anchors = [left, right]
        XCTAssertNil(policy.evaluate(pose: right.pose, anchors: anchors, now: 10, lastKey: 0, lastMouse: 0, current: left.id))
        XCTAssertNil(policy.evaluate(pose: right.pose, anchors: anchors, now: 10.3, lastKey: 0, lastMouse: 0, current: left.id))
        XCTAssertEqual(policy.evaluate(pose: right.pose, anchors: anchors, now: 10.7, lastKey: 0, lastMouse: 0, current: left.id), right.id)
        XCTAssertNil(policy.evaluate(pose: left.pose, anchors: anchors, now: 12, lastKey: 0, lastMouse: 0, current: right.id))
        XCTAssertEqual(policy.evaluate(pose: left.pose, anchors: anchors, now: 12.7, lastKey: 0, lastMouse: 0, current: right.id), left.id)
    }
    func testActivityResetsDwellRatherThanQueuingSwitch() {
        var policy = FocusPolicy()
        policy.typingPause = 3; policy.mousePause = 1.5
        XCTAssertNil(policy.evaluate(pose: right.pose, anchors: [right], now: 10, lastKey: 0, lastMouse: 0, current: nil))
        XCTAssertNil(policy.evaluate(pose: right.pose, anchors: [right], now: 11, lastKey: 10.8, lastMouse: 0, current: nil))
        XCTAssertNil(policy.evaluate(pose: right.pose, anchors: [right], now: 14, lastKey: 10.8, lastMouse: 0, current: nil))
        XCTAssertNil(policy.evaluate(pose: right.pose, anchors: [right], now: 14.7, lastKey: 10.8, lastMouse: 14, current: nil))
        XCTAssertNil(policy.evaluate(pose: right.pose, anchors: [right], now: 16, lastKey: 10.8, lastMouse: 14, current: nil))
        XCTAssertEqual(policy.evaluate(pose: right.pose, anchors: [right], now: 16.7, lastKey: 10.8, lastMouse: 14, current: nil), right.id)
    }
    func testNoFaceOrOffScreenResetsDwell() {
        var policy = FocusPolicy()
        XCTAssertNil(policy.evaluate(pose: right.pose, anchors: [right], now: 10, lastKey: 0, lastMouse: 0, current: nil))
        XCTAssertNil(policy.evaluate(pose: nil, anchors: [right], now: 11, lastKey: 0, lastMouse: 0, current: nil))
        XCTAssertNil(policy.evaluate(pose: right.pose, anchors: [right], now: 12, lastKey: 0, lastMouse: 0, current: nil))
        XCTAssertNil(policy.evaluate(pose: Pose(yaw: 0, pitch: -0.8), anchors: [right], now: 13, lastKey: 0, lastMouse: 0, current: nil))
        XCTAssertNil(policy.evaluate(pose: right.pose, anchors: [right], now: 14, lastKey: 0, lastMouse: 0, current: nil))
    }
    func testAmbiguousTargetsAndCurrentTargetNeverSwitch() {
        var policy = FocusPolicy()
        let close = FocusTarget(name: "Nearby", displayID: 3, pose: Pose(yaw: 0.38, pitch: 0))
        for now in [10.0, 11.0, 12.0] {
            XCTAssertNil(policy.evaluate(pose: right.pose, anchors: [right, close], now: now, lastKey: 0, lastMouse: 0, current: nil))
            XCTAssertNil(policy.evaluate(pose: left.pose, anchors: [left, right], now: now, lastKey: 0, lastMouse: 0, current: left.id))
        }
    }
}

extension FocusPolicyTests {
    func testSeveralPosturesForOneScreenDoNotCompeteOrResetDwell() {
        var target = right
        let lower = Pose(yaw: 0.37, pitch: 0.28)
        target.additionalPoses = [Pose(yaw: 0.36, pitch: 0.02), lower]
        var policy = FocusPolicy()
        XCTAssertNil(policy.evaluate(pose: target.pose, anchors: [left, target], now: 10, lastKey: 0, lastMouse: 0, current: left.id))
        XCTAssertEqual(policy.evaluate(pose: lower, anchors: [left, target], now: 10.7, lastKey: 0, lastMouse: 0, current: left.id), target.id)
        XCTAssertNil(policy.evaluate(pose: left.pose, anchors: [left, target], now: 12, lastKey: 0, lastMouse: 0, current: target.id))
        XCTAssertEqual(policy.evaluate(pose: left.pose, anchors: [left, target], now: 12.7, lastKey: 0, lastMouse: 0, current: target.id), left.id)
    }
    func testOverlappingSamplesOnDifferentScreensHoldFocus() {
        var target = right
        target.additionalPoses = [Pose(yaw: -0.33, pitch: 0)]
        var policy = FocusPolicy()
        for now in [10.0, 11.0] {
            XCTAssertNil(policy.evaluate(pose: left.pose, anchors: [left, target], now: now, lastKey: 0, lastMouse: 0, current: nil))
        }
        XCTAssertLessThan(target.distance(to: left.pose), 0.09)
    }
    func testLegacyCalibrationLoadsAndMultipleSamplesPersist() throws {
        let old = """
        {"id":"00000000-0000-0000-0000-000000000001","name":"Screen","displayID":1,"pose":{"yaw":0.2,"pitch":0}}
        """
        var target = try JSONDecoder().decode(FocusTarget.self, from: Data(old.utf8))
        let identity = target.id
        XCTAssertEqual(target.sampleCount, 1)
        let extra = Pose(yaw: 0.25, pitch: 0.3)
        XCTAssertGreaterThan(target.distance(to: extra), 0.2)
        target.additionalPoses = [extra]
        let restored = try JSONDecoder().decode(FocusTarget.self, from: JSONEncoder().encode(target))
        XCTAssertEqual(restored.id, identity)
        XCTAssertEqual(restored.sampleCount, 2)
        XCTAssertEqual(restored.distance(to: extra), 0)
        target.additionalPoses = nil
        XCTAssertEqual(target.pose, restored.pose)
        XCTAssertEqual(target.sampleCount, 1)
        XCTAssertGreaterThan(target.distance(to: extra), 0.2)
    }
}


extension FocusPolicyTests {
    func testBriefDetectionGapDoesNotStarveSwitchButCannotSwitchOnMissingFace() {
        var policy = FocusPolicy(); policy.dwell = 0.3
        XCTAssertNil(policy.evaluate(pose: right.pose, anchors: [left, right], now: 10, lastKey: 0, lastMouse: 0, current: left.id))
        XCTAssertNil(policy.evaluate(pose: right.pose, anchors: [left, right], now: 10.1, lastKey: 0, lastMouse: 0, current: left.id))
        XCTAssertNil(policy.evaluate(pose: nil, anchors: [left, right], now: 10.2, lastKey: 0, lastMouse: 0, current: left.id))
        XCTAssertEqual(policy.state, .noFace)
        XCTAssertEqual(policy.evaluate(pose: right.pose, anchors: [left, right], now: 10.31, lastKey: 0, lastMouse: 0, current: left.id), right.id)
    }
    func testSustainedLostFaceAndInputRestartCandidate() {
        var policy = FocusPolicy(); policy.dwell = 0.3
        _ = policy.evaluate(pose: right.pose, anchors: [right], now: 10, lastKey: 0, lastMouse: 0, current: nil)
        _ = policy.evaluate(pose: nil, anchors: [right], now: 10.3, lastKey: 0, lastMouse: 0, current: nil)
        XCTAssertNil(policy.candidate)
        XCTAssertNil(policy.evaluate(pose: right.pose, anchors: [right], now: 10.4, lastKey: 0, lastMouse: 0, current: nil))
        XCTAssertNil(policy.evaluate(pose: right.pose, anchors: [right], now: 10.5, lastKey: 10.4, lastMouse: 0, current: nil))
        XCTAssertEqual(policy.state, .typing)
        XCTAssertNil(policy.candidate)
        XCTAssertNil(policy.evaluate(pose: right.pose, anchors: [right], now: 11.3, lastKey: 10.4, lastMouse: 0, current: nil))
        XCTAssertEqual(policy.evaluate(pose: right.pose, anchors: [right], now: 11.61, lastKey: 10.4, lastMouse: 0, current: nil), right.id)
    }
    func testDecisionReportsMismatchAndCurrentTarget() {
        var policy = FocusPolicy()
        XCTAssertNil(policy.evaluate(pose: Pose(yaw: 1.2, pitch: 0), anchors: [right], now: 10, lastKey: 0, lastMouse: 0, current: nil))
        guard case .outsideCalibration(let id, let distance) = policy.state else { return XCTFail("Expected mismatch") }
        XCTAssertEqual(id, right.id); XCTAssertGreaterThan(distance, policy.radius)
        XCTAssertNil(policy.evaluate(pose: right.pose, anchors: [right], now: 11, lastKey: 0, lastMouse: 0, current: right.id))
        XCTAssertEqual(policy.state, .alreadyFocused(right.id))
    }
}


extension FocusPolicyTests {
    func testSideBySideScreensAllowOrdinaryNoddingAndReturnTrip() {
        var policy = FocusPolicy(); policy.dwell = 0.3; policy.pitchWeight = 0.35
        let lookingRight = Pose(yaw: right.pose.yaw, pitch: 0.2)
        XCTAssertNil(policy.evaluate(pose: lookingRight, anchors: [left, right], now: 10, lastKey: 0, lastMouse: 0, current: left.id))
        XCTAssertEqual(policy.evaluate(pose: lookingRight, anchors: [left, right], now: 10.31, lastKey: 0, lastMouse: 0, current: left.id), right.id)
        let lookingLeft = Pose(yaw: left.pose.yaw, pitch: -0.2)
        XCTAssertNil(policy.evaluate(pose: lookingLeft, anchors: [left, right], now: 11, lastKey: 0, lastMouse: 0, current: right.id))
        XCTAssertEqual(policy.evaluate(pose: lookingLeft, anchors: [left, right], now: 11.31, lastKey: 0, lastMouse: 0, current: right.id), left.id)
    }
    func testVerticalScreenMatchingRetainsPitchSeparation() {
        var policy = FocusPolicy(); policy.dwell = 0.3
        let upper = FocusTarget(name: "Upper", displayID: 3, pose: Pose(yaw: 0, pitch: -0.3))
        let lower = FocusTarget(name: "Lower", displayID: 4, pose: Pose(yaw: 0, pitch: 0.3))
        XCTAssertNil(policy.evaluate(pose: lower.pose, anchors: [upper, lower], now: 10, lastKey: 0, lastMouse: 0, current: upper.id))
        XCTAssertEqual(policy.evaluate(pose: lower.pose, anchors: [upper, lower], now: 10.31, lastKey: 0, lastMouse: 0, current: upper.id), lower.id)
    }
}


extension FocusPolicyTests {
    func testFastDwellStillRejectsBriefGlancesAndAllowsBothDirections() {
        var policy = FocusPolicy(); policy.dwell = 0.15
        XCTAssertNil(policy.evaluate(pose: right.pose, anchors: [left, right], now: 10, lastKey: 0, lastMouse: 0, current: left.id))
        XCTAssertNil(policy.evaluate(pose: right.pose, anchors: [left, right], now: 10.14, lastKey: 0, lastMouse: 0, current: left.id))
        XCTAssertEqual(policy.evaluate(pose: right.pose, anchors: [left, right], now: 10.151, lastKey: 0, lastMouse: 0, current: left.id), right.id)
        XCTAssertNil(policy.evaluate(pose: left.pose, anchors: [left, right], now: 11, lastKey: 0, lastMouse: 0, current: right.id))
        XCTAssertEqual(policy.evaluate(pose: left.pose, anchors: [left, right], now: 11.151, lastKey: 0, lastMouse: 0, current: right.id), left.id)
        XCTAssertNil(policy.evaluate(pose: right.pose, anchors: [left, right], now: 12, lastKey: 11.9, lastMouse: 0, current: left.id))
        XCTAssertEqual(policy.state, .typing)
    }
}
