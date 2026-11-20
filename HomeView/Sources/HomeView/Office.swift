import AppKit
import Combine
import HomeViewProtocol

// MARK: - Bildirishnoma kartochkalari (o‘ng yuqori burchakda)

struct ToastAction: Identifiable {
    let id = UUID()
    let title: String
    let primary: Bool
    let handler: () -> Void
}

struct Toast: Identifiable {
    enum Kind {
        case standard
        case lobby(roomID: String)
        case compose(to: String?)
    }

    let id = UUID()
    var icon: String
    var title: String
    var message: String
    var kind: Kind = .standard
    var actions: [ToastAction] = []
    /// nil — o‘zi yopilmaydi.
    var autoDismiss: Double? = 8
}

enum OfficeConnection: Equatable {
    case off, notConfigured, searching, connecting, connected, failed(String)

    var text: String {
        switch self {
        case .off: return "O‘chirilgan"
        case .notConfigured: return "Ismingizni kiriting"
        case .searching: return "Ofis serveri qidirilmoqda..."
        case .connecting: return "Ulanmoqda..."
        case .connected: return "Ulangan"
        case .failed(let reason): return reason
        }
    }
}

/// Menyu bandini yopiq funksiya bilan ishlatish uchun.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) ishlatilmaydi") }

    @objc private func fire() { handler() }
}

// MARK: - Ofis

/// Ofis tarmog‘i bilan ishlaydigan markaziy boshqaruvchi (asosiy oqimda ishlaydi).
/// Server xabarlarini qabul qiladi, hamkasblar ro‘yxatini yuritadi va dunyoga "kimni ko‘rsatish"ni aytadi.
final class Office: ObservableObject {
    static let shared = Office()

    @Published private(set) var connection: OfficeConnection = .off
    @Published private(set) var peers: [PeerInfo] = []
    /// Mac mini'dagi eng yangi ilova (yuklab olish havolasi uchun).
    @Published private(set) var latestRelease: AppRelease?
    /// Shu ilovadan yangiroq versiya joylangan bo‘lsa.
    @Published private(set) var availableUpdate: AppRelease?
    private var announcedBuild = 0
    @Published private(set) var rooms: [RoomInfo] = []
    @Published private(set) var toasts: [Toast] = []
    /// Shaxmat partiyalari: o‘zim o‘ynayotgan va kuzatayotganlarim.
    @Published private(set) var chessGames: [String: ChessGameState] = [:]
    /// Hozir jonli o‘ynalayotgan partiyalar (odamcha bayroqchasi va "kuzatish" uchun).
    @Published private(set) var liveChess: [ChessSummary] = [] {
        didSet { world?.syncOffice(peers: visiblePeers, rooms: worldRooms) }
    }
    private var pendingWatch: String?

    let myID = Settings.shared.peerID
    /// Asosiy monitordagi dunyo — hamkasblar va o‘yinlar shu yerda ko‘rinadi.
    weak var world: SnowWorld? {
        didSet { world?.syncOffice(peers: visiblePeers, rooms: worldRooms) }
    }

    private let client = NetworkClient()
    private var running = false
    private var lastAddress = ""
    private var lastCode = ""
    private var lastProfile: (String, String, AvatarStyle)?
    private var lastStatus: PeerStatus?
    private var autoAway = false
    private var idleTimer: Timer?

    private init() {
        client.onMessage = { [weak self] message in self?.handle(message) }
        client.onState = { [weak self] state in self?.clientState(state) }
        client.helloProvider = { [weak self] in
            self?.helloMessage() ?? .status(.active)
        }
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in self?.checkIdle() }
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    // MARK: - Holat

    var isConnected: Bool { connection == .connected }

    var myInfo: PeerInfo {
        let settings = Settings.shared
        return PeerInfo(id: myID, name: settings.displayName, team: settings.team,
                        avatar: settings.avatar, status: effectiveStatus)
    }

    private var effectiveStatus: PeerStatus {
        let manual = Settings.shared.myStatus
        return manual == .active && autoAway ? .away : manual
    }

    /// Ekranda ko‘rsatiladiganlar: siz tanlaganlar (soni cheklanmagan).
    /// Tartib: avval o‘z jamoangiz, keyin alifbo bo‘yicha.
    var visiblePeers: [PeerInfo] {
        let settings = Settings.shared
        let choices = settings.peerChoices
        let fallback = settings.newPeersVisible
        let myTeam = settings.team.lowercased()
        let chosen = peers.filter { choices[$0.id] ?? fallback }
        return chosen.sorted { a, b in
            let aTeam = !myTeam.isEmpty && a.team.lowercased() == myTeam
            let bTeam = !myTeam.isEmpty && b.team.lowercased() == myTeam
            if aTeam != bTeam { return aTeam }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    // MARK: - Ekrandagi hamkasblarni tanlash

    /// Ro‘yxat qatori: onlayn hamkasblar va ilgari ko‘rilganlar.
    struct Colleague: Identifiable {
        let id: String
        let name: String
        let team: String
        /// nil — hozir oflayn.
        let status: PeerStatus?
        let shown: Bool
    }

    var colleagues: [Colleague] {
        let settings = Settings.shared
        let choices = settings.peerChoices
        let fallback = settings.newPeersVisible
        var rows: [String: Colleague] = [:]
        for (id, entry) in settings.knownPeers where id != myID {
            let name = entry.first ?? "?"
            let team = entry.count > 1 ? entry[1] : ""
            rows[id] = Colleague(id: id, name: name, team: team, status: nil, shown: choices[id] ?? fallback)
        }
        for info in peers {
            rows[info.id] = Colleague(id: info.id, name: info.name, team: info.team, status: info.status,
                                      shown: choices[info.id] ?? fallback)
        }
        return rows.values.sorted { a, b in
            let aOnline = a.status != nil
            let bOnline = b.status != nil
            if aOnline != bOnline { return aOnline }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    func isShown(_ id: String) -> Bool {
        let settings = Settings.shared
        return settings.peerChoices[id] ?? settings.newPeersVisible
    }

    func setShown(_ id: String, _ shown: Bool) {
        setShown([id], shown)
    }

    func setShown(_ ids: [String], _ shown: Bool) {
        guard !ids.isEmpty else { return }
        objectWillChange.send()
        var choices = Settings.shared.peerChoices
        for id in ids {
            choices[id] = shown
        }
        Settings.shared.peerChoices = choices
        world?.syncOffice(peers: visiblePeers, rooms: worldRooms)
    }

    /// Ko‘rilgan hamkasblarni eslab qolish (ro‘yxatda oflayn bo‘lsa ham turishi uchun).
    private func remember(_ list: [PeerInfo]) {
        var known = Settings.shared.knownPeers
        var changed = false
        for info in list where info.id != myID {
            let entry = [info.name, info.team]
            if known[info.id] != entry {
                known[info.id] = entry
                changed = true
            }
        }
        guard changed else { return }
        Settings.shared.knownPeers = known
    }

    func peer(_ id: String) -> PeerInfo? {
        id == myID ? myInfo : peers.first { $0.id == id }
    }

    func name(_ id: String) -> String {
        id == myID ? "Siz" : (peer(id)?.name ?? "Hamkasb")
    }

    var myRoom: RoomInfo? {
        rooms.first { $0.players.contains(myID) }
    }

    // MARK: - Sozlamalar

    func applySettings() {
        let settings = Settings.shared
        guard settings.officeEnabled else {
            if running {
                running = false
                client.stop()
                peers.removeAll()
                rooms.removeAll()
                world?.syncOffice(peers: [], rooms: [])
            }
            connection = .off
            return
        }
        guard settings.isOfficeConfigured else {
            if running {
                running = false
                client.stop()
            }
            connection = .notConfigured
            return
        }
        if !running || settings.serverAddress != lastAddress || settings.officeCode != lastCode {
            running = true
            lastAddress = settings.serverAddress
            lastCode = settings.officeCode
            lastProfile = (settings.displayName, settings.team, settings.avatar)
            lastStatus = effectiveStatus
            client.start(address: settings.serverAddress)
            return
        }
        let profile = (settings.displayName, settings.team, settings.avatar)
        if let last = lastProfile, last.0 != profile.0 || last.1 != profile.1 || last.2 != profile.2 {
            lastProfile = profile
            client.send(.profile(name: profile.0, team: profile.1, avatar: profile.2))
        }
        sendStatusIfChanged()
        world?.syncOffice(peers: visiblePeers, rooms: worldRooms)
    }

    private func sendStatusIfChanged() {
        let status = effectiveStatus
        guard status != lastStatus else { return }
        lastStatus = status
        client.send(.status(status))
    }

    private func helloMessage() -> ClientMessage {
        let settings = Settings.shared
        lastStatus = effectiveStatus
        return .hello(id: myID, name: settings.displayName, team: settings.team, avatar: settings.avatar,
                      status: effectiveStatus, code: settings.officeCode, version: HVProtocol.version)
    }

    /// 5 daqiqa kompyuterga tegilmasa — "uzoqda" (odamcha o‘tirib choy ichadi).
    private func checkIdle() {
        guard running else { return }
        let mouse = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved)
        let keys = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        let clicks = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown)
        let idle = min(mouse, keys, clicks)
        autoAway = idle > 300
        sendStatusIfChanged()
    }

    private func clientState(_ state: NetworkClient.State) {
        switch state {
        case .idle: connection = running ? .searching : .off
        case .searching: connection = .searching
        case .connecting: connection = .connecting
        case .connected: connection = .connected
        case .failed(let reason):
            connection = .failed(reason)
            if !peers.isEmpty {
                peers.removeAll()
                rooms.removeAll()
                world?.syncOffice(peers: [], rooms: [])
            }
        }
    }

    // MARK: - Server xabarlari

    private func handle(_ message: ServerMessage) {
        switch message {
        case .welcome(_, let list, let roomList):
            connection = .connected
            peers = list.filter { $0.id != myID }
            remember(peers)
            rooms = roomList
            world?.syncOffice(peers: visiblePeers, rooms: worldRooms)
            if !list.isEmpty {
                post(Toast(icon: "👋", title: "Ofisga ulandingiz", message: "Hozir \(peers.count) kishi onlayn", autoDismiss: 4))
            }

        case .rejected(let reason):
            connection = .failed(reason)
            post(Toast(icon: "⚠️", title: "Ofisga ulanib bo‘lmadi", message: reason, autoDismiss: 10))

        case .chess(let state):
            let previous = chessGames[state.id]
            chessGames[state.id] = state
            chessChanged(state, previous: previous)

        case .chessLive(let list):
            liveChess = list

        case .latestApp(let release):
            #if APPSTORE
            // TestFlight / App Store versiyasini TestFlight o‘zi yangilaydi — DMG havolasi ko‘rsatilmaydi
            _ = release
            #else
            latestRelease = release
            if release.build > Office.currentBuild {
                availableUpdate = release
                if announcedBuild != release.build {
                    announcedBuild = release.build
                    let message = release.notes.isEmpty ? "Yuklab olib, eski ilovaning o‘rniga qo‘ying — bir daqiqalik ish." : release.notes
                    post(Toast(icon: "🆕", title: "HomeView \(release.version) chiqdi", message: message,
                               actions: [ToastAction(title: "Yuklab olish", primary: true) { [weak self] in self?.openDownloadPage() }],
                               autoDismiss: 30))
                }
            } else {
                availableUpdate = nil
            }
            #endif

        case .notice(let text):
            post(Toast(icon: "ℹ️", title: text, message: "", autoDismiss: 4))

        case .peerJoined(let info), .peerUpdated(let info):
            guard info.id != myID else { return }
            let isNew = Settings.shared.knownPeers[info.id] == nil
            remember([info])
            if isNew && Settings.shared.peerChoices[info.id] == nil && !Settings.shared.newPeersVisible {
                let teamText = info.team.isEmpty ? "" : " (\(info.team))"
                post(Toast(icon: "👋", title: "Yangi hamkasb: \(info.name)\(teamText)", message: "Hozircha ekraningizda ko‘rinmaydi.",
                           actions: [ToastAction(title: "Ekranimga chiqarish", primary: true) { [weak self] in
                               self?.setShown(info.id, true)
                           }], autoDismiss: 12))
            }
            if let index = peers.firstIndex(where: { $0.id == info.id }) {
                peers[index] = info
            } else {
                peers.append(info)
            }
            world?.syncOffice(peers: visiblePeers, rooms: worldRooms)

        case .peerLeft(let id):
            peers.removeAll { $0.id == id }
            world?.syncOffice(peers: visiblePeers, rooms: worldRooms)

        case .ping(let from, let kind):
            switch kind {
            case .wave:
                world?.peerWaves(from)
            case .tea:
                world?.peerSays(from, text: "☕ Choyga chiqamizmi?")
                post(Toast(icon: "☕", title: "\(name(from)) choyga taklif qilyapti", message: "Kichik tanaffus qilamizmi?",
                           actions: [
                            ToastAction(title: "Boraman", primary: true) { [weak self] in self?.chat(to: from, text: "Boraman! ☕") },
                            ToastAction(title: "Keyinroq", primary: false) { [weak self] in self?.chat(to: from, text: "Hozir bandman, keyinroq") }
                           ], autoDismiss: 30))
            }

        case .projectile(let from):
            world?.incomingProjectile(from: from)

        case .chat(let from, let text, let direct):
            world?.peerSays(from, text: text)
            post(Toast(icon: direct ? "💬" : "📣", title: name(from) + (direct ? "" : " (hammaga)"), message: text,
                       actions: [ToastAction(title: "Javob yozish", primary: false) { [weak self] in self?.compose(to: from) }],
                       autoDismiss: 12))

        case .invited(let roomID, let from, let game):
            post(Toast(icon: game.emoji, title: "\(name(from)) sizni «\(game.title)» o‘yiniga chaqiryapti",
                       message: game.rules,
                       actions: [
                        ToastAction(title: "Qabul qilish", primary: true) { [weak self] in self?.respond(roomID: roomID, accept: true) },
                        ToastAction(title: "Rad etish", primary: false) { [weak self] in self?.respond(roomID: roomID, accept: false) }
                       ], autoDismiss: 30))

        case .declined(_, let by):
            post(Toast(icon: "🙅", title: "\(name(by)) hozir o‘ynay olmaydi", message: "", autoDismiss: 5))

        case .room(let info):
            upsertRoom(info)

        case .roomClosed(let roomID):
            rooms.removeAll { $0.id == roomID }
            removeLobbyToast(roomID)
            world?.endStage(roomID)
            world?.syncOffice(peers: visiblePeers, rooms: worldRooms)

        case .game(let roomID, let event):
            world?.stageEvent(roomID, event)
        }
    }

    private func upsertRoom(_ info: RoomInfo) {
        if let index = rooms.firstIndex(where: { $0.id == info.id }) {
            rooms[index] = info
        } else {
            rooms.append(info)
        }
        let iAmIn = info.players.contains(myID)
        switch info.phase {
        case .lobby:
            if iAmIn && !toasts.contains(where: { isLobby($0, info.id) }) {
                post(Toast(icon: info.game.emoji, title: info.game.title, message: info.game.rules,
                           kind: .lobby(roomID: info.id), autoDismiss: nil))
            } else if !iAmIn {
                removeLobbyToast(info.id)
            }
        case .playing:
            removeLobbyToast(info.id)
            if iAmIn && !info.game.isChess {
                let players = info.players.compactMap { peer($0) }
                world?.startStage(info, players: players, myID: myID)
            }
        case .finished:
            removeLobbyToast(info.id)
        }
        world?.syncOffice(peers: visiblePeers, rooms: worldRooms)
    }

    private func isLobby(_ toast: Toast, _ roomID: String) -> Bool {
        if case .lobby(let id) = toast.kind { return id == roomID }
        return false
    }

    private func removeLobbyToast(_ roomID: String) {
        toasts.removeAll { isLobby($0, roomID) }
    }

    // MARK: - Kartochkalar

    func post(_ toast: Toast) {
        // Bir vaqtda ko‘pi bilan 4 ta: eng eskisi (doimiy bo‘lmagani) yopiladi
        if toasts.count >= 4, let index = toasts.firstIndex(where: { $0.autoDismiss != nil }) {
            toasts.remove(at: index)
        }
        toasts.append(toast)
        if let seconds = toast.autoDismiss {
            let id = toast.id
            after(seconds) { [weak self] in self?.dismiss(id) }
        }
    }

    func dismiss(_ id: UUID) {
        toasts.removeAll { $0.id == id }
    }

    // MARK: - Amallar (odamcha menyusi, kartochkalar, o‘yin sahnasi chaqiradi)

    func wave(_ id: String) {
        client.send(.ping(to: id, kind: .wave))
        world?.peerSays(id, text: "👋", fromMe: true)
    }

    func tea(_ id: String) {
        client.send(.ping(to: id, kind: .tea))
        post(Toast(icon: "☕", title: "Taklif yuborildi", message: "\(name(id)) javobini kutyapmiz", autoDismiss: 4))
    }

    func throwAt(_ id: String) {
        world?.throwAtPeer(id) { [weak self] in
            self?.client.send(.projectile(to: id))
        }
    }

    func chat(to id: String?, text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        client.send(.chat(to: id, text: String(clean.prefix(HVProtocol.maxChatLength))))
    }

    func compose(to id: String?) {
        toasts.removeAll { if case .compose = $0.kind { return true }; return false }
        let title = id.map { "\(name($0))ga xabar" } ?? "Hammaga xabar"
        post(Toast(icon: "💬", title: title, message: "", kind: .compose(to: id), autoDismiss: nil))
    }

    func invite(_ id: String, game: GameKind) {
        client.send(.invite(to: id, game: game))
    }

    func respond(roomID: String, accept: Bool) {
        client.send(.respond(roomID: roomID, accept: accept))
    }

    func join(roomID: String) {
        client.send(.join(roomID: roomID))
    }

    func leave(roomID: String) {
        client.send(.leave(roomID: roomID))
        removeLobbyToast(roomID)
        world?.endStage(roomID)
    }

    func start(roomID: String) {
        client.send(.start(roomID: roomID))
    }

    func pass(roomID: String, to id: String) {
        client.send(.pass(roomID: roomID, to: id))
    }

    func hit(roomID: String, targetID: Int) {
        client.send(.hit(roomID: roomID, targetID: targetID))
    }

    // MARK: - Sport o‘yinlari

    func switchTeam(roomID: String) {
        client.send(.switchTeam(roomID: roomID))
    }

    /// Sichqoncha holati (sekundiga ko‘pi bilan 20 marta).
    func sportMove(roomID: String, value: Double) {
        client.send(.sportMove(roomID: roomID, value: value))
    }

    func sportAction(roomID: String, action: SportAction) {
        client.send(.sportAction(roomID: roomID, action: action))
    }

    /// Bo‘sh turgan hamma hamkasbni bitta o‘yinga chaqirish.
    func inviteEveryone(game: GameKind) {
        let playing: Set<String> = Set(rooms.filter { $0.phase == .playing }.flatMap { $0.players })
        let free: [PeerInfo] = peers.filter { $0.id != myID && $0.status == .active && !playing.contains($0.id) }
        let chosen: [PeerInfo] = Array(free.prefix(game.maxPlayers - 1))
        guard !chosen.isEmpty else {
            post(Toast(icon: "🤷", title: "Hozir bo‘sh hamkasb yo‘q", message: "Faol holatdagi hamkasblar chaqiriladi", autoDismiss: 5))
            return
        }
        for info in chosen {
            invite(info.id, game: game)
        }
        post(Toast(icon: game.emoji, title: "\(chosen.count) kishi «\(game.title)»ga chaqirildi",
                   message: "Qabul qilganlar lobbida ko‘rinadi", autoDismiss: 6))
    }

    /// O‘yinlar ro‘yxati: ko‘ngilochar, sport, shaxmat.
    private func addGameItems(to menu: NSMenu, suffix: String = "", action: @escaping (GameKind) -> Void) {
        for game in GameKind.allCases where !game.isTeamGame {
            menu.addItem(ClosureMenuItem("\(game.emoji)  \(game.title)\(suffix)") { action(game) })
        }
        menu.addItem(.separator())
        let sportHeader = NSMenuItem(title: "Sport — 🔵 ko‘klar va 🔴 qizillar", action: nil, keyEquivalent: "")
        sportHeader.isEnabled = false
        menu.addItem(sportHeader)
        for game in GameKind.allCases where game.isSport {
            menu.addItem(ClosureMenuItem("\(game.emoji)  \(game.title)\(suffix)") { action(game) })
        }
        menu.addItem(.separator())
        let chessHeader = NSMenuItem(title: "Shaxmat ♟", action: nil, keyEquivalent: "")
        chessHeader.isEnabled = false
        menu.addItem(chessHeader)
        for game in GameKind.allCases where game.isChess {
            let icon = game.chessMode?.emoji ?? game.emoji
            menu.addItem(ClosureMenuItem("\(icon)  \(game.title)\(suffix)") { action(game) })
        }
    }

    // MARK: - Shaxmat

    /// Ekrandagi bayroqchalar uchun: xonalar + jonli shaxmat partiyalari.
    private var worldRooms: [RoomInfo] {
        let chessRooms: [RoomInfo] = liveChess.map { summary in
            RoomInfo(id: summary.id, game: summary.mode == .team ? .chessTeam : .chessBlitz,
                     hostID: summary.white.first ?? "", players: summary.white + summary.black,
                     phase: .playing, startsAt: nil)
        }
        return rooms + chessRooms
    }

    /// Avval navbati menda bo‘lganlar, keyin davom etayotganlar, keyin tugaganlar.
    var chessGamesSorted: [ChessGameState] {
        let me = myID
        return chessGames.values.sorted { a, b in
            let aTurn: Bool = a.result == nil && a.color(of: me) == a.position.turn
            let bTurn: Bool = b.result == nil && b.color(of: me) == b.position.turn
            if aTurn != bTurn { return aTurn }
            let aActive: Bool = a.result == nil
            let bActive: Bool = b.result == nil
            if aActive != bActive { return aActive }
            return a.updatedAt > b.updatedAt
        }
    }

    /// Navbati menda bo‘lgan partiyalar soni.
    var chessTurnsWaiting: Int {
        let me = myID
        return chessGames.values.filter { $0.result == nil && $0.color(of: me) == $0.position.turn }.count
    }

    func chessOpponentTitle(_ state: ChessGameState, for color: ChessColor) -> String {
        if state.mode == .team {
            return color.opposite == .white ? "Ko‘klar" : "Qizillar"
        }
        return state.players(color.opposite).first.map { name($0) } ?? "Raqib"
    }

    func chessMove(_ gameID: String, _ move: ChessMove) {
        client.send(.chessMove(gameID: gameID, move: move))
    }

    func chessResign(_ gameID: String) {
        client.send(.chessResign(gameID: gameID))
    }

    func chessDraw(_ gameID: String) {
        client.send(.chessDraw(gameID: gameID))
    }

    func watchChess(_ gameID: String) {
        pendingWatch = gameID
        client.send(.chessWatch(gameID: gameID))
    }

    private func openChess(_ gameID: String) -> ToastAction {
        ToastAction(title: "Doskani ochish", primary: true) {
            ChessWindowController.shared.show(gameID: gameID)
        }
    }

    /// Partiya o‘zgardi: yangi boshlanganda, navbat kelganda, durang taklif qilinganda, tugaganda xabar.
    private func chessChanged(_ state: ChessGameState, previous: ChessGameState?) {
        if pendingWatch == state.id {
            pendingWatch = nil
            ChessWindowController.shared.show(gameID: state.id)
            return
        }
        guard let mine = state.color(of: myID) else { return }
        let opponent = chessOpponentTitle(state, for: mine)
        let windowOpen = ChessWindowController.shared.isShowing(state.id)

        if previous == nil && state.moves.isEmpty && state.result == nil {
            if state.mode == .daily {
                let first = mine == .white ? "Birinchi yurish sizda." : "\(opponent) birinchi yuradi."
                post(Toast(icon: "📅", title: "Kunlik shaxmat: \(opponent) bilan",
                           message: "Siz — \(mine.title.lowercased()). \(first)",
                           actions: [openChess(state.id)], autoDismiss: 15))
            } else {
                ChessWindowController.shared.show(gameID: state.id)
            }
            return
        }
        guard let previous else { return }

        if previous.result == nil, let result = state.result {
            let title: String
            if let winner = result.winner {
                title = winner == mine ? "🏆 Siz yutdingiz!" : "\(opponent) yutdi"
            } else {
                title = "🤝 Durang"
            }
            post(Toast(icon: "♟️", title: title, message: "Shaxmat: \(result.reason.title)",
                       actions: [openChess(state.id)], autoDismiss: 10))
            return
        }

        let myTurn: Bool = state.result == nil && state.position.turn == mine
        let newMove: Bool = state.moves.count > previous.moves.count
        if myTurn && newMove && !windowOpen {
            let last = state.sans.last ?? ""
            post(Toast(icon: "♞", title: "Navbat sizda", message: "\(opponent): \(last)",
                       actions: [openChess(state.id)], autoDismiss: state.mode == .daily ? 20 : 8))
        }
        if state.drawOffer == mine.opposite && previous.drawOffer != mine.opposite && !windowOpen {
            post(Toast(icon: "🤝", title: "\(opponent) durang taklif qildi", message: "",
                       actions: [openChess(state.id)], autoDismiss: 15))
        }
    }

    // MARK: - Yuklab olish va yangilanish

    static var currentBuild: Int {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return Int(value) ?? 0
    }

    /// Yuklab olish sahifasi. Server qo‘lda kiritilgan bo‘lsa — o‘sha manzil (Bonjour ishlamaydigan tarmoqlar uchun).
    var downloadPageURL: URL? {
        let manual = Settings.shared.serverAddress.trimmingCharacters(in: .whitespaces)
        if !manual.isEmpty {
            let host = manual.components(separatedBy: ":").first ?? manual
            return URL(string: "http://\(host):\(HVProtocol.downloadPort)/")
        }
        guard let release = latestRelease else { return nil }
        return URL(string: release.url)
    }

    func openDownloadPage() {
        guard let url = downloadPageURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Havolani nusxalash — hamkasbga Telegram yoki Slack'da yuborish uchun.
    func copyDownloadLink() {
        guard let url = downloadPageURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        post(Toast(icon: "🔗", title: "Havola nusxalandi", message: url.absoluteString, autoDismiss: 5))
    }

    func setStatus(_ status: PeerStatus) {
        Settings.shared.myStatus = status
    }

    // MARK: - Odamcha menyusi

    /// Hamkasbning odamchasi bosilganda chiqadigan menyu.
    func showMenu(for id: String, at point: NSPoint, in view: NSView) {
        guard let info = peer(id) else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let header = NSMenuItem(title: info.team.isEmpty ? info.name : "\(info.name) · \(info.team)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if let room = rooms.first(where: { $0.hostID == id && $0.phase == .lobby && !$0.players.contains(myID) }) {
            menu.addItem(ClosureMenuItem("\(room.game.emoji) «\(room.game.title)»ga qo‘shilish (\(room.players.count)/\(room.game.maxPlayers))") { [weak self] in
                self?.join(roomID: room.id)
            })
            menu.addItem(.separator())
        }

        if let live = liveChess.first(where: { $0.white.contains(id) || $0.black.contains(id) }) {
            menu.addItem(ClosureMenuItem("♟  Partiyani kuzatish") { [weak self] in self?.watchChess(live.id) })
            menu.addItem(.separator())
        }

        let theme = SeasonTheme.current
        menu.addItem(ClosureMenuItem("👋  Salom berish") { [weak self] in self?.wave(id) })
        menu.addItem(ClosureMenuItem("\(theme.kind.emoji)  \(theme.projectileTitle) otish") { [weak self] in self?.throwAt(id) })
        menu.addItem(ClosureMenuItem("💬  Xabar yozish…") { [weak self] in self?.compose(to: id) })
        menu.addItem(ClosureMenuItem("☕  Choyga taklif qilish") { [weak self] in self?.tea(id) })

        let gamesItem = NSMenuItem(title: "🎮  O‘yinga taklif qilish", action: nil, keyEquivalent: "")
        let games = NSMenu()
        addGameItems(to: games) { [weak self] game in self?.invite(id, game: game) }
        gamesItem.submenu = games
        menu.addItem(gamesItem)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("🙈  Ekranimdan olib tashlash") { [weak self] in
            guard let self else { return }
            self.setShown(id, false)
            self.post(Toast(icon: "🙈", title: "\(info.name) ekraningizdan olib tashlandi",
                            message: "Xabar yozish va o‘ynash mumkin. Qaytarish: ❄ → Ofis → Hamkasblar.",
                            actions: [ToastAction(title: "Qaytarish", primary: false) { [weak self] in
                                self?.setShown(id, true)
                            }], autoDismiss: 8))
        })
        menu.popUp(positioning: nil, at: point, in: view)
    }

    /// ❄ menyusidagi "Ofis" bo‘limi.
    func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let state = NSMenuItem(title: connection == .connected ? "Onlayn: \(peers.count) kishi" : connection.text,
                               action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)
        menu.addItem(.separator())

        let current = Settings.shared.myStatus
        for (status, title) in [(PeerStatus.active, "🟢  Faol"), (.busy, "🔕  Band (taklif va koptoklar kelmaydi)"), (.hidden, "👻  Ko‘rinmas")] {
            let item = ClosureMenuItem(title) { [weak self] in self?.setStatus(status) }
            item.state = current == status ? .on : .off
            menu.addItem(item)
        }

        if isConnected {
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("📣  Hammaga xabar…") { [weak self] in self?.compose(to: nil) })
            let everyoneItem = NSMenuItem(title: "🎮  Hammani o‘yinga chaqirish", action: nil, keyEquivalent: "")
            let everyoneMenu = NSMenu()
            addGameItems(to: everyoneMenu) { [weak self] game in self?.inviteEveryone(game: game) }
            everyoneItem.submenu = everyoneMenu
            everyoneItem.isEnabled = !peers.isEmpty
            menu.addItem(everyoneItem)
            let waiting = chessTurnsWaiting
            let chessTitle = waiting > 0 ? "♟  Shaxmat partiyalarim — navbat sizda (\(waiting))" : "♟  Shaxmat partiyalarim"
            let chessItem = ClosureMenuItem(chessTitle) { ChessWindowController.shared.show() }
            chessItem.isEnabled = !chessGames.isEmpty
            menu.addItem(chessItem)
            #if !APPSTORE
            if downloadPageURL != nil {
                menu.addItem(ClosureMenuItem("🔗  Ilova havolasini nusxalash (hamkasbga yuborish)") { [weak self] in
                    self?.copyDownloadLink()
                })
            }
            #endif
            menu.addItem(.separator())
            let everyone = colleagues
            let shownCount = everyone.filter { $0.shown }.count
            menu.addItem(ClosureMenuItem("👥  Hamkasblar — ekranda \(shownCount) / \(everyone.count)…") {
                PeopleWindowController.shared.show()
            })
            if !peers.isEmpty {
                let shortList = peers.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }).prefix(15)
                for info in shortList {
                    let icon: String
                    switch info.status {
                    case .away: icon = "☕"
                    case .busy: icon = "🔕"
                    default: icon = "🟢"
                    }
                    let item = NSMenuItem(title: "\(icon)  \(info.name)\(info.team.isEmpty ? "" : " · \(info.team)")", action: nil, keyEquivalent: "")
                    let sub = NSMenu()
                    sub.addItem(ClosureMenuItem("👋  Salom berish") { [weak self] in self?.wave(info.id) })
                    sub.addItem(ClosureMenuItem("💬  Xabar yozish…") { [weak self] in self?.compose(to: info.id) })
                    sub.addItem(ClosureMenuItem("☕  Choyga taklif qilish") { [weak self] in self?.tea(info.id) })
                    sub.addItem(.separator())
                    let gamesItem = NSMenuItem(title: "🎮  O‘yinga taklif qilish", action: nil, keyEquivalent: "")
                    let games = NSMenu()
                    addGameItems(to: games) { [weak self] game in self?.invite(info.id, game: game) }
                    gamesItem.submenu = games
                    sub.addItem(gamesItem)
                    item.submenu = sub
                    menu.addItem(item)
                }
            }
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Ofis sozlamalari…") { SettingsWindowController.shared.show() })
        return menu
    }
}
