import Foundation
import Network
import HomeViewProtocol

/// Serverning "miyasi": kim ulangan, kim qaysi holatda, qaysi o‘yin xonalari ochiq.
/// Hamma ish bitta navbatda (queue) bajariladi — bir vaqtda ikki joydan o‘zgartirish bo‘lmaydi.
final class Hub {
    /// O‘yin fizikasi ham shu navbatda — shuning uchun eng yuqori ustuvorlik.
    let queue = DispatchQueue(label: "uz.homeview.hub", qos: .userInteractive)
    private let code: String
    private var sessions: [ObjectIdentifier: Session] = [:]
    private var byPeer: [String: Session] = [:]
    private var rooms: [String: Room] = [:]
    /// Mac mini'ga joylangan eng yangi ilova (bo‘lmasa nil).
    private var release: AppRelease?
    /// Shaxmat partiyalari (xonalardan alohida, diskka saqlanadi).
    let chess: ChessManager

    init(code: String, chessStore: URL) {
        self.code = code
        chess = ChessManager(queue: queue, storeURL: chessStore)
        chess.send = { [weak self] peer, message in
            self?.send(message, toPeer: peer)
        }
        chess.broadcast = { [weak self] message in
            self?.broadcast(message)
        }
        chess.isOnline = { [weak self] peer in
            self?.byPeer[peer] != nil
        }
        chess.nameOf = { [weak self] peer in
            self?.byPeer[peer]?.peer?.name ?? "?"
        }
        chess.start()
    }

    // MARK: - Ulanishlar

    func accept(_ connection: NWConnection) {
        let session = Session(connection: connection)
        sessions[ObjectIdentifier(session)] = session
        connection.stateUpdateHandler = { [weak self, weak session] state in
            guard let self, let session else { return }
            switch state {
            case .failed, .cancelled:
                self.drop(session)
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(session)
    }

    private func receive(_ session: Session) {
        session.connection.receiveMessage { [weak self, weak session] data, context, _, error in
            guard let self, let session else { return }
            if error != nil {
                self.drop(session)
                return
            }
            if let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata,
               metadata.opcode == .close {
                self.drop(session)
                return
            }
            if let data, !data.isEmpty, let message = HVCoding.decode(ClientMessage.self, from: data) {
                self.handle(message, from: session)
            }
            self.receive(session)
        }
    }

    private func drop(_ session: Session) {
        guard sessions.removeValue(forKey: ObjectIdentifier(session)) != nil else { return }
        session.connection.cancel()
        guard let peer = session.peer, byPeer[peer.id] === session else { return }
        byPeer.removeValue(forKey: peer.id)
        Log.info("Chiqdi: \(peer.name)")
        removeFromRooms(peer.id)
        chess.peerDisconnected(peer.id)
        if peer.status != .hidden {
            broadcast(.peerLeft(id: peer.id))
        }
    }

    // MARK: - Yuborish

    private func send(_ message: ServerMessage, to session: Session) {
        guard let data = HVCoding.encode(message) else { return }
        send(data: data, to: session)
    }

    private func send(data: Data, to session: Session) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "qk", metadata: [metadata])
        session.connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
    }

    private func send(_ message: ServerMessage, toPeer id: String) {
        if let session = byPeer[id] { send(message, to: session) }
    }

    /// Hammaga (ixtiyoriy: bittasidan tashqari).
    private func broadcast(_ message: ServerMessage, except excluded: String? = nil) {
        for (id, session) in byPeer where id != excluded {
            send(message, to: session)
        }
    }

    /// Xona a’zolariga: xabar bir marta kodlanadi, hammaga bir xil baytlar ketadi.
    func sendToRoom(_ roomID: String, _ message: ServerMessage) {
        guard let room = rooms[roomID], let data = HVCoding.encode(message) else { return }
        for id in room.info.players {
            if let session = byPeer[id] { send(data: data, to: session) }
        }
    }

    private func visiblePeers(except id: String) -> [PeerInfo] {
        byPeer.values.compactMap { $0.peer }.filter { $0.id != id && $0.status != .hidden }
    }

    private func name(of id: String) -> String {
        byPeer[id]?.peer?.name ?? "Hamkasb"
    }

    // MARK: - Xabarlarni qayta ishlash

    private func handle(_ message: ClientMessage, from session: Session) {
        if case let .hello(id, name, team, avatar, status, code, version) = message {
            hello(session, id: id, name: name, team: team, avatar: avatar, status: status, code: code, version: version)
            return
        }
        guard let me = session.peer else { return }   // salomlashmagan — hech narsa qilinmaydi

        switch message {
        case .hello:
            break

        case .status(let status):
            updatePeer(session) { $0.status = status }

        case .profile(let name, let team, let avatar):
            updatePeer(session) {
                $0.name = String(name.prefix(32))
                $0.team = String(team.prefix(24))
                $0.avatar = avatar
            }

        case .ping(let to, let kind):
            guard let target = reachable(to, from: session, what: kind == .tea ? "taklif" : "salom") else { return }
            send(.ping(from: me.id, kind: kind), to: target)

        case .projectile(let to):
            guard Date().timeIntervalSince(session.lastProjectile) > 1.2 else { return }
            session.lastProjectile = Date()
            guard let target = reachable(to, from: session, what: "koptok") else { return }
            send(.projectile(from: me.id), to: target)

        case .chat(let to, let text):
            let clean = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(HVProtocol.maxChatLength))
            guard !clean.isEmpty, Date().timeIntervalSince(session.lastChat) > 0.7 else { return }
            session.lastChat = Date()
            if let to {
                guard let target = reachable(to, from: session, what: "xabar") else { return }
                send(.chat(from: me.id, text: clean, direct: true), to: target)
            } else {
                broadcast(.chat(from: me.id, text: clean, direct: false), except: me.id)
            }

        case .invite(let to, let game):
            invite(from: session, to: to, game: game)

        case .respond(let roomID, let accept):
            respond(peerID: me.id, roomID: roomID, accept: accept)

        case .join(let roomID):
            join(peerID: me.id, roomID: roomID)

        case .leave(let roomID):
            leave(peerID: me.id, roomID: roomID)

        case .start(let roomID):
            if let room = rooms[roomID], room.info.hostID == me.id { startGame(room) }

        case .pass(let roomID, let to):
            rooms[roomID]?.logic?.pass(from: me.id, to: to)

        case .hit(let roomID, let targetID):
            rooms[roomID]?.logic?.hit(targetID: targetID, by: me.id)

        case .switchTeam(let roomID):
            switchTeam(peerID: me.id, roomID: roomID)

        case .sportMove(let roomID, let value):
            rooms[roomID]?.logic?.move(me.id, value: value)

        case .sportAction(let roomID, let action):
            rooms[roomID]?.logic?.action(me.id, action)

        case .chessMove(let gameID, let move):
            chess.move(gameID, by: me.id, move: move)

        case .chessResign(let gameID):
            chess.resign(gameID, by: me.id)

        case .chessDraw(let gameID):
            chess.draw(gameID, by: me.id)

        case .chessWatch(let gameID):
            chess.watch(gameID, by: me.id)
        }
    }

    private func hello(_ session: Session, id: String, name: String, team: String, avatar: AvatarStyle,
                       status: PeerStatus, code: String, version: Int) {
        guard self.code.isEmpty || code == self.code else {
            send(.rejected(reason: "Ofis kodi noto‘g‘ri"), to: session)
            return
        }
        guard version >= HVProtocol.version else {
            // Eski ilova "yangi versiya chiqdi" kartochkasini ko‘rsata oladi — havolani avval yuboramiz
            if let release {
                send(.latestApp(release), to: session)
            }
            send(.rejected(reason: "Ilovangiz eski — HomeView'ning yangi versiyasini o‘rnating"), to: session)
            return
        }
        guard !id.isEmpty, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            send(.rejected(reason: "Ism kiritilmagan"), to: session)
            return
        }
        // Xuddi shu odam qayta ulandi — eskisini yopamiz
        if let old = byPeer[id], old !== session {
            old.peer = nil
            sessions.removeValue(forKey: ObjectIdentifier(old))
            old.connection.cancel()
        }
        let peer = PeerInfo(id: id, name: String(name.prefix(32)), team: String(team.prefix(24)), avatar: avatar, status: status)
        let wasKnown = session.peer != nil
        session.peer = peer
        byPeer[id] = session
        send(.welcome(you: id, peers: visiblePeers(except: id), rooms: rooms.values.map { $0.info }), to: session)
        if let release {
            send(.latestApp(release), to: session)
        }
        chess.peerConnected(id)
        if !wasKnown && peer.status != .hidden {
            broadcast(.peerJoined(peer), except: id)
        }
        Log.info("Ulandi: \(peer.name) (\(peer.team)), jami \(byPeer.count)")
    }

    private func updatePeer(_ session: Session, _ change: (inout PeerInfo) -> Void) {
        guard var peer = session.peer else { return }
        let wasHidden = peer.status == .hidden
        change(&peer)
        session.peer = peer
        let isHidden = peer.status == .hidden
        if wasHidden && !isHidden {
            broadcast(.peerJoined(peer), except: peer.id)
        } else if !wasHidden && isHidden {
            broadcast(.peerLeft(id: peer.id), except: peer.id)
        } else if !isHidden {
            broadcast(.peerUpdated(peer), except: peer.id)
        }
    }

    /// Qabul qiluvchi ulanganmi va band emasmi? Bo‘lmasa — yuboruvchiga tushuntiriladi.
    private func reachable(_ id: String, from sender: Session, what: String) -> Session? {
        guard let target = byPeer[id], let peer = target.peer, peer.status != .hidden else {
            send(.notice(text: "Bu hamkasb hozir tarmoqda emas"), to: sender)
            return nil
        }
        if peer.status == .busy {
            send(.notice(text: "\(peer.name) hozir band — \(what) keyinroq"), to: sender)
            return nil
        }
        return target
    }

    // MARK: - O‘yin xonalari

    private func invite(from session: Session, to: String, game: GameKind) {
        guard let me = session.peer, to != me.id else { return }
        guard reachable(to, from: session, what: "taklif") != nil else { return }
        let room: Room
        if let existing = rooms.values.first(where: { $0.info.hostID == me.id && $0.info.phase == .lobby && $0.info.game == game }) {
            room = existing
        } else {
            removeFromRooms(me.id)
            let info = RoomInfo(id: UUID().uuidString, game: game, hostID: me.id, players: [me.id], phase: .lobby,
                                startsAt: nil, teams: game.isTeamGame ? [me.id: TeamSide.blue] : nil)
            room = Room(info: info)
            rooms[info.id] = room
            scheduleLobbyTimeout(room)
        }
        room.invited.insert(to)
        send(.invited(roomID: room.info.id, from: me.id, game: game), toPeer: to)
        broadcast(.room(room.info))
    }

    private func respond(peerID: String, roomID: String, accept: Bool) {
        guard let room = rooms[roomID] else {
            send(.notice(text: "Bu o‘yin allaqachon tugagan"), toPeer: peerID)
            return
        }
        room.invited.remove(peerID)
        if accept {
            join(peerID: peerID, roomID: roomID)
        } else {
            send(.declined(roomID: roomID, by: peerID), toPeer: room.info.hostID)
            if room.info.players.count < 2 && room.invited.isEmpty { close(room) }
        }
    }

    private func join(peerID: String, roomID: String) {
        guard let room = rooms[roomID] else { return }
        guard room.info.phase == .lobby else {
            send(.notice(text: "O‘yin allaqachon boshlangan"), toPeer: peerID)
            return
        }
        guard !room.info.players.contains(peerID) else { return }
        guard room.info.players.count < room.info.game.maxPlayers else {
            send(.notice(text: "O‘yinda joy qolmadi"), toPeer: peerID)
            return
        }
        removeFromRooms(peerID)
        room.info.players.append(peerID)
        if room.info.game.isTeamGame {
            // Kamroq odamli jamoaga qo‘shiladi
            let blues = room.info.teams?.values.filter { $0 == TeamSide.blue }.count ?? 0
            let reds = room.info.teams?.values.filter { $0 == TeamSide.red }.count ?? 0
            var teams = room.info.teams ?? [:]
            teams[peerID] = reds < blues ? TeamSide.red : TeamSide.blue
            room.info.teams = teams
        }
        if room.info.game.isChess && room.info.game != .chessTeam && room.info.players.count >= room.info.game.maxPlayers {
            // Ikki kishilik shaxmat: raqib qo‘shildi — darhol boshlaymiz
            startGame(room)
            return
        }
        if room.info.players.count >= room.info.game.minPlayers && room.info.startsAt == nil {
            // Yetarli o‘yinchi yig‘ildi — 20 soniyadan keyin o‘zi boshlanadi (yoki xona egasi oldinroq boshlaydi)
            let startsAt = Date().timeIntervalSince1970 + 20
            room.info.startsAt = startsAt
            queue.asyncAfter(deadline: .now() + 20) { [weak self, weak room] in
                guard let self, let room, room.info.phase == .lobby else { return }
                self.startGame(room)
            }
        }
        broadcast(.room(room.info))
    }

    private func leave(peerID: String, roomID: String) {
        guard let room = rooms[roomID], let index = room.info.players.firstIndex(of: peerID) else { return }
        room.info.players.remove(at: index)
        room.info.teams?.removeValue(forKey: peerID)
        room.logic?.playerLeft(peerID)
        if room.info.players.isEmpty || (room.info.phase == .lobby && room.info.players.count < 2 && room.invited.isEmpty) {
            close(room)
            return
        }
        if room.info.hostID == peerID, let newHost = room.info.players.first {
            room.info.hostID = newHost
        }
        broadcast(.room(room.info))
    }

    private func removeFromRooms(_ peerID: String) {
        for room in rooms.values where room.info.players.contains(peerID) {
            leave(peerID: peerID, roomID: room.info.id)
        }
        for room in rooms.values { room.invited.remove(peerID) }
    }

    private func scheduleLobbyTimeout(_ room: Room) {
        // Hech kim qo‘shilmasa — 60 soniyadan keyin xona yopiladi
        queue.asyncAfter(deadline: .now() + 60) { [weak self, weak room] in
            guard let self, let room, room.info.phase == .lobby, room.info.players.count < 2 else { return }
            self.close(room)
        }
    }

    private func startGame(_ room: Room) {
        guard room.info.phase == .lobby, room.info.players.count >= room.info.game.minPlayers else { return }
        if room.info.game.isTeamGame { balanceTeams(room) }
        if let mode = room.info.game.chessMode {
            // Shaxmat: partiya alohida yashaydi, xona darhol yopiladi
            let assignment = teams(of: room)
            let white = room.info.players.filter { assignment[$0] == TeamSide.blue }
            let black = room.info.players.filter { assignment[$0] == TeamSide.red }
            chess.create(mode: mode, white: white, black: black)
            close(room)
            return
        }
        room.info.phase = .playing
        room.info.startsAt = nil
        broadcast(.room(room.info))
        let roomID = room.info.id
        let emit: (GameEvent) -> Void = { [weak self] event in
            self?.sendToRoom(roomID, .game(roomID: roomID, event: event))
        }
        let finish: () -> Void = { [weak self, weak room] in
            guard let self, let room else { return }
            room.info.phase = .finished
            self.broadcast(.room(room.info))
            self.queue.asyncAfter(deadline: .now() + 6) { [weak self, weak room] in
                guard let self, let room else { return }
                self.close(room)
            }
        }
        switch room.info.game {
        case .hotBall:
            room.logic = HotBallGame(players: room.info.players, queue: queue, emit: emit, finish: finish)
        case .marksman:
            room.logic = MarksmanGame(players: room.info.players, queue: queue, emit: emit, finish: finish)
        case .volleyball:
            room.logic = VolleyballGame(teams: teams(of: room), queue: queue, emit: emit, finish: finish)
        case .tennis:
            room.logic = TennisGame(teams: teams(of: room), queue: queue, emit: emit, finish: finish)
        case .penalty:
            room.logic = PenaltyGame(teams: teams(of: room), queue: queue, emit: emit, finish: finish)
        case .basketball:
            room.logic = BasketballGame(teams: teams(of: room), queue: queue, emit: emit, finish: finish)
        case .tugOfWar:
            room.logic = TugOfWarGame(teams: teams(of: room), queue: queue, emit: emit, finish: finish)
        case .chessBlitz, .chessDaily, .chessTeam:
            return   // yuqorida ChessManager'ga topshirilgan
        }
        Log.info("O‘yin boshlandi: \(room.info.game.title), \(room.info.players.count) kishi")
        room.logic?.start()
    }

    private func teams(of room: Room) -> [String: Int] {
        var result: [String: Int] = [:]
        for id in room.info.players {
            result[id] = room.info.team(of: id)
        }
        return result
    }

    /// Ikkala jamoada ham kamida bitta odam bo‘lsin.
    private func balanceTeams(_ room: Room) {
        var teams = room.info.teams ?? [:]
        for id in room.info.players where teams[id] == nil { teams[id] = TeamSide.blue }
        let blues = room.info.players.filter { teams[$0] == TeamSide.blue }
        let reds = room.info.players.filter { teams[$0] == TeamSide.red }
        if reds.isEmpty, let last = blues.last, blues.count > 1 {
            teams[last] = TeamSide.red
        } else if blues.isEmpty, let last = reds.last, reds.count > 1 {
            teams[last] = TeamSide.blue
        }
        room.info.teams = teams
    }

    private func switchTeam(peerID: String, roomID: String) {
        guard let room = rooms[roomID], room.info.phase == .lobby, room.info.game.isTeamGame,
              room.info.players.contains(peerID) else { return }
        var teams = room.info.teams ?? [:]
        let current = teams[peerID] ?? TeamSide.blue
        teams[peerID] = current == TeamSide.blue ? TeamSide.red : TeamSide.blue
        room.info.teams = teams
        broadcast(.room(room.info))
    }

    /// Javon yangi versiyani sezdi (hub navbatida chaqiriladi) — hammaga aytamiz.
    func updateRelease(_ newRelease: AppRelease?) {
        let changed = newRelease != release
        release = newRelease
        guard changed, let newRelease else { return }
        broadcast(.latestApp(newRelease))
        Log.info("Yangi versiya e’lon qilindi: HomeView \(newRelease.version) (build \(newRelease.build))")
    }

    private func close(_ room: Room) {
        guard rooms.removeValue(forKey: room.info.id) != nil else { return }
        room.logic?.stop()
        room.logic = nil
        broadcast(.roomClosed(roomID: room.info.id))
    }
}

/// O‘yin xonasi.
final class Room {
    var info: RoomInfo
    var invited: Set<String> = []
    var logic: GameLogic?

    init(info: RoomInfo) {
        self.info = info
    }
}
