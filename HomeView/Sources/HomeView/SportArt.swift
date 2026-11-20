import AppKit
import QuartzCore

/// Sport to‘plari — CoreGraphics bilan bir marta chiziladi (64×64), keyin kerakli o‘lchamga cho‘ziladi.
enum SportArt {
    private static let box = CGSize(width: 64, height: 64)
    private static let center = CGPoint(x: 32, y: 32)

    private static func clipToBall(_ ctx: CGContext) {
        ctx.addEllipse(in: CGRect(x: 3, y: 3, width: 58, height: 58))
        ctx.clip()
    }

    private static func arc(_ ctx: CGContext, center: CGPoint, radius: CGFloat, from start: CGFloat, to end: CGFloat,
                            color: CGColor, width: CGFloat) {
        ctx.beginPath()
        ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.strokePath()
    }

    static let volleyball: CGImage? = Art.image(SportArt.box) { ctx in
        Art.circle(ctx, 29, at: SportArt.center, cg(0xFFFFFF))
        ctx.saveGState()
        SportArt.clipToBall(ctx)
        SportArt.arc(ctx, center: CGPoint(x: 6, y: 58), radius: 38, from: -1.2, to: 0.1, color: cg(0xFDD835), width: 9)
        SportArt.arc(ctx, center: CGPoint(x: 64, y: 20), radius: 36, from: 1.7, to: 3.0, color: cg(0x1E88E5), width: 9)
        SportArt.arc(ctx, center: CGPoint(x: 18, y: -4), radius: 34, from: 0.2, to: 1.45, color: cg(0xFDD835), width: 9)
        ctx.restoreGState()
        Art.circle(ctx, 29, at: SportArt.center, nil, stroke: cg(0x37474F), lineWidth: 2.5)
    }

    static let football: CGImage? = Art.image(SportArt.box) { ctx in
        Art.circle(ctx, 29, at: SportArt.center, cg(0xFFFFFF))
        ctx.saveGState()
        SportArt.clipToBall(ctx)
        let dark = cg(0x212121)
        var pentagon: [CGPoint] = []
        for index in 0..<5 {
            let angle: CGFloat = CGFloat(index) * 2 * .pi / 5 + .pi / 2
            pentagon.append(CGPoint(x: 32 + cos(angle) * 10, y: 32 + sin(angle) * 10))
        }
        Art.poly(ctx, pentagon, dark)
        for corner in pentagon {
            let dx: CGFloat = corner.x - 32
            let dy: CGFloat = corner.y - 32
            let outer = CGPoint(x: 32 + dx * 2.9, y: 32 + dy * 2.9)
            Art.line(ctx, [corner, outer], dark, width: 2)
            Art.circle(ctx, 7, at: outer, dark)
        }
        ctx.restoreGState()
        Art.circle(ctx, 29, at: SportArt.center, nil, stroke: cg(0x424242), lineWidth: 2.5)
    }

    static let basketball: CGImage? = Art.image(SportArt.box) { ctx in
        Art.circle(ctx, 29, at: SportArt.center, cg(0xEF6C00))
        ctx.saveGState()
        SportArt.clipToBall(ctx)
        let seam = cg(0x3E2723)
        Art.line(ctx, [CGPoint(x: 32, y: 2), CGPoint(x: 32, y: 62)], seam, width: 2.2)
        Art.line(ctx, [CGPoint(x: 2, y: 32), CGPoint(x: 62, y: 32)], seam, width: 2.2)
        SportArt.arc(ctx, center: CGPoint(x: -6, y: 32), radius: 30, from: -1.1, to: 1.1, color: seam, width: 2.2)
        SportArt.arc(ctx, center: CGPoint(x: 70, y: 32), radius: 30, from: 2.04, to: 4.24, color: seam, width: 2.2)
        Art.circle(ctx, 9, at: CGPoint(x: 22, y: 44), cg(0xFFFFFF, 0.18))
        ctx.restoreGState()
        Art.circle(ctx, 29, at: SportArt.center, nil, stroke: cg(0x3E2723), lineWidth: 2.5)
    }

    static let pingPong: CGImage? = Art.image(SportArt.box) { ctx in
        Art.circle(ctx, 29, at: SportArt.center, cg(0xFFF8E1), stroke: cg(0xBDBDBD), lineWidth: 2)
        Art.circle(ctx, 10, at: CGPoint(x: 23, y: 42), cg(0xFFFFFF, 0.9))
    }
}
