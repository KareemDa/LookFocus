import XCTest
import CoreGraphics
import FocusCore
import FocusVision
import ImageIO
import UniformTypeIdentifiers

final class FaceContinuityTests: XCTestCase {
    let original = CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.3)
    func testLockedFaceCanTurnWithLowerConfidence() {
        let turned = FaceBounds(rect: original.offsetBy(dx: 0.04, dy: -0.02), confidence: 0.51)
        XCTAssertEqual(FaceContinuity.select([turned], near: original), 0)
        XCTAssertNil(FaceSelection.dominant(in: [FaceCandidate(area: 0.06, confidence: 0.51)]))
    }
    func testLockCannotJumpToBackgroundOrDistantFace() {
        XCTAssertNil(FaceContinuity.select([
            FaceBounds(rect: CGRect(x: 0.1, y: 0.3, width: 0.05, height: 0.08), confidence: 0.9),
            FaceBounds(rect: original.offsetBy(dx: 0.5, dy: 0), confidence: 0.9)
        ], near: original))
    }
    func testCompetingForegroundFacesHoldFocus() {
        XCTAssertNil(FaceContinuity.select([
            FaceBounds(rect: original, confidence: 0.9),
            FaceBounds(rect: original.offsetBy(dx: 0.3, dy: 0), confidence: 0.8)
        ], near: original))
    }
    func testSuppliedPhotographsProduceFreshAnglesAcrossHeadTurn() throws {
        guard let monitor = ProcessInfo.processInfo.environment["LOOKFOCUS_MONITOR_PHOTO"],
              let mac = ProcessInfo.processInfo.environment["LOOKFOCUS_MAC_PHOTO"] else {
            throw XCTSkip("Owner photographs are optional local verification inputs, never bundled")
        }
        let tracker = FaceTracker()
        let first = try XCTUnwrap(tracker.process(URL(fileURLWithPath: monitor), at: 0).0)
        let second = try XCTUnwrap(tracker.process(URL(fileURLWithPath: mac), at: 0.125).0)
        let third = try XCTUnwrap(tracker.process(URL(fileURLWithPath: monitor), at: 0.25).0)
        XCTAssertGreaterThan(abs(first.yaw - second.yaw), 0.5)
        XCTAssertEqual(first.yaw, third.yaw, accuracy: 0.1)
        XCTAssertEqual(first.pitch, third.pitch, accuracy: 0.1)
        let blankURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: blankURL) }
        let context = try XCTUnwrap(CGContext(data: nil, width: 843, height: 434, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 843, height: 434))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(blankURL as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        XCTAssertNil(try tracker.process(blankURL, at: 0.375).0, "Tracking a box must never repeat a stale head angle")
        XCTAssertNil(try tracker.process(blankURL, at: 1.5).0)
        tracker.reset()
        XCTAssertNotNil(try tracker.process(URL(fileURLWithPath: mac), at: 2).0)
    }
}
