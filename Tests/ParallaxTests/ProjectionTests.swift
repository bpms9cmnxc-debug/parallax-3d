import ParallaxCore
import simd
import XCTest

final class ProjectionTests: XCTestCase {
    func testCenteredEyeIsSymmetric() {
        let f = OffAxis.frustum(eye: SIMD3(0, 0, 0.55), screenW: 0.4, screenH: 0.25)
        XCTAssertEqual(f.left, -f.right, accuracy: 0.0001)
        XCTAssertEqual(f.bottom, -f.top, accuracy: 0.0001)
        XCTAssertGreaterThan(f.near, 0)
        XCTAssertLessThan(f.near, 0.55)
    }

    func testLookFromTheRightShearsFrustum() {
        let center = OffAxis.frustum(eye: SIMD3(0, 0, 0.55), screenW: 0.4, screenH: 0.25)
        let right = OffAxis.frustum(eye: SIMD3(0.12, 0, 0.55), screenW: 0.4, screenH: 0.25)
        XCTAssertLessThan(right.left, center.left)
        XCTAssertLessThan(right.right, center.right)
    }

    func testCloserHeadShrinksNearRelativeFrustum() {
        let far = OffAxis.faceToWorld(midX: 0.5, midY: 0.5, ipdNorm: 0.04, screenW: 0.4, screenH: 0.25, sensitivity: 1)
        let near = OffAxis.faceToWorld(midX: 0.5, midY: 0.5, ipdNorm: 0.12, screenW: 0.4, screenH: 0.25, sensitivity: 1)
        XCTAssertGreaterThan(far.z, near.z)
    }

    func testSelfieXFlips() {
        let left = OffAxis.faceToWorld(midX: 0.25, midY: 0.5, ipdNorm: 0.08, screenW: 0.4, screenH: 0.25, sensitivity: 1)
        let right = OffAxis.faceToWorld(midX: 0.75, midY: 0.5, ipdNorm: 0.08, screenW: 0.4, screenH: 0.25, sensitivity: 1)
        XCTAssertGreaterThan(left.x, 0)
        XCTAssertLessThan(right.x, 0)
    }

    func testMacMirrorInvertsX() {
        let unmirrored = OffAxis.faceToWorld(
            midX: 0.75, midY: 0.5, ipdNorm: 0.08, screenW: 0.4, screenH: 0.25, sensitivity: 1, mirrored: false
        )
        let mirrored = OffAxis.faceToWorld(
            midX: 0.75, midY: 0.5, ipdNorm: 0.08, screenW: 0.4, screenH: 0.25, sensitivity: 1, mirrored: true
        )
        XCTAssertLessThan(unmirrored.x, 0)
        XCTAssertGreaterThan(mirrored.x, 0)
        XCTAssertEqual(unmirrored.x, -mirrored.x, accuracy: 0.0001)
    }

    func testProjectionHasPerspectiveDivide() {
        let m = OffAxis.projection(eye: SIMD3(0, 0, 0.55), screenW: 0.4, screenH: 0.25)
        XCTAssertEqual(m.columns.2.w, -1, accuracy: 0.0001)
        XCTAssertEqual(m.columns.3.w, 0, accuracy: 0.0001)
    }

    func testHologramAtScreenIsInsideMetalClip() {
        let eye = SIMD3<Float>(0, 0.02, 0.55)
        let P = OffAxis.projection(eye: eye, screenW: 0.4, screenH: 0.25)
        // World origin (the mug) in camera space: SceneKit looks −Z.
        let cam = SIMD4<Float>(0, -0.02, -0.55, 1)
        let clip = simd_mul(P, cam)
        XCTAssertGreaterThan(abs(clip.w), 0.05)
        let ndc = SIMD3(clip.x / clip.w, clip.y / clip.w, clip.z / clip.w)
        XCTAssertLessThan(abs(ndc.x), 1)
        XCTAssertLessThan(abs(ndc.y), 1)
        XCTAssertGreaterThan(ndc.z, 0)
        XCTAssertLessThan(ndc.z, 1)
    }

    func testCloseFaceDoesNotEnterTheHologram() {
        let close = OffAxis.faceToWorld(midX: 0.5, midY: 0.5, ipdNorm: 0.22, screenW: 0.4, screenH: 0.25, sensitivity: 1)
        XCTAssertGreaterThanOrEqual(close.z, OffAxis.minZ)
        XCTAssertGreaterThan(close.z, OffAxis.near + 0.3)
    }

    func testSideLookIsARealAngle() {
        let side = OffAxis.faceToWorld(
            midX: 0.32, midY: 0.5, ipdNorm: 0.08, screenW: 0.4, screenH: 0.25, sensitivity: 1.4, mirrored: true
        )
        XCTAssertLessThan(side.x, -0.18)
        let angle = atan(abs(side.x) / side.z) * 180 / Float.pi
        XCTAssertGreaterThan(angle, 18)
    }

    func testManualDistanceOverride() {
        let auto = OffAxis.faceToWorld(midX: 0.5, midY: 0.5, ipdNorm: 0.08, screenW: 0.4, screenH: 0.25, sensitivity: 1)
        let forced = OffAxis.faceToWorld(
            midX: 0.5, midY: 0.5, ipdNorm: 0.08, screenW: 0.4, screenH: 0.25, sensitivity: 1, distanceOverride: 0.7
        )
        XCTAssertGreaterThan(abs(auto.z - forced.z), 0.01)
        XCTAssertEqual(forced.z, 0.7, accuracy: 0.001)
    }

    func testCenteredHologramStaysInsideClipAtMinDistance() {
        let eye = SIMD3<Float>(0, 0.02, OffAxis.minZ)
        let P = OffAxis.projection(eye: eye, screenW: 0.4, screenH: 0.25)
        let cam = SIMD4<Float>(0, -0.02, -OffAxis.minZ, 1)
        let clip = simd_mul(P, cam)
        let ndcZ = clip.z / clip.w
        XCTAssertGreaterThan(ndcZ, 0)
        XCTAssertLessThan(ndcZ, 1)
        XCTAssertLessThan(abs(clip.x / clip.w), 0.3)
    }

    func testCalibratedBezelMapsToScreenEdge() {
        var cal = Calibration()
        cal.screenW = 0.40
        cal.screenH = 0.25
        cal.leftNX = 0.30
        cal.rightNX = 0.70
        cal.centerNX = 0.50
        cal.centerNY = 0.50
        cal.ipdAtCenter = 0.08
        cal.zAtCenter = 0.60
        cal.completed = true
        let left = OffAxis.faceToWorld(
            midX: 0.30, midY: 0.50, ipdNorm: 0.08, screenW: 0.4, screenH: 0.25,
            sensitivity: 1, calibration: cal
        )
        let right = OffAxis.faceToWorld(
            midX: 0.70, midY: 0.50, ipdNorm: 0.08, screenW: 0.4, screenH: 0.25,
            sensitivity: 1, calibration: cal
        )
        XCTAssertEqual(left.x, -0.20, accuracy: 0.01)
        XCTAssertEqual(right.x, 0.20, accuracy: 0.01)
    }

    func testLidarOffsetMovesYToScreenCentre() {
        let pkt = TrackerPacket(x: 0.01, y: -0.14, z: 0.62, ipd: 0.063, quality: 0.9, source: "lidar")
        var cal = Calibration()
        cal.iphoneOffsetY = 0.14
        let w = OffAxis.lidarToScreen(pkt, calibration: cal)
        XCTAssertEqual(w.y, 0, accuracy: 0.005)
        XCTAssertEqual(w.z, 0.62, accuracy: 0.001)
    }

    func testFaceHighInImageLooksFromAbove() {
        let high = OffAxis.faceToWorld(midX: 0.5, midY: 0.25, ipdNorm: 0.08, screenW: 0.4, screenH: 0.25, sensitivity: 1)
        let low = OffAxis.faceToWorld(midX: 0.5, midY: 0.75, ipdNorm: 0.08, screenW: 0.4, screenH: 0.25, sensitivity: 1)
        XCTAssertGreaterThan(high.y, 0)
        XCTAssertLessThan(low.y, 0)
    }
}
