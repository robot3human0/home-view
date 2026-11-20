import AppKit
import HomeViewProtocol

/// Bir marta chizilgan rasm bo‘lagi. `box` — qism koordinatalaridagi egallagan joyi,
/// (0,0) nuqta esa aylanish markazi (pivot).
struct Part {
    let image: CGImage?
    let box: CGRect

    /// Qism qatlamining ichki koordinatalarida pivot qayerda (bola qatlamlarni qo‘yish uchun).
    var pivotInBounds: CGPoint { CGPoint(x: -box.minX, y: -box.minY) }
}

/// Ilovadagi barcha rasmlar shu yerda kod bilan chiziladi — tashqi rasm fayli yo‘q.
/// Har bir rasm ishga tushganda bir marta tayyorlanadi, keyin faqat ekranda suriladi.
enum Art {
    /// Kod bilan chiziladigan rasmlar aniqligi (har nuqtaga 4 piksel — kattalashtirilganda ham tiniq).
    static let scale: CGFloat = 4
    static let colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    // MARK: - Chizish asboblari

    static func image(_ size: CGSize, _ draw: (CGContext) -> Void) -> CGImage? {
        let width = max(1, Int((size.width * scale).rounded(.up)))
        let height = max(1, Int((size.height * scale).rounded(.up)))
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        draw(ctx)
        return ctx.makeImage()
    }

    static func part(_ box: CGRect, _ draw: (CGContext) -> Void) -> Part {
        let picture = image(box.size) { ctx in
            ctx.translateBy(x: -box.minX, y: -box.minY)
            draw(ctx)
        }
        return Part(image: picture, box: box)
    }

    static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    static func blend(_ a: UInt32, _ b: UInt32, _ t: CGFloat) -> CGColor {
        func channel(_ value: UInt32, _ shift: UInt32) -> CGFloat { CGFloat((value >> shift) & 0xFF) / 255 }
        return CGColor(srgbRed: channel(a, 16) * (1 - t) + channel(b, 16) * t,
                       green: channel(a, 8) * (1 - t) + channel(b, 8) * t,
                       blue: channel(a, 0) * (1 - t) + channel(b, 0) * t,
                       alpha: 1)
    }

    static func fillStroke(_ ctx: CGContext, _ path: CGPath, fill: CGColor?, stroke: CGColor?, lineWidth: CGFloat) {
        if let fill {
            ctx.addPath(path)
            ctx.setFillColor(fill)
            ctx.fillPath()
        }
        if let stroke {
            ctx.addPath(path)
            ctx.setStrokeColor(stroke)
            ctx.setLineWidth(lineWidth)
            ctx.setLineJoin(.round)
            ctx.strokePath()
        }
    }

    static func rect(_ ctx: CGContext, _ r: CGRect, _ fill: CGColor?, radius: CGFloat = 0,
                     stroke: CGColor? = nil, lineWidth: CGFloat = 1) {
        let corner = min(radius, r.width / 2, r.height / 2)
        let path = corner > 0
            ? CGPath(roundedRect: r, cornerWidth: corner, cornerHeight: corner, transform: nil)
            : CGPath(rect: r, transform: nil)
        fillStroke(ctx, path, fill: fill, stroke: stroke, lineWidth: lineWidth)
    }

    static func ellipse(_ ctx: CGContext, _ r: CGRect, _ fill: CGColor?, stroke: CGColor? = nil, lineWidth: CGFloat = 1) {
        fillStroke(ctx, CGPath(ellipseIn: r, transform: nil), fill: fill, stroke: stroke, lineWidth: lineWidth)
    }

    static func circle(_ ctx: CGContext, _ radius: CGFloat, at p: CGPoint, _ fill: CGColor?,
                       stroke: CGColor? = nil, lineWidth: CGFloat = 1) {
        ellipse(ctx, CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2),
                fill, stroke: stroke, lineWidth: lineWidth)
    }

    static func poly(_ ctx: CGContext, _ points: [CGPoint], _ fill: CGColor?, stroke: CGColor? = nil, lineWidth: CGFloat = 1) {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        fillStroke(ctx, path, fill: fill, stroke: stroke, lineWidth: lineWidth)
    }

    static func line(_ ctx: CGContext, _ points: [CGPoint], _ color: CGColor, width: CGFloat) {
        let path = CGMutablePath()
        path.addLines(between: points)
        ctx.addPath(path)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
    }

    // MARK: - Qor, koptok, uchqun, dog‘lar

    /// Qor parchasi (16 pt). Oq oynalar ustida ham ko‘rinishi uchun ingichka ko‘kimtir hoshiyasi bor.
    static let flake: CGImage? = image(CGSize(width: 16, height: 16)) { ctx in
        let r = CGRect(x: 2, y: 2, width: 12, height: 12)
        ctx.setFillColor(color(1, 1, 1))
        ctx.fillEllipse(in: r)
        ctx.setStrokeColor(color(0.55, 0.65, 0.80, 0.65))
        ctx.setLineWidth(1.4)
        ctx.strokeEllipse(in: r)
    }

    static let snowball: CGImage? = image(CGSize(width: 32, height: 32)) { ctx in
        let r = CGRect(x: 2, y: 2, width: 28, height: 28)
        ctx.saveGState()
        ctx.addEllipse(in: r)
        ctx.clip()
        let colors = [color(1, 1, 1), color(0.80, 0.86, 0.95)] as CFArray
        let locations: [CGFloat] = [0, 1]
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
            ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: 12, y: 21), startRadius: 1,
                                   endCenter: CGPoint(x: 16, y: 16), endRadius: 16,
                                   options: [.drawsAfterEndLocation])
        }
        ctx.setFillColor(color(0.72, 0.79, 0.90, 0.6))
        let specks: [(CGFloat, CGFloat, CGFloat)] = [(20, 9, 1.6), (9, 12, 1.2), (22, 18, 1.0), (14, 7, 1.0)]
        for (x, y, radius) in specks {
            ctx.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        }
        ctx.restoreGState()
        ctx.setStrokeColor(color(0.50, 0.60, 0.75, 0.8))
        ctx.setLineWidth(1.2)
        ctx.strokeEllipse(in: r)
    }

    static let sparkle: CGImage? = image(CGSize(width: 16, height: 16)) { ctx in
        let c: CGFloat = 8
        let path = CGMutablePath()
        path.move(to: CGPoint(x: c, y: c + 7.5))
        path.addQuadCurve(to: CGPoint(x: c + 7.5, y: c), control: CGPoint(x: c + 1.2, y: c + 1.2))
        path.addQuadCurve(to: CGPoint(x: c, y: c - 7.5), control: CGPoint(x: c + 1.2, y: c - 1.2))
        path.addQuadCurve(to: CGPoint(x: c - 7.5, y: c), control: CGPoint(x: c - 1.2, y: c - 1.2))
        path.addQuadCurve(to: CGPoint(x: c, y: c + 7.5), control: CGPoint(x: c - 1.2, y: c + 1.2))
        ctx.addPath(path)
        ctx.setFillColor(color(1, 1, 1))
        ctx.fillPath()
    }

    /// Ekranga "yopishgan" qor dog‘ining 3 xil varianti.
    // MARK: - Ishchi (oyoqlari position nuqtasida, o‘ngga qaragan)

    struct WorkerParts {
        let leg: Part
        let armBack: Part
        let armFront: Part
        let shovel: Part
        let body: Part
        let brows: Part
        let blush: Part
    }

    /// Ishchining asbobi: qishda kurak, bahor va kuzda xaskash (grabli), yozda supurgi.
    enum ToolKind {
        case shovel, rake, broom, none
    }

    static func workerParts(skin skinHex: UInt32, hatStyle: HatStyle, hatColor hatHex: UInt32,
                            vest vestHex: UInt32, tool: ToolKind, worker: Bool = true) -> WorkerParts {
        if let realistic = realisticWorkerParts(skin: skinHex, hatStyle: hatStyle, hatColor: hatHex,
                                                vest: vestHex, tool: tool, worker: worker) {
            return realistic
        }
        let pants = cg(0x1F2A44)
        let boot = cg(0x222222)
        let vest = cg(vestHex)
        let vestDark = blend(vestHex, 0x000000, 0.15)
        let mitten = cg(0x333333)
        let reflective = cg(0xE8EEF2, 0.95)
        let skin = cg(skinHex)
        let nose = blend(skinHex, 0xFF0000, 0.25)

        let leg = part(CGRect(x: -2.6, y: -11.2, width: 6.4, height: 11.4)) { ctx in
            rect(ctx, CGRect(x: -2, y: -10, width: 4, height: 10), pants, radius: 1)
            rect(ctx, CGRect(x: -2.4, y: -11, width: 6, height: 3), boot, radius: 1)
        }

        func arm(_ sleeve: CGColor) -> Part {
            part(CGRect(x: -2.4, y: -12.4, width: 4.8, height: 12.6)) { ctx in
                rect(ctx, CGRect(x: -1.8, y: -10, width: 3.6, height: 10), sleeve, radius: 1.5)
                circle(ctx, 2.1, at: CGPoint(x: 0, y: -10), mitten)
            }
        }

        let toolPart = part(CGRect(x: -6, y: -32, width: 27, height: 33)) { ctx in
            drawTool(ctx, tool)
        }

        let body = part(CGRect(x: -9.8, y: 9.6, width: 20.6, height: 33.4)) { ctx in
            rect(ctx, CGRect(x: -7, y: 10, width: 14, height: 14), vest, radius: 3.5)
            rect(ctx, CGRect(x: -7, y: 15, width: 14, height: 2.2), reflective)
            rect(ctx, CGRect(x: -7, y: 19.5, width: 14, height: 1.6), reflective)
            circle(ctx, 5.6, at: CGPoint(x: 0.6, y: 28.6), skin)
            circle(ctx, 0.9, at: CGPoint(x: 3.2, y: 29.6), cg(0x1A1A1A))
            circle(ctx, 1.2, at: CGPoint(x: 5.9, y: 28.2), nose)
            line(ctx, [CGPoint(x: 2.4, y: 26.2), CGPoint(x: 4.6, y: 26.4)], cg(0x5A2A1A), width: 0.9)
            drawWorkerHat(ctx, hatStyle, hatHex)
        }

        let brows = part(CGRect(x: 0.4, y: 29.6, width: 5.2, height: 2.8)) { ctx in
            line(ctx, [CGPoint(x: 1.2, y: 31.6), CGPoint(x: 4.8, y: 30.5)], cg(0x1A1A1A), width: 1.3)
        }

        let blush = part(CGRect(x: 0, y: 24.8, width: 4.8, height: 4.8)) { ctx in
            circle(ctx, 2.2, at: CGPoint(x: 2.4, y: 27.2), cg(0xE53935, 0.55))
        }

        return WorkerParts(leg: leg, armBack: arm(vestDark), armFront: arm(vest), shovel: toolPart,
                           body: body, brows: brows, blush: blush)
    }

    /// Realistik odam: kulrang qismlar tanlangan ranglarga bo‘yaladi.
    /// Ishchida — aks ettiruvchi chiziqli nimcha va qo‘lqop, hamkasbda — kurtka va qo‘l.
    private static func realisticWorkerParts(skin skinHex: UInt32, hatStyle: HatStyle, hatColor hatHex: UInt32,
                                             vest vestHex: UInt32, tool: ToolKind, worker: Bool) -> WorkerParts? {
        guard ArtPack.isAvailable else { return nil }
        let legBox = CGRect(x: -2.6, y: -11.2, width: 6.4, height: 11.4)
        let armBox = CGRect(x: -2.4, y: -12.4, width: 4.8, height: 12.6)
        let bodyBox = CGRect(x: -9.8, y: 9.6, width: 20.6, height: 33.4)
        let toolBox = CGRect(x: -6, y: -32, width: 27, height: 33)
        let skin = cg(skinHex)
        let hat = cg(hatHex)
        let vest = cg(vestHex)
        let vestDark = blend(vestHex, 0x000000, 0.15)
        let handLayer: (String, CGColor?) = worker ? ("hv_person_glove", nil) : ("hv_person_hand", skin)

        var hatLayers: [(String, CGColor?)] = []
        switch hatStyle {
        case .beanie:
            hatLayers = [("hv_hat_beanie", hat), ("hv_hat_beanie_pom", nil)]
        case .cap:
            hatLayers = [("hv_hat_cap", hat)]
        case .doppi:
            hatLayers = [("hv_hat_doppi", nil)]
        case .strawHat:
            hatLayers = [("hv_hat_straw", nil), ("hv_hat_straw_band", hat)]
        }
        var bodyLayers: [(String, CGColor?)] = [("hv_person_torso", vest)]
        bodyLayers.append((worker ? "hv_person_stripes" : "hv_person_jacket", nil))
        bodyLayers.append(("hv_person_head", skin))
        bodyLayers.append(("hv_person_face", nil))
        bodyLayers.append(contentsOf: hatLayers)

        guard let leg = ArtPack.part("hv_person_leg", legBox),
              let armBack = ArtPack.composed(armBox, [("hv_person_sleeve", vestDark), handLayer]),
              let armFront = ArtPack.composed(armBox, [("hv_person_sleeve", vest), handLayer]),
              let body = ArtPack.composed(bodyBox, bodyLayers) else { return nil }

        let toolName: String?
        switch tool {
        case .shovel: toolName = "hv_tool_shovel"
        case .rake: toolName = "hv_tool_rake"
        case .broom: toolName = "hv_tool_broom"
        case .none: toolName = nil
        }
        let toolPart = toolName.flatMap { ArtPack.part($0, toolBox) } ?? part(toolBox) { _ in }

        let brows = part(CGRect(x: 0.4, y: 29.6, width: 5.2, height: 2.8)) { ctx in
            line(ctx, [CGPoint(x: 1.6, y: 31.5), CGPoint(x: 4.6, y: 30.7)], cg(0x2A1C14), width: 0.9)
        }
        let blush = part(CGRect(x: 0, y: 24.8, width: 4.8, height: 4.8)) { ctx in
            circle(ctx, 1.9, at: CGPoint(x: 2.6, y: 27.4), cg(0xE53935, 0.35))
        }
        return WorkerParts(leg: leg, armBack: armBack, armFront: armFront, shovel: toolPart,
                           body: body, brows: brows, blush: blush)
    }

    /// Bosh kiyim: qishki shapka, kepka, do‘ppi yoki somon shlyapa.
    static func drawWorkerHat(_ ctx: CGContext, _ style: HatStyle, _ hex: UInt32) {
        let hat = cg(hex)
        let hatDark = blend(hex, 0x000000, 0.3)
        switch style {
        case .beanie:
            rect(ctx, CGRect(x: -5.6, y: 31.2, width: 12.4, height: 5.4), hat, radius: 2.4)
            rect(ctx, CGRect(x: -6.2, y: 30.4, width: 13.6, height: 2.2), hatDark, radius: 1)
            circle(ctx, 2.3, at: CGPoint(x: 0.6, y: 37.6), whiteColor, stroke: cg(0xC9D3E0), lineWidth: 0.6)
        case .cap:
            rect(ctx, CGRect(x: -5.4, y: 31, width: 12, height: 5.2), hat, radius: 2.6)
            poly(ctx, [CGPoint(x: 5, y: 31.2), CGPoint(x: 10.6, y: 30.6), CGPoint(x: 10.2, y: 32), CGPoint(x: 5, y: 32.8)], hatDark)
            circle(ctx, 0.9, at: CGPoint(x: 0.6, y: 36.2), hatDark)
        case .doppi:
            rect(ctx, CGRect(x: -5.4, y: 31, width: 12, height: 4.8), cg(0x1B1B1B), radius: 1.2)
            line(ctx, [CGPoint(x: -5, y: 31.7), CGPoint(x: 6.2, y: 31.7)], cg(0xF5F5F5), width: 0.6)
            for x in [CGFloat(-2.6), 3.6] {
                ellipse(ctx, CGRect(x: x - 1, y: 32.6, width: 2, height: 2.4), cg(0xF5F5F5))
            }
        case .strawHat:
            ellipse(ctx, CGRect(x: -9.4, y: 30, width: 20, height: 3.4), cg(0xE6C35C), stroke: cg(0xB8963E), lineWidth: 0.6)
            rect(ctx, CGRect(x: -4.6, y: 31.4, width: 10.4, height: 5.2), cg(0xE6C35C), radius: 2,
                 stroke: cg(0xB8963E), lineWidth: 0.6)
            rect(ctx, CGRect(x: -4.6, y: 32, width: 10.4, height: 1.5), hat)
        }
    }

    /// Asbob qo‘l ichida chiziladi (qo‘l osilib turgan holatda, kaft — 0,-10 atrofida).
    static func drawTool(_ ctx: CGContext, _ tool: ToolKind) {
        switch tool {
        case .shovel:
            line(ctx, [CGPoint(x: -3, y: -3), CGPoint(x: 11, y: -21)], cg(0x7B5230), width: 1.8)
            poly(ctx, [CGPoint(x: 9, y: -20), CGPoint(x: 16.5, y: -25), CGPoint(x: 14.5, y: -28.5), CGPoint(x: 7, y: -23.5)],
                 cg(0x90A4AE), stroke: cg(0x546E7A), lineWidth: 0.8)
        case .rake:
            line(ctx, [CGPoint(x: -3, y: -3), CGPoint(x: 12, y: -22)], cg(0x8D6E63), width: 1.6)
            line(ctx, [CGPoint(x: 8.2, y: -25), CGPoint(x: 16, y: -19)], cg(0x78909C), width: 1.6)
            for i in 0..<5 {
                let t = CGFloat(i) / 4
                let base = CGPoint(x: 8.2 + 7.8 * t, y: -25 + 6 * t)
                line(ctx, [base, CGPoint(x: base.x + 2.2, y: base.y - 3)], cg(0x78909C), width: 1)
            }
        case .broom:
            line(ctx, [CGPoint(x: -3, y: -3), CGPoint(x: 10, y: -19)], cg(0xA1887F), width: 1.6)
            poly(ctx, [CGPoint(x: 8, y: -18), CGPoint(x: 12.4, y: -21.2), CGPoint(x: 20, y: -30), CGPoint(x: 9, y: -31)],
                 cg(0xD4A64A), stroke: cg(0x9C7A2E), lineWidth: 0.7)
            line(ctx, [CGPoint(x: 9.2, y: -20.4), CGPoint(x: 11.8, y: -22.4)], cg(0xC62828), width: 1.2)
        case .none:
            break
        }
    }

    // MARK: - Qorbola

    struct SnowmanParts {
        let bottom: Part       // qorbola koordinatalarida (oyoq — 0,0)
        let middleBall: Part   // o‘rta shar markazida
        let headBall: Part     // bosh markazida
        let face: Part
    }

    /// Qorbola shapkasi turlari.
    enum HatKind: CaseIterable {
        case topHat, bucket, doppi, beanie
    }

    /// Shapka (bosh markaziga nisbatan). Har bir qorbola o‘zinikini oladi.
    static func snowmanHat(_ kind: HatKind, color hex: UInt32) -> Part {
        let hatBox = CGRect(x: -9.5, y: 4.5, width: 19, height: 15.5)
        let layers: [(String, CGColor?)]
        switch kind {
        case .topHat: layers = [("hv_sm_tophat", nil), ("hv_sm_tophat_band", cg(hex))]
        case .bucket: layers = [("hv_sm_bucket", cg(hex))]
        case .doppi: layers = [("hv_sm_doppi", nil)]
        case .beanie: layers = [("hv_sm_beanie", cg(hex)), ("hv_sm_pompom", nil)]
        }
        if let realistic = ArtPack.composed(hatBox, layers) {
            return realistic
        }
        return part(CGRect(x: -9.5, y: 4.5, width: 19, height: 15.5)) { ctx in
            switch kind {
            case .topHat:
                rect(ctx, CGRect(x: -8.5, y: 6.2, width: 17, height: 2.6), cg(0x212121), radius: 1)
                rect(ctx, CGRect(x: -5.8, y: 7.5, width: 11.6, height: 10), cg(0x212121), radius: 1.5)
                rect(ctx, CGRect(x: -5.8, y: 9, width: 11.6, height: 2.2), cg(hex))
            case .bucket:
                poly(ctx, [CGPoint(x: -7, y: 5.6), CGPoint(x: 7, y: 5.6), CGPoint(x: 5.4, y: 17), CGPoint(x: -5.4, y: 17)],
                     cg(hex), stroke: blend(hex, 0x000000, 0.35), lineWidth: 0.8)
                rect(ctx, CGRect(x: -7.4, y: 5.4, width: 14.8, height: 2), blend(hex, 0x000000, 0.25), radius: 1)
                line(ctx, [CGPoint(x: -6.5, y: 7), CGPoint(x: -8.5, y: 12), CGPoint(x: -6, y: 15)], cg(0x9E9E9E), width: 0.8)
            case .doppi:
                // O‘zbek do‘ppisi: qora asos, oq qalampir naqshlari va oq hoshiya
                rect(ctx, CGRect(x: -7.6, y: 5.4, width: 15.2, height: 7.6), cg(0x1B1B1B), radius: 2.2)
                line(ctx, [CGPoint(x: -7.2, y: 6.2), CGPoint(x: 7.2, y: 6.2)], cg(0xF5F5F5), width: 0.7)
                for x in [CGFloat(-4.6), 0, 4.6] {
                    let motif = CGMutablePath()
                    motif.move(to: CGPoint(x: x - 1.1, y: 7.4))
                    motif.addQuadCurve(to: CGPoint(x: x + 0.9, y: 11.6), control: CGPoint(x: x - 2.4, y: 10.6))
                    motif.addQuadCurve(to: CGPoint(x: x - 1.1, y: 7.4), control: CGPoint(x: x + 1.4, y: 8.6))
                    fillStroke(ctx, motif, fill: cg(0xF5F5F5), stroke: nil, lineWidth: 0)
                }
            case .beanie:
                ellipse(ctx, CGRect(x: -7.6, y: 5, width: 15.2, height: 11), cg(hex))
                rect(ctx, CGRect(x: -8, y: 5, width: 16, height: 3.2), blend(hex, 0x000000, 0.25), radius: 1.4)
                circle(ctx, 2.6, at: CGPoint(x: 0, y: 16.6), whiteColor, stroke: cg(0xC9D3E0), lineWidth: 0.6)
            }
        }
    }

    /// O‘rta shar bezaklari: qo‘l-shoxchalar, tugmalar va berilgan rangdagi sharf.
    static func snowmanDecor(scarf hex: UInt32) -> Part {
        let decorBox = CGRect(x: -23, y: -8, width: 46, height: 24)
        if let realistic = ArtPack.composed(decorBox, [("hv_sm_decor", nil), ("hv_sm_scarf", cg(hex))]) {
            return realistic
        }
        return part(CGRect(x: -23, y: -8, width: 46, height: 24)) { ctx in
            let wood = cg(0x6D4C41)
            line(ctx, [CGPoint(x: -9, y: 2), CGPoint(x: -21, y: 11)], wood, width: 1.6)
            line(ctx, [CGPoint(x: -17, y: 8), CGPoint(x: -19, y: 14)], wood, width: 1.2)
            line(ctx, [CGPoint(x: 9, y: 2), CGPoint(x: 21, y: 11)], wood, width: 1.6)
            line(ctx, [CGPoint(x: 17, y: 8), CGPoint(x: 22, y: 6)], wood, width: 1.2)
            for y in [CGFloat(3), -1.5, -6] {
                circle(ctx, 1.2, at: CGPoint(x: 0, y: y), cg(0x263238))
            }
            rect(ctx, CGRect(x: -9.5, y: 6.5, width: 19, height: 4.2), cg(hex), radius: 2)
            rect(ctx, CGRect(x: 3, y: -4, width: 4.2, height: 11), blend(hex, 0x000000, 0.15), radius: 1.5)
        }
    }

    static let snowman: SnowmanParts = {
        if let bottom = ArtPack.part("hv_sm_bottom", CGRect(x: -15.5, y: -1.5, width: 31, height: 30)),
           let middle = ArtPack.part("hv_sm_middle", CGRect(x: -11.5, y: -11.5, width: 23, height: 23)),
           let head = ArtPack.part("hv_sm_head", CGRect(x: -9, y: -9, width: 18, height: 18)),
           let face = ArtPack.part("hv_sm_face", CGRect(x: -4.5, y: -5.5, width: 15.5, height: 9.5)) {
            return SnowmanParts(bottom: bottom, middleBall: middle, headBall: head, face: face)
        }
        let rim = cg(0xB4C3D8)
        let bottom = part(CGRect(x: -15.5, y: -1.5, width: 31, height: 30)) { ctx in
            circle(ctx, 14, at: CGPoint(x: 0, y: 13), whiteColor, stroke: rim, lineWidth: 1)
        }
        let middleBall = part(CGRect(x: -11.5, y: -11.5, width: 23, height: 23)) { ctx in
            circle(ctx, 10.5, at: .zero, whiteColor, stroke: rim, lineWidth: 1)
        }
        let headBall = part(CGRect(x: -9, y: -9, width: 18, height: 18)) { ctx in
            circle(ctx, 8, at: .zero, whiteColor, stroke: rim, lineWidth: 1)
        }
        let face = part(CGRect(x: -4.5, y: -5.5, width: 15.5, height: 9.5)) { ctx in
            circle(ctx, 1.2, at: CGPoint(x: -2.8, y: 2.2), cg(0x1A1A1A))
            circle(ctx, 1.2, at: CGPoint(x: 2.8, y: 2.2), cg(0x1A1A1A))
            poly(ctx, [CGPoint(x: 0, y: 0.9), CGPoint(x: 0, y: -1.5), CGPoint(x: 9.5, y: -0.6)], cg(0xFF7A1A))
            for i in 0..<5 {
                let t = CGFloat(i) / 4
                circle(ctx, 0.65, at: CGPoint(x: -3.6 + 7.2 * t, y: -3.3 - sin(t * .pi) * 1.1), cg(0x37474F))
            }
        }
        return SnowmanParts(bottom: bottom, middleBall: middleBall, headBall: headBall, face: face)
    }()

    // MARK: - Qor tozalovchi mashina (g‘ildirak ostidagi yo‘l — y=0, o‘ngga qaragan)

    struct PlowParts {
        let body: Part
        let glow: Part
        let wheel: Part
        /// Kuzgi mashinaning aylanuvchi cho‘tkasi (boshqalarida nil).
        let brush: Part?
        let sprayColor: CGColor
        /// Yozgi suv sepuvchi mashina doim suv sepib yuradi.
        let alwaysSpray: Bool
    }

    // MARK: - Qorbobo, Qorqiz, chana va bug‘ular (chana markazi — 0,0, o‘ngga uchadi)

    struct SantaParts {
        let body: Part
        let reindeer: Part
        let leg: Part
        let shine: Part
    }

    static let santa: SantaParts = {
        if let body = ArtPack.part("hv_santa_body", CGRect(x: -57, y: -9, width: 211, height: 63)),
           let reindeer = ArtPack.part("hv_santa_reindeer", CGRect(x: -17, y: -2, width: 47, height: 36)),
           let leg = ArtPack.part("hv_santa_leg", CGRect(x: -1.5, y: -10.5, width: 3.2, height: 11)),
           let nose = ArtPack.part("hv_santa_nose", CGRect(x: 22.7, y: 9.3, width: 9, height: 9)) {
            // "shine" — oldingi bug‘uning (Rudolf) miltillovchi qizil burni
            return SantaParts(body: body, reindeer: reindeer, leg: leg, shine: nose)
        }
        let gold = cg(0xFFD54F)
        let skin = cg(0xF5CBA7)
        let red = cg(0xD32F2F)

        let body = part(CGRect(x: -57, y: -9, width: 211, height: 63)) { ctx in
            line(ctx, [CGPoint(x: 30, y: 9), CGPoint(x: 70, y: 6), CGPoint(x: 112, y: 6), CGPoint(x: 152, y: 6)],
                 gold, width: 1.1)
            // Sovg‘alar qopi
            circle(ctx, 10, at: CGPoint(x: -46, y: 16), cg(0x8D6E63), stroke: cg(0x5D4037), lineWidth: 1)
            rect(ctx, CGRect(x: -49, y: 24, width: 6, height: 4), cg(0x5D4037), radius: 1.5)
            // Qorqiz
            rect(ctx, CGRect(x: -40, y: 8, width: 13, height: 17), cg(0x1E88E5), radius: 5)
            line(ctx, [CGPoint(x: -37.5, y: 28), CGPoint(x: -39.5, y: 17)], cg(0xC69C3F), width: 2.2)
            circle(ctx, 4.8, at: CGPoint(x: -33.5, y: 29), skin)
            rect(ctx, CGRect(x: -39, y: 32.5, width: 11, height: 4.5), cg(0xE3F2FD), radius: 2,
                 stroke: cg(0x90CAF9), lineWidth: 0.8)
            circle(ctx, 0.8, at: CGPoint(x: -31.5, y: 29.5), cg(0x1A1A1A))
            // Qorbobo
            rect(ctx, CGRect(x: -24, y: 8, width: 19, height: 21), red, radius: 7)
            rect(ctx, CGRect(x: -24, y: 15, width: 19, height: 3), cg(0x212121))
            circle(ctx, 6, at: CGPoint(x: -13, y: 34), skin)
            ellipse(ctx, CGRect(x: -20, y: 23, width: 14, height: 13), whiteColor, stroke: cg(0xCFD8DC), lineWidth: 0.6)
            circle(ctx, 0.9, at: CGPoint(x: -10.5, y: 35.5), cg(0x1A1A1A))
            circle(ctx, 1.4, at: CGPoint(x: -7.5, y: 33), cg(0xE57373))
            poly(ctx, [CGPoint(x: -20, y: 38), CGPoint(x: -6, y: 38), CGPoint(x: -17, y: 50)], red)
            rect(ctx, CGRect(x: -20.5, y: 36.5, width: 15.5, height: 3.2), whiteColor, radius: 1.5)
            circle(ctx, 2.6, at: CGPoint(x: -17, y: 50), whiteColor)
            // Chana
            let sleigh = CGMutablePath()
            sleigh.move(to: CGPoint(x: -46, y: 0))
            sleigh.addLine(to: CGPoint(x: -46, y: 17))
            sleigh.addQuadCurve(to: CGPoint(x: -38, y: 19), control: CGPoint(x: -46, y: 20))
            sleigh.addLine(to: CGPoint(x: 14, y: 11))
            sleigh.addQuadCurve(to: CGPoint(x: 30, y: 17), control: CGPoint(x: 26, y: 9))
            sleigh.addQuadCurve(to: CGPoint(x: 26, y: 0), control: CGPoint(x: 36, y: 4))
            sleigh.closeSubpath()
            fillStroke(ctx, sleigh, fill: cg(0xC62828), stroke: gold, lineWidth: 1.6)
            // Chana oyoqlari
            let runner = CGMutablePath()
            runner.move(to: CGPoint(x: -50, y: -7))
            runner.addLine(to: CGPoint(x: 28, y: -7))
            runner.addQuadCurve(to: CGPoint(x: 38, y: 4), control: CGPoint(x: 40, y: -7))
            fillStroke(ctx, runner, fill: nil, stroke: gold, lineWidth: 2)
            for x in [CGFloat(-36), 12] {
                line(ctx, [CGPoint(x: x, y: -7), CGPoint(x: x, y: 0)], gold, width: 1.6)
            }
        }

        let fur = cg(0x8D6E63)
        let antler = cg(0x5D4037)
        let reindeer = part(CGRect(x: -17, y: -2, width: 47, height: 36)) { ctx in
            ellipse(ctx, CGRect(x: -14, y: -1, width: 28, height: 13), fur)
            circle(ctx, 2.2, at: CGPoint(x: -14, y: 8), cg(0xEFEBE9))
            poly(ctx, [CGPoint(x: 9, y: 6), CGPoint(x: 15, y: 16), CGPoint(x: 18, y: 13), CGPoint(x: 14, y: 4)], fur)
            circle(ctx, 5, at: CGPoint(x: 17, y: 16), fur)
            ellipse(ctx, CGRect(x: 18, y: 11, width: 9, height: 6), cg(0xA1887F))
            circle(ctx, 0.9, at: CGPoint(x: 18.5, y: 17.5), cg(0x1A1A1A))
            line(ctx, [CGPoint(x: 15, y: 20), CGPoint(x: 13, y: 28), CGPoint(x: 9, y: 31)], antler, width: 1.4)
            line(ctx, [CGPoint(x: 13.6, y: 25.5), CGPoint(x: 17, y: 30)], antler, width: 1.2)
            line(ctx, [CGPoint(x: 17, y: 20.5), CGPoint(x: 18, y: 29), CGPoint(x: 21, y: 32)], antler, width: 1.4)
            circle(ctx, 1.6, at: CGPoint(x: 27, y: 13.5), cg(0x3E2723))
            line(ctx, [CGPoint(x: 11, y: 9), CGPoint(x: 15.5, y: 12)], cg(0xC62828), width: 2)
            circle(ctx, 2.2, at: CGPoint(x: 13.5, y: 8.5), cg(0xFFC107), stroke: cg(0xB28704), lineWidth: 0.6)
        }
        let leg = part(CGRect(x: -1.5, y: -10.5, width: 3.2, height: 11)) { ctx in
            rect(ctx, CGRect(x: -1, y: -10, width: 2.2, height: 10), cg(0x6D4C41), radius: 1)
        }
        let shine = part(CGRect(x: 9, y: 4, width: 9, height: 9)) { ctx in
            circle(ctx, 4.5, at: CGPoint(x: 13.5, y: 8.5), cg(0xFFF59D, 0.45))
        }
        return SantaParts(body: body, reindeer: reindeer, leg: leg, shine: shine)
    }()

    // MARK: - Sozlamalar oynasidagi jonli ko‘rinish uchun yig‘ma rasmlar

    /// Qism rasmini kontekstga pivot nuqtasi va burchagi bilan bosadi; `inside` — shu qism ichidagi bolalar.
    static func stamp(_ piece: Part, in ctx: CGContext, at pivot: CGPoint, angle: CGFloat = 0,
                      inside: (CGContext) -> Void = { _ in }) {
        ctx.saveGState()
        ctx.translateBy(x: pivot.x, y: pivot.y)
        if angle != 0 { ctx.rotate(by: angle) }
        if let picture = piece.image {
            ctx.draw(picture, in: piece.box)
        }
        inside(ctx)
        ctx.restoreGState()
    }

}
