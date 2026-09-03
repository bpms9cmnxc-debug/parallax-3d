import AppKit
import CoreGraphics
import SceneKit
import SwiftUI

enum ScreenMeasure {
    private static var lastDisplay: CGDirectDisplayID = 0
    private static var lastFrameW: CGFloat = 0
    private static var metersPerPoint: Float = 0
    private static let fallback: (Float, Float) = (0.30, 0.19)

    /// Physical size of the SceneKit view in metres — the hologram portal.
    static func meters(for view: NSView) -> (w: Float, h: Float) {
        let screen = view.window?.screen ?? NSScreen.main
        guard let screen else { return fallback }
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let id: CGDirectDisplayID
        if let num = screen.deviceDescription[key] as? NSNumber {
            id = CGDirectDisplayID(num.uint32Value)
        } else {
            id = CGMainDisplayID()
        }
        let frame = screen.frame
        if id != lastDisplay || abs(frame.width - lastFrameW) > 0.5 {
            let mm = CGDisplayScreenSize(id)
            guard mm.width > 40, frame.width > 20 else { return fallback }
            lastDisplay = id
            lastFrameW = frame.width
            metersPerPoint = Float(mm.width / 1000) / Float(frame.width)
        }
        guard metersPerPoint > 0 else { return fallback }
        let w = Float(max(view.bounds.width, 1)) * metersPerPoint
        let h = Float(max(view.bounds.height, 1)) * metersPerPoint
        return (max(0.16, w), max(0.10, h))
    }
}

struct HologramView: NSViewRepresentable {
    let controller: HologramController

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = controller.scene
        view.backgroundColor = NSColor(red: 0.027, green: 0.031, blue: 0.039, alpha: 1)
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        view.rendersContinuously = true
        view.isPlaying = true
        view.isJitteringEnabled = false
        view.isTemporalAntialiasingEnabled = false
        view.preferredFramesPerSecond = 60
        view.delegate = context.coordinator
        view.pointOfView = controller.cameraNode
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        view.pointOfView = controller.cameraNode
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        let controller: HologramController
        private var last: TimeInterval = 0
        private var lastViewW: CGFloat = 0
        private var lastViewH: CGFloat = 0

        init(controller: HologramController) {
            self.controller = controller
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            let dt = last == 0 ? 1 / 60 : min(time - last, 0.1)
            last = time
            controller.tick(dt: Float(dt))
            if let view = renderer as? SCNView {
                let bw = view.bounds.width
                let bh = view.bounds.height
                if abs(bw - lastViewW) > 0.5 || abs(bh - lastViewH) > 0.5 {
                    lastViewW = bw
                    lastViewH = bh
                    let m = ScreenMeasure.meters(for: view)
                    controller.resize(widthMeters: m.w, heightMeters: m.h)
                }
            }
        }
    }
}
