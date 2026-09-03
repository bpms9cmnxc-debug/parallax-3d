import ParallaxCore
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

    func testFaceHighInImageLooksFromAbove() {
        let high = OffAxis.faceToWorld(midX: 0.5, midY: 0.25, ipdNorm: 0.08, screenW: 0.4, screenH: 0.25, sensitivity: 1)
        let low = OffAxis.faceToWorld(midX: 0.5, midY: 0.75, ipdNorm: 0.08, screenW: 0.4, screenH: 0.25, sensitivity: 1)
        XCTAssertGreaterThan(high.y, 0)
        XCTAssertLessThan(low.y, 0)
    }
}
