import XCTest
@testable import FocusCore

final class StabilityTests: XCTestCase {
    func testBothSuppliedPosturesSelectForegroundFace() {
        XCTAssertEqual(FaceSelection.dominant(in: [
            FaceCandidate(area: 0.04919, confidence: 0.786),
            FaceCandidate(area: 0.00391, confidence: 0.662)
        ]), 0)
        XCTAssertEqual(FaceSelection.dominant(in: [
            FaceCandidate(area: 0.00375, confidence: 0.715),
            FaceCandidate(area: 0.06285, confidence: 0.866)
        ]), 1)
    }
    func testProfileConfidenceObservedDuringLiveTrackingIsAccepted() {
        XCTAssertEqual(FaceSelection.dominant(in: [FaceCandidate(area: 0.05, confidence: 0.68), FaceCandidate(area: 0.004, confidence: 0.8)]), 0)
    }
    func testBackgroundFaceAloneAndAmbiguousFacesNeverControlFocus() {
        XCTAssertNil(FaceSelection.dominant(in: [FaceCandidate(area: 0.00375, confidence: 0.715)]))
        XCTAssertNil(FaceSelection.dominant(in: [FaceCandidate(area: 0.05, confidence: 0.9), FaceCandidate(area: 0.04, confidence: 0.9)]))
        XCTAssertNil(FaceSelection.dominant(in: [FaceCandidate(area: 0.05, confidence: 0.5)]))
    }
    func testSavedPosturesSurviveRestartAndDamagedLatestRecord() throws {
        let name = "LookFocusTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = CalibrationStore(defaults: defaults)
        var target = FocusTarget(name: "Screen", displayID: 1, pose: Pose(yaw: 0, pitch: 0))
        target.additionalPoses = [Pose(yaw: 0.1, pitch: 0.3)]
        store.save([target])
        store.save([target])
        XCTAssertEqual(CalibrationStore(defaults: defaults).load().first?.sampleCount, 2)
        defaults.set(Data("damaged".utf8), forKey: "anchors")
        XCTAssertEqual(store.load().first?.id, target.id)
        XCTAssertEqual(store.load().first?.sampleCount, 2)
        store.save([])
        XCTAssertTrue(store.load().isEmpty, "Explicit removal must not resurrect backup targets")
    }
}
