import AVFoundation
import AppKit
import Combine
import Foundation
import ParallaxCore
import QuartzCore
import SwiftUI

final class AppModel: ObservableObject {
    let camera = CameraSession()
    let hologram = HologramController()
    private let tracker = EyeTracker()

    @Published var eyes: TrackedEyes?
    @Published var modelId = "mug"
    @Published var modelScale: Float = 1
    @Published var importName: String?
    @Published var importError: String?
    @Published var sensitivity: Float = 1.15
    @Published var mode = "demo"
    @Published var eye = EyeWorld(x: 0, y: 0.02, z: 0.55)
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
    private var smoothed = EyeWorld(x: 0, y: 0.02, z: 0.55)

    var live: Bool { wantsCamera && camera.isRunning && (eyes?.tracking ?? false) }
    var searching: Bool { wantsCamera && !(eyes?.tracking ?? false) }
    var cameraActive: Bool { wantsCamera }

    func start() {
        guard !running else { return }
        running = true
        hologram.setEye(smoothed)
        camera.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
        camera.onBuffer = { [weak self] pb in
            guard let self else { return }
            let size = self.hologram.screenSize()
            let sample = self.tracker.detect(
                buffer: pb,
                screenW: size.w,
                screenH: size.h,
                sensitivity: self.sensitivity
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
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            self?.loadImported(url: url)
        }
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

    private func step(_ dt: Float) {
        var target = smoothed
        if live, let w = eyes?.world {
            target = w
            mode = "camera"
        } else if !camera.isRunning {
            demoT += dt
            target = EyeWorld(
                x: sin(demoT * 0.55) * 0.22,
                y: sin(demoT * 0.37) * 0.10 + 0.02,
                z: 0.50 + sin(demoT * 0.22) * 0.12
            )
            mode = "demo"
        }
        let k = 1 - exp(-10 * dt)
        smoothed = EyeWorld(
            x: smoothed.x + (target.x - smoothed.x) * k,
            y: smoothed.y + (target.y - smoothed.y) * k,
            z: smoothed.z + (target.z - smoothed.z) * k
        )
        hologram.setEye(smoothed)
        hudClock += dt
        if hudClock >= 0.048 {
            hudClock = 0
            eye = smoothed
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
