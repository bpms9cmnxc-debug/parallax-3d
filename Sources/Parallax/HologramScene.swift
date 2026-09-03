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
    private var pendingEye = EyeWorld(x: 0, y: 0.02, z: 0.55)
    private var pendingModelId: String?
    private var pendingImported: SCNNode?
    private var pendingScale: Float?
    private var modelScale: Float = 1

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
        scene.fogEndDistance = 4.5
        scene.fogStartDistance = 1.4
        scene.fogDensityExponent = 1.2

        camera.zNear = 0.04
        camera.zFar = 8
        camera.fieldOfView = 32
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0.02, 0.55)
        scene.rootNode.addChildNode(cameraNode)
        scene.rootNode.addChildNode(room)
        scene.rootNode.addChildNode(stage)
        addLights()
        rebuildRoom()
        applyModel("mug")
    }

    func resize(aspect: Float) {
        let w = 0.235 * max(aspect, 0.5)
        eyeLock.lock()
        let unchanged = abs(w - screenW) < 0.002
        if !unchanged {
            screenH = 0.235
            screenW = w
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
        case "import":
            model = imported ?? SCNNode()
        default:
            model = buildMug()
        }
        if model.parent !== stage {
            model.removeFromParentNode()
            stage.addChildNode(model)
        }
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
            stage.simdScale = SIMD3(repeating: modelScale)
        }
        applyEye(e, screenW: sw, screenH: sh)
        elapsed += dt
    }

    private func applyEye(_ eye: EyeWorld, screenW: Float, screenH: Float) {
        let e = SIMD3<Float>(eye.x, eye.y, max(0.12, eye.z))
        cameraNode.position = SCNVector3(e.x, e.y, e.z)
        cameraNode.eulerAngles = SCNVector3Zero
        cameraNode.orientation = SCNQuaternion(0, 0, 0, 1)
        let f = OffAxis.frustum(eye: e, screenW: screenW, screenH: screenH)
        camera.projectionTransform = SCNMatrix4(OffAxis.projectionMatrix(
            left: f.left, right: f.right, top: f.top, bottom: f.bottom, near: f.near, far: f.far
        ))
    }

    private func addLights() {
        let amb = SCNNode()
        amb.light = SCNLight()
        amb.light?.type = .ambient
        amb.light?.color = NSColor(white: 0.72, alpha: 1)
        amb.light?.intensity = 220
        scene.rootNode.addChildNode(amb)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.color = NSColor(white: 0.95, alpha: 1)
        key.light?.intensity = 900
        key.light?.castsShadow = true
        key.position = SCNVector3(0.4, 0.55, 0.7)
        key.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(key)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .omni
        rim.light?.color = NSColor(red: 0.91, green: 0.76, blue: 0.60, alpha: 1)
        rim.light?.intensity = 500
        rim.position = SCNVector3(0, 0.02, -0.02)
        scene.rootNode.addChildNode(rim)
    }

    private func rebuildRoom() {
        room.childNodes.forEach { $0.removeFromParentNode() }
        let w = CGFloat(screenW)
        let h = CGFloat(screenH)
        let d: CGFloat = 1.15
        let wall = SCNMaterial()
        wall.diffuse.contents = NSColor(red: 0.063, green: 0.071, blue: 0.094, alpha: 1)
        wall.roughness.contents = 0.86
        wall.metalness.contents = 0.08
        wall.lightingModel = .physicallyBased

        func plane(_ sw: CGFloat, _ sh: CGFloat) -> SCNNode {
            let n = SCNNode(geometry: SCNPlane(width: sw, height: sh))
            n.geometry?.firstMaterial = wall
            return n
        }

        let floor = plane(w, d)
        floor.eulerAngles.x = -.pi / 2
        floor.position = SCNVector3(0, -h / 2, -d / 2)
        room.addChildNode(floor)

        let ceil = plane(w, d)
        ceil.eulerAngles.x = .pi / 2
        ceil.position = SCNVector3(0, h / 2, -d / 2)
        room.addChildNode(ceil)

        let back = plane(w, h)
        back.position = SCNVector3(0, 0, -d)
        room.addChildNode(back)

        let left = plane(d, h)
        left.eulerAngles.y = .pi / 2
        left.position = SCNVector3(-w / 2, 0, -d / 2)
        room.addChildNode(left)

        let right = plane(d, h)
        right.eulerAngles.y = -.pi / 2
        right.position = SCNVector3(w / 2, 0, -d / 2)
        room.addChildNode(right)

        room.addChildNode(volumeGrid(w: w, h: h, d: d))

        let edge = SCNMaterial()
        edge.diffuse.contents = NSColor(red: 0.545, green: 0.576, blue: 0.620, alpha: 1)
        edge.metalness.contents = 0.85
        edge.roughness.contents = 0.38
        edge.lightingModel = .physicallyBased
        let t: CGFloat = 0.012
        let bars: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (w + t * 2, t, 0, h / 2 + t / 2),
            (w + t * 2, t, 0, -h / 2 - t / 2),
            (t, h + t * 2, -w / 2 - t / 2, 0),
            (t, h + t * 2, w / 2 + t / 2, 0),
        ]
        for b in bars {
            let geo = SCNBox(width: b.0, height: b.1, length: 0.028, chamferRadius: 0)
            geo.firstMaterial = edge
            let n = SCNNode(geometry: geo)
            n.position = SCNVector3(b.2, b.3, 0)
            room.addChildNode(n)
        }
    }

    private func volumeGrid(w: CGFloat, h: CGFloat, d: CGFloat) -> SCNNode {
        let g = SCNNode()
        var verts: [SCNVector3] = []
        let nx = 8, ny = 5, nz = 9
        let x0 = -w / 2, y0 = -h / 2
        let z0: CGFloat = 0.04, z1 = -d * 0.92
        for iz in 0...nz {
            let z = z0 + (z1 - z0) * CGFloat(iz) / CGFloat(nz)
            for ix in 0...nx {
                let x = x0 + w * CGFloat(ix) / CGFloat(nx)
                verts.append(SCNVector3(x, y0, z))
                verts.append(SCNVector3(x, y0 + h, z))
            }
            for iy in 0...ny {
                let y = y0 + h * CGFloat(iy) / CGFloat(ny)
                verts.append(SCNVector3(x0, y, z))
                verts.append(SCNVector3(x0 + w, y, z))
            }
        }
        for ix in 0...nx {
            let x = x0 + w * CGFloat(ix) / CGFloat(nx)
            for iy in 0...ny {
                let y = y0 + h * CGFloat(iy) / CGFloat(ny)
                verts.append(SCNVector3(x, y, z0))
                verts.append(SCNVector3(x, y, z1))
            }
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
        mat.diffuse.contents = NSColor(red: 0.24, green: 0.27, blue: 0.31, alpha: 1)
        mat.emission.contents = NSColor(red: 0.18, green: 0.22, blue: 0.25, alpha: 1)
        mat.lightingModel = .constant
        geo.firstMaterial = mat
        g.addChildNode(SCNNode(geometry: geo))

        let floor = SCNNode(geometry: SCNGeometry.lines(
            from: gridFloor(size: min(w, d) * 0.92, n: 12)
        ))
        floor.geometry?.firstMaterial = mat
        floor.position = SCNVector3(0, -h / 2 + 0.001, -d * 0.42)
        g.addChildNode(floor)
        return g
    }

    private func gridFloor(size: CGFloat, n: Int) -> [SCNVector3] {
        var v: [SCNVector3] = []
        let h = size / 2
        for i in 0...n {
            let t = -h + size * CGFloat(i) / CGFloat(n)
            v.append(SCNVector3(t, 0, -h))
            v.append(SCNVector3(t, 0, h))
            v.append(SCNVector3(-h, 0, t))
            v.append(SCNVector3(h, 0, t))
        }
        return v
    }

    private func metal(_ color: NSColor, roughness: CGFloat = 0.28, metalness: CGFloat = 0.92) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = metalness
        m.roughness.contents = roughness
        return m
    }

    private func clay(_ color: NSColor) -> SCNMaterial {
        metal(color, roughness: 0.45, metalness: 0.08)
    }

    private func node(_ geo: SCNGeometry, _ mat: SCNMaterial, at p: SCNVector3 = SCNVector3Zero) -> SCNNode {
        geo.firstMaterial = mat
        let n = SCNNode(geometry: geo)
        n.position = p
        n.castsShadow = true
        return n
    }

    private func buildMug() -> SCNNode {
        let root = SCNNode()
        let cup = clay(NSColor(red: 0.937, green: 0.910, blue: 0.863, alpha: 1))
        let drink = metal(NSColor(red: 0.24, green: 0.14, blue: 0.09, alpha: 1), roughness: 0.2, metalness: 0.05)
        let band = metal(NSColor(red: 0.369, green: 0.918, blue: 0.831, alpha: 1), roughness: 0.3, metalness: 0.35)

        root.addChildNode(node(SCNCylinder(radius: 0.055, height: 0.1), cup))
        let rim = node(SCNTorus(ringRadius: 0.053, pipeRadius: 0.006), cup, at: SCNVector3(0, 0.05, 0))
        rim.eulerAngles.x = .pi / 2
        root.addChildNode(rim)
        let liquid = node(SCNCylinder(radius: 0.046, height: 0.004), drink, at: SCNVector3(0, 0.038, 0))
        root.addChildNode(liquid)
        let handle = node(SCNTorus(ringRadius: 0.032, pipeRadius: 0.009), cup, at: SCNVector3(0.062, 0.004, 0))
        handle.eulerAngles.y = .pi / 2
        handle.eulerAngles.z = 0.45
        root.addChildNode(handle)
        let stripe = node(SCNTorus(ringRadius: 0.054, pipeRadius: 0.0045), band, at: SCNVector3(0, -0.008, 0))
        stripe.eulerAngles.x = .pi / 2
        root.addChildNode(stripe)
        root.addChildNode(node(SCNCylinder(radius: 0.041, height: 0.01), cup, at: SCNVector3(0, -0.055, 0)))
        root.position = SCNVector3(0, 0.01, -0.06)
        return root
    }

    private func buildBust() -> SCNNode {
        let root = SCNNode()
        let stone = clay(NSColor(red: 0.85, green: 0.827, blue: 0.78, alpha: 1))
        let dark = clay(NSColor(red: 0.16, green: 0.18, blue: 0.21, alpha: 1))
        let hair = clay(NSColor(red: 0.604, green: 0.565, blue: 0.518, alpha: 1))
        let live = metal(NSColor(red: 0.369, green: 0.918, blue: 0.831, alpha: 1), roughness: 0.35, metalness: 0.2)

        let cranium = node(SCNSphere(radius: 0.055), stone, at: SCNVector3(0, 0.118, 0))
        cranium.scale = SCNVector3(0.95, 1.05, 0.92)
        root.addChildNode(cranium)
        let jaw = node(SCNSphere(radius: 0.042), stone, at: SCNVector3(0, 0.078, 0.008))
        jaw.scale = SCNVector3(0.9, 0.78, 0.95)
        root.addChildNode(jaw)
        let nose = node(SCNCone(topRadius: 0, bottomRadius: 0.011, height: 0.03), stone, at: SCNVector3(0, 0.108, 0.052))
        nose.eulerAngles.x = .pi / 2
        root.addChildNode(nose)
        root.addChildNode(node(SCNBox(width: 0.055, height: 0.008, length: 0.018, chamferRadius: 0), stone, at: SCNVector3(0, 0.128, 0.038)))
        for sx in [-1.0, 1.0] {
            let socket = node(SCNSphere(radius: 0.012), dark, at: SCNVector3(sx * 0.02, 0.116, 0.046))
            socket.scale = SCNVector3(1, 0.7, 0.45)
            root.addChildNode(socket)
            root.addChildNode(node(SCNSphere(radius: 0.006), live, at: SCNVector3(sx * 0.02, 0.116, 0.052)))
            let ear = node(SCNSphere(radius: 0.016), stone, at: SCNVector3(sx * 0.056, 0.11, -0.002))
            ear.scale = SCNVector3(0.35, 1, 0.7)
            root.addChildNode(ear)
        }
        root.addChildNode(node(SCNBox(width: 0.022, height: 0.004, length: 0.008, chamferRadius: 0), dark, at: SCNVector3(0, 0.086, 0.044)))
        let hairCap = node(SCNSphere(radius: 0.058), hair, at: SCNVector3(0, 0.128, -0.004))
        hairCap.eulerAngles.x = -0.15
        root.addChildNode(hairCap)
        root.addChildNode(node(SCNCylinder(radius: 0.023, height: 0.05), stone, at: SCNVector3(0, 0.038, 0)))
        root.addChildNode(node(SCNBox(width: 0.16, height: 0.05, length: 0.07, chamferRadius: 0.01), stone, at: SCNVector3(0, 0.005, 0)))
        root.addChildNode(node(SCNCylinder(radius: 0.044, height: 0.02), stone, at: SCNVector3(0, 0.022, 0)))
        root.addChildNode(node(
            SCNBox(width: 0.12, height: 0.024, length: 0.08, chamferRadius: 0),
            metal(NSColor(red: 0.773, green: 0.800, blue: 0.839, alpha: 1), roughness: 0.4),
            at: SCNVector3(0, -0.03, 0)
        ))
        root.position = SCNVector3(0, -0.02, -0.055)
        return root
    }

    private func buildCar() -> SCNNode {
        let root = SCNNode()
        let paint = metal(NSColor(red: 0.773, green: 0.800, blue: 0.839, alpha: 1), roughness: 0.22, metalness: 0.7)
        let dark = metal(NSColor(red: 0.10, green: 0.11, blue: 0.125, alpha: 1), roughness: 0.7, metalness: 0.15)
        let glass = metal(NSColor(red: 0.54, green: 0.64, blue: 0.72, alpha: 1), roughness: 0.08, metalness: 0.2)
        glass.transparency = 0.28
        let lamp = SCNMaterial()
        lamp.lightingModel = .physicallyBased
        lamp.diffuse.contents = NSColor(red: 0.369, green: 0.918, blue: 0.831, alpha: 1)
        lamp.emission.contents = NSColor(red: 0.369, green: 0.918, blue: 0.831, alpha: 1)
        let tail = SCNMaterial()
        tail.lightingModel = .physicallyBased
        tail.diffuse.contents = NSColor(red: 0.77, green: 0.35, blue: 0.31, alpha: 1)
        tail.emission.contents = NSColor(red: 0.77, green: 0.35, blue: 0.31, alpha: 1)
        let hubMat = metal(NSColor(white: 0.82, alpha: 1), roughness: 0.25)

        root.addChildNode(node(SCNBox(width: 0.22, height: 0.045, length: 0.11, chamferRadius: 0.008), paint, at: SCNVector3(0, 0.048, 0)))
        root.addChildNode(node(SCNBox(width: 0.07, height: 0.02, length: 0.1, chamferRadius: 0.004), paint, at: SCNVector3(0.075, 0.078, 0)))
        root.addChildNode(node(SCNBox(width: 0.1, height: 0.055, length: 0.1, chamferRadius: 0.006), glass, at: SCNVector3(-0.02, 0.098, 0)))
        root.addChildNode(node(SCNBox(width: 0.09, height: 0.012, length: 0.1, chamferRadius: 0.004), paint, at: SCNVector3(-0.025, 0.13, 0)))
        root.addChildNode(node(SCNBox(width: 0.02, height: 0.025, length: 0.12, chamferRadius: 0), dark, at: SCNVector3(0.12, 0.04, 0)))
        root.addChildNode(node(SCNBox(width: 0.016, height: 0.022, length: 0.12, chamferRadius: 0), dark, at: SCNVector3(-0.118, 0.038, 0)))
        root.addChildNode(node(SCNBox(width: 0.008, height: 0.016, length: 0.05, chamferRadius: 0), dark, at: SCNVector3(0.122, 0.058, 0)))
        for sz in [-1.0, 1.0] {
            let light = node(SCNCylinder(radius: 0.012, height: 0.01), lamp, at: SCNVector3(0.122, 0.06, sz * 0.038))
            light.eulerAngles.z = .pi / 2
            root.addChildNode(light)
            root.addChildNode(node(SCNBox(width: 0.008, height: 0.012, length: 0.022, chamferRadius: 0), tail, at: SCNVector3(-0.126, 0.055, sz * 0.04)))
        }
        for pair in [(0.07, 0.06), (0.07, -0.06), (-0.07, 0.06), (-0.07, -0.06)] {
            let wheel = node(SCNCylinder(radius: 0.028, height: 0.022), dark, at: SCNVector3(pair.0, 0.028, pair.1))
            wheel.eulerAngles.z = .pi / 2
            root.addChildNode(wheel)
            let hub = node(SCNCylinder(radius: 0.012, height: 0.024), hubMat, at: SCNVector3(pair.0, 0.028, pair.1))
            hub.eulerAngles.z = .pi / 2
            root.addChildNode(hub)
        }
        root.addChildNode(node(
            SCNBox(width: 0.2, height: 0.006, length: 0.012, chamferRadius: 0),
            metal(NSColor(red: 0.369, green: 0.918, blue: 0.831, alpha: 1), roughness: 0.3, metalness: 0.3),
            at: SCNVector3(0, 0.072, 0.056)
        ))
        root.position = SCNVector3(0, -0.03, -0.05)
        root.eulerAngles.y = -0.55
        return root
    }
}

private extension SCNGeometry {
    static func lines(from verts: [SCNVector3]) -> SCNGeometry {
        let src = SCNGeometrySource(vertices: verts)
        var idx: [UInt32] = []
        for i in stride(from: 0, to: verts.count, by: 2) {
            idx.append(UInt32(i))
            idx.append(UInt32(i + 1))
        }
        let data = idx.withUnsafeBufferPointer { Data(buffer: $0) }
        let el = SCNGeometryElement(data: data, primitiveType: .line, primitiveCount: verts.count / 2, bytesPerIndex: 4)
        return SCNGeometry(sources: [src], elements: [el])
    }
}

private extension SCNMatrix4 {
    init(_ m: simd_float4x4) {
        self.init(
            m11: CGFloat(m.columns.0.x), m12: CGFloat(m.columns.1.x), m13: CGFloat(m.columns.2.x), m14: CGFloat(m.columns.3.x),
            m21: CGFloat(m.columns.0.y), m22: CGFloat(m.columns.1.y), m23: CGFloat(m.columns.2.y), m24: CGFloat(m.columns.3.y),
            m31: CGFloat(m.columns.0.z), m32: CGFloat(m.columns.1.z), m33: CGFloat(m.columns.2.z), m34: CGFloat(m.columns.3.z),
            m41: CGFloat(m.columns.0.w), m42: CGFloat(m.columns.1.w), m43: CGFloat(m.columns.2.w), m44: CGFloat(m.columns.3.w)
        )
    }
}
