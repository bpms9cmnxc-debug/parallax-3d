import SwiftUI

struct EyeTrackingOverlay: View {
    var preview: NSImage?
    var left: CGPoint?
    var right: CGPoint?
    var face: CGRect?
    var tracking: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ParallaxTheme.surface
                if let preview {
                    Image(nsImage: preview)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .scaleEffect(x: -1, y: 1)
                } else {
                    Text("Kamera aus  ·  Demo aktiv")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(ParallaxTheme.muted)
                }

                Canvas { ctx, size in
                    if let face {
                        let r = vis(face, size)
                        var path = Path(roundedRect: r, cornerRadius: 4)
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
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .allowsHitTesting(false)
    }

    private func vis(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: (1 - p.x) * size.width, y: (1 - p.y) * size.height)
    }

    private func vis(_ r: CGRect, _ size: CGSize) -> CGRect {
        // Vision box origin is bottom-left; preview is selfie-mirrored.
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
