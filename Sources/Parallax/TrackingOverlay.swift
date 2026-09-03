import AppKit
import SwiftUI

struct EyeTrackingOverlay: View {
    var preview: NSImage?
    var left: CGPoint?
    var right: CGPoint?
    var face: CGRect?
    var tracking: Bool

    var body: some View {
        ZStack {
            ParallaxTheme.surface
            Canvas { ctx, size in
                if let preview {
                    let img = ctx.resolve(Image(nsImage: preview))
                    ctx.translateBy(x: size.width, y: 0)
                    ctx.scaleBy(x: -1, y: 1)
                    ctx.draw(img, in: CGRect(origin: .zero, size: size))
                    ctx.scaleBy(x: -1, y: 1)
                    ctx.translateBy(x: -size.width, y: 0)
                }

                if let face {
                    let r = vis(face, size)
                    let path = Path(roundedRect: r, cornerRadius: 4)
                    ctx.stroke(
                        path,
                        with: .color(ParallaxTheme.live.opacity(0.55)),
                        style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])
                    )
                }
                if let left, let right {
                    let a = vis(left, size)
                    let b = vis(right, size)
                    var bar = Path()
                    bar.move(to: a)
                    bar.addLine(to: b)
                    ctx.stroke(bar, with: .color(ParallaxTheme.live), lineWidth: 1.4)
                    drawEye(&ctx, at: a, label: "L")
                    drawEye(&ctx, at: b, label: "R")
                }
            }
            if preview == nil {
                Text("Kamera aus  ·  Demo aktiv")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(ParallaxTheme.muted)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .allowsHitTesting(false)
    }

    private func vis(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: (1 - p.x) * size.width, y: (1 - p.y) * size.height)
    }

    private func vis(_ r: CGRect, _ size: CGSize) -> CGRect {
        // Vision box origin is bottom-left; preview is selfie-mirrored in Canvas.
        let x = (1 - (r.minX + r.width)) * size.width
        let y = (1 - (r.minY + r.height)) * size.height
        return CGRect(
            x: x,
            y: y,
            width: r.width * size.width,
            height: r.height * size.height
        )
    }

    private func drawEye(_ ctx: inout GraphicsContext, at p: CGPoint, label: String) {
        let r: CGFloat = 10
        ctx.stroke(
            Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
            with: .color(ParallaxTheme.live),
            lineWidth: 1.6
        )
        ctx.fill(
            Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
            with: .color(ParallaxTheme.fg)
        )
        ctx.draw(
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(ParallaxTheme.live),
            at: CGPoint(x: p.x + 16, y: p.y - 12)
        )
    }
}
