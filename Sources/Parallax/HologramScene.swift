import AppKit
import Combine
import ParallaxCore
import SceneKit
import simd

final class HologramController: NSObject, ObservableObject {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    let camera = SCNCamera()
    private let room = SCNNode()
    private let stage = SCNNode()
    private var model = SCNNode()
    private var modelId = "mug"
    private var imported: SCNNode?
    private var screenW: Float = 0.4
    private var screenH: Float = 0.25
    private var elapsed: Float = 0
    private let eyeLock = NSLock()
    private var pendingEye = EyeWorld(x: 0, y: 0.02, z: OffAxis.defaultZ)
    private var pendingModelId: String?
    private var pendingImported: SCNNode?
    private var pendingScale: Float?
    private var pendingDepth: Float?
    private var modelScale: Float = 1
    private var hologramDepth: Float = 1.4

    var screenWidth: Float { screenSize().w }
    var screenHeight: Float { screenSize().h }

    func screenSize() -> (w: Float, h: Float) {
        eyeLock.lock()
        defer { eyeLock.unlock() }
        return (screenW, screenH)
    }

    override init() {
        super.init()
        scene.background.contents = NSColor(red: 0.027, green: 0.031, blue: 0.039, alpha: 1)
        scene.fogColor = NSColor(red: 0.027, green: 0.031, blue: 0.039, alpha: 1)
        scene.fogStartDistance = 2.8
        scene.fogEndDistance = 7
        scene.fogDensityExponent = 1
        scene.lightingEnvironment.contents = NSColor(white: 0.62, alpha: 1)
        scene.lightingEnvironment.intensity = 1.6

        camera.zNear = Double(OffAxis.near)
        camera.zFar = Double(OffAxis.far)
        camera.fieldOfView = 32
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0.02, OffAxis.defaultZ)
        scene.rootNode.addChildNode(cameraNode)
        scene.rootNode.addChildNode(room)
        scene.rootNode.addChildNode(stage)
        stage.simdPosition = SIMD3.zero
        addLights()
        rebuildRoom()
        applyModel("diorama")
    }

    func resize(widthMeters: Float, heightMeters: Float) {
        let w = max(0.16, min(0.7, widthMeters))
        let h = max(0.10, min(0.5, heightMeters))
        eyeLock.lock()
        let unchanged = abs(w - screenW) < 0.012 && abs(h - screenH) < 0.012
        if !unchanged {
            screenW = w
            screenH = h
        }
        eyeLock.unlock()
        if unchanged { return }
        rebuildRoom()
    }

    func setModel(_ id: String) {
        eyeLock.lock()
        pendingModelId = id
        eyeLock.unlock()
    }

    func setScale(_ s: Float) {
        eyeLock.lock()
        pendingScale = s
        eyeLock.unlock()
    }

    func setDepth(_ d: Float) {
        eyeLock.lock()
        pendingDepth = d
        eyeLock.unlock()
    }

    func setImported(_ node: SCNNode) {
        eyeLock.lock()
        pendingImported = node
        pendingModelId = "import"
        eyeLock.unlock()
    }

    private func applyModel(_ id: String) {
        model.removeFromParentNode()
        modelId = id
        switch id {
        case "bust":
            model = buildBust()
        case "car":
            model = buildCar()
        case "mug":
            model = buildMug()
        case "import":
            model = imported ?? SCNNode()
        default:
            model = buildDiorama()
        }
        if model.parent !== stage {
            model.removeFromParentNode()
            stage.addChildNode(model)
        }
        applyStageTransform()
    }

    private func applyStageTransform() {
        stage.simdPosition = SIMD3(0, 0, -(hologramDepth - 1) * 0.12)
        stage.simdEulerAngles = SIMD3.zero
        stage.simdScale = SIMD3(modelScale, modelScale, modelScale)
    }

    func setEye(_ eye: EyeWorld) {
        eyeLock.lock()
        pendingEye = eye
        eyeLock.unlock()
    }

    func tick(dt: Float) {
        eyeLock.lock()
        let e = pendingEye
        let queuedModel = pendingModelId
        pendingModelId = nil
        let queuedImport = pendingImported
        pendingImported = nil
        let queuedScale = pendingScale
        pendingScale = nil
        let queuedDepth = pendingDepth
        pendingDepth = nil
        let sw = screenW
        let sh = screenH
        eyeLock.unlock()
        if let queuedImport {
            imported?.removeFromParentNode()
            imported = queuedImport
        }
        if let queuedModel { applyModel(queuedModel) }
        if let queuedScale {
            modelScale = min(2.6, max(0.3, queuedScale))
        }
        if let queuedDepth {
            hologramDepth = min(2.2, max(0.8, queuedDepth))
        }
        if queuedScale != nil || queuedDepth != nil {
            applyStageTransform()
        }
        applyEye(e, screenW: sw, screenH: sh)
        elapsed += dt
    }

    private func applyEye(_ eye: EyeWorld, screenW: Float, screenH: Float) {
        let e = SIMD3<Float>(
            (eye.x * 2000).rounded() / 2000,
            (eye.y * 2000).rounded() / 2000,
            simd_clamp((eye.z * 2000).rounded() / 2000, OffAxis.minZ, OffAxis.maxZ)
        )
        cameraNode.position = SCNVector3(e.x, e.y, e.z)
        cameraNode.eulerAngles = SCNVector3Zero
        cameraNode.orientation = SCNQuaternion(0, 0, 0, 1)
        let f = OffAxis.frustum(eye: e, screenW: screenW, screenH: screenH)
        camera.usesOrthographicProjection = false
        camera.zNear = Double(f.near)
        camera.zFar = Double(f.far)
        camera.projectionTransform = SCNMatrix4(OffAxis.projectionMatrix(
            left: f.left, right: f.right, top: f.top, bottom: f.bottom, near: f.near, far: f.far
        ))
        let look = OffAxis.lookAround(eye: e)
        model.simdEulerAngles = SIMD3(look.pitch * 0.45, look.yaw, 0)
    }

    private func addLights() {
        let amb = SCNNode()
        amb.light = SCNLight()
        amb.light?.type = .ambient
        amb.light?.color = NSColor(white: 0.38, alpha: 1)
        amb.light?.intensity = 420
        scene.rootNode.addChildNode(amb)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.color = NSColor(red: 1, green: 0.97, blue: 0.92, alpha: 1)
        key.light?.intensity = 2000
        key.light?.castsShadow = false
        key.position = SCNVector3(0.45, 0.7, 0.9)
        key.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .omni
        fill.light?.color = NSColor(red: 0.75, green: 0.84, blue: 0.95, alpha: 1)
        fill.light?.intensity = 700
        fill.light?.attenuationStartDistance = 0.05
        fill.light?.attenuationEndDistance = 2.4
        fill.position = SCNVector3(-0.35, 0.2, 0.45)
        scene.rootNode.addChildNode(fill)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .omni
        rim.light?.color = NSColor(red: 1, green: 0.88, blue: 0.7, alpha: 1)
        rim.light?.intensity = 550
        rim.position = SCNVector3(0.1, 0.12, -0.25)
        scene.rootNode.addChildNode(rim)
    }

    private func rebuildRoom() {
        room.childNodes.forEach { $0.removeFromParentNode() }
        // Shallow box = 3D-monitor volume. A deep hallway reads as a 2D photo.
        let w = CGFloat(screenW)
        let h = CGFloat(screenH)
        let d: CGFloat = 0.36
        let zFront: CGFloat = -0.012

        func wall(_ color: NSColor) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .phong
            m.diffuse.contents = color
            m.emission.contents = color.blended(withFraction: 0.72, of: .black) ?? color
            m.specular.contents = NSColor(white: 0.25, alpha: 1)
            m.shininess = 8
            m.isDoubleSided = false
            m.cullMode = .back
            return m
        }

        func plane(_ sw: CGFloat, _ sh: CGFloat, _ material: SCNMaterial) -> SCNNode {
            let n = SCNNode(geometry: SCNPlane(width: sw, height: sh))
            n.geometry?.firstMaterial = material
            n.renderingOrder = -30
            return n
        }

        let floor = plane(w, d, wall(NSColor(red: 0.16, green: 0.15, blue: 0.14, alpha: 1)))
        floor.eulerAngles.x = -.pi / 2
        floor.position = SCNVector3(0, -h / 2, zFront - d / 2)
        room.addChildNode(floor)

        let ceil = plane(w, d, wall(NSColor(red: 0.22, green: 0.23, blue: 0.26, alpha: 1)))
        ceil.eulerAngles.x = .pi / 2
        ceil.position = SCNVector3(0, h / 2, zFront - d / 2)
        room.addChildNode(ceil)

        let back = plane(w, h, wall(NSColor(red: 0.18, green: 0.28, blue: 0.32, alpha: 1)))
        back.position = SCNVector3(0, 0, zFront - d)
        room.addChildNode(back)

        let left = plane(d, h, wall(NSColor(red: 0.62, green: 0.28, blue: 0.18, alpha: 1)))
        left.eulerAngles.y = .pi / 2
        left.position = SCNVector3(-w / 2, 0, zFront - d / 2)
        room.addChildNode(left)

        let right = plane(d, h, wall(NSColor(red: 0.18, green: 0.42, blue: 0.58, alpha: 1)))
        right.eulerAngles.y = -.pi / 2
        right.position = SCNVector3(w / 2, 0, zFront - d / 2)
        room.addChildNode(right)

        let tile: CGFloat = 0.036
        let lightSq = mat(NSColor(red: 0.90, green: 0.86, blue: 0.76, alpha: 1), glow: 0.28)
        let darkSq = mat(NSColor(red: 0.22, green: 0.20, blue: 0.18, alpha: 1), glow: 0.14)
        let cols = max(4, Int(w / tile))
        let rows = max(4, Int(d / tile))
        for ix in 0..<cols {
            for iz in 0..<rows {
                let even = ((ix + iz) & 1) == 0
                let x = -w / 2 + (CGFloat(ix) + 0.5) * (w / CGFloat(cols))
                let z = zFront - (CGFloat(iz) + 0.5) * (d / CGFloat(rows))
                let tw = w / CGFloat(cols) * 0.92
                let td = d / CGFloat(rows) * 0.92
                room.addChildNode(node(
                    SCNBox(width: tw, height: 0.003, length: td, chamferRadius: 0),
                    even ? lightSq : darkSq,
                    at: SCNVector3(x, -h / 2 + 0.004, z)
                ))
            }
        }

        let art = node(
            SCNBox(width: w * 0.28, height: h * 0.22, length: 0.008, chamferRadius: 0.002),
            mat(NSColor(red: 0.95, green: 0.78, blue: 0.28, alpha: 1), glow: 0.5),
            at: SCNVector3(0.0, 0.02, zFront - d + 0.012)
        )
        room.addChildNode(art)

        room.addChildNode(volumeGrid(w: w * 0.88, h: h * 0.88, d: d))
    }

    /// Window frames on the room walls — not a lattice through the model.
    private func volumeGrid(w: CGFloat, h: CGFloat, d: CGFloat) -> SCNNode {
        let g = SCNNode()
        var verts: [SCNVector3] = []
        let x0 = -w / 2, y0 = -h / 2
        let z0: CGFloat = -0.04
        let z1 = -d * 0.92
        let frames = 3
        for iz in 0...frames {
            let z = z0 + (z1 - z0) * CGFloat(iz) / CGFloat(frames)
            verts.append(SCNVector3(x0, y0, z))
            verts.append(SCNVector3(x0 + w, y0, z))
            verts.append(SCNVector3(x0 + w, y0, z))
            verts.append(SCNVector3(x0 + w, y0 + h, z))
            verts.append(SCNVector3(x0 + w, y0 + h, z))
            verts.append(SCNVector3(x0, y0 + h, z))
            verts.append(SCNVector3(x0, y0 + h, z))
            verts.append(SCNVector3(x0, y0, z))
        }
        let src = SCNGeometrySource(vertices: verts)
        var idx: [UInt32] = []
        for i in stride(from: 0, to: verts.count, by: 2) {
            idx.append(UInt32(i))
            idx.append(UInt32(i + 1))
        }
        let data = idx.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(
            data: data,
            primitiveType: .line,
            primitiveCount: verts.count / 2,
            bytesPerIndex: 4
        )
        let geo = SCNGeometry(sources: [src], elements: [element])
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.diffuse.contents = NSColor(red: 0.55, green: 0.62, blue: 0.68, alpha: 1)
        mat.emission.contents = NSColor(red: 0.22, green: 0.28, blue: 0.32, alpha: 1)
        mat.writesToDepthBuffer = false
        mat.readsFromDepthBuffer = false
        geo.firstMaterial = mat
        let node = SCNNode(geometry: geo)
        node.renderingOrder = -20
        g.addChildNode(node)
        return g
    }

    /// Phong + emission so the mesh stays visible even without IBL.
    private func mat(_ color: NSColor, glow: CGFloat = 0.38, phong: Bool = true) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = phong ? .phong : .constant
        m.diffuse.contents = color
        m.ambient.contents = color
        m.specular.contents = NSColor(white: 0.95, alpha: 1)
        m.emission.contents = color.blended(withFraction: 1 - glow, of: .black) ?? color
        m.shininess = 90
        m.locksAmbientWithDiffuse = true
        m.isDoubleSided = true
        m.cullMode = .back
        m.writesToDepthBuffer = true
        m.readsFromDepthBuffer = true
        return m
    }

    private func faceBox(size: CGFloat) -> SCNNode {
        let g = SCNBox(width: size, height: size, length: size, chamferRadius: size * 0.07)
        g.materials = [
            mat(NSColor(red: 0.15, green: 0.92, blue: 0.88, alpha: 1), glow: 0.32),
            mat(NSColor(red: 0.32, green: 0.86, blue: 0.38, alpha: 1), glow: 0.32),
            mat(NSColor(red: 0.96, green: 0.48, blue: 0.12, alpha: 1), glow: 0.32),
            mat(NSColor(red: 0.86, green: 0.28, blue: 0.78, alpha: 1), glow: 0.32),
            mat(NSColor(red: 0.96, green: 0.94, blue: 0.86, alpha: 1), glow: 0.28),
            mat(NSColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1), glow: 0.2),
        ]
        return SCNNode(geometry: g)
    }

    private func node(_ geo: SCNGeometry, _ material: SCNMaterial, at p: SCNVector3 = SCNVector3Zero) -> SCNNode {
        geo.firstMaterial = material
        let n = SCNNode(geometry: geo)
        n.position = p
        n.castsShadow = false
        return n
    }

    private func buildMug() -> SCNNode {
        let root = SCNNode()
        let cup = mat(NSColor(red: 0.96, green: 0.93, blue: 0.86, alpha: 1), glow: 0.48)
        let drink = mat(NSColor(red: 0.32, green: 0.18, blue: 0.10, alpha: 1), glow: 0.22)
        let band = mat(NSColor(red: 0.37, green: 0.92, blue: 0.83, alpha: 1), glow: 0.7)
        let metal = mat(NSColor(red: 0.78, green: 0.82, blue: 0.86, alpha: 1), glow: 0.4)

        root.addChildNode(node(SCNTube(innerRadius: 0.062, outerRadius: 0.082, height: 0.15), cup))
        root.addChildNode(node(SCNCylinder(radius: 0.082, height: 0.012), cup, at: SCNVector3(0, -0.081, 0)))
        let rim = node(SCNTorus(ringRadius: 0.072, pipeRadius: 0.009), cup, at: SCNVector3(0, 0.075, 0))
        rim.eulerAngles.x = .pi / 2
        root.addChildNode(rim)
        root.addChildNode(node(SCNCylinder(radius: 0.06, height: 0.008), drink, at: SCNVector3(0, 0.05, 0)))
        let handle = node(SCNTorus(ringRadius: 0.052, pipeRadius: 0.015), cup, at: SCNVector3(0.1, 0.0, 0))
        handle.eulerAngles.y = .pi / 2
        root.addChildNode(handle)
        root.addChildNode(node(SCNSphere(radius: 0.016), cup, at: SCNVector3(0.148, 0.05, 0)))
        root.addChildNode(node(SCNSphere(radius: 0.016), cup, at: SCNVector3(0.148, -0.05, 0)))
        let stripe = node(SCNTorus(ringRadius: 0.083, pipeRadius: 0.007), band, at: SCNVector3(0, -0.01, 0))
        stripe.eulerAngles.x = .pi / 2
        root.addChildNode(stripe)
        root.addChildNode(node(SCNBox(width: 0.034, height: 0.034, length: 0.006, chamferRadius: 0.004), band, at: SCNVector3(0, 0.01, 0.084)))
        let spoon = node(SCNCapsule(capRadius: 0.006, height: 0.11), metal, at: SCNVector3(0.02, 0.08, 0.02))
        spoon.eulerAngles.z = -0.55
        spoon.eulerAngles.x = 0.35
        root.addChildNode(spoon)
        root.addChildNode(node(SCNSphere(radius: 0.014), metal, at: SCNVector3(-0.02, 0.042, 0.048)))
        root.position = SCNVector3(0, 0.02, 0)
        return root
    }

    private func buildBust() -> SCNNode {
        let root = SCNNode()
        let stone = mat(NSColor(red: 0.91, green: 0.88, blue: 0.80, alpha: 1), glow: 0.46)
        let dark = mat(NSColor(red: 0.22, green: 0.24, blue: 0.28, alpha: 1), glow: 0.18)
        let hair = mat(NSColor(red: 0.58, green: 0.52, blue: 0.45, alpha: 1), glow: 0.28)
        let live = mat(NSColor(red: 0.37, green: 0.92, blue: 0.83, alpha: 1), glow: 0.75)

        let cranium = node(SCNSphere(radius: 0.078), stone, at: SCNVector3(0, 0.155, -0.01))
        cranium.scale = SCNVector3(0.95, 1.08, 1.05)
        root.addChildNode(cranium)
        let jaw = node(SCNSphere(radius: 0.058), stone, at: SCNVector3(0, 0.1, 0.028))
        jaw.scale = SCNVector3(0.9, 0.78, 1.05)
        root.addChildNode(jaw)
        let nose = node(SCNCone(topRadius: 0, bottomRadius: 0.018, height: 0.058), stone, at: SCNVector3(0, 0.138, 0.092))
        nose.eulerAngles.x = .pi / 2
        root.addChildNode(nose)
        root.addChildNode(node(SCNBox(width: 0.082, height: 0.014, length: 0.03, chamferRadius: 0), stone, at: SCNVector3(0, 0.172, 0.062)))
        for sx in [-1.0, 1.0] {
            let socket = node(SCNSphere(radius: 0.016), dark, at: SCNVector3(sx * 0.028, 0.154, 0.078))
            socket.scale = SCNVector3(1, 0.7, 0.45)
            root.addChildNode(socket)
            root.addChildNode(node(SCNSphere(radius: 0.008), live, at: SCNVector3(sx * 0.028, 0.154, 0.086)))
            let ear = node(SCNSphere(radius: 0.024), stone, at: SCNVector3(sx * 0.086, 0.146, 0.0))
            ear.scale = SCNVector3(0.38, 1.05, 0.75)
            root.addChildNode(ear)
        }
        root.addChildNode(node(SCNBox(width: 0.03, height: 0.006, length: 0.012, chamferRadius: 0), dark, at: SCNVector3(0, 0.108, 0.078)))
        let hairCap = node(SCNSphere(radius: 0.084), hair, at: SCNVector3(0, 0.172, -0.02))
        hairCap.eulerAngles.x = -0.25
        root.addChildNode(hairCap)
        root.addChildNode(node(SCNCylinder(radius: 0.032, height: 0.07), stone, at: SCNVector3(0, 0.048, 0.01)))
        root.addChildNode(node(SCNBox(width: 0.22, height: 0.07, length: 0.12, chamferRadius: 0.012), stone, at: SCNVector3(0, 0, 0)))
        root.addChildNode(node(SCNCylinder(radius: 0.058, height: 0.028), stone, at: SCNVector3(0, 0.028, 0.01)))
        root.addChildNode(node(
            SCNBox(width: 0.18, height: 0.03, length: 0.12, chamferRadius: 0),
            mat(NSColor(red: 0.78, green: 0.82, blue: 0.86, alpha: 1), glow: 0.28),
            at: SCNVector3(0, -0.042, 0)
        ))
        root.position = SCNVector3(0, 0.0, 0)
        return root
    }

    private func buildCar() -> SCNNode {
        let root = SCNNode()
        let paint = mat(NSColor(red: 0.86, green: 0.89, blue: 0.93, alpha: 1), glow: 0.42)
        let dark = mat(NSColor(red: 0.16, green: 0.17, blue: 0.19, alpha: 1), glow: 0.16)
        let glass = mat(NSColor(red: 0.45, green: 0.62, blue: 0.78, alpha: 1), glow: 0.35)
        let lamp = mat(NSColor(red: 0.37, green: 0.92, blue: 0.83, alpha: 1), glow: 0.9)
        let tail = mat(NSColor(red: 0.85, green: 0.32, blue: 0.28, alpha: 1), glow: 0.7)
        let hubMat = mat(NSColor(white: 0.88, alpha: 1), glow: 0.4)

        root.addChildNode(node(SCNBox(width: 0.38, height: 0.07, length: 0.18, chamferRadius: 0.012), paint, at: SCNVector3(0, 0.072, 0)))
        root.addChildNode(node(SCNBox(width: 0.12, height: 0.032, length: 0.17, chamferRadius: 0.008), paint, at: SCNVector3(0.13, 0.118, 0)))
        root.addChildNode(node(SCNBox(width: 0.16, height: 0.09, length: 0.168, chamferRadius: 0.01), glass, at: SCNVector3(-0.04, 0.15, 0)))
        root.addChildNode(node(SCNBox(width: 0.15, height: 0.016, length: 0.17, chamferRadius: 0.004), paint, at: SCNVector3(-0.04, 0.198, 0)))
        root.addChildNode(node(SCNBox(width: 0.032, height: 0.04, length: 0.19, chamferRadius: 0), dark, at: SCNVector3(0.205, 0.06, 0)))
        root.addChildNode(node(SCNBox(width: 0.024, height: 0.036, length: 0.19, chamferRadius: 0), dark, at: SCNVector3(-0.205, 0.058, 0)))
        for sz in [-1.0, 1.0] {
            let light = node(SCNCylinder(radius: 0.018, height: 0.016), lamp, at: SCNVector3(0.208, 0.09, sz * 0.058))
            light.eulerAngles.z = .pi / 2
            root.addChildNode(light)
            root.addChildNode(node(SCNBox(width: 0.012, height: 0.018, length: 0.036, chamferRadius: 0), tail, at: SCNVector3(-0.214, 0.082, sz * 0.06)))
            let mirror = node(SCNSphere(radius: 0.014), dark, at: SCNVector3(0.04, 0.148, sz * 0.1))
            mirror.scale = SCNVector3(1.4, 0.7, 0.55)
            root.addChildNode(mirror)
        }
        for pair in [(0.12, 0.1), (0.12, -0.1), (-0.12, 0.1), (-0.12, -0.1)] {
            let wheel = node(SCNCylinder(radius: 0.042, height: 0.036), dark, at: SCNVector3(pair.0, 0.042, pair.1))
            wheel.eulerAngles.z = .pi / 2
            root.addChildNode(wheel)
            let hub = node(SCNCylinder(radius: 0.016, height: 0.038), hubMat, at: SCNVector3(pair.0, 0.042, pair.1))
            hub.eulerAngles.z = .pi / 2
            root.addChildNode(hub)
        }
        root.addChildNode(node(
            SCNBox(width: 0.3, height: 0.01, length: 0.018, chamferRadius: 0),
            mat(NSColor(red: 0.37, green: 0.92, blue: 0.83, alpha: 1), glow: 0.7),
            at: SCNVector3(0, 0.108, 0.092)
        ))
        root.position = SCNVector3(0, -0.01, 0)
        root.eulerAngles.y = -0.35
        return root
    }

    /// Looking-Glass / Sony stage: colored cube (faces!), torus to look through,
    /// sphere in front of the glass, books behind. Relative parallax + occlusion.
    private func buildDiorama() -> SCNNode {
        let root = SCNNode()
        let gold = mat(NSColor(red: 0.92, green: 0.74, blue: 0.28, alpha: 1), glow: 0.4)
        let stone = mat(NSColor(red: 0.55, green: 0.52, blue: 0.48, alpha: 1), glow: 0.22)
        let pop = mat(NSColor(red: 1.0, green: 0.86, blue: 0.18, alpha: 1), glow: 0.55)
        let teal = mat(NSColor(red: 0.22, green: 0.62, blue: 0.58, alpha: 1), glow: 0.38)
        let red = mat(NSColor(red: 0.78, green: 0.24, blue: 0.22, alpha: 1), glow: 0.38)

        let pedestal = node(SCNCylinder(radius: 0.09, height: 0.018), stone, at: SCNVector3(0, -0.078, 0))
        root.addChildNode(pedestal)

        let cube = faceBox(size: 0.055)
        cube.position = SCNVector3(0.0, -0.012, 0.0)
        cube.eulerAngles.y = 0.18
        root.addChildNode(cube)

        let ring = node(SCNTorus(ringRadius: 0.078, pipeRadius: 0.016), gold)
        ring.eulerAngles.x = .pi / 2
        ring.position = SCNVector3(0.0, -0.008, 0.0)
        root.addChildNode(ring)

        root.addChildNode(node(SCNSphere(radius: 0.028), pop, at: SCNVector3(0.11, 0.04, 0.09)))
        root.addChildNode(node(SCNBox(width: 0.08, height: 0.11, length: 0.024, chamferRadius: 0.003), teal, at: SCNVector3(-0.10, -0.02, -0.14)))
        root.addChildNode(node(SCNBox(width: 0.07, height: 0.09, length: 0.022, chamferRadius: 0.003), red, at: SCNVector3(-0.11, -0.032, -0.17)))

        let mug = buildMug()
        mug.scale = SCNVector3(0.42, 0.42, 0.42)
        mug.position = SCNVector3(0.095, -0.04, -0.06)
        mug.eulerAngles.y = -0.7
        root.addChildNode(mug)
        return root
    }
}
