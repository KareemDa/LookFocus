import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var model: AppModel!
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 810),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "LookFocus"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SetupView(model: model))
        window.minSize = NSSize(width: 660, height: 600); window.center()
        model.setupWindow = window
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "LookFocus")
        statusItem.button?.toolTip = "LookFocus · personal focus utility"
        let menu = NSMenu(); menu.delegate = self; statusItem.menu = menu
        let appMenu = NSMenu()
        add("Setup & calibration…", action: #selector(setup), to: appMenu)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit LookFocus", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self; appMenu.addItem(quitItem)
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(); appItem.submenu = appMenu; mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
        // Every launch starts paused; the background argument hides setup when requested.
        if !CommandLine.arguments.contains("--background") {
            model.showSetup()
        }
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = NSMenuItem(title: model.status, action: nil, keyEquivalent: ""); status.isEnabled = false; menu.addItem(status)
        menu.addItem(.separator())
        add(model.trackingAction, action: #selector(toggle), to: menu)
        add("Setup & calibration…", action: #selector(setup), to: menu)
        menu.addItem(.separator())
        add("Quit LookFocus", action: #selector(quit), to: menu)
    }
    private func add(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
    }
    @objc private func toggle() { model.toggle() }
    @objc private func setup() { model.showSetup() }
    @objc private func quit() { model.pause(); NSApp.terminate(nil) }
    func applicationDidBecomeActive(_ notification: Notification) {
        guard let model, !model.calibrating, model.setupWindow?.isVisible == false else { return }
        model.showSetup()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { model.showSetup(); return true }
}

@main
struct LookFocusMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
