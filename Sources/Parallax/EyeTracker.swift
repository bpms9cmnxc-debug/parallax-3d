import CoreVideo
import Foundation
import ParallaxCore
import Vision

struct TrackedEyes: Equatable {
    var left: CGPoint?
    var right: CGPoint?
    var face: CGRect?
    var world: EyeWorld
    var ipd: Float
    var tracking: Bool
}

final class EyeTracker {
    private let request: VNDetectFaceLandmarksRequest = {
        let r = VNDetectFaceLandmarksRequest()
        r.revision = 3
        return r
    }()

    func detect(
        buffer: CVPixelBuffer,
        screenW: Float,
        screenH: Float,
        sensitivity: Float,
        mirrored: Bool
    ) -> TrackedEyes? {
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let face = request.results?.first else { return nil }
        let box = face.boundingBox
        let left = pupil(face.landmarks?.leftPupil, fallback: face.landmarks?.leftEye, box: box)
        let right = pupil(face.landmarks?.rightPupil, fallback: face.landmarks?.rightEye, box: box)
        guard let L = left, let R = right else { return nil }

        let midX = Float((L.x + R.x) * 0.5)
        let midY = Float((L.y + R.y) * 0.5)
        let ipd = Float(hypot(L.x - R.x, L.y - R.y))
        let world = OffAxis.faceToWorld(
            midX: midX,
            midY: 1 - midY,
            ipdNorm: ipd,
            screenW: screenW,
            screenH: screenH,
            sensitivity: sensitivity,
            mirrored: mirrored
        )
        return TrackedEyes(
            left: L,
            right: R,
            face: box,
            world: world,
            ipd: ipd,
            tracking: true
        )
    }

    private func pupil(_ region: VNFaceLandmarkRegion2D?, fallback: VNFaceLandmarkRegion2D?, box: CGRect) -> CGPoint? {
        if let region, region.pointCount > 0 {
            return toImage(centroid(region), box: box)
        }
        if let fallback, fallback.pointCount > 0 {
            return toImage(centroid(fallback), box: box)
        }
        return nil
    }

    private func centroid(_ region: VNFaceLandmarkRegion2D) -> CGPoint {
        var x: CGFloat = 0
        var y: CGFloat = 0
        for i in 0..<region.pointCount {
            let p = region.normalizedPoints[i]
            x += p.x
            y += p.y
        }
        let n = CGFloat(max(1, region.pointCount))
        return CGPoint(x: x / n, y: y / n)
    }

    /// Landmark points are relative to the face box; Vision box origin is bottom-left.
    private func toImage(_ p: CGPoint, box: CGRect) -> CGPoint {
        CGPoint(
            x: box.origin.x + p.x * box.width,
            y: box.origin.y + p.y * box.height
        )
    }
}
