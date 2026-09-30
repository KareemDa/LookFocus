import Foundation
import CoreGraphics


public struct FaceBounds {
    public let rect: CGRect
    public let confidence: Float
    public init(rect: CGRect, confidence: Float) { self.rect = rect; self.confidence = confidence }
}

public enum FaceContinuity {
    public static func hasCompetingFaces(_ faces: [FaceBounds]) -> Bool {
        let areas = faces.filter { $0.confidence >= 0.45 && $0.rect.width * $0.rect.height >= 0.015 }
            .map { $0.rect.width * $0.rect.height }.sorted(by: >)
        return areas.count > 1 && areas[0] < areas[1] * 2.5
    }
    public static func select(_ faces: [FaceBounds], near previous: CGRect) -> Int? {
        guard !hasCompetingFaces(faces) else { return nil }
        let previousArea = previous.width * previous.height
        return faces.indices.filter { index in
            let face = faces[index]
            let area = face.rect.width * face.rect.height
            let overlap = face.rect.intersection(previous)
            let intersection = overlap.isNull ? 0 : overlap.width * overlap.height
            let union = area + previousArea - intersection
            return face.confidence >= 0.45 && area >= 0.015 && area >= previousArea * 0.5 && area <= previousArea * 2 && union > 0 && intersection / union >= 0.25
        }.max { faces[$0].confidence < faces[$1].confidence }
    }
}
