import Foundation
import HomeViewProtocol

/// Server — hakam. O‘yindagi barcha qarorlar (kim yutdi, kimga tegdi) shu yerda qabul qilinadi,
/// ilovalar faqat natijani ko‘rsatadi. Shuning uchun aldab bo‘lmaydi va hammada bir xil o‘yin bo‘ladi.
protocol GameLogic: AnyObject {
    func start()
    func stop()
    func pass(from: String, to: String)
    func hit(targetID: Int, by: String)
    func playerLeft(_ id: String)
    /// Jonli sport: sichqoncha holati (voleybolda x, tennisda y).
    func move(_ id: String, value: Double)
    /// Sport harakati: sakrash, tortish, nishon, zarba...
    func action(_ id: String, _ action: SportAction)
}

extension GameLogic {
    func move(_ id: String, value: Double) {}
    func action(_ id: String, _ action: SportAction) {}
}

// MARK: - Muz koptok (issiq kartoshka)

final class HotBallGame: GameLogic {
    private var alive: [String]
    private var holder: String = ""
    private var lastPass = Date.distantPast
    private var round = 0
    private var running = false
    private let queue: DispatchQueue
    private let emit: (GameEvent) -> Void
    private let finish: () -> Void

    init(players: [String], queue: DispatchQueue, emit: @escaping (GameEvent) -> Void, finish: @escaping () -> Void) {
        self.alive = players.shuffled()
        self.queue = queue
        self.emit = emit
        self.finish = finish
    }

    func start() {
        running = true
        queue.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.nextRound() }
    }

    func stop() {
        running = false
    }

    private func nextRound() {
        guard running else { return }
        if alive.count <= 1 {
            end()
            return
        }
        round += 1
        holder = alive.randomElement() ?? ""
        emit(.hotBallHolder(holder: holder, alive: alive))
        // Pilik uzunligi hech kimga ma’lum emas — qiziq tomoni shunda
        let fuse = Double.random(in: 7...15)
        let thisRound = round
        queue.asyncAfter(deadline: .now() + fuse) { [weak self] in
            guard let self, self.running, self.round == thisRound else { return }
            self.explode()
        }
    }

    private func explode() {
        let loser = holder
        alive.removeAll { $0 == loser }
        emit(.hotBallExploded(loser: loser, alive: alive))
        queue.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.nextRound() }
    }

    private func end() {
        guard running else { return }
        running = false
        emit(.finished(winner: alive.first, scores: [:]))
        finish()
    }

    func pass(from: String, to: String) {
        guard running, from == holder, to != from, alive.contains(to) else { return }
        guard Date().timeIntervalSince(lastPass) > 0.25 else { return }
        lastPass = Date()
        holder = to
        emit(.hotBallHolder(holder: holder, alive: alive))
    }

    func hit(targetID: Int, by: String) {}

    func playerLeft(_ id: String) {
        guard running else { return }
        alive.removeAll { $0 == id }
        if alive.count <= 1 {
            end()
        } else if holder == id {
            holder = alive.randomElement() ?? ""
            emit(.hotBallHolder(holder: holder, alive: alive))
        }
    }
}

// MARK: - Mergan

final class MarksmanGame: GameLogic {
    private let totalTargets = 15
    private var spawned = 0
    private var active: [Int: Bool] = [:]   // nishon id → hali hech kim urmagan
    private var scores: [String: Int]
    private var running = false
    private let queue: DispatchQueue
    private let emit: (GameEvent) -> Void
    private let finish: () -> Void

    init(players: [String], queue: DispatchQueue, emit: @escaping (GameEvent) -> Void, finish: @escaping () -> Void) {
        var initial: [String: Int] = [:]
        for id in players { initial[id] = 0 }
        self.scores = initial
        self.queue = queue
        self.emit = emit
        self.finish = finish
    }

    func start() {
        running = true
        queue.asyncAfter(deadline: .now() + 3) { [weak self] in self?.spawn() }
    }

    func stop() {
        running = false
    }

    private func spawn() {
        guard running else { return }
        guard spawned < totalTargets else {
            queue.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.end() }
            return
        }
        spawned += 1
        let lifetime = Double.random(in: 1.6...2.4)
        let target = GameTarget(id: spawned, x: Double.random(in: 0.12...0.88), y: Double.random(in: 0.3...0.8), lifetime: lifetime)
        active[target.id] = true
        emit(.target(target))
        let id = target.id
        queue.asyncAfter(deadline: .now() + lifetime) { [weak self] in
            guard let self, self.running, self.active[id] == true else { return }
            self.active[id] = false
            self.emit(.targetMissed(targetID: id))
        }
        queue.asyncAfter(deadline: .now() + Double.random(in: 1.4...2.6)) { [weak self] in self?.spawn() }
    }

    func hit(targetID: Int, by: String) {
        guard running, active[targetID] == true, scores[by] != nil else { return }
        active[targetID] = false
        scores[by, default: 0] += 1
        emit(.targetHit(targetID: targetID, by: by, scores: scores))
    }

    private func end() {
        guard running else { return }
        running = false
        let best = scores.max { $0.value < $1.value }
        let winner = (best?.value ?? 0) > 0 ? best?.key : nil
        emit(.finished(winner: winner, scores: scores))
        finish()
    }

    func pass(from: String, to: String) {}

    func playerLeft(_ id: String) {
        scores.removeValue(forKey: id)
        if scores.count < 2 && running {
            end()
        }
    }
}
