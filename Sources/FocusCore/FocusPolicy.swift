import Foundation

public struct Pose: Codable, Equatable {
    public var yaw: Double
    public var pitch: Double
    public init(yaw: Double, pitch: Double) { self.yaw = yaw; self.pitch = pitch }
    public func distance(to other: Pose, pitchWeight: Double = 1.3) -> Double {
        hypot(yaw - other.yaw, (pitch - other.pitch) * pitchWeight)
    }
}

public struct FocusTarget: Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var displayID: UInt32
    public var displayUUID: String?
    public var pose: Pose
    // Existing saved targets have one primary pose; additional postures are additive.
    public var additionalPoses: [Pose]?
    public var sampleCount: Int { 1 + (additionalPoses?.count ?? 0) }
    public func distance(to observed: Pose, pitchWeight: Double = 1.3) -> Double {
        var closest = pose.distance(to: observed, pitchWeight: pitchWeight)
        for sample in additionalPoses ?? [] { closest = min(closest, sample.distance(to: observed, pitchWeight: pitchWeight)) }
        return closest
    }
    public var bundleID: String?
    public var windowTitle: String?
    public init(id: UUID = UUID(), name: String, displayID: UInt32, pose: Pose,
                bundleID: String? = nil, windowTitle: String? = nil) {
        self.id = id; self.name = name; self.displayID = displayID; self.pose = pose
        self.bundleID = bundleID; self.windowTitle = windowTitle
    }
}

public enum FocusState: Equatable {
    case idle, noFace, typing, mouse, ambiguous
    case outsideCalibration(UUID, Double)
    case alreadyFocused(UUID)
    case dwelling(UUID, Double)
    case switchTo(UUID)
}

public struct FocusMatch {
    public let targetID: UUID
    public let distance: Double
    public let ambiguous: Bool
}

// One decision owns matching, dwell and input holds; the UI reports that same decision.
public struct FocusPolicy {
    public var dwell: Double = 0.65
    public var radius: Double = 0.20
    public var pitchWeight: Double = 1.3
    public var typingPause: Double = 0.8
    public var mousePause: Double = 0.4
    public private(set) var candidate: UUID?
    public private(set) var state: FocusState = .idle
    private var since: Double = 0
    private var lastValid: Double?
    public init() {}
    public func match(pose: Pose, anchors: [FocusTarget]) -> FocusMatch? {
        let ranked = anchors.map { ($0.id, $0.distance(to: pose, pitchWeight: pitchWeight)) }.sorted { $0.1 < $1.1 }
        guard let best = ranked.first else { return nil }
        return FocusMatch(targetID: best.0, distance: best.1,
                          ambiguous: ranked.count > 1 && ranked[1].1 - best.1 < 0.045)
    }
    public mutating func reset() { candidate = nil; since = 0; lastValid = nil; state = .idle }
    private mutating func hold(_ reason: FocusState) { reset(); state = reason }
    public mutating func evaluate(pose: Pose?, anchors: [FocusTarget], now: Double,
                                  lastKey: Double, lastMouse: Double, current: UUID?) -> UUID? {
        if now - lastKey < typingPause { hold(.typing); return nil }
        if now - lastMouse < mousePause { hold(.mouse); return nil }
        guard let pose else {
            // Brief detector gaps may pause a candidate, but never trigger a switch with stale data.
            if let lastValid { if now - lastValid > 0.25 { reset() } }
            else { reset() }
            state = .noFace; return nil
        }
        lastValid = now
        guard let best = match(pose: pose, anchors: anchors) else { hold(.idle); return nil }
        guard best.distance <= radius else { hold(.outsideCalibration(best.targetID, best.distance)); return nil }
        if best.ambiguous { hold(.ambiguous); return nil }
        guard best.targetID != current else { hold(.alreadyFocused(best.targetID)); return nil }
        if candidate != best.targetID { candidate = best.targetID; since = now }
        let progress = min(1, max(0, (now - since) / dwell))
        guard progress >= 1 else { state = .dwelling(best.targetID, progress); return nil }
        hold(.switchTo(best.targetID))
        return best.targetID
    }
}
