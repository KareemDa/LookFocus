import Foundation

// Calibration needs a sustained reading, not a fixed deadline after camera startup.
public struct Calibration {
    private var samples: [(pose: Pose, time: Double)] = []
    public private(set) var moved = false
    public init() {}
    public mutating func observe(_ pose: Pose?, at time: Double) -> Pose? {
        guard let pose else {
            if let last = samples.last, time - last.time > 0.4 { samples = [] }
            return nil
        }
        if let last = samples.last {
            guard time > last.time else { return nil }
            if time - last.time > 0.4 { samples = [] }
        }
        if let first = samples.first, pose.distance(to: first.pose) >= 0.12 {
            samples = []; moved = true
        }
        samples.append((pose, time))
        guard samples.count >= 10, let first = samples.first, time - first.time >= 1 else { return nil }
        return Pose(yaw: samples.map { $0.pose.yaw }.reduce(0, +) / Double(samples.count),
                    pitch: samples.map { $0.pose.pitch }.reduce(0, +) / Double(samples.count))
    }
}
