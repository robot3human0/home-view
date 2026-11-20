import Foundation
import HomeViewProtocol

/// Shaxmat hakami. Partiyalar xonalardan alohida yashaydi (kunlik partiya bir necha kun davom etadi),
/// diskka saqlanadi va server qayta ishga tushsa ham yo‘qolmaydi.
/// Hamma ish Hub navbatida bajariladi.
final class ChessManager {
    private struct Record: Codable {
        var id: String
        var mode: ChessMode
        var white: [String]
        var black: [String]
        var position: ChessPosition
        var moves: [ChessMove]
        var sans: [String]
        var keys: [String]
        var whiteTime: Double
        var blackTime: Double
        var turnStartedAt: Double
        var result: ChessResult?
        var drawOffer: ChessColor?
        var votes: [String: ChessMove]
        var voteOrder: [String]
        var updatedAt: Double

        func color(of id: String) -> ChessColor? {
            if white.contains(id) { return .white }
            if black.contains(id) { return .black }
            return nil
        }

        func players(_ color: ChessColor) -> [String] {
            color == .white ? white : black
        }

        var everyone: [String] { white + black }
    }

    private let queue: DispatchQueue
    private let storeURL: URL
    private var games: [String: Record] = [:]
    private var watchers: [String: Set<String>] = [:]
    private var timer: DispatchSourceTimer?

    /// Bitta hamkasbga xabar yuborish.
    var send: (String, ServerMessage) -> Void = { _, _ in }
    /// Hammaga xabar yuborish.
    var broadcast: (ServerMessage) -> Void = { _ in }
    /// Hamkasb hozir ulanganmi.
    var isOnline: (String) -> Bool = { _ in false }
    /// Ism (jurnal uchun).
    var nameOf: (String) -> String = { $0 }

    init(queue: DispatchQueue, storeURL: URL) {
        self.queue = queue
        self.storeURL = storeURL
        load()
    }

    func start() {
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(50))
        source.setEventHandler { [weak self] in
            self?.checkClocks()
        }
        source.resume()
        timer = source
    }

    private var now: Double {
        Date().timeIntervalSince1970
    }

    // MARK: - Partiya boshlash

    func create(mode: ChessMode, white: [String], black: [String]) {
        guard !white.isEmpty, !black.isEmpty else { return }
        let start = ChessPosition.initial
        let record = Record(id: UUID().uuidString, mode: mode, white: white, black: black,
                            position: start, moves: [], sans: [], keys: [start.repetitionKey],
                            whiteTime: mode.clock, blackTime: mode.clock, turnStartedAt: now + startDelay(mode),
                            result: nil, drawOffer: nil, votes: [:], voteOrder: [], updatedAt: now)
        games[record.id] = record
        Log.info("Shaxmat boshlandi (\(mode.title)): \(white.map(nameOf).joined(separator: ", ")) — \(black.map(nameOf).joined(separator: ", "))")
        publish(record)
        save()
        broadcastLive()
    }

    /// Jamoaviyda hamma doskani ochib olguncha bir necha soniya.
    private func startDelay(_ mode: ChessMode) -> Double {
        mode == .team ? 5 : 0
    }

    // MARK: - Ishtirokchi harakatlari

    func move(_ gameID: String, by peer: String, move rawMove: ChessMove) {
        guard var record = games[gameID], record.result == nil,
              let color = record.color(of: peer), color == record.position.turn else { return }
        let move = record.position.normalized(rawMove)
        guard record.position.legalMoves().contains(move) else {
            send(peer, .notice(text: "Bu yurish qoidaga to‘g‘ri kelmaydi"))
            return
        }
        if record.mode == .team {
            guard now >= record.turnStartedAt else { return }
            record.votes[peer] = move
            record.voteOrder.removeAll { $0 == peer }
            record.voteOrder.append(peer)
            games[gameID] = record
            let team = record.players(color).filter(isOnline)
            if !team.isEmpty && team.allSatisfy({ record.votes[$0] != nil }) {
                resolveVotes(gameID)
            } else {
                publish(record)
            }
            return
        }
        play(move, in: &record)
        games[gameID] = record
        finishUpdate(record)
    }

    func resign(_ gameID: String, by peer: String) {
        guard var record = games[gameID], record.result == nil, record.mode != .team,
              let color = record.color(of: peer) else { return }
        record.result = ChessResult(winner: color.opposite, reason: .resignation)
        record.updatedAt = now
        games[gameID] = record
        finishUpdate(record)
    }

    func draw(_ gameID: String, by peer: String) {
        guard var record = games[gameID], record.result == nil, record.mode != .team,
              let color = record.color(of: peer) else { return }
        if record.drawOffer == color.opposite {
            record.result = ChessResult(winner: nil, reason: .agreement)
        } else {
            record.drawOffer = color
        }
        record.updatedAt = now
        games[gameID] = record
        finishUpdate(record)
    }

    func watch(_ gameID: String, by peer: String) {
        guard let record = games[gameID] else {
            send(peer, .notice(text: "Bu partiya allaqachon tugagan"))
            return
        }
        watchers[gameID, default: []].insert(peer)
        send(peer, .chess(state(of: record, for: peer)))
    }

    // MARK: - Ulanish

    func peerConnected(_ peer: String) {
        let recentLimit = now - 6 * 3600
        for record in games.values where record.everyone.contains(peer) {
            if record.result == nil || record.updatedAt > recentLimit {
                send(peer, .chess(state(of: record, for: peer)))
            }
        }
        send(peer, .chessLive(liveSummaries))
    }

    func peerDisconnected(_ peer: String) {
        for gameID in Array(watchers.keys) {
            watchers[gameID]?.remove(peer)
        }
    }

    // MARK: - Yurish

    private func play(_ move: ChessMove, in record: inout Record) {
        let moment = now
        let mover = record.position.turn
        let san = record.position.san(for: move)
        let elapsed = max(0, moment - record.turnStartedAt)
        switch record.mode {
        case .blitz:
            if mover == .white {
                record.whiteTime = max(0, record.whiteTime - elapsed) + record.mode.increment
            } else {
                record.blackTime = max(0, record.blackTime - elapsed) + record.mode.increment
            }
        case .daily, .team:
            record.whiteTime = record.mode.clock
            record.blackTime = record.mode.clock
        }
        record.position = record.position.applying(move)
        record.moves.append(move)
        record.sans.append(san)
        let key = record.position.repetitionKey
        record.keys.append(key)
        record.drawOffer = nil
        record.votes = [:]
        record.voteOrder = []
        record.turnStartedAt = moment
        record.updatedAt = moment
        if let outcome = record.position.evaluate() {
            record.result = outcome
        } else if record.keys.filter({ $0 == key }).count >= 3 {
            record.result = ChessResult(winner: nil, reason: .repetition)
        }
    }

    /// Jamoaviy: eng ko‘p ovoz olgan yurish (teng bo‘lsa — birinchi taklif qilingani).
    /// Hech kim ovoz bermasa — tasodifiy qonuniy yurish (o‘yin to‘xtab qolmasin).
    private func resolveVotes(_ gameID: String) {
        guard var record = games[gameID], record.result == nil else { return }
        var counts: [ChessMove: Int] = [:]
        for move in record.votes.values {
            counts[move, default: 0] += 1
        }
        var chosen: ChessMove?
        var best = 0
        for voter in record.voteOrder {
            guard let move = record.votes[voter], let count = counts[move] else { continue }
            if count > best {
                best = count
                chosen = move
            }
        }
        if chosen == nil {
            chosen = record.position.legalMoves().randomElement()
        }
        guard let move = chosen else { return }
        play(move, in: &record)
        games[gameID] = record
        finishUpdate(record)
    }

    // MARK: - Soatlar (har 0.5 soniyada)

    private func checkClocks() {
        let moment = now
        var changed = false
        for (gameID, record) in games where record.result == nil {
            let side = record.position.turn
            let base: Double = side == .white ? record.whiteTime : record.blackTime
            let left: Double = base - (moment - record.turnStartedAt)
            guard left <= 0 else { continue }
            if record.mode == .team {
                // Navbatdagi jamoadan hech kim ulanmagan bo‘lsa — partiya tark etilgan hisoblanadi
                if record.players(side).filter(isOnline).isEmpty {
                    var updated = record
                    let others = record.players(side.opposite).filter(isOnline)
                    updated.result = ChessResult(winner: others.isEmpty ? nil : side.opposite, reason: .abandoned)
                    updated.updatedAt = moment
                    games[gameID] = updated
                    finishUpdate(updated)
                } else {
                    resolveVotes(gameID)
                }
                continue
            }
            var updated = record
            if side == .white { updated.whiteTime = 0 } else { updated.blackTime = 0 }
            let winner: ChessColor? = record.position.hasMatingMaterial(side.opposite) ? side.opposite : nil
            updated.result = ChessResult(winner: winner, reason: winner == nil ? .insufficientMaterial : .timeout)
            updated.updatedAt = moment
            games[gameID] = updated
            finishUpdate(updated)
        }
        // Tugaganiga 2 kun bo‘lgan partiyalar o‘chiriladi
        let expired = games.values.filter { $0.result != nil && moment - $0.updatedAt > 2 * 86_400 }
        for record in expired {
            games.removeValue(forKey: record.id)
            watchers.removeValue(forKey: record.id)
            changed = true
        }
        if changed { save() }
    }

    // MARK: - Yuborish

    private func finishUpdate(_ record: Record) {
        publish(record)
        save()
        if let result = record.result {
            let outcome = result.winner.map { "\($0.title) yutdi" } ?? "durang"
            Log.info("Shaxmat tugadi (\(record.mode.title)): \(outcome), \(result.reason.title)")
            broadcastLive()
        }
    }

    /// Ishtirokchilar va tomoshabinlarga — har kimga o‘z ko‘rinishi (jamoa ovozlari faqat o‘z jamoasiga).
    private func publish(_ record: Record) {
        var audience = Set(record.everyone)
        audience.formUnion(watchers[record.id] ?? [])
        for peer in audience where isOnline(peer) {
            send(peer, .chess(state(of: record, for: peer)))
        }
    }

    private func state(of record: Record, for viewer: String) -> ChessGameState {
        var visibleVotes: [String: ChessMove] = [:]
        if record.mode == .team, let color = record.color(of: viewer), color == record.position.turn {
            visibleVotes = record.votes
        }
        return ChessGameState(id: record.id, mode: record.mode, white: record.white, black: record.black,
                              position: record.position, moves: record.moves, sans: record.sans,
                              whiteTime: record.whiteTime, blackTime: record.blackTime,
                              turnStartedAt: record.turnStartedAt, result: record.result,
                              drawOffer: record.drawOffer, votes: visibleVotes, updatedAt: record.updatedAt)
    }

    /// Jonli partiyalar (blits va jamoaviy) — odamcha bayroqchasi va "kuzatish" uchun.
    var liveSummaries: [ChessSummary] {
        games.values
            .filter { $0.result == nil && $0.mode != .daily }
            .map { ChessSummary(id: $0.id, mode: $0.mode, white: $0.white, black: $0.black) }
    }

    private func broadcastLive() {
        broadcast(.chessLive(liveSummaries))
    }

    // MARK: - Diskka saqlash

    private func save() {
        let list = Array(games.values)
        guard let data = try? JSONEncoder().encode(list) else { return }
        do {
            try data.write(to: storeURL, options: .atomic)
        } catch {
            Log.info("Shaxmat partiyalarini saqlab bo‘lmadi: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let list = try? JSONDecoder().decode([Record].self, from: data) else { return }
        for record in list {
            games[record.id] = record
        }
        let active = list.filter { $0.result == nil }.count
        Log.info("Shaxmat: \(list.count) ta partiya yuklandi, \(active) tasi davom etmoqda")
    }
}
