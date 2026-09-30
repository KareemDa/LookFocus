import AppKit
import ApplicationServices
import FocusCore

struct WindowReference {
    let element: AXUIElement
    let app: NSRunningApplication
    let title: String
    let frame: CGRect
}

enum WindowFocusResult {
    case success(String), failed(String)
}

final class WindowFocus {
    private var remembered: [UInt32: WindowReference] = [:]
    static var trusted: Bool { AXIsProcessTrusted() }
    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    static func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }
    static func reference(_ element: AXUIElement, app: NSRunningApplication) -> WindowReference? {
        guard let position = value(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = value(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions), dimensions.width > 80, dimensions.height > 80 else { return nil }
        let title = value(element, kAXTitleAttribute) as? String ?? ""
        return WindowReference(element: element, app: app, title: title, frame: CGRect(origin: point, size: dimensions))
    }
    func frontmost() -> WindowReference? {
        guard Self.trusted, let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !app.isTerminated else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        guard let focused = Self.value(axApp, kAXFocusedWindowAttribute),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return Self.reference(focused as! AXUIElement, app: app)
    }
    func remember(_ window: WindowReference) {
        if let display = Self.display(for: window.frame) { remembered[display] = window }
    }
    static func display(for frame: CGRect) -> UInt32? {
        NSScreen.screens.max { a, b in
            let ar = CGDisplayBounds(a.displayID).intersection(frame)
            let br = CGDisplayBounds(b.displayID).intersection(frame)
            return ar.width * ar.height < br.width * br.height
        }.flatMap { screen in
            CGDisplayBounds(screen.displayID).intersects(frame) ? screen.displayID : nil
        }
    }
    private func windows(for app: NSRunningApplication) -> [WindowReference] {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        guard let windows = Self.value(axApp, kAXWindowsAttribute) as? [AXUIElement] else { return [] }
        return windows.compactMap { element in
            if Self.value(element, kAXMinimizedAttribute) as? Bool == true { return nil }
            return Self.reference(element, app: app)
        }
    }
    private func isVisible(_ window: WindowReference) -> Bool {
        let visible = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return visible.contains { item in
            guard item[kCGWindowLayer as String] as? Int == 0,
                  item[kCGWindowOwnerPID as String] as? Int32 == window.app.processIdentifier,
                  let bounds = item[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            return abs(window.frame.minX - frame.minX) < 3 && abs(window.frame.minY - frame.minY) < 3 &&
                abs(window.frame.width - frame.width) < 3 && abs(window.frame.height - frame.height) < 3
        }
    }
    private func resolve(_ anchor: FocusTarget) -> WindowReference? {
        if let bundle = anchor.bundleID {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else { return nil }
            // A saved window target matches its exact title; never silently focus a different document.
            let matches = windows(for: app).filter { $0.title == anchor.windowTitle && Self.display(for: $0.frame) == anchor.displayID }
            guard matches.count == 1, let match = matches.first, isVisible(match) else { return nil }
            return match
        }
        if let remembered = remembered[anchor.displayID], !remembered.app.isTerminated,
           let fresh = Self.reference(remembered.element, app: remembered.app),
           Self.display(for: fresh.frame) == anchor.displayID,
           Self.value(fresh.element, kAXMinimizedAttribute) as? Bool != true, isVisible(fresh) { return fresh }
        // Core Graphics provides visible front-to-back windows; AX performs the actual focus.
        let visible = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for item in visible {
            guard item[kCGWindowLayer as String] as? Int == 0,
                  let pid = item[kCGWindowOwnerPID as String] as? Int32,
                  pid != ProcessInfo.processInfo.processIdentifier,
                  let bounds = item[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  Self.display(for: frame) == anchor.displayID,
                  let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular else { continue }
            if let match = windows(for: app).first(where: {
                abs($0.frame.minX - frame.minX) < 3 && abs($0.frame.minY - frame.minY) < 3 &&
                abs($0.frame.width - frame.width) < 3 && abs($0.frame.height - frame.height) < 3
            }) { return match }
        }
        return nil
    }
    func focus(_ anchor: FocusTarget, movePointer: Bool) -> WindowFocusResult {
        guard Self.trusted else { return .failed("Accessibility is unavailable") }
        guard let window = resolve(anchor) else { return .failed("No accessible visible window on \(anchor.name)") }
        let app = AXUIElementCreateApplication(window.app.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.25)
        let raised = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        guard raised == .success else { return .failed("Window could not be raised (\(raised.rawValue))") }
        // Accessibility focus is the authorized system-level path; AppKit activation is a request.
        let frontmost = AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        if !window.app.isActive && frontmost != .success {
            NSApp.yieldActivation(to: window.app)
            guard window.app.activate(from: .current, options: []) else {
                return .failed("\(window.app.localizedName ?? anchor.name) refused activation")
            }
        }
        _ = AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, window.element)
        _ = AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        if movePointer {
            let error = CGWarpMouseCursorPosition(CGPoint(x: window.frame.midX, y: window.frame.midY))
            if error != .success { return .failed("Window activated; pointer could not move (\(error.rawValue))") }
        }
        return .success(window.app.localizedName ?? anchor.name)
    }

}

extension NSScreen {
    var stableDisplayID: String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
    var displayID: UInt32 { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
}
