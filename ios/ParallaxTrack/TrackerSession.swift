import ARKit
import Foundation
import Network
import QuartzCore
import simd
import Vision

enum CaptureMode: String, CaseIterable, Identifiable {
    case lidar = "LiDAR Rückseite"
    case trueDepth = "TrueDepth Front"
    var id: String { rawValue }
}

/// Rear LiDAR (Pro, phone as webcam) or front TrueDepth. JSON lines to the Mac.
final class TrackerSession: NSObject, ObservableObject, ARSessionDelegate {
    @Published var running = false
    @Published var sending = false
    @Published var status = "Suche Mac…"
    @Published var x: Float = 0
    @Published var y: Float = 0
    @Published var z: Float = 0.6
    @Published var quality: Float = 0
    @Published var hasLidar = false
    @Published var hasTrueDepth = ARFaceTrackingConfiguration.isSupported
    @Published var mode: CaptureMode = ARFaceTrackingConfiguration.isSupported ? .trueDepth : .lidar
    @Published var manualHost = ""

    let ar = ARSession()
    private let faceReq = VNDetectFaceLandmarksRequest()
    private var conn: NWConnection?
    private var browser: NWBrowser?
    private let encoder = JSONEncoder()
    private var lastSend: TimeInterval = 0

    func start() {
        stop()
        running = true
        runAR()
        if manualHost.trimmingCharacters(in: .whitespaces).isEmpty {
            browse()
            status = mode == .lidar ? "LiDAR an — suche Mac" : "TrueDepth an — suche Mac"
        } else {
            connectHost(manualHost.trimmingCharacters(in: .whitespaces))
        }
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

    private func runAR() {
        hasLidar = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        hasTrueDepth = ARFaceTrackingConfiguration.isSupported
        if mode == .trueDepth, hasTrueDepth {
            let cfg = ARFaceTrackingConfiguration()
            ar.delegate = self
            ar.run(cfg, options: [.resetTracking, .removeExistingAnchors])
        } else {
            let cfg = ARWorldTrackingConfiguration()
            if hasLidar { cfg.frameSemantics.insert(.sceneDepth) }
            cfg.worldAlignment = .gravity
            ar.delegate = self
            ar.run(cfg, options: [.resetTracking, .removeExistingAnchors])
        }
    }

    private func browse() {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let b = NWBrowser(for: .bonjour(type: TrackerPacket.bonjourType, domain: "local."), using: params)
        b.stateUpdateHandler = { [weak self] state in
            if case .failed(let err) = state {
                DispatchQueue.main.async { self?.status = "Netzwerk: \(err.localizedDescription)" }
            }
        }
        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self, self.conn == nil else { return }
            if let first = results.first {
                self.connect(first.endpoint)
            }
        }
        b.start(queue: .main)
        browser = b
    }

    private func connectHost(_ host: String) {
        let parts = host.split(separator: ":")
        let h = String(parts.first ?? "")
        let p = parts.count > 1 ? UInt16(parts[1]) ?? TrackerPacket.port : TrackerPacket.port
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(h), port: NWEndpoint.Port(rawValue: p)!)
        connect(endpoint)
        status = "Verbinde \(h)…"
    }

    private func connect(_ endpoint: NWEndpoint) {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let c = NWConnection(to: endpoint, using: params)
        c.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.sending = true
                    self?.status = "Verbunden mit dem Mac"
                case .failed(let err):
                    self?.sending = false
                    self?.status = "Getrennt: \(err.localizedDescription)"
                    self?.conn = nil
                case .cancelled:
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
        if let face = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first {
            emitFace(face, frame: frame)
            return
        }
        emitVision(frame)
    }

    private func emitFace(_ face: ARFaceAnchor, frame: ARFrame) {
        let inv = frame.camera.transform.inverse
        let p = face.transform.columns.3
        let inCam = inv * SIMD4<Float>(p.x, p.y, p.z, 1)
        // Camera +X is the viewer's left. Packet contract is +X right.
        let xM = -inCam.x
        let yM = inCam.y
        let zM = max(0.25, abs(inCam.z))
        push(x: xM, y: yM, z: zM, ipd: 0.063, quality: 0.95, source: "truedepth")
    }

    private func emitVision(_ frame: ARFrame) {
        let buf = frame.capturedImage
        // Buffer space (.up) so bbox, depth map and camera.intrinsics share one origin.
        // .right oriented Vision coords against landscape buffer size put the face on the wrong pixel.
        let handler = VNImageRequestHandler(cvPixelBuffer: buf, orientation: .up, options: [:])
        try? handler.perform([faceReq])
        guard let f = faceReq.results?.first else {
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
        let xM = -((px - cx) * zM / max(fx, 1))
        let yM = -((py - cy) * zM / max(fy, 1))
        let q: Float = depth == nil ? 0.45 : 0.92
        push(x: xM, y: yM, z: zM, ipd: Float(box.width) * 0.35, quality: q, source: depth == nil ? "iphone" : "lidar")
    }

    private func push(x: Float, y: Float, z: Float, ipd: Float, quality: Float, source: String) {
        let now = CACurrentMediaTime()
        DispatchQueue.main.async {
            self.x = x
            self.y = y
            self.z = z
            self.quality = quality
        }
        guard now - lastSend > 0.033, sending else { return }
        lastSend = now
        let pkt = TrackerPacket(x: x, y: y, z: z, ipd: ipd, quality: quality, source: source)
        guard var line = try? encoder.encode(pkt) else { return }
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
