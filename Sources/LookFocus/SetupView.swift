import SwiftUI
import AppKit

struct SetupView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "eye.circle.fill").font(.system(size: 44)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("LookFocus").font(.largeTitle.weight(.semibold))
                    Text("Turn toward your work. Let focus follow.").foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.trackingAction) {
                    model.toggle()
                    if model.running { model.setupWindow?.orderOut(nil) }
                }.buttonStyle(.borderedProminent).disabled(model.calibrating || (!model.running && model.availableTargets.isEmpty))
            }.padding(24)
            Divider()
            Label(model.status, systemImage: model.running ? "viewfinder" : "info.circle")
                .font(.headline)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Everything runs on this Mac. Camera frames are never saved. No account or license key.")
                        .font(.callout).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Allow access").font(.title3.weight(.semibold))
                        HStack {
                            Label("Camera", systemImage: model.cameraGranted ? "checkmark.circle.fill" : "video")
                            Spacer()
                            Button(model.cameraGranted || model.cameraPermissionDenied ? "Camera settings" : "Allow camera") {
                                if model.cameraGranted { model.openPrivacy("Privacy_Camera") }
                                else { model.requestCamera() }
                            }
                        }
                        HStack {
                            Label("Accessibility", systemImage: model.accessibilityGranted ? "checkmark.circle.fill" : "hand.raised")
                            Spacer()
                            Button(model.accessibilityGranted ? "Accessibility settings" : "Allow Accessibility") {
                                WindowFocus.requestAccess(); model.openPrivacy("Privacy_Accessibility")
                            }
                        }
                        if !model.accessibilityGranted {
                            Text("If LookFocus is already on in Accessibility settings, remove its entry and add the installed app again. Your calibration stays saved.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Text("Camera reads your head direction. Accessibility brings your target window forward and detects typing.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Teach it your targets").font(.title3.weight(.semibold))
                            Spacer()
                            Button("Add window target…") { model.calibrateWindow() }
                                .disabled(model.calibrating || !model.accessibilityGranted)
                        }
                        Text("Calibrate each display, then add samples while sitting normally, slightly lower, or leaning. Keep looking at the same screen’s dot. Every posture sample belongs to that screen.")
                            .font(.callout).foregroundStyle(.secondary)
                        ForEach(model.screens, id: \.displayID) { screen in
                            let target = model.anchors.first { $0.displayID == screen.displayID && $0.bundleID == nil }
                            HStack {
                                Image(systemName: "display").frame(width: 24)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(screen.localizedName)
                                    if let target {
                                        Text(target.sampleCount == 1 ? "1 posture sample" : "\(target.sampleCount) posture samples")
                                            .font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        Text("Not calibrated").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if let target {
                                    Button("Test focus") { model.testFocus(target) }.disabled(model.calibrating || !model.accessibilityGranted)
                                }
                                Button(target == nil ? "Calibrate" : "Add sample") { model.calibrate(screen: screen) }.disabled(model.calibrating)
                            }
                        }
                        if !model.availableTargets.isEmpty {
                            ForEach(model.anchors) { anchor in
                                HStack {
                                    Label(anchor.name, systemImage: anchor.bundleID == nil ? "display" : "macwindow")
                                        .lineLimit(1).help(anchor.name)
                                    Spacer()
                                    if anchor.sampleCount > 1 {
                                        Button("Undo last sample") { model.undoLastSample(targetID: anchor.id) }
                                            .disabled(model.calibrating)
                                    }
                                    Button(role: .destructive) {
                                        model.pause(); model.anchors.removeAll { $0.id == anchor.id }
                                    } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless).help("Remove target").accessibilityLabel("Remove \(anchor.name)")
                                }.font(.callout)
                            }
                        }
                        Text("Use head turns, not eye movements alone. Nearby targets may be too close to distinguish. Split panes are not supported in this version.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tracking details").font(.title3.weight(.semibold))
                        Toggle("Show live screen indicator", isOn: $model.showDebugIndicator)
                        Text("Green highlights a clear screen match; orange means uncertain. The label explains why switching is held. It never takes clicks or keyboard focus.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(model.trackingDetails).font(.caption).textSelection(.enabled)
                        Text("Detection: \(model.detectionRate, specifier: "%.1f") readings/s · \(model.detectionMilliseconds, specifier: "%.0f") ms processing").font(.caption)
                        Text(model.lastFocusResult).font(.callout).textSelection(.enabled)
                        Text("Test focus checks window switching without the camera. Live tracking shows the detected direction and its distance from each saved screen sample.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Where to run").font(.title3.weight(.semibold))
                        Toggle("Work setup only", isOn: Binding(
                            get: { model.workPolicy.monitorID != nil },
                            set: { model.setWorkOnly($0) }
                        )).disabled(model.calibrating || (model.workPolicy.monitorID == nil && model.workMonitors.isEmpty))
                        if model.workPolicy.monitorID != nil {
                            Text("Work monitor: \(model.workMonitorName). The camera stays off without it. Tracking resumes on reconnect if it was running; manual pause stays paused.")
                                .font(.callout).foregroundStyle(.secondary)
                        } else {
                            Text("Use your connected external monitor to recognize your work setup. No location permission is needed.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Make it comfortable").font(.title3.weight(.semibold))
                        Picker("Camera", selection: $model.cameraID) {
                            ForEach(model.devices, id: \.uniqueID) { camera in
                                Text(camera.localizedName).tag(camera.uniqueID)
                            }
                        }.disabled(model.calibrating)
                        HStack {
                            Text("Hold before switching")
                            Slider(value: $model.dwell, in: 0.15...1.5, step: 0.05)
                            Text(model.dwell, format: .number.precision(.fractionLength(2)))
                                .monospacedDigit().frame(width: 42)
                            Text("s").foregroundStyle(.secondary)
                        }
                        Toggle("Move the pointer to the focused window", isOn: $model.movePointer)
                        Toggle("Battery saver", isOn: $model.batterySaver)
                        Text("Saver lowers detection rates and turns the camera off after 2 minutes without keyboard or mouse activity. Keyboard or mouse activity resumes it. Turn saver off for faster detection and uninterrupted reading.")
                            .font(.callout).foregroundStyle(.secondary)
                        Toggle("Open at login (starts paused)", isOn: Binding(get: { model.login }, set: { model.setLogin($0) }))
                        Text("Typing holds focus for 0.8 seconds. Mouse activity holds it for 0.4 seconds. The camera stops on pause, lock, and sleep.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }.padding(24)
            }
            Divider()
            HStack {
                Text("Pause or resume anywhere: ⌃⌥⌘P").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { model.setupWindow?.orderOut(nil) }.keyboardShortcut(.escape, modifiers: [])
            }.padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(minWidth: 640, minHeight: 740)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct CalibrationView: View {
    @ObservedObject var model: AppModel
    let title: String
    var selectingWindow = false
    var body: some View {
        VStack(spacing: 14) {
            if selectingWindow {
                Image(systemName: "macwindow").font(.system(size: 28)).foregroundStyle(.tint)
            } else {
                Circle().fill(Color.accentColor).frame(width: 28, height: 28)
            }
            Text(title).font(.headline).multilineTextAlignment(.center)
            Text(model.calibrationText).monospacedDigit()
            HStack(spacing: 12) {
                if !selectingWindow {
                    Label(model.faceFeedback, systemImage: model.pose == nil ? "person.crop.circle.badge.exclamationmark" : "checkmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Cancel") { model.pause(); model.showSetup() }
            }
        }.padding(20).frame(width: 430, height: 210)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
    }
}
