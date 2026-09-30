import Foundation

public struct CalibrationStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults) { self.defaults = defaults }
    public func load() -> [FocusTarget] {
        for key in ["anchors", "anchorsBackup"] {
            if let data = defaults.data(forKey: key), let targets = try? JSONDecoder().decode([FocusTarget].self, from: data) { return targets }
        }
        return []
    }
    public func save(_ targets: [FocusTarget]) {
        guard let data = try? JSONEncoder().encode(targets) else { return }
        if let previous = defaults.data(forKey: "anchors"),
           let decoded = try? JSONDecoder().decode([FocusTarget].self, from: previous), !decoded.isEmpty {
            defaults.set(previous, forKey: "anchorsBackup")
        }
        defaults.set(data, forKey: "anchors")
    }
}
