import XCTest
@testable import FocusCore

final class CaptureCadenceTests: XCTestCase {
    func testIdleAndSettledReduceInferenceWithoutChangingActiveCadence() {
        var cadence = CaptureCadence()
        XCTAssertEqual(cadence.interval(at: 0), 1.0 / 15)
        cadence.mode = .settled
        XCTAssertEqual(cadence.interval(at: 0), 2.0 / 15)
        cadence.mode = .holding
        XCTAssertEqual(cadence.interval(at: 0), 0.2)
        cadence.mode = .active
        XCTAssertEqual(cadence.interval(at: 0), 1.0 / 15)
    }
    func testMissingFaceBacksOffAndRecoveryRestoresResponsiveness() {
        var cadence = CaptureCadence()
        cadence.observe(hasPose: false, at: 10)
        cadence.observe(hasPose: false, at: 11)
        XCTAssertEqual(cadence.interval(at: 11.9), 1.0 / 15)
        XCTAssertEqual(cadence.interval(at: 12), 0.5)
        cadence.observe(hasPose: true, at: 12.5)
        XCTAssertEqual(cadence.interval(at: 12.5), 1.0 / 15)
    }
    func testCalibrationKeepsFullSamplingWhileSearchingForFace() {
        var cadence = CaptureCadence(); cadence.mode = .calibration
        cadence.observe(hasPose: false, at: 0)
        XCTAssertEqual(cadence.interval(at: 20), 0.1)
    }
    func testSaverReducesRatesAndKeepsCalibrationSampling() {
        var cadence = CaptureCadence()
        cadence.batterySaver = true
        XCTAssertEqual(cadence.interval(at: 0), 0.125)
        cadence.mode = .settled
        XCTAssertEqual(cadence.interval(at: 0), 0.25)
        cadence.mode = .holding
        XCTAssertEqual(cadence.interval(at: 0), 0.5)
        cadence.observe(hasPose: false, at: 0)
        XCTAssertEqual(cadence.interval(at: 2), 1)
        cadence.mode = .calibration
        XCTAssertEqual(cadence.interval(at: 3), 0.1)
        cadence.mode = .active
        cadence.observe(hasPose: true, at: 4)
        cadence.batterySaver = false
        XCTAssertEqual(cadence.interval(at: 4), 1.0 / 15)
    }
}
