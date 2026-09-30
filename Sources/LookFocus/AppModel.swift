import AppKit
import SwiftUI
import AVFoundation
import ServiceManagement
import Carbon
import FocusCore

final class AppModel: ObservableObject {
    @Published var anchors: [FocusTarget] = [] { didSet { saveAnchors() } }
    @Published private(set) var workPolicy = WorkSetupPolicy()
    @Published private(set) var workMonitorName = "Work monitor"
    @Published private(set) var awayFromWork = false
    @Published var batterySaver = false {
        didSet {
            UserDefaults.standard.set(batterySaver, forKey: "batterySaver")
            tracker.setBatterySaver(batterySaver)
            if !batterySaver { resumeFromIdle() }
        }
    }
    @Published var showDebugIndicator = false {
        didSet {
            UserDefaults.standard.set(showDebugIndicator, forKey: "showDebugIndicator")
            updateDebugIndicator()
        }
    }
    @Published private(set) var idlePaused = false
    @Published private(set) var debugTitle = "Waiting for a face"
    @Published private(set) var debugMatched = false
    @Published private(set) var detectionRate = 0.0
    @Published private(set) var detectionMilliseconds = 0.0
    private var debugDisplayID: UInt32?
    private var debugPanel: NSPanel?
    private var lastActivity = ProcessInfo.processInfo.systemUptime
    @Published var running = false
    @Published var status = "Ready to set up"
    @Published var trackingDetails = "No camera reading yet"
    @Published var lastFocusResult = "No focus attempt yet"
    @Published var pose: Pose?
    @Published var cameraGranted = false
    @Published var accessibilityGranted = false
    @Published var calibrating = false
    @Published var calibrationText = ""
    @Published var devices: [AVCaptureDevice] = CameraTracker.devices
    @Published var screens: [NSScreen] = NSScreen.screens
    @Published var cameraID: String {
        didSet {
            UserDefaults.standard.set(cameraID, forKey: "cameraID")
            if oldValue != cameraID { pause(); anchors = []; status = "Camera changed. Calibrate your targets again." }
        }
    }
    @Published var dwell: Double { didSet { UserDefaults.standard.set(dwell, forKey: "dwell"); policy.reset() } }
    @Published var movePointer: Bool { didSet { UserDefaults.standard.set(movePointer, forKey: "movePointer") } }
    @Published var login = SMAppService.mainApp.status == .enabled
    var setupWindow: NSWindow?
    private let tracker = CameraTracker()
    private let focus = WindowFocus()
    private var policy = FocusPolicy()
    private var timer: Timer?
    private var lastKey = -Double.infinity
    private var lastMouse = -Double.infinity
    private var lastPoseTime = -Double.infinity
    private var current: UUID?
    private var smoothed: Pose?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var hotkey: EventHotKeyRef?
    private var locked = false
    private var sleeping = false
    private var displayLayout: String = ""
    private var calibrationPanel: NSPanel?
    private var calibrationTimer: Timer?
    private var calibration = Calibration()
    @Published var faceFeedback = "Waiting for camera"
    private var lastSampleTime = -Double.infinity

    init() {
        let defaults = UserDefaults.standard
        workPolicy = WorkSetupPolicy(monitorID: defaults.string(forKey: "workMonitorID"))
        workMonitorName = defaults.string(forKey: "workMonitorName") ?? "Work monitor"
        cameraID = defaults.string(forKey: "cameraID") ?? CameraTracker.devices.first?.uniqueID ?? ""
        dwell = defaults.object(forKey: "dwell") as? Double ?? 0.15
        batterySaver = defaults.bool(forKey: "batterySaver")
        showDebugIndicator = defaults.bool(forKey: "showDebugIndicator")
        movePointer = defaults.bool(forKey: "movePointer")
        tracker.setBatterySaver(batterySaver)
        anchors = CalibrationStore(defaults: defaults).load()
        rebindTargetsToDisplays()
        displayLayout = Self.layout()
        // A changed arrangement must never erase the owner’s saved calibration.
        tracker.onPose = { [weak self] pose, feedback, rate, milliseconds in
            self?.detectionRate = rate
            self?.detectionMilliseconds = milliseconds
            self?.faceFeedback = feedback
            self?.received(pose)
        }
        tracker.onError = { [weak self] error in
            self?.pause(); self?.status = error
        }
        installInputMonitors()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 0.15
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.setSleeping(true) }
        nc.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.setLocked(true) }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.setSleeping(false) }
        nc.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.setLocked(false) }
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.setLocked(true) }
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in self?.setLocked(false) }
        for notification in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            NotificationCenter.default.addObserver(forName: notification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.devices = CameraTracker.devices
                if !self.devices.contains(where: { $0.uniqueID == self.cameraID }) {
                    self.pause(); self.status = "Selected camera disconnected. Choose a camera and recalibrate."
                }
            }
        }
        registerShortcut()
        refresh()
        if awayFromWork {
            status = "Away from work · camera off"
        } else if !accessibilityGranted {
            status = "Accessibility is needed before tracking. Enable the installed LookFocus app in System Settings."
        } else if !cameraGranted {
            status = "Allow Camera access before tracking."
        } else if anchors.isEmpty {
            status = "Calibrate your displays before tracking."
        } else {
            status = "Calibration loaded. Ready to start tracking."
        }
    }
    private static func layout() -> String {
        NSScreen.screens.map { "\($0.displayID):\(CGDisplayBounds($0.displayID))" }.sorted().joined(separator: "|")
    }
    private func saveAnchors() {
        CalibrationStore(defaults: .standard).save(anchors)
    }
    private func installInputMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        let mask: NSEvent.EventTypeMask = [.keyDown, .flagsChanged, .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseUp, .rightMouseUp, .otherMouseUp]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in self?.activity(event) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in self?.activity(event); return event }
    }
    private func activity(_ event: NSEvent) {
        let now = ProcessInfo.processInfo.systemUptime
        lastActivity = now
        if event.type == .keyDown || event.type == .flagsChanged { lastKey = now } else { lastMouse = now }
        policy.reset()
        resumeFromIdle()
        if running { tracker.setMode(.holding) }
    }
    func refresh() {
        defer { updateDebugIndicator() }
        let wasCameraGranted = cameraGranted
        let wasTrusted = accessibilityGranted
        accessibilityGranted = WindowFocus.trusted
        if accessibilityGranted != wasTrusted { installInputMonitors() }
        cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if !running && !calibrating && (wasTrusted != accessibilityGranted || wasCameraGranted != cameraGranted) {
            if !accessibilityGranted { status = "Allow Accessibility before tracking." }
            else if !cameraGranted { status = "Allow Camera before tracking." }
            else { status = availableTargets.isEmpty ? "Calibrate your displays before tracking." : "Ready to start tracking." }
        }
        let wasAway = awayFromWork
        let layout = Self.layout()
        let connectedScreens = NSScreen.screens
        awayFromWork = !workPolicy.allowsTracking(connectedMonitorIDs: Set(connectedScreens.compactMap(\.stableDisplayID)))
        if layout != displayLayout {
            screens = connectedScreens
            if awayFromWork || wasAway { stopTracking() }
            else { pause() }
            displayLayout = layout
            rebindTargetsToDisplays()
            status = "Displays changed. Saved samples are kept; check calibration before resuming."
        }
        if awayFromWork {
            if running || calibrating { stopTracking() }
            status = workPolicy.trackingRequested
                ? "Away from work · camera off · resumes when your work monitor returns"
                : "Away from work · camera off"
        } else if wasAway {
            status = workPolicy.monitorID == nil ? "Ready to start tracking" : "Work monitor connected · ready to track"
            if workPolicy.trackingRequested { startTracking() }
        }
        if running && (!accessibilityGranted || !cameraGranted) {
            pause(); status = "Permission is missing. Enable Camera and Accessibility, then resume."
        }
        if running && !calibrating && !locked && !sleeping {
            let idle = ProcessInfo.processInfo.systemUptime - lastActivity
            if !idlePaused && BatteryIdlePolicy.shouldPause(enabled: batterySaver, idleSeconds: idle) {
                idlePaused = true
                tracker.stop(); policy.reset(); smoothed = nil; pose = nil
            }
            if idlePaused { status = "Battery saver · camera off after 2 minutes idle · use keyboard or mouse to resume" }
        }
        if running && !calibrating && !idlePaused {
            let now = ProcessInfo.processInfo.systemUptime
            let held = now - lastKey < policy.typingPause || now - lastMouse < policy.mousePause || (setupWindow?.isVisible == true && NSApp.isActive)
            if held { tracker.setMode(.holding) }
            else if case .alreadyFocused = policy.state { tracker.setMode(.settled) }
            else { tracker.setMode(.active) }
        }
        if running && !idlePaused, let front = focus.frontmost(), let display = WindowFocus.display(for: front.frame) {
            focus.remember(front)
            current = anchors.first { $0.displayID == display && $0.bundleID == front.app.bundleIdentifier && $0.windowTitle == front.title }?.id
                ?? anchors.first { $0.displayID == display && $0.bundleID == nil }?.id
        } else { current = nil }
    }
    var cameraPermissionDenied: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .denied || status == .restricted
    }
    func requestCamera(completion: (() -> Void)? = nil) {
        if cameraPermissionDenied {
            status = "Camera access is off. Enable LookFocus in System Settings → Privacy & Security → Camera."
            openPrivacy("Privacy_Camera")
            return
        }
        AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
            DispatchQueue.main.async {
                self?.refresh()
                if allowed { completion?() }
                else { self?.status = "Enable LookFocus in System Settings → Privacy & Security → Camera." }
            }
        }
    }
    func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
    var workMonitors: [NSScreen] {
        screens.filter { CGDisplayIsBuiltin($0.displayID) == 0 && $0.stableDisplayID != nil }
    }
    func setWorkOnly(_ enabled: Bool) {
        if enabled {
            guard let screen = workMonitors.first, let id = screen.stableDisplayID else {
                status = "Connect your work monitor to enable Work setup only."
                return
            }
            workPolicy.monitorID = id
            workMonitorName = screen.localizedName
            UserDefaults.standard.set(id, forKey: "workMonitorID")
            UserDefaults.standard.set(workMonitorName, forKey: "workMonitorName")
        } else {
            workPolicy.monitorID = nil
            UserDefaults.standard.removeObject(forKey: "workMonitorID")
        }
        refresh()
    }
    private func rebindTargetsToDisplays() {
        var updated = anchors
        var changed = false
        for index in updated.indices {
            let target = updated[index]
            if let id = target.displayUUID {
                if let screen = screens.first(where: { $0.stableDisplayID == id }), target.displayID != screen.displayID {
                    updated[index].displayID = screen.displayID
                    changed = true
                }
            } else if let screen = screens.first(where: { $0.displayID == target.displayID }), let id = screen.stableDisplayID {
                updated[index].displayUUID = id
                changed = true
            }
        }
        if changed { anchors = updated }
    }
    var trackingAction: String {
        if running { return "Pause" }
        if awayFromWork && workPolicy.trackingRequested { return "Cancel automatic resume" }
        return "Start tracking"
    }
    func toggle() {
        if running || (awayFromWork && workPolicy.trackingRequested) { pause() }
        else { resume() }
    }
    func resume() {
        refresh()
        startTracking()
    }
    private func startTracking() {
        guard !running else { return }
        guard !awayFromWork else { status = "Away from work · camera off"; return }
        guard accessibilityGranted else {
            status = "Accessibility is not active for this build. Remove LookFocus in Accessibility settings, then add the installed app again."
            return
        }
        guard cameraGranted else { status = "Allow Camera access before starting."; return }
        guard globalMonitor != nil else { status = "Input monitoring is unavailable. Reopen LookFocus before starting."; return }
        guard !availableTargets.isEmpty else { status = "Calibrate a connected display before starting."; return }
        guard !locked, !sleeping else { status = "Waiting for your Mac to unlock."; return }
        workPolicy.requestTracking()
        idlePaused = false
        lastActivity = ProcessInfo.processInfo.systemUptime
        debugTitle = "Waiting for a face"; debugMatched = false; debugDisplayID = nil
        running = true; policy.reset(); lastKey = ProcessInfo.processInfo.systemUptime
        status = "Waiting for a face"
        tracker.setMode(.active)
        tracker.start(deviceID: cameraID)
        updateDebugIndicator()
    }
    func pause() {
        workPolicy.pause()
        stopTracking()
        if awayFromWork { status = "Away from work · camera off" }
    }
    private func stopTracking() {
        idlePaused = false
        running = false; cancelCalibration(); tracker.stop(); policy.reset(); smoothed = nil
        status = "Paused · camera off"
        updateDebugIndicator()
    }
    private func setSleeping(_ value: Bool) { sleeping = value; updateSuspension() }
    private func setLocked(_ value: Bool) { locked = value; updateSuspension() }
    private func updateSuspension() {
        defer { updateDebugIndicator() }
        if locked || sleeping {
            cancelCalibration(); tracker.stop(); policy.reset(); smoothed = nil
            status = "Suspended · camera off"
        } else {
            lastKey = ProcessInfo.processInfo.systemUptime; policy.reset()
            if running && !awayFromWork && !idlePaused { tracker.start(deviceID: cameraID); status = "Waiting for a face" }
            else if !running && workPolicy.trackingRequested && !awayFromWork { startTracking() }
        }
    }
    var availableTargets: [FocusTarget] {
        let connected = Set(screens.map(\.displayID))
        return anchors.filter { connected.contains($0.displayID) }
    }
    private func resumeFromIdle() {
        guard running, idlePaused, !awayFromWork, !locked, !sleeping,
              cameraGranted, accessibilityGranted else { return }
        idlePaused = false
        lastActivity = ProcessInfo.processInfo.systemUptime
        policy.reset(); smoothed = nil; pose = nil
        debugTitle = "Waiting for a face"; debugMatched = false
        tracker.setMode(.holding)
        tracker.start(deviceID: cameraID)
        status = "Activity detected · camera resuming"
        updateDebugIndicator()
    }
    private func updateDebugIndicator() {
        guard showDebugIndicator, running, !calibrating, !idlePaused, !locked, !sleeping, !awayFromWork else {
            debugPanel?.orderOut(nil)
            return
        }
        guard let screen = screens.first(where: { $0.displayID == debugDisplayID }) ?? NSScreen.main else { return }
        if debugPanel == nil {
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear
            panel.hasShadow = false; panel.ignoresMouseEvents = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            let content = DebugHostingView(rootView: DebugIndicator(model: self))
            content.wantsLayer = true
            content.layer?.backgroundColor = NSColor.clear.cgColor
            panel.contentView = content
            debugPanel = panel
        }
        if debugPanel?.frame != screen.frame { debugPanel?.setFrame(screen.frame, display: true) }
        if debugPanel?.isVisible == false { debugPanel?.orderFrontRegardless() }
    }
    private func received(_ value: Pose?) {
        defer { updateDebugIndicator() }
        guard !locked, !sleeping, !idlePaused, running || calibrating else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if calibrating { pose = value; if value != nil { lastPoseTime = now }; return }
        let xCenters = screens.map { $0.frame.midX }; let yCenters = screens.map { $0.frame.midY }
        let horizontalSpan = (xCenters.max() ?? 0) - (xCenters.min() ?? 0)
        let verticalSpan = (yCenters.max() ?? 0) - (yCenters.min() ?? 0)
        policy.pitchWeight = screens.count > 1 && horizontalSpan > 2 * verticalSpan ? 0.35 : 1.3
        if let value {
            let previous = now - lastPoseTime <= 0.25 ? (smoothed ?? value) : value
            let filtered = Pose(yaw: previous.yaw * 0.4 + value.yaw * 0.6, pitch: previous.pitch * 0.4 + value.pitch * 0.6)
            smoothed = filtered; pose = filtered; lastPoseTime = now
            if let match = policy.match(pose: filtered, anchors: availableTargets),
               let target = availableTargets.first(where: { $0.id == match.targetID }) {
                debugDisplayID = target.displayID
                debugMatched = match.distance <= policy.radius && !match.ambiguous
                debugTitle = debugMatched ? "Looking toward: \(target.name)" : "Uncertain · closest: \(target.name)"
            } else { debugTitle = "No calibrated screen"; debugMatched = false; debugDisplayID = nil }
            let matches = availableTargets.map { "\($0.name): \(String(format: "%.2f", $0.distance(to: filtered, pitchWeight: policy.pitchWeight)))" }.joined(separator: " · ")
            trackingDetails = String(format: "Head %.0f° / %.0f° · ", filtered.yaw * 180 / .pi, filtered.pitch * 180 / .pi) + matches + " · match limit 0.20"
        } else { pose = nil; trackingDetails = faceFeedback; debugTitle = faceFeedback; debugMatched = false; debugDisplayID = nil }
        guard accessibilityGranted, cameraGranted else { policy.reset(); return }
        if setupWindow?.isVisible == true && NSApp.isActive { policy.reset(); tracker.setMode(.holding); status = "Setup open · use Done to allow switching"; return }
        if NSEvent.pressedMouseButtons != 0 || !NSEvent.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            policy.reset(); tracker.setMode(.holding); status = "Button or shortcut held · focus held"; return
        }
        policy.dwell = dwell
        var effectiveCurrent = current
        if movePointer, let target = anchors.first(where: { $0.id == current }),
           !screens.contains(where: { $0.displayID == target.displayID && $0.frame.contains(NSEvent.mouseLocation) }) {
            effectiveCurrent = nil
        }
        let selected = policy.evaluate(pose: pose, anchors: availableTargets, now: now, lastKey: lastKey, lastMouse: lastMouse, current: effectiveCurrent)
        func name(_ id: UUID) -> String { anchors.first { $0.id == id }?.name ?? "target" }
        switch policy.state {
        case .alreadyFocused: tracker.setMode(.settled)
        case .typing, .mouse: tracker.setMode(.holding)
        default: tracker.setMode(.active)
        }
        switch policy.state {
        case .idle: status = "No calibrated connected screen"
        case .noFace: status = "\(faceFeedback) · focus held"
        case .typing: status = "Typing · focus held briefly"
        case .mouse: status = "Mouse active · focus held briefly"
        case .ambiguous: status = "Between targets · turn toward one screen"
        case .outsideCalibration(let id, _): status = "Head direction outside saved samples · closest: \(name(id))"
        case .alreadyFocused(let id): status = "Already focused: \(name(id))"
        case .dwelling(let id, let progress): status = "Looking at \(name(id)) · \(Int(progress * 100))% ready"
        case .switchTo(let id): status = "Switching to \(name(id))"
        }
        if let selected, let target = anchors.first(where: { $0.id == selected }) { performFocus(target) }
    }
    private func performFocus(_ target: FocusTarget) {
        switch focus.focus(target, movePointer: movePointer) {
        case .failed(let reason):
            lastFocusResult = reason; status = reason; lastMouse = ProcessInfo.processInfo.systemUptime
        case .success(let appName):
            current = target.id
            lastFocusResult = "Requested \(appName) on \(target.name)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self else { return }
                if let front = self.focus.frontmost(), WindowFocus.display(for: front.frame) == target.displayID {
                    self.lastFocusResult = "Verified: \(front.app.localizedName ?? appName) on \(target.name)"
                } else {
                    self.lastFocusResult = "Activation was requested but \(target.name) did not become focused"
                }
            }
        }
    }
    func testFocus(_ target: FocusTarget) {
        pause(); setupWindow?.orderOut(nil)
        performFocus(target)
    }
    func calibrate(screen: NSScreen) {
        beginCalibration(screen: screen, windowTarget: false)
    }
    func undoLastSample(targetID: UUID) {
        guard let index = anchors.firstIndex(where: { $0.id == targetID }),
              var extras = anchors[index].additionalPoses, !extras.isEmpty else { return }
        pause()
        extras.removeLast()
        anchors[index].additionalPoses = extras.isEmpty ? nil : extras
        status = "Last posture sample removed. Earlier calibration is kept."
    }
    func calibrateWindow() {
        beginCalibration(screen: nil, windowTarget: true)
    }
    private func beginCalibration(screen: NSScreen?, windowTarget: Bool) {
        refresh()
        guard !awayFromWork else { status = "Connect your work monitor before calibrating · camera off"; return }
        guard !locked, !sleeping else { return }
        guard cameraGranted else {
            requestCamera { [weak self] in self?.beginCalibration(screen: screen, windowTarget: windowTarget) }; return
        }
        if windowTarget && !accessibilityGranted { status = "Allow Accessibility before adding a window target."; return }
        pause(); calibrating = true; calibration = Calibration(); pose = nil; smoothed = nil; lastSampleTime = -.infinity; faceFeedback = "Waiting for camera"
        tracker.setMode(.calibration)
        tracker.start(deviceID: cameraID)
        let started = ProcessInfo.processInfo.systemUptime
        var targetWindow: WindowReference?
        var targetScreen = screen
        var shown = false
        if windowTarget {
            setupWindow?.orderOut(nil)
            calibrationText = "Switch to your target window: 6s"
            guard let instructionScreen = NSScreen.main ?? NSScreen.screens.first else {
                finishCalibration(error: "No display available. Connect a display and retry."); return
            }
            showCalibration(on: instructionScreen, title: "Switch to your target window now. Use ⌘Tab or click its window.", selectingWindow: true)
        }
        else { showCalibration(on: screen!, title: "Look at this dot. Hold your head naturally."); shown = true }
        calibrationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let now = ProcessInfo.processInfo.systemUptime
            let elapsed = now - started
            if windowTarget && !shown && elapsed >= 6 {
                guard let window = self.focus.frontmost(), !window.title.isEmpty, window.app.bundleIdentifier != nil,
                      let displayID = WindowFocus.display(for: window.frame),
                      let selectedScreen = NSScreen.screens.first(where: { $0.displayID == displayID }) else {
                    self.finishCalibration(error: "No named window selected. Switch to the target window and try again."); return
                }
                targetWindow = window; targetScreen = selectedScreen
                self.showCalibration(on: selectedScreen, title: "Look at this window's dot. Hold your head naturally.", windowFrame: window.frame)
                shown = true
            }
            let sampleStart = windowTarget ? 9.0 : 3.0
            if elapsed < sampleStart {
                self.calibrationText = windowTarget && !shown
                    ? "Switch to your target window: \(max(1, Int(ceil(6 - elapsed))))s"
                    : "Settle into your posture: \(Int(ceil(sampleStart - elapsed)))s"
                return
            }
            let fresh = self.pose != nil && now - self.lastPoseTime < 0.3
            self.calibrationText = fresh ? "Hold steady · collecting your sample" : self.faceFeedback
            var mean: Pose?
            if fresh && self.lastPoseTime != self.lastSampleTime {
                mean = self.calibration.observe(self.pose, at: self.lastPoseTime)
                self.lastSampleTime = self.lastPoseTime
            } else if !fresh {
                _ = self.calibration.observe(nil, at: now)
            }
            if let mean, let selectedScreen = targetScreen {
                let replacing = self.anchors.first { $0.displayID == selectedScreen.displayID && $0.bundleID == targetWindow?.app.bundleIdentifier && $0.windowTitle == targetWindow?.title }
                let others = self.anchors.filter { $0.id != replacing?.id }
                guard !others.contains(where: { $0.distance(to: mean) < 0.09 }) else {
                    self.finishCalibration(error: "This direction is too close to another target. Turn your head farther, or remove the overlapping target."); return
                }
                if var existing = replacing, let index = self.anchors.firstIndex(where: { $0.id == existing.id }) {
                    existing.displayUUID = selectedScreen.stableDisplayID
                    existing.additionalPoses = (existing.additionalPoses ?? []) + [mean]
                    self.anchors[index] = existing
                    self.finishCalibration(error: nil)
                    self.status = "Sample added for \(existing.name). \(existing.sampleCount) postures now lead to this target."
                } else {
                    var anchor = FocusTarget(name: targetWindow?.title ?? selectedScreen.localizedName, displayID: selectedScreen.displayID,
                                             pose: mean, bundleID: targetWindow?.app.bundleIdentifier, windowTitle: targetWindow?.title)
                    anchor.displayUUID = selectedScreen.stableDisplayID
                    self.anchors.append(anchor)
                    self.finishCalibration(error: nil)
                }
            } else if elapsed >= sampleStart + 20 {
                let reason = fresh && self.calibration.moved
                    ? "Your head kept moving. Hold your chosen posture steady and try again."
                    : "\(self.faceFeedback). No steady sample was saved. Adjust the camera or lighting and retry."
                self.finishCalibration(error: reason)
            }
        }
    }
    private func showCalibration(on screen: NSScreen, title: String, windowFrame: CGRect? = nil, selectingWindow: Bool = false) {
        calibrationPanel?.close()
        let size = NSSize(width: 430, height: 210)
        var center = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
        if let frame = windowFrame {
            // AX/CG coordinates start at the primary screen's top edge; AppKit starts at its bottom.
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            center = NSPoint(x: frame.midX, y: top - frame.midY)
        }
        let panel = NSPanel(contentRect: NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.contentView = NSHostingView(rootView: CalibrationView(model: self, title: title, selectingWindow: selectingWindow))
        panel.orderFrontRegardless(); calibrationPanel = panel
    }
    func cancelCalibration() {
        calibrationTimer?.invalidate(); calibrationTimer = nil
        calibrationPanel?.close(); calibrationPanel = nil
        if calibrating { calibrating = false; tracker.stop() }
    }
    private func finishCalibration(error: String?) {
        cancelCalibration(); status = error ?? "Target saved. Add another, or start tracking."
        showSetup()
    }
    func showSetup() { setupWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            login = SMAppService.mainApp.status == .enabled
            if enabled && !login { status = "Approve LookFocus in System Settings → General → Login Items." }
        } catch { login = SMAppService.mainApp.status == .enabled; status = "Couldn't change login setting: \(error.localizedDescription)" }
    }
    private func registerShortcut() {
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
            guard let data else { return OSStatus(eventNotHandledErr) }
            let model = Unmanaged<AppModel>.fromOpaque(data).takeUnretainedValue()
            DispatchQueue.main.async { model.toggle() }
            return noErr
        }, 1, &event, pointer, nil)
        let id = EventHotKeyID(signature: 0x4C4F4F4B, id: 1)
        if RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(controlKey | optionKey | cmdKey), id, GetApplicationEventTarget(), 0, &hotkey) != noErr {
            status = "Pause shortcut is in use. Use the menu bar pause control."
        }
    }
}
