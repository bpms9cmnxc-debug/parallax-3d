import ARKit
import Foundation
import Network
import QuartzCore
import simd
import Vision

/// Rear camera + LiDAR (Pro) or IPD fallback. Sends JSON lines to Parallax on the Mac.
final class TrackerSession: NSObject, ObservableObject, ARSessionDelegate {
    @Published var running = false
    @Published var sending = false
    @Published var status = "Suche Mac…"
    @Published var x: Float = 0
    @Published var y: Float = 0
    @Published var z: Float = 0.6
    @Published var quality: Float = 0
    @Published var hasLidar = false

    private let ar = ARSession()
    private let face = VNDetectFaceLandmarksRequest()
    private var conn: NWConnection?
    private var browser: NWBrowser?
    private let encoder = JSONEncoder()
    private var lastSend: TimeInterval = 0

    func start() {
        stop()
        running = true
        hasLidar = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        let cfg = ARWorldTrackingConfiguration()
        if hasLidar { cfg.frameSemantics.insert(.sceneDepth) }
        cfg.worldAlignment = .gravity
        ar.delegate = self
        ar.run(cfg, options: [.resetTracking, .removeExistingAnchors])
        browse()
        status = hasLidar ? "LiDAR an — suche Mac" : "Kein LiDAR — suche Mac"
    }

    func stop() {
        running = false
        sending = false
        ar.pause()
        conn?.cancel()
        conn = nil
        browser?.cancel()
        browser = nil
    }

    private func browse() {
        let b = NWBrowser(for: .bonjour(type: "_parallax._tcp", domain: "local."), using: .tcp)
        b.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                DispatchQueue.main.async { self?.status = "Netzwerkfehler" }
            }
        }
        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self, self.conn == nil else { return }
            if let first = results.first, case .service = first.endpoint {
                self.connect(first.endpoint)
            }
        }
        b.start(queue: .main)
        browser = b
    }

    private func connect(_ endpoint: NWEndpoint) {
        let c = NWConnection(to: endpoint, using: .tcp)
        c.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.sending = true
                    self?.status = "Verbunden mit dem Mac"
                case .failed, .cancelled:
                    self?.sending = false
                    self?.status = "Getrennt"
                    self?.conn = nil
                default:
                    break
                }
            }
        }
        c.start(queue: .global(qos: .userInitiated))
        conn = c
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard running else { return }
        let buf = frame.capturedImage
        let handler = VNImageRequestHandler(cvPixelBuffer: buf, orientation: .right, options: [:])
        try? handler.perform([face])
        guard let f = face.results?.first else {
            DispatchQueue.main.async { self.quality = 0 }
            return
        }
        let box = f.boundingBox
        let mid = CGPoint(x: box.midX, y: box.midY)
        var depth: Float?
        if let d = frame.smoothedSceneDepth ?? frame.sceneDepth {
            depth = Self.sample(d.depthMap, nx: Float(mid.x), ny: Float(mid.y))
        }
        let zM = depth ?? max(0.45, 0.045 / max(Float(box.width) * 0.35, 0.02))
        let intr = frame.camera.intrinsics
        let fx = intr.columns.0.x
        let fy = intr.columns.1.y
        let cx = intr.columns.2.x
        let cy = intr.columns.2.y
        let imgW = Float(CVPixelBufferGetWidth(buf))
        let imgH = Float(CVPixelBufferGetHeight(buf))
        let px = Float(mid.x) * imgW
        let py = (1 - Float(mid.y)) * imgH
        let xM = (px - cx) * zM / max(fx, 1)
        let yM = -((py - cy) * zM / max(fy, 1))
        let q: Float = depth == nil ? 0.45 : 0.9
        let now = CACurrentMediaTime()
        DispatchQueue.main.async {
            self.x = xM
            self.y = yM
            self.z = zM
            self.quality = q
        }
        guard now - lastSend > 0.033, sending else { return }
        lastSend = now
        let pkt = [
            "x": xM, "y": yM, "z": zM,
            "ipd": Float(box.width) * 0.35,
            "quality": q,
            "source": depth == nil ? "iphone" : "lidar",
        ] as [String: Any]
        guard var line = try? JSONSerialization.data(withJSONObject: pkt) else { return }
        line.append(0x0A)
        conn?.send(content: line, completion: .contentProcessed { _ in })
    }

    private static func sample(_ pb: CVPixelBuffer, nx: Float, ny: Float) -> Float? {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let stride = CVPixelBufferGetBytesPerRow(pb) / MemoryLayout<Float32>.size
        let x = min(w - 1, max(0, Int(nx * Float(w - 1))))
        let y = min(h - 1, max(0, Int((1 - ny) * Float(h - 1))))
        let ptr = base.assumingMemoryBound(to: Float32.self)
        var sum: Float = 0
        var n: Float = 0
        for dy in -2...2 {
            for dx in -2...2 {
                let xx = min(w - 1, max(0, x + dx))
                let yy = min(h - 1, max(0, y + dy))
                let v = ptr[yy * stride + xx]
                if v > 0.2, v < 2.5 {
                    sum += v
                    n += 1
                }
            }
        }
        guard n > 4 else { return nil }
        return sum / n
    }
}
