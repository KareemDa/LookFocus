import XCTest
@testable import FocusCore

final class CalibrationTests: XCTestCase {
    let pose = Pose(yaw: 0.3, pitch: 0.1)
    func testCameraStartupDoesNotConsumeCollectionTime() {
        var calibration = Calibration()
        XCTAssertNil(calibration.observe(nil, at: 3))
        XCTAssertNil(calibration.observe(nil, at: 8))
        for i in 0..<10 { XCTAssertNil(calibration.observe(pose, at: 10 + Double(i) * 0.1)) }
        let result = calibration.observe(pose, at: 11.1)
        XCTAssertEqual(result?.yaw ?? 0, pose.yaw, accuracy: 0.0001)
        XCTAssertEqual(result?.pitch ?? 0, pose.pitch, accuracy: 0.0001)
    }
    func testMissingFaceBreaksSteadyReading() {
        var calibration = Calibration()
        for i in 0..<9 { XCTAssertNil(calibration.observe(pose, at: Double(i) * 0.1)) }
        XCTAssertNil(calibration.observe(nil, at: 1.3))
        XCTAssertNil(calibration.observe(pose, at: 1.4))
    }
    func testMovementRestartsSampleWithoutAveragingAcrossPostures() {
        var calibration = Calibration()
        for i in 0..<9 { XCTAssertNil(calibration.observe(pose, at: Double(i) * 0.1)) }
        let lower = Pose(yaw: 0.3, pitch: 0.4)
        XCTAssertNil(calibration.observe(lower, at: 0.9))
        XCTAssertTrue(calibration.moved)
        for i in 1..<10 { XCTAssertNil(calibration.observe(lower, at: 0.9 + Double(i) * 0.1)) }
        let result = calibration.observe(lower, at: 2.0)
        XCTAssertEqual(result?.yaw ?? 0, lower.yaw, accuracy: 0.0001)
        XCTAssertEqual(result?.pitch ?? 0, lower.pitch, accuracy: 0.0001)
    }
    func testRepeatedFrameCannotCompleteCalibration() {
        var calibration = Calibration()
        for _ in 0..<30 { XCTAssertNil(calibration.observe(pose, at: 1)) }
        XCTAssertNil(calibration.observe(pose, at: 1.1))
    }
}
