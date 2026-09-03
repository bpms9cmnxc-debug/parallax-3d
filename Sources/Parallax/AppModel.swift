import AVFoundation
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
    @Published var modelId = "orrery"
    @Published var sensitivity: Float = 1.15
    @Published var mode = "demo"
    @Published var eye = EyeWorld(x: 0, y: 0.02, z: 0.55)
    @Published var fps = 0

    private var demoT: Float = 0
    private var timer: Timer?
    private var frames = 0
    private var fpsClock: Float = 0
    private var bag = Set<AnyCancellable>()
    private var lastLock: TimeInterval = 0

    var live: Bool { camera.isRunning && (eyes?.tracking ?? false) }
    var searching: Bool { camera.isRunning && !(eyes?.tracking ?? false) }

    func start() {
        hologram.setEye(eye)
        camera.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
        camera.onBuffer = { [weak self] pb in
            guard let self else { return }
            let sample = self.tracker.detect(
                buffer: pb,
                screenW: self.hologram.screenWidth,
                screenH: self.hologram.screenHeight,
                sensitivity: self.sensitivity
            )
            DispatchQueue.main.async {
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
            self?.startCamera()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        camera.stop()
        camera.onBuffer = nil
    }

    func setModel(_ id: String) {
        modelId = id
        hologram.setModel(id)
    }

    func startCamera() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
            DispatchQueue.main.async {
                guard let self else { return }
                if ok {
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
        camera.stop()
        eyes = nil
        mode = "demo"
    }

    private func step(_ dt: Float) {
        var target = eye
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
        eye = EyeWorld(
            x: eye.x + (target.x - eye.x) * k,
            y: eye.y + (target.y - eye.y) * k,
            z: eye.z + (target.z - eye.z) * k
        )
        hologram.setEye(eye)
        frames += 1
        fpsClock += dt
        if fpsClock >= 0.4 {
            fps = Int((Float(frames) / fpsClock).rounded())
            frames = 0
            fpsClock = 0
        }
    }
}
