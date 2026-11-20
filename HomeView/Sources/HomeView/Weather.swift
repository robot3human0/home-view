import AppKit

/// Har bir faslning ob-havo holatlari. Foydalanuvchi bittasini tanlaydi yoki "Avtomatik" qoldiradi —
/// unda holatlar 20–45 daqiqada o‘zi almashadi (kunduzi va kechasi har xil).
enum WeatherKind: String, CaseIterable {
    // Qish
    case snowfall, iceAndSnow, blizzard, frostySun
    // Bahor
    case blossoms, springRain, thunderstorm, rainbow
    // Yoz
    case poplarFluff, heat, summerShower, fireflyNight
    // Kuz
    case leafFall, autumnRain, fog, windy

    var season: SeasonKind {
        switch self {
        case .snowfall, .iceAndSnow, .blizzard, .frostySun: return .winter
        case .blossoms, .springRain, .thunderstorm, .rainbow: return .spring
        case .poplarFluff, .heat, .summerShower, .fireflyNight: return .summer
        case .leafFall, .autumnRain, .fog, .windy: return .autumn
        }
    }

    var title: String {
        switch self {
        case .snowfall: return "Qor yog‘moqda"
        case .iceAndSnow: return "Muz va qor"
        case .blizzard: return "Bo‘ron"
        case .frostySun: return "Ayozli quyosh"
        case .blossoms: return "Gullar to‘kilmoqda"
        case .springRain: return "Bahor yomg‘iri"
        case .thunderstorm: return "Momaqaldiroq"
        case .rainbow: return "Kamalak"
        case .poplarFluff: return "Terak paxmog‘i"
        case .heat: return "Jazirama"
        case .summerShower: return "Yozgi jala"
        case .fireflyNight: return "Yulduzli kecha"
        case .leafFall: return "Xazonrezgi"
        case .autumnRain: return "Kuzgi yomg‘ir"
        case .fog: return "Tuman"
        case .windy: return "Kuzgi shamol"
        }
    }

    var emoji: String {
        switch self {
        case .snowfall: return "🌨"
        case .iceAndSnow: return "🧊"
        case .blizzard: return "🌬"
        case .frostySun: return "✨"
        case .blossoms: return "🌸"
        case .springRain: return "🌦"
        case .thunderstorm: return "⛈"
        case .rainbow: return "🌈"
        case .poplarFluff: return "🌾"
        case .heat: return "☀️"
        case .summerShower: return "🌧"
        case .fireflyNight: return "🌙"
        case .leafFall: return "🍂"
        case .autumnRain: return "☔️"
        case .fog: return "🌫"
        case .windy: return "🍃"
        }
    }

    /// Bir qatorli tavsif (menyu va sozlamalarda).
    var summary: String {
        switch self {
        case .snowfall: return "Momiq qor yog‘adi, oynalar ustida to‘planadi."
        case .iceAndSnow: return "Ekran tepasida sumalaklar, burchaklarda qirov, yerda muz yaltiraydi."
        case .blizzard: return "Kuchli shamol, quyuq qor, oq to‘zon."
        case .frostySun: return "Siyrak qor, havoda muz uchqunlari yaltiraydi, sovuq quyosh."
        case .blossoms: return "O‘rik va olcha gullari to‘kiladi."
        case .springRain: return "Iliq yomg‘ir, yerda ko‘lmaklar va to‘lqinlar."
        case .thunderstorm: return "Kuchli jala, chaqmoq chaqadi."
        case .rainbow: return "Yomg‘irdan keyin: mayda shivalash, osmonda kamalak."
        case .poplarFluff: return "Terak paxmog‘i havoda suzib yuradi."
        case .heat: return "Yorqin quyosh nurlari, havo jim."
        case .summerShower: return "Qisqa, kuchli yozgi jala."
        case .fireflyNight: return "Kechki salqin, pastda chiroq qo‘ng‘izlari uchadi."
        case .leafFall: return "Sariq va qizil barglar to‘kiladi."
        case .autumnRain: return "Barglar va yomg‘ir birga, yerda ko‘lmaklar."
        case .fog: return "Ekran bo‘ylab quyuq tuman suzib o‘tadi."
        case .windy: return "Kuchli shamol barglarni uchirib yuradi."
        }
    }

    static func options(for season: SeasonKind) -> [WeatherKind] {
        allCases.filter { $0.season == season }
    }

    /// Avtomatik rejimda kunning shu vaqtida mos keladimi.
    func fits(hour: Int) -> Bool {
        let night = hour >= 20 || hour < 5
        switch self {
        case .fireflyNight: return night
        case .heat, .frostySun, .rainbow: return !night
        default: return true
        }
    }

    var profile: WeatherProfile {
        var p = WeatherProfile()
        switch self {
        case .snowfall, .blossoms, .poplarFluff, .leafFall:
            break
        case .iceAndSnow:
            p.particles = 0.7
            p.accumulation = 0.85
            p.effects = [.icicles, .frost, .iceSheen]
        case .blizzard:
            p.particles = 1.7
            p.windBias = 55
            p.gustiness = 2.2
            p.accumulation = 1.3
            p.effects = [.whiteout]
        case .frostySun:
            p.particles = 0.15
            p.accumulation = 0.25
            p.effects = [.coldSun, .diamondDust, .frost]
        case .springRain:
            p.particles = 0.3
            p.rain = 0.65
            p.accumulation = 0.25
            p.effects = [.splashes, .puddles]
        case .thunderstorm:
            p.particles = 0.12
            p.rain = 1.0
            p.windBias = 25
            p.gustiness = 1.8
            p.accumulation = 0.1
            p.effects = [.splashes, .puddles, .lightning]
        case .rainbow:
            p.particles = 0.6
            p.rain = 0.1
            p.effects = [.rainbow, .puddles, .sunGlare]
        case .heat:
            p.particles = 0.2
            p.accumulation = 0.3
            p.effects = [.sunGlare]
        case .summerShower:
            p.particles = 0
            p.rain = 0.9
            p.accumulation = 0
            p.effects = [.splashes, .puddles]
        case .fireflyNight:
            p.particles = 0.2
            p.accumulation = 0.3
            p.effects = [.fireflies]
        case .autumnRain:
            p.particles = 0.6
            p.rain = 0.55
            p.accumulation = 0.6
            p.effects = [.splashes, .puddles]
        case .fog:
            p.particles = 0.35
            p.accumulation = 0.4
            p.effects = [.fog]
        case .windy:
            p.particles = 1.5
            p.windBias = 60
            p.gustiness = 2.0
            p.accumulation = 1.1
        }
        return p
    }
}

enum WeatherEffect {
    case splashes, puddles, lightning, fog, frost, icicles, iceSheen
    case sunGlare, coldSun, diamondDust, fireflies, rainbow, whiteout
}

/// Ob-havo holatining dunyoga ta’siri.
struct WeatherProfile {
    /// Fasl zarrachalari (qor, gul, paxmoq, barg) miqdoriga ko‘paytiruvchi.
    var particles: Float = 1
    /// Yomg‘ir kuchi (0 — yo‘q, 1 — jala).
    var rain: Float = 0
    /// Doimiy shamol (pt/s) — yo‘nalishi har safar tasodifiy.
    var windBias: CGFloat = 0
    /// Shamol o‘zgaruvchanligi.
    var gustiness: CGFloat = 1
    /// To‘planish tezligiga ko‘paytiruvchi.
    var accumulation: CGFloat = 1
    var effects: Set<WeatherEffect> = []
}

/// Hozirgi ob-havoni hal qiladi: tanlangan holat yoki avtomatik almashinish.
final class WeatherDirector {
    static let shared = WeatherDirector()

    private(set) var current: WeatherKind = .snowfall
    private(set) var isAuto = true
    private var autoKind: WeatherKind?
    private var autoUntil = Date.distantPast

    /// Hozirgi holatni qayta hisoblaydi. O‘zgargan bo‘lsa — true.
    @discardableResult
    func refresh(season: SeasonKind, now: Date = Date()) -> Bool {
        let hour = Calendar.current.component(.hour, from: now)
        let next: WeatherKind
        if let chosen = WeatherKind(rawValue: Settings.shared.weatherChoice), chosen.season == season {
            isAuto = false
            next = chosen
        } else {
            isAuto = true
            if let kind = autoKind, kind.season == season, now < autoUntil, kind.fits(hour: hour) {
                next = kind
            } else {
                next = pick(season: season, hour: hour, avoiding: autoKind)
                autoKind = next
                autoUntil = now.addingTimeInterval(Double.random(in: 1200...2700))
            }
        }
        let changed = next != current
        current = next
        return changed
    }

    /// Asosiy holat ko‘proq, keskinlari kamroq chiqadi.
    private func pick(season: SeasonKind, hour: Int, avoiding previous: WeatherKind?) -> WeatherKind {
        let options = WeatherKind.options(for: season)
        var weights: [Double] = []
        for kind in options {
            var weight: Double
            switch kind {
            case .snowfall, .blossoms, .poplarFluff, .leafFall: weight = 4
            case .fireflyNight: weight = 6
            case .thunderstorm, .blizzard: weight = 1
            default: weight = 2
            }
            if !kind.fits(hour: hour) { weight = 0 }
            if kind == previous { weight *= 0.3 }
            weights.append(weight)
        }
        let total = weights.reduce(0, +)
        guard total > 0, let fallback = options.first else { return .snowfall }
        var roll = Double.random(in: 0..<total)
        for (index, weight) in weights.enumerated() {
            if roll < weight { return options[index] }
            roll -= weight
        }
        return fallback
    }
}
