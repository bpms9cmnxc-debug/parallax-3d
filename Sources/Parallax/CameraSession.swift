import AVFoundation
import AppKit
import Combine
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import QuartzCore

final class CameraSession: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var errorMessage: String?
    @Published var preview: NSImage?
    @Published var deviceName = "—"

    var onBuffer: ((CVPixelBuffer) -> Void)?

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "parallax.camera", qos: .userInteractive)
    private var lastPreview: CFTimeInterval = 0
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    func start() {
        DispatchQueue.main.async { self.errorMessage = nil }
        queue.async { [weak self] in self?.configureAndRun() }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.output.setSampleBufferDelegate(nil, queue: nil)
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async {
                self.isRunning = false
                self.preview = nil
            }
        }
    }

    private func configureAndRun() {
        if session.isRunning { session.stopRunning() }
        output.setSampleBufferDelegate(nil, queue: nil)
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        } else if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }

        guard let device = preferredDevice() else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.errorMessage = "Keine Kamera gefunden." }
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                DispatchQueue.main.async { self.errorMessage = "Kamera nicht verfügbar." }
                return
            }
            session.addInput(input)
        } catch {
            session.commitConfiguration()
            DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
            return
        }

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.errorMessage = "Kamera nicht verfügbar." }
            return
        }
        session.addOutput(output)
        // Leave the pixel buffer unmirrored so Vision matches the web tracker.
        // The overlay mirrors only the preview.
        session.commitConfiguration()

        session.startRunning()
        let name = device.localizedName
        let running = session.isRunning
        DispatchQueue.main.async {
            self.deviceName = name
            self.isRunning = running
            if !running {
                self.errorMessage = "Kamera konnte nicht gestartet werden."
            }
        }
    }

    private func preferredDevice() -> AVCaptureDevice? {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .continuityCamera, .external]
        if #available(macOS 14.0, *) {
            types.append(.deskViewCamera)
        }
        let found = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .unspecified
        ).devices
        if let front = found.first(where: { $0.deviceType == .builtInWideAngleCamera && $0.position == .front }) {
            return front
        }
        return found.first ?? AVCaptureDevice.default(for: .video)
    }
}

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onBuffer?(pb)
        let now = CACurrentMediaTime()
        if now - lastPreview >= 0.08 {
            lastPreview = now
            // Render while the capture buffer is still valid — CIImage does not copy pixels.
            let ci = CIImage(cvPixelBuffer: pb)
            if let img = Self.makePreview(ci) {
                DispatchQueue.main.async { [weak self] in self?.preview = img }
            }
        }
    }

    private static func makePreview(_ ci: CIImage) -> NSImage? {
        let extent = ci.extent
        guard extent.width > 1, extent.height > 1 else { return nil }
        let scale = min(1, 480 / extent.width)
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let tw = extent.width * scale
        let th = extent.height * scale
        guard let cg = ciContext.createCGImage(scaled, from: CGRect(x: 0, y: 0, width: tw, height: th)) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: tw, height: th))
    }
}
