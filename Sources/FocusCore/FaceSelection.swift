import Foundation

public struct FaceCandidate {
    public let area: Double
    public let confidence: Float
    public init(area: Double, confidence: Float) { self.area = area; self.confidence = confidence }
}

// Ignore small background faces; similarly sized foreground faces remain ambiguous.
public enum FaceSelection {
    public static func dominant(in faces: [FaceCandidate]) -> Int? {
        let ranked = faces.indices.sorted { faces[$0].area > faces[$1].area }
        guard let first = ranked.first, faces[first].area >= 0.02, faces[first].confidence >= 0.65 else { return nil }
        if ranked.count > 1 && faces[first].area < faces[ranked[1]].area * 2.5 { return nil }
        return first
    }
}
