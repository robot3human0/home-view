import AppKit
import ImageIO

/// Realistik rasmlar to‘plami (Art/*.png).
///
/// Rasmlar tools/art/ dagi skriptlar bilan vektor grafika sifatida chizilgan: yorug‘lik, soya va
/// hajm bilan, har nuqtaga 8 piksel aniqlikda. Har bir PNG Swift kodidagi qism "qutisi" (Part.box)
/// bilan aynan bir xil o‘lchamda — shuning uchun animatsiya tizimi o‘zgarmaydi.
///
/// Rangini foydalanuvchi tanlaydigan qismlar (shapka, kurtka, yuz) kulrang tusda chizilgan:
/// ilova ularni tanlangan rangga "ko‘paytirib" bo‘yaydi, soya va hajm saqlanib qoladi.
///
/// Rasmlar topilmasa (masalan, `swift run` bilan .app'siz ishga tushirilganda) — hamma joyda
/// avvalgi kod bilan chizilgan rasmlar ishlatiladi.
enum ArtPack {
    /// PNG'lar har nuqtaga 8 piksel qilib chizilgan.
    static let pixelsPerPoint: CGFloat = 8

    private static var cache: [String: CGImage] = [:]
    private static var missing: Set<String> = []

    static func image(_ name: String) -> CGImage? {
        if let cached = cache[name] { return cached }
        if missing.contains(name) { return nil }
        let bundle = Bundle.main
        let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "Art")
            ?? bundle.url(forResource: name, withExtension: "png")
        guard let url,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let picture = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            missing.insert(name)
            return nil
        }
        cache[name] = picture
        return picture
    }

    /// To‘plam ilovaga qo‘shilganmi.
    static var isAvailable: Bool {
        image("hv_person_leg") != nil
    }

    /// Bitta PNG'dan qism.
    static func part(_ name: String, _ box: CGRect) -> Part? {
        guard let picture = image(name) else { return nil }
        return Part(image: picture, box: box)
    }

    /// Bir nechta qatlamdan bitta qism: (rasm nomi, bo‘yoq rangi yoki nil).
    static func composed(_ box: CGRect, _ layers: [(String, CGColor?)]) -> Part? {
        let pictures: [(CGImage, CGColor?)] = layers.compactMap { item in
            guard let picture = image(item.0) else { return nil }
            return (picture, item.1)
        }
        guard !pictures.isEmpty else { return nil }
        let rendered = Art.image(box.size) { ctx in
            let rect = CGRect(origin: .zero, size: box.size)
            for (picture, tint) in pictures {
                if let tint {
                    drawTinted(ctx, picture, in: rect, tint: tint)
                } else {
                    ctx.draw(picture, in: rect)
                }
            }
        }
        return Part(image: rendered, box: box)
    }

    /// Kulrang rasmni rangga ko‘paytiradi: oq joylar — sof rang, kulrang joylar — soyadagi rang.
    /// Shaffoflik (alfa) rasmnikicha qoladi.
    static func drawTinted(_ ctx: CGContext, _ picture: CGImage, in rect: CGRect, tint: CGColor) {
        ctx.saveGState()
        ctx.beginTransparencyLayer(in: rect, auxiliaryInfo: nil)
        ctx.draw(picture, in: rect)
        ctx.setBlendMode(.multiply)
        ctx.setFillColor(tint)
        ctx.fill(rect)
        ctx.setBlendMode(.destinationIn)
        ctx.draw(picture, in: rect)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
}
