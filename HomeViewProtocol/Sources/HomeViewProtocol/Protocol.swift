import Foundation

/// Ilova va server bir-biriga yuboradigan barcha xabarlar shu faylda.
/// Ikkala tomon ham aynan shu kodni ishlatadi — shuning uchun ular hech qachon "har xil tilda" gaplashmaydi.
public enum HVProtocol {
    /// Bonjour xizmat turi: ilova ofis tarmog‘ida serverni shu nom bilan topadi.
    public static let serviceType = "_homeview._tcp"
    public static let defaultPort: UInt16 = 47777
    /// Mac mini'dagi yuklab olish sahifasi (oddiy veb-sahifa) shu portda.
    public static let downloadPort: UInt16 = 47778
    /// 4 — shaxmat. Eski ilovalarga "yangilang" deyiladi (yangi versiya havolasi bilan).
    public static let version = 4
    public static let maxChatLength = 200
}

// MARK: - Odamcha va hamkasb

public enum PeerStatus: String, Codable, CaseIterable {
    case active, away, busy, hidden
}

public enum HatStyle: String, Codable, CaseIterable {
    case beanie, cap, doppi, strawHat
}

public struct AvatarStyle: Codable, Equatable {
    public var hat: HatStyle
    public var hatColor: UInt32
    public var vestColor: UInt32
    public var skinColor: UInt32

    public init(hat: HatStyle, hatColor: UInt32, vestColor: UInt32, skinColor: UInt32) {
        self.hat = hat
        self.hatColor = hatColor
        self.vestColor = vestColor
        self.skinColor = skinColor
    }

    public static let standard = AvatarStyle(hat: .doppi, hatColor: 0x1E3A5F, vestColor: 0x1E88E5, skinColor: 0xE0AC69)
}

public struct PeerInfo: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var team: String
    public var avatar: AvatarStyle
    public var status: PeerStatus

    public init(id: String, name: String, team: String, avatar: AvatarStyle, status: PeerStatus) {
        self.id = id
        self.name = name
        self.team = team
        self.avatar = avatar
        self.status = status
    }
}

// MARK: - O‘yinlar

public enum GameKind: String, Codable, CaseIterable {
    /// Issiq kartoshka: koptokni portlashidan oldin boshqaga uzatish kerak.
    case hotBall
    /// Hammaning ekranida bir vaqtda nishon chiqadi — kim birinchi bossa, ochko o‘shaniki.
    case marksman
    /// Jamoaviy sport o‘yinlari (ko‘klar va qizillar).
    case volleyball, tennis, penalty, basketball, tugOfWar
    /// Shaxmat: lobbida rang tanlanadi (ko‘klar — oqlar, qizillar — qoralar), keyin partiya alohida oynada.
    case chessBlitz, chessDaily, chessTeam

    public var title: String {
        switch self {
        case .hotBall: return "Muz koptok"
        case .marksman: return "Mergan"
        case .volleyball: return "Voleybol"
        case .tennis: return "Stol tennisi"
        case .penalty: return "Penalti"
        case .basketball: return "Basketbol"
        case .tugOfWar: return "Arqon tortish"
        case .chessBlitz: return "Shaxmat · blits"
        case .chessDaily: return "Shaxmat · kunlik"
        case .chessTeam: return "Shaxmat · jamoaviy"
        }
    }

    public var emoji: String {
        switch self {
        case .hotBall: return "💣"
        case .marksman: return "🎯"
        case .volleyball: return "🏐"
        case .tennis: return "🏓"
        case .penalty: return "⚽"
        case .basketball: return "🏀"
        case .tugOfWar: return "🪢"
        case .chessBlitz, .chessDaily, .chessTeam: return "♟️"
        }
    }

    public var rules: String {
        switch self {
        case .hotBall: return "Koptok kimda portlasa, o‘sha chiqadi. Koptok sizga kelsa — tezda boshqa o‘yinchini bosing!"
        case .marksman: return "Ekranda nishon chiqadi. Kim birinchi bossa — ochko o‘shaniki."
        case .volleyball: return "Odamchangiz sichqonchaga ergashadi, bosish — sakrash. To‘p sizning tomoningizga tushmasin. 7 ochkogacha."
        case .tennis: return "Raketkangiz sichqonchaga ergashadi. To‘pni qaytaring — o‘tkazib yuborgan jamoa ochko beradi. 7 ochkogacha."
        case .penalty: return "Navbat bilan: tepuvchi darvozaning bir joyini bosadi, darvozabon qayerga sakrashini tanlaydi. Har jamoaga 5 ta zarba."
        case .basketball: return "Odamchangizdan sichqonchani orqaga tortib qo‘yib yuboring — to‘p otiladi. 3 raund, savat har safar uzoqlashadi."
        case .tugOfWar: return "Iloji boricha tez bosing! Jamoangiz qancha tez bossa, arqonni shuncha kuchli tortadi."
        case .chessBlitz: return "Har kimga 5 daqiqa, har yurishga +3 soniya. Doska alohida oynada ochiladi."
        case .chessDaily: return "Bo‘sh paytingizda yuring — har yurishga 24 soatgacha. Navbat kelganda xabar beramiz."
        case .chessTeam: return "Ko‘klar oqlarda, Qizillar qoralarda. Har yurishga 60 soniya: jamoa ovoz beradi, ko‘pchilik tanlagani o‘ynaladi."
        }
    }

    /// Lobbida ikki jamoaga bo‘linadimi (sport va shaxmat).
    public var isTeamGame: Bool {
        switch self {
        case .hotBall, .marksman: return false
        default: return true
        }
    }

    /// Ekranning pastidagi sport maydonida o‘ynaladi.
    public var isSport: Bool {
        switch self {
        case .volleyball, .tennis, .penalty, .basketball, .tugOfWar: return true
        default: return false
        }
    }

    public var isChess: Bool {
        chessMode != nil
    }

    public var chessMode: ChessMode? {
        switch self {
        case .chessBlitz: return .blitz
        case .chessDaily: return .daily
        case .chessTeam: return .team
        default: return nil
        }
    }

    public var minPlayers: Int { 2 }

    public var maxPlayers: Int {
        switch self {
        case .hotBall: return 10
        case .marksman: return 12
        case .volleyball: return 8
        case .tennis: return 4
        case .penalty: return 12
        case .basketball: return 12
        case .tugOfWar: return 16
        case .chessBlitz, .chessDaily: return 2
        case .chessTeam: return 12
        }
    }
}

/// Jamoalar: 0 — ko‘klar (chapda), 1 — qizillar (o‘ngda).
public enum TeamSide {
    public static let blue = 0
    public static let red = 1

    public static func name(_ team: Int) -> String {
        team == blue ? "Ko‘klar" : "Qizillar"
    }

    public static func emoji(_ team: Int) -> String {
        team == blue ? "🔵" : "🔴"
    }
}

/// Maydon o‘lchami: eni 1 birlik, balandligi 0.45 birlik. Hamma ekranda bir xil nisbatda chiziladi.
public enum Court {
    public static let height: Double = 0.45
}

/// Basketbol to‘pining uchishi — server ham, ilova ham aynan shu formula bilan hisoblaydi.
public enum BasketPhysics {
    public static let startY: Double = 0.12
    public static let gravity: Double = 1.6
    public static let maxSpeed: Double = 1.55
    public static let tolerance: Double = 0.034

    public static func velocity(angle: Double, power: Double) -> (vx: Double, vy: Double) {
        let clamped: Double = min(1, max(0.15, power))
        let speed: Double = maxSpeed * clamped
        return (cos(angle) * speed, sin(angle) * speed)
    }

    public static func point(x0: Double, angle: Double, power: Double, t: Double) -> (x: Double, y: Double) {
        let v = velocity(angle: angle, power: power)
        let x: Double = x0 + v.vx * t
        let drop: Double = 0.5 * gravity * t * t
        let y: Double = startY + v.vy * t - drop
        return (x, y)
    }

    /// To‘p halqaga tushadimi: halqa chizig‘ini pastga qarab kesib o‘tganda balandligi to‘g‘ri kelsa — ha.
    public static func isMade(x0: Double, angle: Double, power: Double, hoopX: Double, hoopY: Double) -> Bool {
        let v = velocity(angle: angle, power: power)
        guard v.vx > 0.01 else { return false }
        let t: Double = (hoopX - x0) / v.vx
        guard t > 0 else { return false }
        let y: Double = point(x0: x0, angle: angle, power: power, t: t).y
        let falling: Double = v.vy - gravity * t
        return falling < 0 && abs(y - hoopY) < tolerance
    }

    /// To‘p yerga tushadigan (yoki halqaga yetadigan) vaqt.
    public static func flightTime(x0: Double, angle: Double, power: Double, hoopX: Double, made: Bool) -> Double {
        let v = velocity(angle: angle, power: power)
        if made && v.vx > 0.01 {
            return (hoopX - x0) / v.vx
        }
        let a: Double = 0.5 * gravity
        let disc: Double = v.vy * v.vy + 4 * a * startY
        let root: Double = (v.vy + disc.squareRoot()) / (2 * a)
        return min(max(root, 0.3), 3)
    }
}

public enum RoomPhase: String, Codable {
    case lobby, playing, finished
}

public struct RoomInfo: Codable, Equatable, Identifiable {
    public var id: String
    public var game: GameKind
    public var hostID: String
    public var players: [String]
    public var phase: RoomPhase
    /// Lobbi avtomatik boshlanadigan vaqt (Unix sekund), bo‘lmasa nil.
    public var startsAt: Double?
    /// Jamoaviy o‘yinlarda: o‘yinchi → jamoa (0 — ko‘klar, 1 — qizillar).
    public var teams: [String: Int]?

    public init(id: String, game: GameKind, hostID: String, players: [String], phase: RoomPhase,
                startsAt: Double?, teams: [String: Int]? = nil) {
        self.id = id
        self.game = game
        self.hostID = hostID
        self.players = players
        self.phase = phase
        self.startsAt = startsAt
        self.teams = teams
    }

    public func team(of id: String) -> Int {
        teams?[id] ?? TeamSide.blue
    }
}

/// Mergan o‘yinidagi nishon. x va y — ekran o‘lchamiga nisbatan (0...1), y pastdan yuqoriga.
public struct GameTarget: Codable, Equatable {
    public var id: Int
    public var x: Double
    public var y: Double
    public var lifetime: Double

    public init(id: Int, x: Double, y: Double, lifetime: Double) {
        self.id = id
        self.x = x
        self.y = y
        self.lifetime = lifetime
    }
}

/// Jonli sport o‘yinidagi bitta tana (o‘yinchi yoki raketka).
public struct SportBody: Codable, Equatable {
    public var id: String
    public var x: Double
    public var y: Double

    public init(id: String, x: Double, y: Double) {
        self.id = id
        self.x = x
        self.y = y
    }
}

/// Jonli sport o‘yinining holati — server sekundiga 15 marta yuboradi.
public struct SportState: Codable {
    public var bodies: [SportBody]
    public var ballX: Double
    public var ballY: Double
    public var blue: Int
    public var red: Int
    /// Arqon tortishda arqonning holati (-1 — ko‘klar yutdi, 1 — qizillar yutdi).
    public var rope: Double
    public var timeLeft: Double
    /// Server soati (sekund). Ilova holatlar orasini shu vaqt bo‘yicha silliq to‘ldiradi.
    public var time: Double?

    public init(bodies: [SportBody], ballX: Double, ballY: Double, blue: Int, red: Int, rope: Double, timeLeft: Double,
                time: Double? = nil) {
        self.bodies = bodies
        self.ballX = ballX
        self.ballY = ballY
        self.blue = blue
        self.red = red
        self.rope = rope
        self.timeLeft = timeLeft
        self.time = time
    }
}

public enum PenaltyOutcome: String, Codable {
    case goal, saved, post
}

public enum SportAction: Codable {
    case jump
    case pull
    /// Penalti: darvozaga nisbatan (0...1) nishon.
    case aim(x: Double, y: Double)
    /// Penalti: darvozabon qayerga sakraydi (0...1).
    case dive(x: Double)
    /// Basketbol: burchak (radian) va kuch (0...1).
    case shoot(angle: Double, power: Double)
}

public enum GameEvent: Codable {
    case hotBallHolder(holder: String, alive: [String])
    case hotBallExploded(loser: String, alive: [String])
    case target(GameTarget)
    case targetHit(targetID: Int, by: String, scores: [String: Int])
    case targetMissed(targetID: Int)
    case finished(winner: String?, scores: [String: Int])
    case sportState(SportState)
    case sportPoint(team: Int, blue: Int, red: Int, text: String)
    case penaltyTurn(shooter: String, keeper: String, turn: Int, seconds: Double)
    case penaltyResult(shooter: String, keeper: String, aimX: Double, aimY: Double, diveX: Double,
                       outcome: PenaltyOutcome, blue: Int, red: Int)
    case basketRound(round: Int, hoopX: Double, hoopY: Double, seconds: Double, spots: [String: Double])
    case basketShot(player: String, x0: Double, angle: Double, power: Double, made: Bool, points: Int, blue: Int, red: Int)
    case teamFinished(winner: Int?, blue: Int, red: Int)
}

// MARK: - Xabarlar

public enum PingKind: String, Codable {
    case wave, tea
}

/// Ilova → server.
public enum ClientMessage: Codable {
    case hello(id: String, name: String, team: String, avatar: AvatarStyle, status: PeerStatus, code: String, version: Int)
    case status(PeerStatus)
    case profile(name: String, team: String, avatar: AvatarStyle)
    case ping(to: String, kind: PingKind)
    case projectile(to: String)
    case chat(to: String?, text: String)
    case invite(to: String, game: GameKind)
    case respond(roomID: String, accept: Bool)
    case join(roomID: String)
    case leave(roomID: String)
    case start(roomID: String)
    case pass(roomID: String, to: String)
    case hit(roomID: String, targetID: Int)
    case switchTeam(roomID: String)
    case sportMove(roomID: String, value: Double)
    case sportAction(roomID: String, action: SportAction)
    /// Yurish (jamoaviyda — ovoz).
    case chessMove(gameID: String, move: ChessMove)
    case chessResign(gameID: String)
    /// Durang taklif qilish yoki raqib taklifini qabul qilish.
    case chessDraw(gameID: String)
    case chessWatch(gameID: String)
}

/// Mac mini'ga joylangan eng yangi ilova versiyasi.
public struct AppRelease: Codable, Equatable {
    public var version: String
    public var build: Int
    /// Yuklab olish sahifasi, masalan http://build-mini.local:47778/
    public var url: String
    public var notes: String

    public init(version: String, build: Int, url: String, notes: String) {
        self.version = version
        self.build = build
        self.url = url
        self.notes = notes
    }
}

/// Server → ilova.
public enum ServerMessage: Codable {
    case welcome(you: String, peers: [PeerInfo], rooms: [RoomInfo])
    case rejected(reason: String)
    case notice(text: String)
    case peerJoined(PeerInfo)
    case peerUpdated(PeerInfo)
    case peerLeft(id: String)
    case ping(from: String, kind: PingKind)
    case projectile(from: String)
    case chat(from: String, text: String, direct: Bool)
    case invited(roomID: String, from: String, game: GameKind)
    case declined(roomID: String, by: String)
    case room(RoomInfo)
    case roomClosed(roomID: String)
    case game(roomID: String, event: GameEvent)
    /// Ulanganda va yangi versiya joylanganda yuboriladi.
    case latestApp(AppRelease)
    /// Partiya holati (har o‘zgarishda).
    case chess(ChessGameState)
    /// Hozir jonli o‘ynalayotgan partiyalar.
    case chessLive([ChessSummary])
}

// MARK: - Kodlash

public enum HVCoding {
    public static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }
}
