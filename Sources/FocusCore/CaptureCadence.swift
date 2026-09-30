import Foundation

public enum CaptureMode { case active, settled, holding, calibration }

// Slow expensive inference when it cannot change focus; a valid face immediately restores cadence.
public struct CaptureCadence {
    public var mode: CaptureMode = .active
    public var batterySaver = false
    private var missingSince: Double?
    public init() {}
    public mutating func observe(hasPose: Bool, at time: Double) {
        if hasPose { missingSince = nil }
        else if missingSince == nil { missingSince = time }
    }
    public func interval(at time: Double) -> Double {
        if mode == .calibration { return 0.10 }
        if let missingSince, time - missingSince >= 2 { return batterySaver ? 1.0 : 0.50 }
        switch mode {
        case .active: return batterySaver ? 0.125 : 1.0 / 15
        case .settled: return batterySaver ? 0.25 : 2.0 / 15
        case .holding: return batterySaver ? 0.50 : 0.20
        case .calibration: return 0.10
        }
    }
}
