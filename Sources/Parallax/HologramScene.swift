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
    private var modelId = "orrery"
    private var screenW: Float = 0.4
    private var screenH: Float = 0.25
    private var rings: [(SCNNode, SIMD3<Float>, Float)] = []
    private var planets: [(SCNNode, Float, Float, Float)] = []
    private var elapsed: Float = 0

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
        setModel("orrery")
    }

    func resize(aspect: Float) {
        let w = 0.235 * max(aspect, 0.5)
        if abs(w - screenW) < 0.002 { return }
        screenH = 0.235
        screenW = w
        rebuildRoom()
    }

    func setModel(_ id: String) {
        guard id != modelId || model.parent == nil else { return }
        modelId = id
        model.removeFromParentNode()
        rings.removeAll()
        planets.removeAll()
        switch id {
        case "relic": model = buildRelic()
        case "vessel": model = buildVessel()
        default: model = buildOrrery()
        }
        stage.addChildNode(model)
    }

    func applyEye(_ eye: EyeWorld) {
        let e = SIMD3<Float>(eye.x, eye.y, max(0.12, eye.z))
        cameraNode.position = SCNVector3(e.x, e.y, e.z)
        cameraNode.eulerAngles = SCNVector3Zero
        let f = OffAxis.frustum(eye: e, screenW: screenW, screenH: screenH)
        camera.projectionTransform = SCNMatrix4(OffAxis.projectionMatrix(
            left: f.left, right: f.right, top: f.top, bottom: f.bottom, near: f.near, far: f.far
        ))
    }

    func tick(dt: Float) {
        elapsed += dt
        for (node, axis, spin) in rings {
            node.simdEulerAngles += axis * spin * dt
        }
        for i in planets.indices {
            planets[i].3 += planets[i].2 * dt
            let p = planets[i]
            p.0.simdPosition = SIMD3(
                cos(p.3) * p.1,
                0.01 * sin(p.3 * 2),
                sin(p.3) * p.1
            )
        }
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

    private func metal(_ color: NSColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = 0.92
        m.roughness.contents = 0.28
        return m
    }

    private func buildOrrery() -> SCNNode {
        let root = SCNNode()
        let sunMat = SCNMaterial()
        sunMat.lightingModel = .physicallyBased
        sunMat.diffuse.contents = NSColor(red: 0.95, green: 0.84, blue: 0.70, alpha: 1)
        sunMat.emission.contents = NSColor(red: 0.91, green: 0.76, blue: 0.60, alpha: 1)
        sunMat.roughness.contents = 0.35
        let sun = SCNNode(geometry: SCNSphere(radius: 0.048))
        sun.geometry?.firstMaterial = sunMat
        root.addChildNode(sun)

        let ringR: [CGFloat] = [0.11, 0.155, 0.2, 0.245]
        let tilts: [Float] = [0.18, 1.05, 0.55, -0.7]
        let spins: [Float] = [0.22, -0.16, 0.12, -0.09]
        let axes: [SIMD3<Float>] = [
            SIMD3(0, 1, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1),
        ]
        for i in ringR.indices {
            let torus = SCNTorus(ringRadius: ringR[i], pipeRadius: 0.0032)
            torus.firstMaterial = metal(NSColor(red: 0.773, green: 0.800, blue: 0.839, alpha: 1))
            let n = SCNNode(geometry: torus)
            n.simdEulerAngles.x = tilts[i]
            root.addChildNode(n)
            rings.append((n, axes[i], spins[i]))
        }
        for i in ringR.indices {
            let p = SCNNode(geometry: SCNSphere(radius: 0.012 + CGFloat(i) * 0.003))
            p.geometry?.firstMaterial = metal(NSColor(white: 0.7 - CGFloat(i) * 0.08, alpha: 1))
            root.addChildNode(p)
            planets.append((p, Float(ringR[i]), 0.35 - Float(i) * 0.05, Float(i) * 1.2))
        }
        let mark = SCNNode(geometry: SCNBox(width: 0.018, height: 0.018, length: 0.05, chamferRadius: 0))
        mark.geometry?.firstMaterial = metal(NSColor(red: 0.369, green: 0.918, blue: 0.831, alpha: 1))
        mark.position = SCNVector3(0.22, 0.04, 0.08)
        root.addChildNode(mark)
        root.position = SCNVector3(0, 0.015, -0.02)
        return root
    }

    private func buildRelic() -> SCNNode {
        let root = SCNNode()
        let knot = SCNNode(geometry: SCNTorus(ringRadius: 0.075, pipeRadius: 0.022))
        knot.geometry?.firstMaterial = metal(NSColor(red: 0.773, green: 0.800, blue: 0.839, alpha: 1))
        root.addChildNode(knot)
        rings.append((knot, SIMD3(0, 1, 0), 0.18))
        let cage = SCNNode(geometry: SCNSphere(radius: 0.175))
        let wire = SCNMaterial()
        wire.diffuse.contents = NSColor(white: 0.6, alpha: 0.35)
        wire.fillMode = .lines
        wire.lightingModel = .constant
        cage.geometry?.firstMaterial = wire
        root.addChildNode(cage)
        rings.append((cage, SIMD3(0, 1, 0), 0.12))
        let blade = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: 0.012, height: 0.11))
        blade.geometry?.firstMaterial = metal(NSColor(red: 0.369, green: 0.918, blue: 0.831, alpha: 1))
        blade.eulerAngles.z = .pi / 2
        blade.position = SCNVector3(0.14, 0.02, 0.05)
        root.addChildNode(blade)
        root.position = SCNVector3(0, 0.02, -0.01)
        return root
    }

    private func buildVessel() -> SCNNode {
        let root = SCNNode()
        let body = metal(NSColor(red: 0.773, green: 0.800, blue: 0.839, alpha: 1))
        let dark = metal(NSColor(red: 0.16, green: 0.18, blue: 0.21, alpha: 1))
        let hull = SCNNode(geometry: SCNCapsule(capRadius: 0.038, height: 0.16))
        hull.geometry?.firstMaterial = body
        hull.eulerAngles.z = .pi / 2
        root.addChildNode(hull)
        let nose = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: 0.038, height: 0.08))
        nose.geometry?.firstMaterial = body
        nose.eulerAngles.z = -.pi / 2
        nose.position.x = 0.13
        root.addChildNode(nose)
        let wingL = SCNNode(geometry: SCNBox(width: 0.08, height: 0.006, length: 0.14, chamferRadius: 0))
        wingL.geometry?.firstMaterial = dark
        wingL.position = SCNVector3(-0.02, 0, 0.08)
        wingL.eulerAngles.y = 0.25
        let wingR = wingL.clone()
        wingR.position.z = -0.08
        wingR.eulerAngles.y = -0.25
        root.addChildNode(wingL)
        root.addChildNode(wingR)
        let engine = SCNNode(geometry: SCNCylinder(radius: 0.02, height: 0.03))
        let em = SCNMaterial()
        em.diffuse.contents = NSColor(red: 0.95, green: 0.84, blue: 0.70, alpha: 1)
        em.emission.contents = NSColor(red: 0.95, green: 0.84, blue: 0.70, alpha: 1)
        engine.geometry?.firstMaterial = em
        engine.eulerAngles.z = .pi / 2
        engine.position.x = -0.12
        root.addChildNode(engine)
        root.eulerAngles.y = -0.35
        root.position = SCNVector3(0, 0.01, 0.02)
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
