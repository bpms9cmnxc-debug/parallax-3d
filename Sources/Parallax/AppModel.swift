import AVFoundation
import AppKit
import Combine
import Foundation
import ParallaxCore
import QuartzCore
import simd
import SwiftUI

final class AppModel: ObservableObject {
    let camera = CameraSession()
    let hologram = HologramController()
    let iphone = TrackerLink()
    private let tracker = EyeTracker()

    @Published var eyes: TrackedEyes?
    @Published var modelId = "diorama"
    @Published var modelScale: Float = 1
    @Published var importName: String?
    @Published var importError: String?
    @Published var sensitivity: Float = 1.8
    @Published var autoDistance = true
    @Published var distanceMeters: Float = OffAxis.defaultZ
    @Published var tooClose = false
    @Published var hologramDepth: Float = 1.7
    @Published var calibration = Calibration.load()
    @Published var showCalibrate = false
    @Published var showIPhone = false
    @Published var cameras: [(id: String, name: String)] = []
    @Published var cameraID = ""
    @Published var mode = "demo"
    @Published var eye = EyeWorld(x: 0, y: 0.02, z: OffAxis.defaultZ)
    @Published var fps = 0

    private var demoT: Float = 0
    private var timer: Timer?
    private var frames = 0
    private var fpsClock: Float = 0
    private var hudClock: Float = 0
    private var bag = Set<AnyCancellable>()
    private var lastLock: TimeInterval = 0
    private var running = false
    private var wantsCamera = false
    private var smoothed = EyeWorld(x: 0, y: 0.02, z: OffAxis.defaultZ)
    private var iphoneOrigin = SIMD3<Float>(repeating: 0)

    var live: Bool { wantsCamera && camera.isRunning && (eyes?.tracking ?? false) }
    var searching: Bool { wantsCamera && !(eyes?.tracking ?? false) }
    var cameraActive: Bool { wantsCamera }

    func start() {
        guard !running else { return }
        running = true
        if calibration.completed {
            let d = calibration.depth
            hologramDepth = d < 0.5 ? 1.7 : min(2.2, max(0.8, d))
        }
        hologram.setEye(smoothed)
        hologram.setDepth(hologramDepth)
        iphone.start()
        refreshCameras()
        camera.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.cameras = self.camera.devices
                if self.cameraID.isEmpty { self.cameraID = self.camera.devices.first?.id ?? "" }
                self.objectWillChange.send()
            }
            .store(in: &bag)
        camera.onBuffer = { [weak self] pb in
            guard let self else { return }
            let size = self.hologram.screenSize()
            let sample = self.tracker.detect(
                buffer: pb,
                screenW: size.w,
                screenH: size.h,
                sensitivity: self.sensitivity,
                mirrored: self.camera.isMirrored,
                calibration: self.calibration.completed ? self.calibration : nil,
                distanceOverride: self.autoDistance ? nil : self.distanceMeters
            )
            DispatchQueue.main.async {
                guard self.running, self.wantsCamera else { return }
                let now = CACurrentMediaTime()
                if let sample {
                    self.eyes = sample
                    self.lastLock = now
                    self.mode = "camera"
                } else if let prev = self.eyes, prev.tracking, now - self.lastLock > 0.28 {
                    self.eyes = TrackedEyes(
                        left: prev.left,
                        right: prev.right,
                        face: prev.face,
                        world: prev.world,
                        ipd: prev.ipd,
                        tracking: false
                    )
                }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            self?.step(1 / 60)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.running else { return }
            self.startCamera()
        }
    }

    func stop() {
        running = false
        wantsCamera = false
        timer?.invalidate()
        timer = nil
        camera.stop()
        camera.onBuffer = nil
        iphone.stop()
        bag.removeAll()
        eyes = nil
    }

    func setModel(_ id: String) {
        if id == "import", importName == nil {
            pickImport()
            return
        }
        modelId = id
        hologram.setModel(id)
    }

    func setScale(_ s: Float) {
        modelScale = s
        hologram.setScale(s)
    }

    func pickImport() {
        let panel = NSOpenPanel()
        panel.title = "3-D-Modell importieren"
        panel.prompt = "Importieren"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ModelImporter.allowedTypes
        // runModal is reliable in a sandboxed SwiftUI app; begin() without a
        // window often never appears.
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadImported(url: url)
    }

    private func loadImported(url: URL) {
        do {
            let node = try ModelImporter.load(url: url)
            hologram.setImported(node)
            importName = url.lastPathComponent
            importError = nil
            modelScale = 1
            hologram.setScale(1)
            modelId = "import"
        } catch {
            importError = error.localizedDescription
        }
    }

    func startCamera() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
            DispatchQueue.main.async {
                guard let self, self.running else { return }
                if ok {
                    self.wantsCamera = true
                    self.camera.start()
                    self.mode = "camera"
                } else {
                    self.camera.errorMessage = "Kamera blockiert. Systemeinstellungen → Datenschutz & Sicherheit → Kamera."
                    self.mode = "demo"
                }
            }
        }
    }

    func stopCamera() {
        wantsCamera = false
        camera.stop()
        eyes = nil
        mode = "demo"
    }

    func setDistance(_ meters: Float) {
        autoDistance = false
        distanceMeters = min(OffAxis.maxZ, max(OffAxis.minZ, meters))
    }

    func setDepth(_ d: Float) {
        hologramDepth = min(2.2, max(0.8, d))
        hologram.setDepth(hologramDepth)
        calibration.depth = hologramDepth
        calibration.save()
    }

    func refreshCameras() {
        camera.refreshDevices()
        cameras = camera.devices
        if cameraID.isEmpty, let first = cameras.first { cameraID = first.id }
    }

    func setCamera(_ id: String) {
        cameraID = id
        camera.selectDevice(id)
    }

    func zeroIPhone() {
        guard let p = iphone.latest else { return }
        iphoneOrigin = SIMD3(p.x, p.y + calibration.iphoneOffsetY, 0)
    }

    func applyCalibration(_ cal: Calibration) {
        var c = cal
        c.completed = true
        c.depth = hologramDepth
        calibration = c
        c.save()
        hologram.setDepth(c.depth)
    }

    func faceSample() -> (nx: Float, ny: Float, ipd: Float)? {
        guard let e = eyes, let L = e.left, let R = e.right else { return nil }
        let nx = Float((L.x + R.x) * 0.5)
        let ny = Float(1 - (L.y + R.y) * 0.5)
        return (nx, ny, e.ipd)
    }

    private func step(_ dt: Float) {
        var target = smoothed
        if let pkt = iphone.latest, iphone.connected, pkt.quality > 0.25 {
            var w = OffAxis.lidarToScreen(pkt, calibration: calibration, origin: iphoneOrigin)
            let g = max(0.8, sensitivity)
            w.x *= g
            w.y *= g
            tooClose = pkt.z < OffAxis.minZ
            if !autoDistance { w.z = distanceMeters }
            target = w
            mode = "lidar"
        } else if live, let sample = eyes, sample.tracking {
            var w = sample.world
            tooClose = OffAxis.rawDistance(ipdNorm: sample.ipd) < OffAxis.minZ
            if !autoDistance {
                w.z = distanceMeters
            }
            target = w
            mode = "camera"
        } else if !camera.isRunning {
            tooClose = false
            demoT += dt
            target = EyeWorld(
                x: sin(demoT * 0.62) * 0.30,
                y: sin(demoT * 0.41) * 0.12 + 0.02,
                z: 0.58 + sin(demoT * 0.18) * 0.06
            )
            mode = "demo"
        }
        let kxy = 1 - exp(-8 * dt)
        let kz = 1 - exp(-4.5 * dt)
        smoothed = EyeWorld(
            x: smoothed.x + (target.x - smoothed.x) * kxy,
            y: smoothed.y + (target.y - smoothed.y) * kxy,
            z: min(OffAxis.maxZ, max(OffAxis.minZ, smoothed.z + (target.z - smoothed.z) * kz))
        )
        hologram.setEye(smoothed)
        hudClock += dt
        if hudClock >= 0.048 {
            hudClock = 0
            eye = smoothed
            if autoDistance, mode == "camera" || mode == "lidar" {
                distanceMeters = smoothed.z
            }
        }
        frames += 1
        fpsClock += dt
        if fpsClock >= 0.4 {
            fps = Int((Float(frames) / fpsClock).rounded())
            frames = 0
            fpsClock = 0
        }
    }
}
