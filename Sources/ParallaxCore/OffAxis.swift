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
    /// Closest allowed viewer. Closer than this and the near plane slices the hologram
    /// (“mittig = nichts mehr”). Desk range, not a webcam-fill selfie.
    public static let minZ: Float = 0.45
    public static let maxZ: Float = 0.95
    public static let defaultZ: Float = 0.58
    /// Near plane in metres — small and constant so the model at z≈0 is never clipped.
    public static let near: Float = 0.022
    public static let far: Float = 8
    /// Lateral gain: a modest head move (~15 % of the frame) must already look *around* the object.
    public static let lateralGain: Float = 2.15
    public static let verticalGain: Float = 1.25
    /// Extra yaw/pitch of the object so cube faces and the mug handle appear.
    /// A desk move is only ~12–15°; light-field monitors show ~40°.
    public static let orbitGain: Float = 1.65

    /// Sheared frustum: screen on z = 0, viewer at `eye`. Scene does not rotate.
    public static func frustum(
        eye: SIMD3<Float>,
        screenW: Float,
        screenH: Float,
        nearPad: Float = 0.08,
        far: Float = OffAxis.far
    ) -> (left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) {
        _ = nearPad
        let z = max(minZ, eye.z)
        let near = OffAxis.near
        let pad: Float = 1.02
        let halfW = screenW * 0.5 * pad
        let halfH = screenH * 0.5 * pad
        let left = (near * (-halfW - eye.x)) / z
        let right = (near * (halfW - eye.x)) / z
        let bottom = (near * (-halfH - eye.y)) / z
        let top = (near * (halfH - eye.y)) / z
        return (left, right, bottom, top, near, far)
    }

    /// Column-major OpenGL perspective, remapped to Metal clip Z in [0, 1].
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
        let glToMetal = simd_float4x4(columns: (
            SIMD4(1, 0, 0, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(0, 0, 0.5, 0),
            SIMD4(0, 0, 0.5, 1)
        ))
        return glToMetal * gl
    }

    public static func lookAround(eye: SIMD3<Float>) -> (pitch: Float, yaw: Float) {
        let z = max(minZ, eye.z)
        let yaw = atan2(eye.x, z) * orbitGain
        let pitch = -atan2(eye.y, z) * orbitGain * 0.55
        return (min(0.55, max(-0.55, pitch)), min(1.05, max(-1.05, yaw)))
    }

    public static func projection(eye: SIMD3<Float>, screenW: Float, screenH: Float) -> simd_float4x4 {
        let f = frustum(eye: eye, screenW: screenW, screenH: screenH)
        return projectionMatrix(left: f.left, right: f.right, top: f.top, bottom: f.bottom, near: f.near, far: f.far)
    }

    /// IPD fraction of the frame → metres. 63 mm IPD, ~70° FaceTime FOV.
    public static func rawDistance(ipdNorm: Float) -> Float {
        0.045 / max(ipdNorm, 0.02)
    }

    public static func clampedDistance(ipdNorm: Float) -> Float {
        simd_clamp(rawDistance(ipdNorm: ipdNorm), minZ, maxZ)
    }

    /// Webcam face → viewer in metres.
    /// `distanceOverride` (metres) replaces IPD depth when the user calibrates manually.
    public static func faceToWorld(
        midX: Float,
        midY: Float,
        ipdNorm: Float,
        screenW: Float,
        screenH: Float,
        sensitivity: Float,
        mirrored: Bool = false,
        distanceOverride: Float? = nil,
        calibration: Calibration? = nil
    ) -> EyeWorld {
        if let cal = calibration, cal.completed {
            return calibratedWorld(
                midX: midX, midY: midY, ipdNorm: ipdNorm,
                sensitivity: sensitivity, mirrored: mirrored,
                distanceOverride: distanceOverride, cal: cal
            )
        }
        let nx = mirrored ? (midX - 0.5) * 2 : (0.5 - midX) * 2
        let ny = (0.5 - midY) * 2
        let z = distanceOverride.map { simd_clamp($0, minZ, maxZ) } ?? clampedDistance(ipdNorm: ipdNorm)
        let gain = max(0.6, sensitivity)
        return EyeWorld(
            x: nx * screenW * lateralGain * gain,
            y: ny * screenH * verticalGain * gain,
            z: z
        )
    }

    /// Left bezel sample → −screenW/2, right bezel → +screenW/2. Real window geometry.
    public static func calibratedWorld(
        midX: Float,
        midY: Float,
        ipdNorm: Float,
        sensitivity: Float,
        mirrored: Bool,
        distanceOverride: Float?,
        cal: Calibration
    ) -> EyeWorld {
        _ = mirrored
        let lo = min(cal.leftNX, cal.rightNX)
        let hi = max(cal.leftNX, cal.rightNX)
        let span = max(0.10, hi - lo)
        let t = (midX - lo) / span
        let gain = max(0.7, sensitivity)
        let x = (t - 0.5) * cal.screenW * gain
        let mPer = cal.screenW / span
        let y = (cal.centerNY - midY) * mPer * gain
        let z: Float
        if let d = distanceOverride {
            z = simd_clamp(d, minZ, maxZ)
        } else {
            z = simd_clamp(cal.zAtCenter * (cal.ipdAtCenter / max(ipdNorm, 0.02)), minZ, maxZ)
        }
        return EyeWorld(x: x, y: y, z: z)
    }

    public static func lidarToScreen(
        _ packet: TrackerPacket,
        calibration: Calibration,
        origin: SIMD3<Float> = .zero
    ) -> EyeWorld {
        EyeWorld(
            x: packet.x - origin.x,
            y: packet.y - origin.y + calibration.iphoneOffsetY,
            z: simd_clamp(packet.z, minZ, maxZ)
        )
    }
}
