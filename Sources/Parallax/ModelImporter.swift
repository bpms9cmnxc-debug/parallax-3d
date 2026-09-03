import AppKit
import ModelIO
import SceneKit
import SceneKit.ModelIO
import UniformTypeIdentifiers

enum ModelImporter {
    static var allowedTypes: [UTType] {
        let exts = ["obj", "stl", "dae", "usd", "usda", "usdc", "usdz", "scn", "ply", "abc"]
        return exts.compactMap { UTType(filenameExtension: $0) }
    }

    static func load(url: URL) throws -> SCNNode {
        let got = url.startAccessingSecurityScopedResource()
        defer { if got { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()
        if ["glb", "gltf", "fbx"].contains(ext) {
            throw ImportError.unsupported(ext)
        }

        let root: SCNNode
        if ["scn", "dae"].contains(ext) {
            let scene = try SCNScene(url: url, options: nil)
            root = SCNNode()
            for child in scene.rootNode.childNodes {
                root.addChildNode(child.clone())
            }
        } else {
            let asset = MDLAsset(url: url)
            asset.loadTextures()
            if asset.count == 0 {
                throw ImportError.empty
            }
            let scene = SCNScene(mdlAsset: asset)
            root = SCNNode()
            for child in scene.rootNode.childNodes {
                root.addChildNode(child)
            }
        }
        return normalize(root)
    }

    private static func normalize(_ src: SCNNode) -> SCNNode {
        let wrap = SCNNode()
        wrap.addChildNode(src)
        let bb = src.boundingBox
        let min = bb.min
        let max = bb.max
        let center = SIMD3<Float>(
            Float(min.x + max.x) * 0.5,
            Float(min.y + max.y) * 0.5,
            Float(min.z + max.z) * 0.5
        )
        src.simdPosition -= center
        let sizeY = Float(max.y - min.y)
        let maxDim = Swift.max(
            Float(max.x - min.x),
            Swift.max(sizeY, Float(max.z - min.z)),
            1e-5
        )
        let scale = 0.22 / maxDim
        wrap.simdScale = SIMD3(repeating: scale)
        wrap.simdPosition.y = -0.02 + sizeY * 0.5 * scale
        wrap.simdPosition.z = -0.04
        wrap.enumerateHierarchy { node, _ in
            node.castsShadow = true
            guard let geo = node.geometry else { return }
            if geo.materials.isEmpty {
                geo.firstMaterial = fallbackMaterial()
            }
            for mat in geo.materials {
                if mat.lightingModel == .physicallyBased {
                    mat.lightingModel = .phong
                }
                if mat.emission.contents == nil {
                    mat.emission.contents = NSColor(white: 0.22, alpha: 1)
                }
                mat.locksAmbientWithDiffuse = true
                mat.isDoubleSided = true
            }
        }
        return wrap
    }

    private static func fallbackMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .phong
        m.diffuse.contents = NSColor(red: 0.86, green: 0.89, blue: 0.93, alpha: 1)
        m.emission.contents = NSColor(white: 0.28, alpha: 1)
        m.locksAmbientWithDiffuse = true
        m.isDoubleSided = true
        return m
    }

    enum ImportError: LocalizedError {
        case unsupported(String)
        case empty
        var errorDescription: String? {
            switch self {
            case .unsupported(let ext):
                return "Format .\(ext) läuft in der Browser-Demo. Auf dem Mac: OBJ, STL, DAE, USD, USDZ, SCN oder PLY."
            case .empty:
                return "Die Datei enthält kein 3-D-Mesh."
            }
        }
    }
}
