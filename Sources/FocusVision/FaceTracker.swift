import Foundation
import Vision
import ImageIO
import CoreVideo
import FocusCore

// A spatial lock follows the foreground face; it does not identify a person.
public final class FaceTracker {
    private let detector = VNDetectFaceRectanglesRequest()
    private let landmarks = VNDetectFaceLandmarksRequest()
    private var sequence = VNSequenceRequestHandler()
    private var tracking: VNTrackObjectRequest?
    private var lastFace: CGRect?
    private var lastSeen = -Double.infinity

    public init() { detector.revision = VNDetectFaceRectanglesRequestRevision3 }

    public func reset() {
        tracking = nil
        lastFace = nil
        lastSeen = -Double.infinity
        sequence = VNSequenceRequestHandler()
    }

    public func process(_ buffer: CVPixelBuffer, at time: Double) throws -> (Pose?, String) {
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)
        return try process(handler, at: time) { request in
            try self.sequence.perform([request], on: buffer, orientation: .up)
        }
    }

    // Also used to verify the real Vision pipeline against owner-supplied photographs.
    public func process(_ url: URL, at time: Double) throws -> (Pose?, String) {
        let handler = VNImageRequestHandler(url: url, options: [:])
        return try process(handler, at: time) { request in
            try self.sequence.perform([request], onImageURL: url, orientation: .up)
        }
    }

    private func process(_ handler: VNImageRequestHandler, at time: Double,
                         track: (VNTrackObjectRequest) throws -> Void) throws -> (Pose?, String) {
        if time - lastSeen > 1 { reset() }
        var predicted = lastFace
        if let tracking {
            do {
                try track(tracking)
                if let observation = tracking.results?.first as? VNDetectedObjectObservation,
                   observation.confidence >= 0.5,
                   let previous = lastFace,
                   FaceContinuity.select([FaceBounds(rect: observation.boundingBox, confidence: observation.confidence)], near: previous) != nil {
                    predicted = observation.boundingBox
                    tracking.inputObservation = observation
                }
            } catch { self.tracking = nil }
        }
        detector.regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
        try handler.perform([detector])
        let faces = detector.results ?? []
        let selected: Int?
        if let predicted {
            selected = FaceContinuity.select(faces.map { FaceBounds(rect: $0.boundingBox, confidence: $0.confidence) }, near: predicted)
        } else {
            selected = FaceSelection.dominant(in: faces.map {
                FaceCandidate(area: $0.boundingBox.width * $0.boundingBox.height, confidence: $0.confidence)
            })
        }
        if let selected { return try accept(faces[selected], at: time, track: track, recovered: false) }

        // Never use a crop to bypass the two-foreground-face guard.
        if FaceContinuity.hasCompetingFaces(faces.map { FaceBounds(rect: $0.boundingBox, confidence: $0.confidence) }) {
            reset()
            return (nil, "Two foreground faces · focus held")
        }
        if let predicted {
            detector.regionOfInterest = predicted.insetBy(dx: -predicted.width * 0.6, dy: -predicted.height * 0.6)
                .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            try handler.perform([detector])
            let cropped = detector.results ?? []
            if let index = FaceContinuity.select(cropped.map { FaceBounds(rect: $0.boundingBox, confidence: $0.confidence) }, near: predicted) {
                let face = cropped[index]
                landmarks.inputFaceObservations = [face]
                try handler.perform([landmarks])
                if let points = landmarks.results?.first?.landmarks,
                   points.nose?.pointCount ?? 0 > 0,
                   (points.leftEye?.pointCount ?? 0) + (points.rightEye?.pointCount ?? 0) > 0 {
                    return try accept(face, at: time, track: track, recovered: true)
                }
            }
            return (nil, "Finding your face again · focus held")
        }
        return (nil, faces.isEmpty ? "No face detected" : "Face uncertain · face the camera briefly")
    }

    private func accept(_ face: VNFaceObservation, at time: Double,
                        track: (VNTrackObjectRequest) throws -> Void, recovered: Bool) throws -> (Pose?, String) {
        guard let yaw = face.yaw?.doubleValue, let pitch = face.pitch?.doubleValue,
              yaw.isFinite, pitch.isFinite else { return (nil, "Face found · head direction unavailable") }
        lastFace = face.boundingBox
        lastSeen = time
        // Seed on this frame so the next processed frame has real image history.
        if tracking == nil {
            let request = VNTrackObjectRequest(detectedObjectObservation: face)
            request.trackingLevel = .fast
            do {
                try track(request)
                tracking = request
            } catch {
                // A valid fresh pose remains usable even if optional box tracking fails.
                tracking = nil
            }
        } else {
            tracking?.inputObservation = face
        }
        return (Pose(yaw: yaw, pitch: pitch), recovered ? "Face recovered locally" : "Face tracked locally")
    }
}
