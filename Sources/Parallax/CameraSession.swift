import AVFoundation
import AppKit
import Combine
import CoreMedia
import CoreVideo
import Foundation

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
    private let previewQueue = DispatchQueue(label: "parallax.preview", qos: .utility)

    func start() {
        DispatchQueue.main.async { self.errorMessage = nil }
        queue.async { [weak self] in self?.configureAndRun() }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async {
                self.isRunning = false
                self.preview = nil
            }
        }
    }

    private func configureAndRun() {
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
            if session.canAddInput(input) { session.addInput(input) }
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
        if session.canAddOutput(output) { session.addOutput(output) }

        if let conn = output.connection(with: .video), conn.isVideoMirroringSupported {
            let front = device.position == .front || device.position == .unspecified
            conn.isVideoMirrored = front
        }
        session.commitConfiguration()

        session.startRunning()
        let name = device.localizedName
        DispatchQueue.main.async {
            self.deviceName = name
            self.isRunning = true
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
            let copy = pb
            previewQueue.async { [weak self] in
                guard let img = Self.makePreview(copy) else { return }
                DispatchQueue.main.async { self?.preview = img }
            }
        }
    }

    private static func makePreview(_ pb: CVPixelBuffer) -> NSImage? {
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        guard w > 1, h > 1 else { return nil }
        let ci = CIImage(cvPixelBuffer: pb)
        let scale = min(1, 480 / CGFloat(w))
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let tw = CGFloat(w) * scale
        let th = CGFloat(h) * scale
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        guard let cg = ctx.createCGImage(scaled, from: CGRect(x: 0, y: 0, width: tw, height: th)) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: tw, height: th))
    }
}
