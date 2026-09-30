import Foundation

public enum BatteryIdlePolicy {
    public static let pauseAfter: Double = 120
    public static func shouldPause(enabled: Bool, idleSeconds: Double) -> Bool {
        enabled && idleSeconds >= pauseAfter
    }
}
