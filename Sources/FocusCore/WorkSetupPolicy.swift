import Foundation

public struct WorkSetupPolicy {
    public var monitorID: String?
    public private(set) var trackingRequested = false
    public init(monitorID: String? = nil) { self.monitorID = monitorID }
    public func allowsTracking(connectedMonitorIDs: Set<String>) -> Bool {
        guard let monitorID else { return true }
        return connectedMonitorIDs.contains(monitorID)
    }
    public mutating func requestTracking() { trackingRequested = true }
    public mutating func pause() { trackingRequested = false }
}
