import Foundation
import simd

public struct EyeWorld: Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var z: Float

    public init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

    public var simd: SIMD3<Float> { SIMD3(x, y, z) }
}

public enum OffAxis {
    /// Sheared frustum: screen sits on z = 0, viewer at `eye` (metres).
    /// Moving the eye does not rotate the scene — you look *around* it.
    public static func frustum(
        eye: SIMD3<Float>,
        screenW: Float,
        screenH: Float,
        nearPad: Float = 0.08,
        far: Float = 8
    ) -> (left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) {
        let z = max(0.12, eye.z)
        let near = min(max(0.04, z * nearPad), z * 0.45)
        let halfW = screenW * 0.5
        let halfH = screenH * 0.5
        let left = (near * (-halfW - eye.x)) / z
        let right = (near * (halfW - eye.x)) / z
        let bottom = (near * (-halfH - eye.y)) / z
        let top = (near * (halfH - eye.y)) / z
        return (left, right, bottom, top, near, far)
    }

    /// Column-major 4×4. OpenGL `makePerspective`, then remapped to Metal
    /// clip Z in [0, 1] — SceneKit on Apple Silicon clips anything with NDC z < 0.
    /// (A GL matrix alone puts the hologram at the screen plane at z_ndc ≈ −1…0.8;
    ///  the lattice further back can survive, which looks like “only a grid”.)
    public static func projectionMatrix(
        left: Float, right: Float, top: Float, bottom: Float, near: Float, far: Float
    ) -> simd_float4x4 {
        let x = 2 * near / (right - left)
        let y = 2 * near / (top - bottom)
        let a = (right + left) / (right - left)
        let b = (top + bottom) / (top - bottom)
        let c = -(far + near) / (far - near)
        let d = -2 * far * near / (far - near)
        let gl = simd_float4x4(columns: (
            SIMD4(x, 0, 0, 0),
            SIMD4(0, y, 0, 0),
            SIMD4(a, b, c, -1),
            SIMD4(0, 0, d, 0)
        ))
        // ndc.z_metal = 0.5 * ndc.z_gl + 0.5
        let glToMetal = simd_float4x4(columns: (
            SIMD4(1, 0, 0, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(0, 0, 0.5, 0),
            SIMD4(0, 0, 0.5, 1)
        ))
        return glToMetal * gl
    }

    public static func projection(eye: SIMD3<Float>, screenW: Float, screenH: Float) -> simd_float4x4 {
        let f = frustum(eye: eye, screenW: screenW, screenH: screenH)
        return projectionMatrix(left: f.left, right: f.right, top: f.top, bottom: f.bottom, near: f.near, far: f.far)
    }

    /// Webcam face sample → viewer position in metres.
    /// Unmirrored buffer: face moving to the user's right appears at smaller x.
    /// Mirrored FaceTime buffer (`mirrored: true`): face moving right appears at larger x.
    public static func faceToWorld(
        midX: Float,
        midY: Float,
        ipdNorm: Float,
        screenW: Float,
        screenH: Float,
        sensitivity: Float,
        mirrored: Bool = false
    ) -> EyeWorld {
        let nx = mirrored ? (midX - 0.5) * 2 : (0.5 - midX) * 2
        let ny = (0.5 - midY) * 2
        let z = simd_clamp(0.56 * (0.078 / max(ipdNorm, 0.02)), 0.28, 1.25)
        return EyeWorld(
            x: nx * screenW * 0.72 * sensitivity,
            y: ny * screenH * 0.62 * sensitivity,
            z: z
        )
    }
}
