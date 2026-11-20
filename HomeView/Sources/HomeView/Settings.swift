import Foundation
import HomeViewProtocol

/// O‘lcham sozlamalarining chegaralari (menyudagi va sozlamalar oynasidagi slayderlar uchun umumiy).
enum SizeRange {
    static let flake: ClosedRange<Double> = 0.5...2.5
    static let snowman: ClosedRange<Double> = 0.6...2.5
    static let worker: ClosedRange<Double> = 0.6...2.5
    static let plow: ClosedRange<Double> = 0.6...2.0
    static let ball: ClosedRange<Double> = 0.6...2.5
}

/// Son sozlamalarining chegaralari.
enum CountRange {
    static let crew: ClosedRange<Int> = 0...12
    static let plows: ClosedRange<Int> = 0...4
    static let snowmen: ClosedRange<Int> = 1...6
}

extension Notification.Name {
    static let qorSettingsChanged = Notification.Name("HomeView.settingsChanged")
    static let qorHotKey = Notification.Name("HomeView.hotKey")
}

/// Foydalanuvchi sozlamalari. Hammasi uzluksiz qiymat — slayder bilan surib o‘zgartiriladi.
/// Har bir o‘zgarishda .qorSettingsChanged xabari yuboriladi va ekrandagi hamma narsa darhol moslashadi.
final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            "snowAmount": 0.4,
            "windStrength": 0.0,
            "windGusty": true,
            "flakeScale": 1.0,
            "snowmanScale": 1.0,
            "workerScale": 1.0,
            "plowScale": 1.0,
            "ballScale": 1.0,
            "crewCount": 4,
            "plowCount": 1,
            "snowmanCount": 2,
            "mouseInWorkMode": true,
            "crewFightsBack": true,
            "santa": true,
            "snowOnWindows": true,
            "fullScreen": false,
            "hideFromCapture": true,
            "seasonChoice": 0,
            "officeEnabled": false,
            "displayName": "",
            "team": "",
            "avatarHat": HatStyle.doppi.rawValue,
            "avatarHatColor": Int(AvatarStyle.standard.hatColor),
            "avatarVestColor": Int(AvatarStyle.standard.vestColor),
            "avatarSkinColor": Int(AvatarStyle.standard.skinColor),
            "serverAddress": "",
            "officeCode": "",
            "myStatus": PeerStatus.active.rawValue,
            "newPeersVisible": true,
            "weatherChoice": "auto"
        ])
    }

    // MARK: - Ob-havo

    /// Qor kuchi: 0 — to‘xtagan (yerdagi qor eriydi), 1 — bo‘ron.
    var snowAmount: Double {
        get { clampDouble(defaults.double(forKey: "snowAmount"), 0...1) }
        set { setDouble(clampDouble(newValue, 0...1), "snowAmount") }
    }

    /// 1440 pt enli ekran uchun sekundiga tug‘iladigan qor parchalari.
    var flakesPerSecond: Double {
        snowAmount < 0.02 ? 0 : 320 * pow(snowAmount, 1.4)
    }

    var isSnowing: Bool { flakesPerSecond > 0 }
    var isBlizzard: Bool { snowAmount > 0.8 }

    static func snowTitle(_ amount: Double) -> String {
        switch amount {
        case ..<0.02: return "To‘xtagan"
        case ..<0.25: return "Yengil"
        case ..<0.55: return "O‘rtacha"
        case ..<0.8: return "Kuchli"
        default: return "Bo‘ron"
        }
    }

    /// Shamol: -1 — chapga kuchli, 0 — shamolsiz, 1 — o‘ngga kuchli.
    var windStrength: Double {
        get { clampDouble(defaults.double(forKey: "windStrength"), -1...1) }
        set { setDouble(clampDouble(newValue, -1...1), "windStrength") }
    }

    static func windTitle(_ value: Double) -> String {
        let percent = Int((abs(value) * 100).rounded())
        if percent < 5 { return "Shamolsiz" }
        return value < 0 ? "← \(percent)%" : "\(percent)% →"
    }

    /// Shamol vaqti-vaqti bilan yo‘nalishi va kuchini o‘zgartiradi (bo‘ronlar).
    var windGusty: Bool {
        get { defaults.bool(forKey: "windGusty") }
        set { setBool(newValue, "windGusty") }
    }

    // MARK: - O‘lchamlar (1.0 — asl o‘lcham)

    var flakeScale: Double {
        get { clampDouble(defaults.double(forKey: "flakeScale"), SizeRange.flake) }
        set { setDouble(clampDouble(newValue, SizeRange.flake), "flakeScale") }
    }

    var snowmanScale: Double {
        get { clampDouble(defaults.double(forKey: "snowmanScale"), SizeRange.snowman) }
        set { setDouble(clampDouble(newValue, SizeRange.snowman), "snowmanScale") }
    }

    var workerScale: Double {
        get { clampDouble(defaults.double(forKey: "workerScale"), SizeRange.worker) }
        set { setDouble(clampDouble(newValue, SizeRange.worker), "workerScale") }
    }

    var plowScale: Double {
        get { clampDouble(defaults.double(forKey: "plowScale"), SizeRange.plow) }
        set { setDouble(clampDouble(newValue, SizeRange.plow), "plowScale") }
    }

    var ballScale: Double {
        get { clampDouble(defaults.double(forKey: "ballScale"), SizeRange.ball) }
        set { setDouble(clampDouble(newValue, SizeRange.ball), "ballScale") }
    }

    func resetSizes() {
        for key in ["flakeScale", "snowmanScale", "workerScale", "plowScale", "ballScale"] {
            defaults.set(1.0, forKey: key)
        }
        notify()
    }

    static func percentTitle(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    // MARK: - Brigada

    /// Ekrandagi ishchilar soni (qor bor paytda hammasi chiqadi).
    var crewCount: Int {
        get { clampInt(defaults.integer(forKey: "crewCount"), CountRange.crew) }
        set { setInt(clampInt(newValue, CountRange.crew), "crewCount") }
    }

    var workersEnabled: Bool { crewCount > 0 }

    /// Bir vaqtda yo‘lda bo‘lishi mumkin bo‘lgan qor tozalovchi mashinalar.
    var plowCount: Int {
        get { clampInt(defaults.integer(forKey: "plowCount"), CountRange.plows) }
        set { setInt(clampInt(newValue, CountRange.plows), "plowCount") }
    }

    /// Ekranda bir vaqtda turishi mumkin bo‘lgan qorbolalar.
    var snowmanCount: Int {
        get { clampInt(defaults.integer(forKey: "snowmanCount"), CountRange.snowmen) }
        set { setInt(clampInt(newValue, CountRange.snowmen), "snowmanCount") }
    }

    // MARK: - Xulq-atvor va ko‘rinish

    /// Ish rejimida ham qorbola, ishchi, sovg‘a va mashinalarni sichqoncha bilan bosish mumkin.
    var mouseInWorkMode: Bool {
        get { defaults.bool(forKey: "mouseInWorkMode") }
        set { setBool(newValue, "mouseInWorkMode") }
    }

    /// Qorbolalarni qayta-qayta buzsangiz, ishchilar ish rejimida ham sizga qor otadi.
    var crewFightsBack: Bool {
        get { defaults.bool(forKey: "crewFightsBack") }
        set { setBool(newValue, "crewFightsBack") }
    }

    var santaEnabled: Bool {
        get { defaults.bool(forKey: "santa") }
        set { setBool(newValue, "santa") }
    }

    var snowOnWindows: Bool {
        get { defaults.bool(forKey: "snowOnWindows") }
        set { setBool(newValue, "snowOnWindows") }
    }

    var showInFullScreen: Bool {
        get { defaults.bool(forKey: "fullScreen") }
        set { setBool(newValue, "fullScreen") }
    }

    var hideFromCapture: Bool {
        get { defaults.bool(forKey: "hideFromCapture") }
        set { setBool(newValue, "hideFromCapture") }
    }

    // MARK: - Fasl

    /// 0 — avtomatik (sanaga qarab), 1 — qish, 2 — bahor, 3 — yoz, 4 — kuz.
    var seasonChoice: Int {
        get { clampInt(defaults.integer(forKey: "seasonChoice"), 0...4) }
        set { setInt(clampInt(newValue, 0...4), "seasonChoice") }
    }

    var resolvedSeason: SeasonKind {
        let choice = seasonChoice
        guard choice > 0 else { return SeasonKind.current() }
        return SeasonKind.allCases[choice - 1]
    }

    // MARK: - Ofis (tarmoq)

    var officeEnabled: Bool {
        get { defaults.bool(forKey: "officeEnabled") }
        set { setBool(newValue, "officeEnabled") }
    }

    var displayName: String {
        get { defaults.string(forKey: "displayName") ?? "" }
        set { setString(String(newValue.prefix(32)), "displayName") }
    }

    var team: String {
        get { defaults.string(forKey: "team") ?? "" }
        set { setString(String(newValue.prefix(24)), "team") }
    }

    var avatar: AvatarStyle {
        get {
            AvatarStyle(hat: HatStyle(rawValue: defaults.string(forKey: "avatarHat") ?? "") ?? .doppi,
                        hatColor: UInt32(truncatingIfNeeded: defaults.integer(forKey: "avatarHatColor")),
                        vestColor: UInt32(truncatingIfNeeded: defaults.integer(forKey: "avatarVestColor")),
                        skinColor: UInt32(truncatingIfNeeded: defaults.integer(forKey: "avatarSkinColor")))
        }
        set {
            guard newValue != avatar else { return }
            defaults.set(newValue.hat.rawValue, forKey: "avatarHat")
            defaults.set(Int(newValue.hatColor), forKey: "avatarHatColor")
            defaults.set(Int(newValue.vestColor), forKey: "avatarVestColor")
            defaults.set(Int(newValue.skinColor), forKey: "avatarSkinColor")
            notify()
        }
    }

    /// Bo‘sh — server ofis tarmog‘idan avtomatik topiladi (Bonjour). Aks holda "192.168.1.20" yoki "server.local:47777".
    var serverAddress: String {
        get { defaults.string(forKey: "serverAddress") ?? "" }
        set { setString(newValue.trimmingCharacters(in: .whitespaces), "serverAddress") }
    }

    var officeCode: String {
        get { defaults.string(forKey: "officeCode") ?? "" }
        set { setString(newValue.trimmingCharacters(in: .whitespaces), "officeCode") }
    }

    /// Qo‘lda tanlangan holat: faol, band yoki ko‘rinmas ("uzoqda" o‘zi aniqlanadi).
    var myStatus: PeerStatus {
        get { PeerStatus(rawValue: defaults.string(forKey: "myStatus") ?? "") ?? .active }
        set { setString(newValue.rawValue, "myStatus") }
    }

    // MARK: - Ob-havo

    /// "auto" yoki WeatherKind nomi (masalan "autumnRain"). Boshqa faslniki bo‘lsa — avtomatik.
    var weatherChoice: String {
        get { defaults.string(forKey: "weatherChoice") ?? "auto" }
        set { setString(newValue, "weatherChoice") }
    }

    // MARK: - Ekrandagi hamkasblar

    /// Har bir hamkasb uchun sizning tanlovingiz: true — ekranda yuradi, false — yashirin.
    /// Tanlov qilinmaganlar uchun `newPeersVisible` ishlaydi.
    var peerChoices: [String: Bool] {
        get { defaults.dictionary(forKey: "peerChoices") as? [String: Bool] ?? [:] }
        set {
            defaults.set(newValue, forKey: "peerChoices")
            notify()
        }
    }

    /// Hali tanlanmagan (yangi qo‘shilgan) hamkasblar ekranda avtomatik ko‘rinsinmi.
    var newPeersVisible: Bool {
        get { defaults.bool(forKey: "newPeersVisible") }
        set { setBool(newValue, "newPeersVisible") }
    }

    /// Ilgari ko‘rilgan hamkasblar: id → [ism, jamoa]. Oflayn bo‘lsa ham ro‘yxatda turadi —
    /// shuning uchun ishga hali kelmagan do‘stingizni ham oldindan tanlab qo‘yish mumkin.
    var knownPeers: [String: [String]] {
        get { defaults.dictionary(forKey: "knownPeers") as? [String: [String]] ?? [:] }
        set { defaults.set(newValue, forKey: "knownPeers") }
    }

    /// Shu kompyuterning doimiy identifikatori (birinchi ishga tushganda yaratiladi).
    var peerID: String {
        if let existing = defaults.string(forKey: "peerID"), !existing.isEmpty { return existing }
        let created = UUID().uuidString
        defaults.set(created, forKey: "peerID")
        return created
    }

    var isOfficeConfigured: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Ichki yordamchilar

    private func setString(_ value: String, _ key: String) {
        guard (defaults.string(forKey: key) ?? "") != value else { return }
        defaults.set(value, forKey: key)
        notify()
    }

    // Qiymat o‘zgarmagan bo‘lsa xabar yuborilmaydi — menyu va oyna bir-birini cheksiz yangilab qo‘ymasligi uchun.

    private func setDouble(_ value: Double, _ key: String) {
        guard abs(defaults.double(forKey: key) - value) > 0.0005 else { return }
        defaults.set(value, forKey: key)
        notify()
    }

    private func setInt(_ value: Int, _ key: String) {
        guard defaults.integer(forKey: key) != value else { return }
        defaults.set(value, forKey: key)
        notify()
    }

    private func setBool(_ value: Bool, _ key: String) {
        guard defaults.bool(forKey: key) != value else { return }
        defaults.set(value, forKey: key)
        notify()
    }

    private func clampDouble(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func clampInt(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func notify() {
        NotificationCenter.default.post(name: .qorSettingsChanged, object: nil)
    }
}

/// O‘yin rejimi va hisob. Barcha ekranlar uchun bitta.
final class GameState {
    static let shared = GameState()
    var playMode = false
    var playerScore = 0
    var crewScore = 0

    func resetScore() {
        playerScore = 0
        crewScore = 0
    }
}
