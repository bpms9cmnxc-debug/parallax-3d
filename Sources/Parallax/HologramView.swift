import AppKit
import SceneKit
import SwiftUI

struct HologramView: NSViewRepresentable {
    let controller: HologramController

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = controller.scene
        view.backgroundColor = NSColor(red: 0.027, green: 0.031, blue: 0.039, alpha: 1)
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = true
        view.allowsCameraControl = false
        view.rendersContinuously = true
        view.isPlaying = true
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

        init(controller: HologramController) {
            self.controller = controller
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            let dt = last == 0 ? 1 / 60 : min(time - last, 0.1)
            last = time
            controller.tick(dt: Float(dt))
            if let view = renderer as? SCNView {
                let w = Float(max(view.bounds.width, 1))
                let h = Float(max(view.bounds.height, 1))
                controller.resize(aspect: w / h)
            }
        }
    }
}
