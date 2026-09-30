import AppKit
import AVFoundation
import FocusVision
import FocusCore

final class CameraTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "LookFocus.camera", qos: .userInitiated)
    private var cadence = CaptureCadence()
    private var requestedMode: CaptureMode = .active
    private var requestedBatterySaver = false
    private var lastDelivery: Double?
    private var lastFrame: Double = 0
    private let faceTracker = FaceTracker()
    private var configuredDevice: String?
    private var generation = UUID()
    private var activeGeneration = UUID()
    var onPose: ((Pose?, String, Double, Double) -> Void)?
    var onError: ((String) -> Void)?
    static var devices: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external],
                                        mediaType: .video, position: .unspecified).devices
    }
    func setMode(_ mode: CaptureMode) {
        guard requestedMode != mode else { return }
        requestedMode = mode
        queue.async { self.cadence.mode = mode }
    }
    func setBatterySaver(_ enabled: Bool) {
        requestedBatterySaver = enabled
        queue.async { self.cadence.batterySaver = enabled }
    }
    func start(deviceID: String?) {
        generation = UUID()
        let run = generation
        let mode = requestedMode
        let saver = requestedBatterySaver
        queue.async { [self] in
            activeGeneration = run
            lastFrame = 0
            lastDelivery = nil
            faceTracker.reset()
            cadence = CaptureCadence(); cadence.mode = mode; cadence.batterySaver = saver
            do {
                let device = Self.devices.first { $0.uniqueID == deviceID }
                guard let device else { throw NSError(domain: "LookFocus", code: 1, userInfo: [NSLocalizedDescriptionKey: "Selected camera is unavailable. Connect it, or choose another camera and recalibrate."]) }
                if configuredDevice != device.uniqueID {
                    session.beginConfiguration()
                    session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .vga640x480
                    for input in session.inputs { session.removeInput(input) }
                    for output in session.outputs { session.removeOutput(output) }
                    do {
                        let input = try AVCaptureDeviceInput(device: device)
                        guard session.canAddInput(input) else { throw NSError(domain: "LookFocus", code: 2, userInfo: [NSLocalizedDescriptionKey: "Camera is unavailable. Close other camera apps and retry."]) }
                        session.addInput(input)
                        let output = AVCaptureVideoDataOutput()
                        output.alwaysDiscardsLateVideoFrames = true
                        output.setSampleBufferDelegate(self, queue: queue)
                        guard session.canAddOutput(output) else { throw NSError(domain: "LookFocus", code: 3, userInfo: [NSLocalizedDescriptionKey: "Camera video output is unavailable."]) }
                        session.addOutput(output)
                        configuredDevice = device.uniqueID
                        session.commitConfiguration()
                    } catch { session.commitConfiguration(); throw error }
                }
                // Keep image detail while reducing sensor/ISP delivery where the device permits it.
                var rateControlledExternally = false
                if #available(macOS 26.0, *) {
                    rateControlledExternally = device.isVideoFrameDurationLocked || device.isFollowingExternalSyncDevice
                }
                if !rateControlledExternally && device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 15 && $0.maxFrameRate >= 15 }) {
                    do {
                        try device.lockForConfiguration()
                        defer { device.unlockForConfiguration() }
                        if #available(macOS 15.0, *), device.isAutoVideoFrameRateEnabled { device.isAutoVideoFrameRateEnabled = false }
                        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
                        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 15)
                    } catch {
                        // Optional rate limiting must not stop otherwise usable camera capture.
                    }
                }
                if !session.isRunning { session.startRunning() }
            } catch { DispatchQueue.main.async {
                guard self.generation == run else { return }
                self.onError?(error.localizedDescription)
            } }
        }
    }
    func stop() {
        generation = UUID()
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFrame >= cadence.interval(at: now) * 0.95 else { return }
        lastFrame = now
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        do {
            let (pose, feedback) = try faceTracker.process(buffer, at: now)
            deliver(pose, feedback, analysisTime: ProcessInfo.processInfo.systemUptime - now)
        } catch {
            faceTracker.reset()
            deliver(nil, "Camera analysis failed", analysisTime: ProcessInfo.processInfo.systemUptime - now)
        }
    }

    private func deliver(_ pose: Pose?, _ feedback: String, analysisTime: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        let rate = lastDelivery.map { 1 / max(0.001, now - $0) } ?? 0
        lastDelivery = now
        cadence.observe(hasPose: pose != nil, at: ProcessInfo.processInfo.systemUptime)
        let run = activeGeneration
        DispatchQueue.main.async {
            guard self.generation == run else { return }
            self.onPose?(pose, feedback, rate, analysisTime * 1000)
        }
    }
}
