import AppKit
import HomeViewProtocol

/// To‘rt fasl. Har birining o‘z g‘oyasi: nima yog‘adi, brigada nima qiladi, nima yasaydi,
/// qanday mashina keladi, osmondan kim uchib o‘tadi va nima bilan "otishiladi".
enum SeasonKind: String, CaseIterable {
    case winter, spring, summer, autumn

    /// Menyu satridagi belgi (SF Symbol).
    var menuBarSymbol: String {
        switch self {
        case .winter: return "snowflake"
        case .spring: return "camera.macro"
        case .summer: return "sun.max.fill"
        case .autumn: return "leaf.fill"
        }
    }

    var title: String {
        switch self {
        case .winter: return "Qish"
        case .spring: return "Bahor"
        case .summer: return "Yoz"
        case .autumn: return "Kuz"
        }
    }

    var emoji: String {
        switch self {
        case .winter: return "❄️"
        case .spring: return "🌸"
        case .summer: return "☀️"
        case .autumn: return "🍂"
        }
    }

    /// Sanaga qarab: dekabr–fevral qish, mart–may bahor, iyun–avgust yoz, sentyabr–noyabr kuz.
    static func current(at date: Date = Date()) -> SeasonKind {
        switch Calendar.current.component(.month, from: date) {
        case 12, 1, 2: return .winter
        case 3, 4, 5: return .spring
        case 6, 7, 8: return .summer
        default: return .autumn
        }
    }
}

enum VisitorKind {
    case santa, swallows, balloon, cranes
}

/// Yog‘ayotgan narsalarning bitta "qatlami" (uzoq / o‘rta / yaqin).
struct ParticleLayerStyle {
    let name: String
    let rate: Float
    let velocity: CGFloat
    let scale: CGFloat
    let alpha: CGFloat
    let color: CGColor
    let spin: CGFloat
    let emissionRange: CGFloat
    /// Realistik rasm (bo‘lsa — fasl rasmining o‘rniga).
    var image: CGImage? = nil
}

/// Bitta faslning to‘liq "ssenariysi".
final class SeasonTheme {
    let kind: SeasonKind

    // Yog‘ayotgan narsa va to‘planish
    let particleTitle: String
    let particleEmoji: String
    let particleImage: CGImage?
    let layers: [ParticleLayerStyle]
    let accumulation: CGFloat
    let pileFill: CGColor
    let pileStroke: CGColor
    let burstColors: [CGColor]

    // Brigada
    let workerHat: HatStyle
    let workerHatColors: [UInt32]
    let tool: Art.ToolKind
    let monumentTitle: String
    let monumentPlural: String
    let monumentEmoji: String
    let vehicleTitle: String
    let visitor: VisitorKind
    let visitorTitle: String
    let projectileTitle: String
    let projectileImage: CGImage?
    let splats: [CGImage]
    let gift: Part

    // Gaplar
    let idle: [String]
    let hello: [String]
    let buildStart: [String]
    let buildDone: [String]
    let rebuild: [String]
    let grief: [[String]]
    let protect: [String]
    let angryBreak: String
    let vehicleArrive: String

    // Sozlamalar oynasidagi jonli ko‘rinish uchun osmon ranglari
    let skyTop: (Double, Double, Double)
    let skyBottom: (Double, Double, Double)

    init(kind: SeasonKind) {
        self.kind = kind
        let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        switch kind {
        case .winter:
            particleTitle = "Qor"
            particleEmoji = "🌨"
            particleImage = Art.flake
            layers = SeasonTheme.realistic(kind, [
                ParticleLayerStyle(name: "far", rate: 36, velocity: 30, scale: 0.26, alpha: 0.75, color: white, spin: 0, emissionRange: 0.18),
                ParticleLayerStyle(name: "mid", rate: 28, velocity: 44, scale: 0.42, alpha: 0.9, color: white, spin: 0, emissionRange: 0.18),
                ParticleLayerStyle(name: "near", rate: 16, velocity: 64, scale: 0.62, alpha: 1, color: white, spin: 0, emissionRange: 0.18)
            ])
            accumulation = 1
            pileFill = white
            pileStroke = cg(0xA9B9CF, 0.95)
            burstColors = [white]
            workerHat = .beanie
            workerHatColors = [0x1E3A5F, 0x7B1E1E, 0x2E4D2E, 0x4A2C6B]
            tool = .shovel
            monumentTitle = "Qorbola"
            monumentPlural = "Qorbolalar"
            monumentEmoji = "⛄"
            vehicleTitle = "Qor tozalovchi mashina"
            visitor = .santa
            visitorTitle = "Qorbobo"
            projectileTitle = "Qor koptok"
            idle = ["Qor ko‘p-ku bugun!", "Choy ichamizmi?", "Kurakni bering!", "Sovuq-a...", "Qo‘llarim muzladi", "Qor — baraka!"]
            hello = ["Assalomu alaykum!", "Qani, ishga!", "Qor ko‘p-ku bugun!"]
            buildStart = ["Qorbola yasaymiz!", "Qani, qorbola!", "Hozir zo‘r narsa yasaymiz"]
            buildDone = ["Qorbola tayyor!", "Zo‘r chiqdi-a?", "Tayyor!"]
            rebuild = ["Qaytadan yasaymiz!", "Bu safar yaxshiroq bo‘ladi!", "Taslim bo‘lmaymiz!"]
            grief = [["Voy, qorbolam!", "Kim buzdi?!", "Shuncha mehnat...", "Eh, attang!"],
                     ["Yana-ya?!", "Endi qo‘riqlaymiz!", "Bu kimning ishi?!"],
                     ["Bas qiling!", "Endi ko‘rasiz!", "Sabr kosasi to‘ldi!"]]
            protect = ["Hey, tegma!", "Qorbolani buzma!", "Nima qilyapsan?!"]
            angryBreak = "Qorbolamni buzding!"
            vehicleArrive = "Mashina keldi!"
            skyTop = (0.06, 0.12, 0.23)
            skyBottom = (0.20, 0.33, 0.53)

        case .spring:
            particleTitle = "Gul barglari"
            particleEmoji = "🌸"
            particleImage = Art.petal
            layers = SeasonTheme.realistic(kind, [
                ParticleLayerStyle(name: "far", rate: 14, velocity: 26, scale: 0.34, alpha: 0.8, color: cg(0xFFFFFF), spin: 1.2, emissionRange: 0.5),
                ParticleLayerStyle(name: "mid", rate: 11, velocity: 36, scale: 0.5, alpha: 0.95, color: cg(0xF8BBD0), spin: 1.6, emissionRange: 0.5),
                ParticleLayerStyle(name: "near", rate: 6, velocity: 50, scale: 0.7, alpha: 1, color: cg(0xF48FB1), spin: 2.0, emissionRange: 0.5)
            ])
            accumulation = 0.7
            pileFill = cg(0xFCE4EC)
            pileStroke = cg(0xF48FB1, 0.9)
            burstColors = [cg(0xF8BBD0), cg(0xFFFFFF), cg(0xF48FB1)]
            workerHat = .cap
            workerHatColors = [0x2E7D32, 0x558B2F, 0x1E3A5F]
            tool = .rake
            monumentTitle = "Lolazor"
            monumentPlural = "Lolazorlar"
            monumentEmoji = "🌷"
            vehicleTitle = "Traktor"
            visitor = .swallows
            visitorTitle = "Qaldirg‘ochlar"
            projectileTitle = "Gul to‘pi"
            idle = ["Bahor keldi!", "Navro‘z muborak!", "Havo ajoyib-a", "Gullar ochilyapti", "Sumalak qachon?", "Qaldirg‘ochlar keldi!"]
            hello = ["Assalomu alaykum!", "Bahoringiz muborak!", "Qani, ishga!"]
            buildStart = ["Lola ekamiz!", "Gulzor qilamiz!", "Ketmonni bering!"]
            buildDone = ["Lolalar ochildi!", "Gulzor tayyor!", "Chiroyli-a?"]
            rebuild = ["Qaytadan ekamiz!", "Gullar yana ochiladi!", "Taslim bo‘lmaymiz!"]
            grief = [["Voy, lolalarim!", "Kim bosib ketdi?!", "Shuncha mehnat..."],
                     ["Yana-ya?!", "Endi gulzorni qo‘riqlaymiz!", "Bu kimning ishi?!"],
                     ["Bas qiling!", "Endi ko‘rasiz!", "Sabr kosasi to‘ldi!"]]
            protect = ["Gullarga tegma!", "Lolalarni bosma!", "Ehtiyot bo‘ling!"]
            angryBreak = "Lolalarimni payhon qilding!"
            vehicleArrive = "Traktor keldi!"
            skyTop = (0.45, 0.70, 0.92)
            skyBottom = (0.78, 0.90, 0.98)

        case .summer:
            particleTitle = "Terak paxmog‘i"
            particleEmoji = "🌬"
            particleImage = Art.fluff
            layers = SeasonTheme.realistic(kind, [
                ParticleLayerStyle(name: "far", rate: 7, velocity: 12, scale: 0.4, alpha: 0.7, color: cg(0xFFFFFF), spin: 0.3, emissionRange: 1.2),
                ParticleLayerStyle(name: "mid", rate: 5, velocity: 16, scale: 0.6, alpha: 0.85, color: cg(0xFFFDE7), spin: 0.4, emissionRange: 1.2),
                ParticleLayerStyle(name: "near", rate: 3, velocity: 22, scale: 0.85, alpha: 0.9, color: cg(0xFFFFFF), spin: 0.5, emissionRange: 1.2)
            ])
            accumulation = 0.35
            pileFill = cg(0xF7F5EE)
            pileStroke = cg(0xD7CCC8, 0.9)
            burstColors = [cg(0xE53935), cg(0x43A047), cg(0x81D4FA)]
            workerHat = .strawHat
            workerHatColors = [0xC62828, 0x1565C0, 0x2E7D32]
            tool = .broom
            monumentTitle = "Tarvuz uyumi"
            monumentPlural = "Tarvuz uyumlari"
            monumentEmoji = "🍉"
            vehicleTitle = "Suv sepuvchi mashina"
            visitor = .balloon
            visitorTitle = "Havo shari"
            projectileTitle = "Suv to‘pi"
            idle = ["Issiq-a...", "Tarvuz yeymizmi?", "Soya qayerda?", "Muzqaymoq bormi?", "Choyxonaga boramizmi?", "Salqin suv bormi?"]
            hello = ["Assalomu alaykum!", "Issiq-a bugun!", "Qani, ishga!"]
            buildStart = ["Tarvuz teramiz!", "Bozorga tayyorlaymiz!", "Eng shirinini tanlaymiz"]
            buildDone = ["Tarvuzlar tayyor!", "Shirin tarvuzlar!", "Kelinglar, tarvuz!"]
            rebuild = ["Qaytadan teramiz!", "Polizda tarvuz ko‘p!", "Taslim bo‘lmaymiz!"]
            grief = [["Voy, tarvuzlarim!", "Kim yorib yubordi?!", "Shuncha mehnat..."],
                     ["Yana-ya?!", "Endi qo‘riqlaymiz!", "Bu kimning ishi?!"],
                     ["Bas qiling!", "Endi ko‘rasiz!", "Sabr kosasi to‘ldi!"]]
            protect = ["Tarvuzlarga tegma!", "Sotib oling, keyin!", "Ehtiyot bo‘ling!"]
            angryBreak = "Tarvuzimni yording!"
            vehicleArrive = "Suv sepuvchi keldi!"
            skyTop = (0.22, 0.60, 0.92)
            skyBottom = (0.70, 0.88, 0.99)

        case .autumn:
            particleTitle = "Barglar"
            particleEmoji = "🍂"
            particleImage = Art.leaf
            layers = SeasonTheme.realistic(kind, [
                ParticleLayerStyle(name: "far", rate: 12, velocity: 30, scale: 0.4, alpha: 0.85, color: cg(0xFBC02D), spin: 1.6, emissionRange: 0.45),
                ParticleLayerStyle(name: "mid", rate: 9, velocity: 42, scale: 0.6, alpha: 0.95, color: cg(0xF57C00), spin: 2.0, emissionRange: 0.45),
                ParticleLayerStyle(name: "near", rate: 5, velocity: 56, scale: 0.82, alpha: 1, color: cg(0xC62828), spin: 2.4, emissionRange: 0.45)
            ])
            accumulation = 0.8
            pileFill = cg(0xE8A04C)
            pileStroke = cg(0xB5651D, 0.9)
            burstColors = [cg(0xFBC02D), cg(0xF57C00), cg(0xC62828)]
            workerHat = .cap
            workerHatColors = [0x6D4C41, 0x37474F, 0x5D4037]
            tool = .rake
            monumentTitle = "Qo‘riqchi qo‘g‘irchoq"
            monumentPlural = "Qo‘riqchilar"
            monumentEmoji = "🎃"
            vehicleTitle = "Ko‘cha supuruvchi mashina"
            visitor = .cranes
            visitorTitle = "Turnalar"
            projectileTitle = "Barg to‘pi"
            idle = ["Barglar ko‘p-ku!", "Kuz — hosil fasli", "Anor pishibdi", "Salqin bo‘lyapti", "Choy ichamizmi?", "Turnalar ketyapti..."]
            hello = ["Assalomu alaykum!", "Barglar ko‘p-ku bugun!", "Qani, ishga!"]
            buildStart = ["Qo‘riqchi yasaymiz!", "Qo‘g‘irchoq qilamiz!", "Qovoqni olib keling!"]
            buildDone = ["Qo‘riqchi tayyor!", "Endi qarg‘alar qo‘rqadi!", "Zo‘r chiqdi-a?"]
            rebuild = ["Qaytadan yasaymiz!", "Bu safar mustahkamroq!", "Taslim bo‘lmaymiz!"]
            grief = [["Voy, qo‘riqchim!", "Kim buzdi?!", "Shuncha mehnat..."],
                     ["Yana-ya?!", "Endi qo‘riqlaymiz!", "Bu kimning ishi?!"],
                     ["Bas qiling!", "Endi ko‘rasiz!", "Sabr kosasi to‘ldi!"]]
            protect = ["Qo‘riqchiga tegma!", "Qovoqni urma!", "Ehtiyot bo‘ling!"]
            angryBreak = "Qo‘g‘irchog‘imni buzding!"
            vehicleArrive = "Supuruvchi mashina keldi!"
            skyTop = (0.36, 0.30, 0.42)
            skyBottom = (0.85, 0.60, 0.42)
        }
        projectileImage = Art.projectile(kind)
        splats = Art.splats(kind)
        gift = Art.gift(kind)
    }

    // Sozlamalar oynasidagi ko‘rinish uchun yig‘ma rasmlar (bir marta yasaladi)
    lazy var workerPreview: Part = Art.workerPreview(self)
    lazy var monumentPreview: Part = Art.monumentPreview(kind)
    lazy var vehiclePreview: Part = Art.vehiclePreview(kind)

    /// Realistik zarrachalar: uzoqdagisi, o‘rtadagisi va yaqindagisi — har xil rasm.
    /// Rasmlar o‘zi rangli, shuning uchun bo‘yoq oq bo‘ladi (faqat shaffoflik qoladi).
    static func realistic(_ kind: SeasonKind, _ styles: [ParticleLayerStyle]) -> [ParticleLayerStyle] {
        guard ArtPack.isAvailable else { return styles }
        let names: [String]
        switch kind {
        case .winter: names = ["hv_p_flake_dot", "hv_p_flake_soft", "hv_p_flake_crystal"]
        case .spring: names = ["hv_p_petal_white", "hv_p_petal_pink", "hv_p_petal_pink"]
        case .summer: names = ["hv_p_fluff", "hv_p_fluff", "hv_p_fluff"]
        case .autumn: names = ["hv_p_leaf_gold", "hv_p_leaf_orange", "hv_p_leaf_red"]
        }
        let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        var result: [ParticleLayerStyle] = []
        for (index, style) in styles.enumerated() {
            var copy = ParticleLayerStyle(name: style.name, rate: style.rate, velocity: style.velocity, scale: style.scale,
                                          alpha: style.alpha, color: white, spin: style.spin, emissionRange: style.emissionRange)
            copy.image = ArtPack.image(names[min(index, names.count - 1)])
            result.append(copy)
        }
        return result
    }

    // MARK: - Hozirgi fasl

    private static var cache: [SeasonKind: SeasonTheme] = [:]

    static func theme(_ kind: SeasonKind) -> SeasonTheme {
        if let cached = cache[kind] { return cached }
        let theme = SeasonTheme(kind: kind)
        cache[kind] = theme
        return theme
    }

    /// Butun ilova shu faslda ishlaydi. AppDelegate fasl o‘zgarganda yangilaydi.
    static var current: SeasonTheme = theme(Settings.shared.resolvedSeason)
}
