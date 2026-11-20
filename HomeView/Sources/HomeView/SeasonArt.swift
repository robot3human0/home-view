import AppKit
import HomeViewProtocol

/// Fasllarga xos rasmlar: yog‘adigan narsalar, otiladigan "koptoklar", dog‘lar, sovg‘alar,
/// yasaladigan narsalar (qorbola, lolazor, tarvuz uyumi, qo‘riqchi), mashinalar, uchuvchilar.
extension Art {

    // MARK: - Yog‘adigan narsalar (oq rangda chiziladi, emitter rang beradi)

    static let petal: CGImage? = image(CGSize(width: 16, height: 16)) { ctx in
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 8, y: 1.5))
        path.addQuadCurve(to: CGPoint(x: 6.6, y: 13.8), control: CGPoint(x: 0.5, y: 7))
        path.addLine(to: CGPoint(x: 8, y: 12.2))
        path.addLine(to: CGPoint(x: 9.4, y: 13.8))
        path.addQuadCurve(to: CGPoint(x: 8, y: 1.5), control: CGPoint(x: 15.5, y: 7))
        path.closeSubpath()
        fillStroke(ctx, path, fill: color(1, 1, 1), stroke: color(0.75, 0.75, 0.78, 0.8), lineWidth: 0.8)
    }

    static let fluff: CGImage? = image(CGSize(width: 16, height: 16)) { ctx in
        let colors = [color(1, 1, 1, 0.95), color(1, 1, 1, 0)] as CFArray
        let locations: [CGFloat] = [0, 1]
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
            ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: 8, y: 8), startRadius: 0,
                                   endCenter: CGPoint(x: 8, y: 8), endRadius: 7.5, options: [])
        }
        for i in 0..<10 {
            let angle = CGFloat(i) / 10 * .pi * 2
            line(ctx, [CGPoint(x: 8, y: 8), CGPoint(x: 8 + cos(angle) * 7, y: 8 + sin(angle) * 7)],
                 color(1, 1, 1, 0.7), width: 0.4)
        }
        circle(ctx, 1.1, at: CGPoint(x: 8, y: 8), color(0.85, 0.82, 0.75))
    }

    static let leaf: CGImage? = image(CGSize(width: 16, height: 16)) { ctx in
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 8, y: 1))
        path.addQuadCurve(to: CGPoint(x: 8, y: 14.5), control: CGPoint(x: -1, y: 7))
        path.addQuadCurve(to: CGPoint(x: 8, y: 1), control: CGPoint(x: 17, y: 7))
        path.closeSubpath()
        fillStroke(ctx, path, fill: color(1, 1, 1), stroke: color(0.7, 0.7, 0.7, 0.9), lineWidth: 0.7)
        line(ctx, [CGPoint(x: 8, y: 0), CGPoint(x: 8, y: 13.5)], color(0.65, 0.65, 0.65), width: 0.8)
        for y in [CGFloat(5), 8, 11] {
            line(ctx, [CGPoint(x: 8, y: y - 1.5), CGPoint(x: 4.6, y: y + 0.6)], color(0.7, 0.7, 0.7), width: 0.5)
            line(ctx, [CGPoint(x: 8, y: y - 1.5), CGPoint(x: 11.4, y: y + 0.6)], color(0.7, 0.7, 0.7), width: 0.5)
        }
    }

    // MARK: - Otiladigan "koptoklar"

    static func projectile(_ kind: SeasonKind) -> CGImage? {
        switch kind {
        case .winter: return snowball
        case .spring: return roundBall(top: color(1, 0.93, 0.96), bottom: color(0.96, 0.6, 0.74), rim: color(0.85, 0.4, 0.6)) { ctx in
            for (x, y, a) in [(11.0, 20.0, 0.4), (19.0, 12.0, -0.8), (21.0, 21.0, 1.6), (12.0, 10.0, 2.4)] {
                ctx.saveGState()
                ctx.translateBy(x: CGFloat(x), y: CGFloat(y))
                ctx.rotate(by: CGFloat(a))
                ellipse(ctx, CGRect(x: -2, y: -3.5, width: 4, height: 7), color(1, 1, 1, 0.85))
                ctx.restoreGState()
            }
        }
        case .summer: return roundBall(top: color(0.75, 0.9, 1), bottom: color(0.13, 0.53, 0.9), rim: color(0.08, 0.35, 0.7)) { ctx in
            ellipse(ctx, CGRect(x: 9, y: 19, width: 7, height: 5), color(1, 1, 1, 0.75))
            poly(ctx, [CGPoint(x: 14, y: 29), CGPoint(x: 18, y: 29), CGPoint(x: 16, y: 31.5)], color(0.08, 0.35, 0.7))
        }
        case .autumn: return roundBall(top: color(1, 0.8, 0.4), bottom: color(0.85, 0.4, 0.1), rim: color(0.6, 0.3, 0.1)) { ctx in
            for (x, y, a, r, g, b) in [(10.0, 20.0, 0.6, 1.0, 0.85, 0.2), (20.0, 11.0, -0.9, 0.8, 0.2, 0.1),
                                        (21.0, 21.0, 1.9, 0.95, 0.55, 0.1), (11.0, 10.0, 2.6, 0.7, 0.35, 0.1)] {
                ctx.saveGState()
                ctx.translateBy(x: CGFloat(x), y: CGFloat(y))
                ctx.rotate(by: CGFloat(a))
                ellipse(ctx, CGRect(x: -2.6, y: -4.5, width: 5.2, height: 9), color(CGFloat(r), CGFloat(g), CGFloat(b), 0.9))
                ctx.restoreGState()
            }
        }
        }
    }

    private static func roundBall(top: CGColor, bottom: CGColor, rim: CGColor, details: (CGContext) -> Void) -> CGImage? {
        image(CGSize(width: 32, height: 32)) { ctx in
            let r = CGRect(x: 2, y: 2, width: 28, height: 28)
            ctx.saveGState()
            ctx.addEllipse(in: r)
            ctx.clip()
            let colors = [top, bottom] as CFArray
            let locations: [CGFloat] = [0, 1]
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
                ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: 12, y: 21), startRadius: 1,
                                       endCenter: CGPoint(x: 16, y: 16), endRadius: 16, options: [.drawsAfterEndLocation])
            }
            details(ctx)
            ctx.restoreGState()
            ctx.setStrokeColor(rim)
            ctx.setLineWidth(1.2)
            ctx.strokeEllipse(in: r)
        }
    }

    // MARK: - Ekranga tekkandagi dog‘lar

    private enum Scatter { case drops, petals, leaves }

    static func splats(_ kind: SeasonKind) -> [CGImage] {
        (0..<3).compactMap { index -> CGImage? in
            let seed = UInt64(index) + 1
            switch kind {
            case .winter:
                return makeSplat(seed: seed, fill: color(1, 1, 1, 0.96), shade: color(0.86, 0.90, 0.97, 0.55),
                                 rim: color(0.55, 0.65, 0.80, 0.6), drips: true, scatter: .drops)
            case .spring:
                return makeSplat(seed: seed, fill: color(1, 0.93, 0.96, 0.92), shade: color(0.97, 0.7, 0.8, 0.5),
                                 rim: color(0.9, 0.5, 0.65, 0.6), drips: false, scatter: .petals)
            case .summer:
                return makeSplat(seed: seed, fill: color(0.78, 0.92, 1, 0.72), shade: color(0.45, 0.72, 0.95, 0.45),
                                 rim: color(0.25, 0.55, 0.9, 0.7), drips: true, scatter: .drops)
            case .autumn:
                return makeSplat(seed: seed, fill: color(1, 0.88, 0.65, 0.55), shade: color(0.92, 0.55, 0.2, 0.4),
                                 rim: color(0.7, 0.4, 0.15, 0.5), drips: false, scatter: .leaves)
            }
        }
    }

    private static func makeSplat(seed: UInt64, fill: CGColor, shade: CGColor, rim: CGColor,
                                  drips: Bool, scatter: Scatter) -> CGImage? {
        var rnd = SeededRandom(seed: seed &* 7919)
        return image(CGSize(width: 220, height: 220)) { ctx in
            let center = CGPoint(x: 110, y: 114)
            if drips {
                for i in 0..<3 {
                    let x = center.x - 34 + CGFloat(i) * 30 + CGFloat(rnd.next(in: -8...8))
                    let length = CGFloat(rnd.next(in: 30...62))
                    let width = CGFloat(rnd.next(in: 7...12))
                    rect(ctx, CGRect(x: x - width / 2, y: center.y - 50 - length, width: width, height: length + 20),
                         fill, radius: width / 2, stroke: rim, lineWidth: 1.5)
                }
            }
            var points: [CGPoint] = []
            for i in 0..<22 {
                let angle = CGFloat(i) / 22 * .pi * 2
                var radius = CGFloat(rnd.next(in: 54...74))
                if i % 3 == 0 { radius += CGFloat(rnd.next(in: 6...18)) }
                points.append(CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
            }
            let blob = smoothClosedPath(points)
            fillStroke(ctx, blob, fill: fill, stroke: nil, lineWidth: 0)
            ctx.saveGState()
            ctx.addPath(blob)
            ctx.clip()
            ctx.setFillColor(shade)
            ctx.fillEllipse(in: CGRect(x: center.x - 20, y: center.y - 80, width: 110, height: 70))
            ctx.restoreGState()
            fillStroke(ctx, blob, fill: nil, stroke: rim, lineWidth: 2)

            for i in 0..<14 {
                let angle = CGFloat(rnd.next(in: 0...(2 * Double.pi)))
                let distance = CGFloat(rnd.next(in: 40...97))
                let p = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
                switch scatter {
                case .drops:
                    circle(ctx, CGFloat(rnd.next(in: 2.5...7)), at: p, fill, stroke: rim, lineWidth: 1)
                case .petals, .leaves:
                    ctx.saveGState()
                    ctx.translateBy(x: p.x, y: p.y)
                    ctx.rotate(by: angle + CGFloat(rnd.next(in: -1...1)))
                    let tint: CGColor
                    if scatter == .petals {
                        tint = i % 2 == 0 ? color(0.97, 0.72, 0.82) : color(1, 0.95, 0.97)
                    } else {
                        let palette = [color(0.98, 0.75, 0.18), color(0.96, 0.49, 0.0), color(0.78, 0.16, 0.16)]
                        tint = palette[i % 3]
                    }
                    let size = CGFloat(rnd.next(in: 7...13))
                    ellipse(ctx, CGRect(x: -size * 0.32, y: -size / 2, width: size * 0.64, height: size), tint,
                            stroke: color(0, 0, 0, 0.15), lineWidth: 0.6)
                    ctx.restoreGState()
                }
            }
        }
    }

    // MARK: - Sovg‘alar (Qorbobo, qushlar va havo shari tashlab ketadi)

    static func gift(_ kind: SeasonKind) -> Part {
        switch kind {
        case .winter:
            return part(CGRect(x: -8.5, y: -1, width: 17, height: 17)) { ctx in
                let ribbon = cg(0xFFEB3B)
                rect(ctx, CGRect(x: -7.5, y: 0, width: 15, height: 12), cg(0xE53935), radius: 1.5, stroke: cg(0xB71C1C), lineWidth: 0.8)
                rect(ctx, CGRect(x: -1.3, y: 0, width: 2.6, height: 12), ribbon)
                rect(ctx, CGRect(x: -7.5, y: 5, width: 15, height: 2.4), ribbon)
                ellipse(ctx, CGRect(x: -6, y: 11, width: 5.5, height: 4), ribbon)
                ellipse(ctx, CGRect(x: 0.5, y: 11, width: 5.5, height: 4), ribbon)
            }
        case .spring:
            return part(CGRect(x: -9, y: -1, width: 18, height: 21)) { ctx in
                poly(ctx, [CGPoint(x: -6, y: 9), CGPoint(x: 6, y: 9), CGPoint(x: 0, y: 0)], cg(0xFFF3E0), stroke: cg(0xBCAAA4), lineWidth: 0.8)
                for (x, hex) in [(CGFloat(-4), UInt32(0xE53935)), (0, 0xFDD835), (4, 0xEC407A)] {
                    line(ctx, [CGPoint(x: x * 0.4, y: 6), CGPoint(x: x, y: 13)], cg(0x388E3C), width: 1.2)
                    ellipse(ctx, CGRect(x: x - 2.8, y: 12, width: 5.6, height: 6.5), cg(hex))
                }
            }
        case .summer:
            return part(CGRect(x: -7, y: -1, width: 14, height: 22)) { ctx in
                poly(ctx, [CGPoint(x: -5, y: 10), CGPoint(x: 5, y: 10), CGPoint(x: 0, y: 0)], cg(0xD7A86E), stroke: cg(0x8D6E63), lineWidth: 0.8)
                line(ctx, [CGPoint(x: -3, y: 7), CGPoint(x: 2, y: 2)], cg(0x8D6E63), width: 0.5)
                line(ctx, [CGPoint(x: 3, y: 7), CGPoint(x: -2, y: 2)], cg(0x8D6E63), width: 0.5)
                circle(ctx, 5, at: CGPoint(x: 0, y: 12), cg(0xF8BBD0))
                circle(ctx, 4.2, at: CGPoint(x: 0, y: 17), whiteColor, stroke: cg(0xE0E0E0), lineWidth: 0.5)
                circle(ctx, 1, at: CGPoint(x: 0.5, y: 21), cg(0xE53935))
            }
        case .autumn:
            return part(CGRect(x: -8, y: -1, width: 16, height: 17)) { ctx in
                circle(ctx, 7, at: CGPoint(x: 0, y: 7), cg(0xC62828), stroke: cg(0x8E1B1B), lineWidth: 0.8)
                poly(ctx, [CGPoint(x: -2.5, y: 13), CGPoint(x: -3, y: 16), CGPoint(x: -1, y: 14.4), CGPoint(x: 0, y: 16.2),
                           CGPoint(x: 1, y: 14.4), CGPoint(x: 3, y: 16), CGPoint(x: 2.5, y: 13)], cg(0x8E1B1B))
                ellipse(ctx, CGRect(x: -4, y: 7, width: 3, height: 4), cg(0xFFFFFF, 0.35))
            }
        }
    }

    // MARK: - Yasaladigan narsa (qorbola / lolazor / tarvuz uyumi / qo‘riqchi)
    // Joylashuv har doim bir xil: pastki qism — (0,0), o‘rta — (0,34), yuqori — (0,51).

    struct MonumentParts {
        let bottom: Part
        let middleBall: Part
        let middleDecor: Part
        let headBall: Part
        let face: Part
        let topper: Part
        /// Bosqichlarga qarab "tegish" balandligi.
        let hitHeights: [CGFloat]
    }

    static func monumentParts(_ kind: SeasonKind) -> MonumentParts {
        switch kind {
        case .winter:
            let parts = snowman
            let scarves: [UInt32] = [0xD32F2F, 0x1E88E5, 0x43A047, 0xFB8C00, 0x8E24AA, 0x00897B]
            let hatColors: [UInt32] = [0xC62828, 0x1E88E5, 0x2E7D32, 0x6A1B9A, 0xEF6C00]
            return MonumentParts(bottom: parts.bottom, middleBall: parts.middleBall,
                                 middleDecor: snowmanDecor(scarf: scarves.randomElement() ?? 0xD32F2F),
                                 headBall: parts.headBall, face: parts.face,
                                 topper: snowmanHat(HatKind.allCases.randomElement() ?? .topHat, color: hatColors.randomElement() ?? 0xC62828),
                                 hitHeights: [28, 45, 62])
        case .spring: return tulipBed()
        case .summer: return melonPile()
        case .autumn: return scarecrow()
        }
    }

    private static func tulipBed() -> MonumentParts {
        let stems: [CGFloat] = [-14, -7, 0, 7, 14]
        let green = cg(0x388E3C)
        let bottom = part(CGRect(x: -25, y: -4, width: 50, height: 18)) { ctx in
            ellipse(ctx, CGRect(x: -24, y: -3, width: 48, height: 13), cg(0x6D4C41))
            ellipse(ctx, CGRect(x: -21, y: 3, width: 42, height: 6), cg(0x8D6E63))
            for x in stride(from: CGFloat(-18), through: 18, by: 6) {
                line(ctx, [CGPoint(x: x, y: 7), CGPoint(x: x + 1.5, y: 11.5)], cg(0x66BB6A), width: 1)
            }
        }
        let middle = part(CGRect(x: -20, y: -34, width: 40, height: 26)) { ctx in
            for (i, x) in stems.enumerated() {
                line(ctx, [CGPoint(x: x, y: -32), CGPoint(x: x * 0.9, y: -10)], green, width: 1.6)
                let side: CGFloat = i % 2 == 0 ? 1 : -1
                poly(ctx, [CGPoint(x: x, y: -28), CGPoint(x: x + side * 5.5, y: -21), CGPoint(x: x, y: -17)], cg(0x43A047))
            }
        }
        let flowerColors: [UInt32] = [0xE53935, 0xFDD835, 0xEC407A, 0xE53935, 0x8E24AA].shuffled()
        let decor = part(CGRect(x: -26, y: -35, width: 52, height: 10)) { ctx in
            for x in [CGFloat(-21), 20] {
                for k in 0..<5 {
                    let a = CGFloat(k) / 5 * .pi * 2
                    circle(ctx, 1.3, at: CGPoint(x: x + cos(a) * 1.8, y: -30 + sin(a) * 1.8), whiteColor)
                }
                circle(ctx, 1, at: CGPoint(x: x, y: -30), cg(0xFDD835))
            }
        }
        let head = part(CGRect(x: -20, y: -30, width: 40, height: 13)) { ctx in
            for (i, x) in stems.enumerated() {
                let cx = x * 0.9
                let hex = flowerColors[i % flowerColors.count]
                ellipse(ctx, CGRect(x: cx - 3.5, y: -28, width: 7, height: 8), cg(hex))
                poly(ctx, [CGPoint(x: cx - 3.5, y: -22), CGPoint(x: cx - 2.2, y: -18.5), CGPoint(x: cx, y: -21.5),
                           CGPoint(x: cx + 2.2, y: -18.5), CGPoint(x: cx + 3.5, y: -22)], cg(hex))
            }
        }
        let face = part(CGRect(x: 8, y: -17, width: 13, height: 10)) { ctx in
            ellipse(ctx, CGRect(x: 11, y: -14, width: 7, height: 5), cg(0xFDD835))
            line(ctx, [CGPoint(x: 13.5, y: -14), CGPoint(x: 13.5, y: -9)], cg(0x212121), width: 1)
            line(ctx, [CGPoint(x: 15.5, y: -14), CGPoint(x: 15.5, y: -9)], cg(0x212121), width: 1)
            ellipse(ctx, CGRect(x: 12, y: -10, width: 4, height: 3), cg(0xFFFFFF, 0.8))
        }
        let wing = [0x42A5F5, 0xFFB300, 0xAB47BC, 0xEF5350].randomElement() ?? 0x42A5F5
        let topper = part(CGRect(x: -8, y: -14, width: 16, height: 12)) { ctx in
            ellipse(ctx, CGRect(x: -7, y: -9, width: 7, height: 6), cg(UInt32(wing)))
            ellipse(ctx, CGRect(x: 0, y: -9, width: 7, height: 6), cg(UInt32(wing)))
            ellipse(ctx, CGRect(x: -5, y: -13, width: 5, height: 4), blend(UInt32(wing), 0xFFFFFF, 0.3))
            ellipse(ctx, CGRect(x: 0, y: -13, width: 5, height: 4), blend(UInt32(wing), 0xFFFFFF, 0.3))
            line(ctx, [CGPoint(x: 0, y: -13), CGPoint(x: 0, y: -4)], cg(0x212121), width: 1.2)
        }
        return MonumentParts(bottom: bottom, middleBall: middle, middleDecor: decor, headBall: head,
                             face: face, topper: topper, hitHeights: [16, 30, 44])
    }

    private static func melon(_ ctx: CGContext, center: CGPoint) {
        ellipse(ctx, CGRect(x: center.x - 7.5, y: center.y - 6, width: 15, height: 12), cg(0x2E7D32), stroke: cg(0x1B5E20), lineWidth: 0.8)
        for dx in [CGFloat(-4), 0, 4] {
            line(ctx, [CGPoint(x: center.x + dx * 0.6, y: center.y - 5.4), CGPoint(x: center.x + dx, y: center.y),
                       CGPoint(x: center.x + dx * 0.6, y: center.y + 5.4)], cg(0x1B5E20), width: 1)
        }
        ellipse(ctx, CGRect(x: center.x - 4.5, y: center.y + 1, width: 4, height: 2.6), cg(0xFFFFFF, 0.25))
    }

    private static func melonPile() -> MonumentParts {
        let bottom = part(CGRect(x: -27, y: -1, width: 54, height: 17)) { ctx in
            rect(ctx, CGRect(x: -26, y: 0, width: 52, height: 4), cg(0x8D6E63), radius: 1, stroke: cg(0x5D4037), lineWidth: 0.6)
            for x in [CGFloat(-15), 0, 15] { melon(ctx, center: CGPoint(x: x, y: 9.5)) }
        }
        let middle = part(CGRect(x: -17, y: -22, width: 34, height: 14)) { ctx in
            for x in [CGFloat(-8), 8] { melon(ctx, center: CGPoint(x: x, y: -15)) }
        }
        let qovun = [0xFBC02D, 0xF9A825, 0xFFCA28].randomElement() ?? 0xFBC02D
        let decor = part(CGRect(x: -38, y: -35, width: 76, height: 28)) { ctx in
            ellipse(ctx, CGRect(x: 20, y: -34, width: 15, height: 10), cg(UInt32(qovun)), stroke: blend(UInt32(qovun), 0x000000, 0.25), lineWidth: 0.7)
            line(ctx, [CGPoint(x: 22, y: -29), CGPoint(x: 33, y: -29)], blend(UInt32(qovun), 0x000000, 0.2), width: 0.5)
            line(ctx, [CGPoint(x: -31, y: -34), CGPoint(x: -31, y: -16)], cg(0x6D4C41), width: 1.6)
            rect(ctx, CGRect(x: -37, y: -17, width: 12, height: 9), cg(0xFFF8E1), radius: 1.5, stroke: cg(0x8D6E63), lineWidth: 0.8)
            poly(ctx, [CGPoint(x: -35, y: -14), CGPoint(x: -27, y: -14), CGPoint(x: -31, y: -10)], cg(0xE53935))
        }
        let head = part(CGRect(x: -9, y: -28, width: 18, height: 14)) { ctx in
            melon(ctx, center: CGPoint(x: 0, y: -21))
        }
        let face = part(CGRect(x: 3, y: -20, width: 14, height: 10)) { ctx in
            poly(ctx, [CGPoint(x: 4, y: -18), CGPoint(x: 16, y: -18), CGPoint(x: 10, y: -11)], cg(0xE53935))
            line(ctx, [CGPoint(x: 4, y: -18), CGPoint(x: 16, y: -18)], cg(0x2E7D32), width: 1.6)
            for x in [CGFloat(8), 10, 12] { circle(ctx, 0.5, at: CGPoint(x: x, y: -15), cg(0x212121)) }
        }
        let topper = part(CGRect(x: -6, y: -16, width: 12, height: 9)) { ctx in
            ellipse(ctx, CGRect(x: -5, y: -15, width: 10, height: 7), cg(UInt32(qovun)), stroke: blend(UInt32(qovun), 0x000000, 0.25), lineWidth: 0.6)
        }
        return MonumentParts(bottom: bottom, middleBall: middle, middleDecor: decor, headBall: head,
                             face: face, topper: topper, hitHeights: [16, 28, 42])
    }

    private static func pumpkin(_ ctx: CGContext, center: CGPoint, width: CGFloat, height: CGFloat) {
        ellipse(ctx, CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height),
                cg(0xEF6C00), stroke: cg(0xBF360C), lineWidth: 0.8)
        for dx in [-width * 0.2, width * 0.2] {
            line(ctx, [CGPoint(x: center.x + dx * 0.6, y: center.y - height * 0.45), CGPoint(x: center.x + dx, y: center.y),
                       CGPoint(x: center.x + dx * 0.6, y: center.y + height * 0.45)], cg(0xBF360C), width: 0.7)
        }
        rect(ctx, CGRect(x: center.x - 1, y: center.y + height / 2 - 1, width: 2, height: 3), cg(0x558B2F), radius: 0.8)
    }

    private static func scarecrow() -> MonumentParts {
        let straw = cg(0xE6C35C)
        let bottom = part(CGRect(x: -24, y: -1, width: 48, height: 38)) { ctx in
            rect(ctx, CGRect(x: -1.5, y: 0, width: 3, height: 36), cg(0x6D4C41))
            for dx in [CGFloat(-5), -2, 2, 5] {
                line(ctx, [CGPoint(x: 0, y: 10), CGPoint(x: dx, y: 2)], straw, width: 1)
            }
            pumpkin(ctx, center: CGPoint(x: -16, y: 4.5), width: 12, height: 9)
            pumpkin(ctx, center: CGPoint(x: 17, y: 4), width: 10, height: 8)
        }
        let middle = part(CGRect(x: -27, y: -4, width: 54, height: 10)) { ctx in
            rect(ctx, CGRect(x: -22, y: 1, width: 44, height: 2.4), cg(0x6D4C41), radius: 1)
            for x in [CGFloat(-22), 22] {
                for dy in [CGFloat(-2.5), 0, 2.5] {
                    line(ctx, [CGPoint(x: x, y: 2.2), CGPoint(x: x + (x < 0 ? -4 : 4), y: 2.2 + dy)], straw, width: 0.9)
                }
            }
        }
        let shirt = [0xC62828, 0x1565C0, 0x2E7D32, 0x6D4C41].randomElement() ?? 0xC62828
        let decor = part(CGRect(x: -10, y: -12, width: 20, height: 20)) { ctx in
            rect(ctx, CGRect(x: -8, y: -10, width: 16, height: 17), cg(UInt32(shirt)), radius: 2.5,
                 stroke: blend(UInt32(shirt), 0x000000, 0.3), lineWidth: 0.7)
            for x in [CGFloat(-3), 3] {
                line(ctx, [CGPoint(x: x, y: -10), CGPoint(x: x, y: 7)], blend(UInt32(shirt), 0x000000, 0.25), width: 0.6)
            }
            line(ctx, [CGPoint(x: -8, y: -2), CGPoint(x: 8, y: -2)], blend(UInt32(shirt), 0x000000, 0.25), width: 0.6)
            rect(ctx, CGRect(x: 1.5, y: -8, width: 4.5, height: 4.5), cg(0xFBC02D), radius: 0.5)
        }
        let head = part(CGRect(x: -10, y: -10, width: 20, height: 18)) { ctx in
            pumpkin(ctx, center: CGPoint(x: 0, y: -1.5), width: 18, height: 15)
        }
        let face = part(CGRect(x: -7, y: -8, width: 14, height: 10)) { ctx in
            let dark = cg(0x3E2723)
            poly(ctx, [CGPoint(x: -5, y: -0.5), CGPoint(x: -1.5, y: -0.5), CGPoint(x: -3.2, y: 2.6)], dark)
            poly(ctx, [CGPoint(x: 1.5, y: -0.5), CGPoint(x: 5, y: -0.5), CGPoint(x: 3.2, y: 2.6)], dark)
            poly(ctx, [CGPoint(x: -5, y: -4), CGPoint(x: -3, y: -6), CGPoint(x: -1, y: -4.4), CGPoint(x: 1, y: -6),
                       CGPoint(x: 3, y: -4.4), CGPoint(x: 5, y: -4), CGPoint(x: 0, y: -2.6)], dark)
        }
        let band = [0xC62828, 0x1565C0, 0x6A1B9A].randomElement() ?? 0xC62828
        let topper = part(CGRect(x: -13, y: 3, width: 26, height: 11)) { ctx in
            ellipse(ctx, CGRect(x: -12, y: 4, width: 24, height: 4), straw, stroke: cg(0xB8963E), lineWidth: 0.6)
            poly(ctx, [CGPoint(x: -5.5, y: 6), CGPoint(x: 5.5, y: 6), CGPoint(x: 4, y: 12.5), CGPoint(x: -4, y: 12.5)], straw,
                 stroke: cg(0xB8963E), lineWidth: 0.6)
            rect(ctx, CGRect(x: -5.2, y: 6.8, width: 10.4, height: 1.6), cg(UInt32(band)))
        }
        return MonumentParts(bottom: bottom, middleBall: middle, middleDecor: decor, headBall: head,
                             face: face, topper: topper, hitHeights: [36, 50, 66])
    }

    // MARK: - Mashinalar (yo‘l — y=0, o‘ngga qaragan)

    private static var vehicleCache: [String: PlowParts] = [:]

    static func vehicleParts(_ kind: SeasonKind, small: Bool) -> PlowParts {
        let key = "\(kind.rawValue)-\(small)"
        if let cached = vehicleCache[key] { return cached }
        let sprayColor: CGColor = kind == .summer ? cg(0x81D4FA) : (kind == .autumn ? cg(0xF57C00) : whiteColor)
        if let body = ArtPack.part("hv_vehicle_\(kind.rawValue)_\(small ? "small" : "big")",
                                   CGRect(x: -59, y: -2, width: 132, height: 58)),
           let wheel = ArtPack.part("hv_vehicle_wheel", CGRect(x: -9.5, y: -9.5, width: 19, height: 19)) {
            let glow = part(CGRect(x: 20, y: 45, width: 14, height: 14)) { ctx in
                circle(ctx, 7, at: CGPoint(x: 27, y: 52), cg(0xFFC107, 0.45))
            }
            let brush = kind == .autumn ? ArtPack.part("hv_vehicle_brush", CGRect(x: -10, y: -10, width: 20, height: 20)) : nil
            let parts = PlowParts(body: body, glow: glow, wheel: wheel, brush: brush,
                                  sprayColor: sprayColor, alwaysSpray: kind == .summer)
            vehicleCache[key] = parts
            return parts
        }
        let palette: (UInt32, UInt32, UInt32)
        switch (kind, small) {
        case (.winter, false): palette = (0xFF8F00, 0xFFA000, 0xE07000)
        case (.winter, true): palette = (0x1E88E5, 0x42A5F5, 0x1565C0)
        case (.spring, false): palette = (0x43A047, 0x66BB6A, 0x2E7D32)
        case (.spring, true): palette = (0x7CB342, 0x9CCC65, 0x558B2F)
        case (.summer, false): palette = (0x1E88E5, 0x90CAF9, 0x1565C0)
        case (.summer, true): palette = (0x00ACC1, 0x80DEEA, 0x00838F)
        case (.autumn, false): palette = (0xFBC02D, 0xFDD835, 0xF57F17)
        case (.autumn, true): palette = (0xEF6C00, 0xFB8C00, 0xBF360C)
        }
        let main = cg(palette.0)
        let light = cg(palette.1)
        let dark = cg(palette.2)
        let steel = cg(0x37474F)
        let glass = cg(0xB3E5FC)
        let glassRim = cg(0x607D8B)

        let body = part(CGRect(x: -59, y: -2, width: 132, height: 58)) { ctx in
            rect(ctx, CGRect(x: -58, y: 7, width: 108, height: 9), steel, radius: 2)
            // Orqa qism
            if kind == .summer {
                rect(ctx, CGRect(x: -58, y: 17, width: 64, height: 25), light, radius: 12, stroke: dark, lineWidth: 1)
                rect(ctx, CGRect(x: -58, y: 26, width: 64, height: 4), main)
            } else {
                rect(ctx, CGRect(x: -58, y: 16, width: 64, height: 27), main, radius: 3, stroke: dark, lineWidth: 1)
                for x in [CGFloat(-48), -32, -16] {
                    rect(ctx, CGRect(x: x, y: 18, width: 3, height: 23), dark, radius: 1)
                }
                if kind == .spring {
                    for x in stride(from: CGFloat(-52), through: 0, by: 9) {
                        ellipse(ctx, CGRect(x: x, y: 40, width: 11, height: 6), cg(0x6D4C41))
                    }
                } else if kind == .autumn {
                    let leaves = [cg(0xFBC02D), cg(0xEF6C00), cg(0xC62828)]
                    for (i, x) in stride(from: CGFloat(-52), through: 0, by: 6).enumerated() {
                        ellipse(ctx, CGRect(x: x, y: 41, width: 6, height: 4), leaves[i % 3])
                    }
                } else {
                    rect(ctx, CGRect(x: -58, y: 24, width: 64, height: 2.4), cg(0xFFFFFF, 0.85))
                }
            }
            // Kabina
            rect(ctx, CGRect(x: 9, y: 16, width: 37, height: 33), light, radius: 5, stroke: dark, lineWidth: 1)
            rect(ctx, CGRect(x: 25, y: 31, width: 17, height: 13), glass, radius: 2, stroke: glassRim, lineWidth: 1)
            rect(ctx, CGRect(x: 12, y: 31, width: 10, height: 13), glass, radius: 2, stroke: glassRim, lineWidth: 1)
            line(ctx, [CGPoint(x: 23, y: 18), CGPoint(x: 23, y: 44)], dark, width: 1)
            rect(ctx, CGRect(x: 22.5, y: 49, width: 9, height: 5.5), cg(0xFFC107), radius: 2, stroke: cg(0xB28704), lineWidth: 0.8)
            // Old qismidagi moslama
            rect(ctx, CGRect(x: 46, y: 9, width: 12, height: 5), steel, radius: 1)
            switch kind {
            case .winter:
                poly(ctx, [CGPoint(x: 56, y: 1), CGPoint(x: 68, y: -1), CGPoint(x: 72, y: 30), CGPoint(x: 60, y: 27)],
                     cg(0xB0BEC5), stroke: cg(0x546E7A), lineWidth: 1)
            case .spring:
                rect(ctx, CGRect(x: 57, y: 2, width: 3, height: 20), cg(0x78909C), radius: 1)
                for y in stride(from: CGFloat(3), through: 19, by: 4) {
                    line(ctx, [CGPoint(x: 59, y: y), CGPoint(x: 66, y: y - 3)], cg(0x78909C), width: 1.2)
                }
            case .summer:
                rect(ctx, CGRect(x: 56, y: 4, width: 14, height: 3), cg(0x78909C), radius: 1.5)
                for x in [CGFloat(59), 63, 67] { circle(ctx, 1.2, at: CGPoint(x: x, y: 4), cg(0x455A64)) }
            case .autumn:
                line(ctx, [CGPoint(x: 52, y: 12), CGPoint(x: 64, y: 9)], steel, width: 2.4)
            }
        }
        let glow = part(CGRect(x: 20, y: 45, width: 14, height: 14)) { ctx in
            circle(ctx, 7, at: CGPoint(x: 27, y: 52), cg(0xFFD54F, 0.5))
        }
        let wheel = part(CGRect(x: -9.5, y: -9.5, width: 19, height: 19)) { ctx in
            circle(ctx, 9, at: .zero, cg(0x212121))
            circle(ctx, 3.8, at: .zero, cg(0xB0BEC5))
            line(ctx, [CGPoint(x: -6.5, y: 0), CGPoint(x: 6.5, y: 0)], cg(0x616161), width: 1.4)
        }
        var brush: Part?
        if kind == .autumn {
            brush = part(CGRect(x: -10, y: -10, width: 20, height: 20)) { ctx in
                circle(ctx, 9, at: .zero, cg(0x8D6E63), stroke: cg(0x5D4037), lineWidth: 0.8)
                for i in 0..<12 {
                    let a = CGFloat(i) / 12 * .pi * 2
                    line(ctx, [CGPoint(x: cos(a) * 3, y: sin(a) * 3), CGPoint(x: cos(a) * 9.5, y: sin(a) * 9.5)], cg(0x3E2723), width: 1)
                }
            }
        }
        let parts = PlowParts(body: body, glow: glow, wheel: wheel, brush: brush,
                              sprayColor: kind == .summer ? cg(0x81D4FA) : (kind == .autumn ? cg(0xF57C00) : whiteColor),
                              alwaysSpray: kind == .summer)
        vehicleCache[key] = parts
        return parts
    }

    // MARK: - Sozlamalar oynasidagi jonli ko‘rinish uchun yig‘ma rasmlar

    static func workerPreview(_ theme: SeasonTheme) -> Part {
        let parts = workerParts(skin: 0xE0AC69, hatStyle: theme.workerHat, hatColor: theme.workerHatColors.first ?? 0x1E3A5F,
                                vest: 0xF57C00, tool: theme.tool)
        return part(CGRect(x: -10, y: -2, width: 41, height: 46)) { ctx in
            stamp(parts.leg, in: ctx, at: CGPoint(x: -2.6, y: 11), angle: 0.25)
            stamp(parts.leg, in: ctx, at: CGPoint(x: 2.6, y: 11), angle: -0.25)
            stamp(parts.armBack, in: ctx, at: CGPoint(x: -4, y: 22), angle: -0.3)
            stamp(parts.body, in: ctx, at: .zero)
            stamp(parts.armFront, in: ctx, at: CGPoint(x: 3, y: 22), angle: 0.35) { inner in
                stamp(parts.shovel, in: inner, at: .zero)
            }
        }
    }

    static func monumentPreview(_ kind: SeasonKind) -> Part {
        let parts = monumentParts(kind)
        return part(CGRect(x: -38, y: -4, width: 76, height: 76)) { ctx in
            stamp(parts.bottom, in: ctx, at: .zero)
            stamp(parts.middleBall, in: ctx, at: CGPoint(x: 0, y: 34))
            stamp(parts.middleDecor, in: ctx, at: CGPoint(x: 0, y: 34))
            stamp(parts.headBall, in: ctx, at: CGPoint(x: 0, y: 51))
            stamp(parts.face, in: ctx, at: CGPoint(x: 0, y: 51))
            stamp(parts.topper, in: ctx, at: CGPoint(x: 0, y: 51))
        }
    }

    static func vehiclePreview(_ kind: SeasonKind) -> Part {
        let parts = vehicleParts(kind, small: false)
        return part(CGRect(x: -60, y: -3, width: 136, height: 61)) { ctx in
            stamp(parts.body, in: ctx, at: .zero)
            stamp(parts.glow, in: ctx, at: .zero)
            for x in [CGFloat(-42), -22, 30] {
                stamp(parts.wheel, in: ctx, at: CGPoint(x: x, y: 9))
            }
            if let brush = parts.brush {
                stamp(brush, in: ctx, at: CGPoint(x: 64, y: 9))
            }
        }
    }

    /// Ofisdagi odamchangiz (sozlamalar oynasidagi ko‘rinish uchun).
    static func avatarPreview(_ style: AvatarStyle) -> Part {
        let parts = workerParts(skin: style.skinColor, hatStyle: style.hat, hatColor: style.hatColor,
                                vest: style.vestColor, tool: .none, worker: false)
        return part(CGRect(x: -11, y: -1, width: 23, height: 44)) { ctx in
            stamp(parts.leg, in: ctx, at: CGPoint(x: -2.6, y: 11), angle: 0.12)
            stamp(parts.leg, in: ctx, at: CGPoint(x: 2.6, y: 11), angle: -0.12)
            stamp(parts.armBack, in: ctx, at: CGPoint(x: -4, y: 22), angle: -0.2)
            stamp(parts.body, in: ctx, at: .zero)
            stamp(parts.armFront, in: ctx, at: CGPoint(x: 3, y: 22), angle: 0.2)
        }
    }

    // MARK: - Uchuvchilar: qaldirg‘och, turna, havo shari

    struct BirdParts {
        let body: Part
        let wing: Part
    }

    static let swallow: BirdParts = {
        if let body = ArtPack.part("hv_swallow_body", CGRect(x: -15, y: -5, width: 31, height: 10)),
           let wing = ArtPack.part("hv_swallow_wing", CGRect(x: -7, y: -1, width: 11, height: 13)) {
            return BirdParts(body: body, wing: wing)
        }
        let navy = cg(0x1A237E)
        let body = part(CGRect(x: -15, y: -5, width: 31, height: 10)) { ctx in
            poly(ctx, [CGPoint(x: -7, y: 0), CGPoint(x: -14, y: 3.5), CGPoint(x: -10.5, y: 0), CGPoint(x: -14, y: -3.5)], navy)
            ellipse(ctx, CGRect(x: -8, y: -2.6, width: 15, height: 5.2), navy)
            ellipse(ctx, CGRect(x: -4, y: -2.6, width: 9, height: 2.8), cg(0xFFFFFF, 0.9))
            circle(ctx, 2.6, at: CGPoint(x: 7.5, y: 0.6), navy)
            circle(ctx, 1, at: CGPoint(x: 7.8, y: -0.6), cg(0xC62828))
        }
        let wing = part(CGRect(x: -7, y: -1, width: 11, height: 13)) { ctx in
            poly(ctx, [CGPoint(x: -1, y: 0), CGPoint(x: -6, y: 11), CGPoint(x: 1, y: 11.5), CGPoint(x: 3, y: 1)], navy)
        }
        return BirdParts(body: body, wing: wing)
    }()

    static let crane: BirdParts = {
        if let body = ArtPack.part("hv_crane_body", CGRect(x: -20, y: -5, width: 46, height: 12)),
           let wing = ArtPack.part("hv_crane_wing", CGRect(x: -11, y: -1, width: 18, height: 17)) {
            return BirdParts(body: body, wing: wing)
        }
        let body = part(CGRect(x: -20, y: -5, width: 46, height: 12)) { ctx in
            line(ctx, [CGPoint(x: -8, y: -1), CGPoint(x: -19, y: -3)], cg(0x37474F), width: 1)
            ellipse(ctx, CGRect(x: -9, y: -3, width: 18, height: 7), cg(0xECEFF1), stroke: cg(0xB0BEC5), lineWidth: 0.6)
            line(ctx, [CGPoint(x: 8, y: 1), CGPoint(x: 18, y: 4)], cg(0xECEFF1), width: 1.8)
            circle(ctx, 1.8, at: CGPoint(x: 19, y: 4.2), cg(0x263238))
            circle(ctx, 0.8, at: CGPoint(x: 19, y: 5.6), cg(0xC62828))
            line(ctx, [CGPoint(x: 20.5, y: 4), CGPoint(x: 25, y: 3.2)], cg(0x5D4037), width: 1)
        }
        let wing = part(CGRect(x: -11, y: -1, width: 18, height: 17)) { ctx in
            poly(ctx, [CGPoint(x: -2, y: 0), CGPoint(x: -10, y: 14), CGPoint(x: 6, y: 15.5), CGPoint(x: 4, y: 1)], cg(0xCFD8DC))
            poly(ctx, [CGPoint(x: -7.6, y: 10), CGPoint(x: -10, y: 14), CGPoint(x: 6, y: 15.5), CGPoint(x: 5.4, y: 11)], cg(0x263238))
        }
        return BirdParts(body: body, wing: wing)
    }()

    /// Laylak (bahor): oq tana, qora qanot uchlari, qizil tumshuq va oyoqlar.
    /// Rasm to‘plami bo‘lmasa — turna rasmi ishlatiladi.
    static let stork: BirdParts = {
        if let body = ArtPack.part("hv_stork_body", CGRect(x: -30, y: -9, width: 64, height: 18)),
           let wing = ArtPack.part("hv_stork_wing", CGRect(x: -15, y: -1, width: 26, height: 23)) {
            return BirdParts(body: body, wing: wing)
        }
        return crane
    }()

    static let balloon: Part = ArtPack.part("hv_balloon", CGRect(x: -32, y: -1, width: 64, height: 99)) ?? drawnBalloon

    private static let drawnBalloon: Part = part(CGRect(x: -32, y: -1, width: 64, height: 99)) { ctx in
        let envelope = CGRect(x: -30, y: 24, width: 60, height: 72)
        ctx.saveGState()
        ctx.addEllipse(in: envelope)
        ctx.clip()
        let stripes: [UInt32] = [0xE53935, 0xFDD835, 0x1E88E5, 0xFFFFFF, 0xE53935, 0xFDD835]
        for (i, hex) in stripes.enumerated() {
            rect(ctx, CGRect(x: -30 + CGFloat(i) * 10, y: 24, width: 10, height: 72), cg(hex))
        }
        ellipse(ctx, CGRect(x: -22, y: 62, width: 16, height: 24), cg(0xFFFFFF, 0.25))
        ctx.restoreGState()
        ellipse(ctx, envelope, nil, stroke: cg(0x000000, 0.2), lineWidth: 1)
        poly(ctx, [CGPoint(x: -14, y: 30), CGPoint(x: 14, y: 30), CGPoint(x: 7, y: 20), CGPoint(x: -7, y: 20)], cg(0xC62828))
        for (from, to) in [(CGPoint(x: -7, y: 20), CGPoint(x: -8, y: 11)), (CGPoint(x: 7, y: 20), CGPoint(x: 8, y: 11))] {
            line(ctx, [from, to], cg(0x5D4037), width: 0.7)
        }
        circle(ctx, 2.6, at: CGPoint(x: -3.5, y: 13.5), cg(0xF1C27D))
        circle(ctx, 2.6, at: CGPoint(x: 3.5, y: 13.5), cg(0xE0AC69))
        rect(ctx, CGRect(x: -9, y: 0, width: 18, height: 12), cg(0xA1887F), radius: 1.5, stroke: cg(0x5D4037), lineWidth: 0.8)
        for x in [CGFloat(-4.5), 0, 4.5] {
            line(ctx, [CGPoint(x: x, y: 0.5), CGPoint(x: x, y: 11.5)], cg(0x6D4C41), width: 0.5)
        }
    }
}
