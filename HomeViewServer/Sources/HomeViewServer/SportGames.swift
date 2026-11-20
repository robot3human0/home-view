import Foundation
import HomeViewProtocol

// MARK: - Jamoaviy o‘yinlar uchun umumiy asos

/// Ko‘klar va qizillar jamoasi, hisob, server "soati" (fizika uchun) va o‘yin tugashi.
class TeamGame: GameLogic {
    let queue: DispatchQueue
    let emit: (GameEvent) -> Void
    private let finishCallback: () -> Void
    var teams: [String: Int]
    var blueScore = 0
    var redScore = 0
    var running = false
    private var timer: DispatchSourceTimer?

    init(teams: [String: Int], queue: DispatchQueue, emit: @escaping (GameEvent) -> Void, finish: @escaping () -> Void) {
        self.teams = teams
        self.queue = queue
        self.emit = emit
        self.finishCallback = finish
    }

    func start() { running = true }

    func stop() {
        running = false
        timer?.cancel()
        timer = nil
    }

    func pass(from: String, to: String) {}
    func hit(targetID: Int, by: String) {}
    func move(_ id: String, value: Double) {}
    func action(_ id: String, _ action: SportAction) {}

    func playerLeft(_ id: String) {
        teams.removeValue(forKey: id)
        if running && (members(TeamSide.blue).isEmpty || members(TeamSide.red).isEmpty) {
            end()
        }
    }

    func members(_ team: Int) -> [String] {
        teams.filter { $0.value == team }.map { $0.key }.sorted()
    }

    /// Fizika uchun doimiy qadam (sekundiga hz marta).
    /// .strict — macOS taymerni boshqalari bilan "guruhlab" kechiktirmasin.
    /// Taymer baribir kechiksa, o‘tgan vaqt bir nechta teng qadam bilan quvib yetiladi —
    /// o‘yin sekinlashmaydi va to‘p sakramaydi.
    func startTicking(hz: Double, _ step: @escaping (Double) -> Void) {
        let interval: Double = 1.0 / hz
        let source = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        source.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(1))
        var last = ProcessInfo.processInfo.systemUptime
        var pending: Double = 0
        source.setEventHandler { [weak self] in
            guard let self, self.running else { return }
            let now = ProcessInfo.processInfo.systemUptime
            pending += min(now - last, 0.25)
            last = now
            var steps = 0
            while pending >= interval * 0.999 && steps < 6 && self.running {
                step(interval)
                pending -= interval
                steps += 1
            }
        }
        source.resume()
        timer = source
    }

    /// Server soati — holat xabarlariga yoziladi.
    var clock: Double {
        ProcessInfo.processInfo.systemUptime
    }

    func addPoint(to team: Int, points: Int = 1, text: String) {
        if team == TeamSide.blue {
            blueScore += points
        } else {
            redScore += points
        }
        emit(.sportPoint(team: team, blue: blueScore, red: redScore, text: text))
    }

    func end() {
        guard running else { return }
        running = false
        timer?.cancel()
        timer = nil
        var winner: Int?
        if blueScore > redScore { winner = TeamSide.blue }
        if redScore > blueScore { winner = TeamSide.red }
        emit(.teamFinished(winner: winner, blue: blueScore, red: redScore))
        finishCallback()
    }

    func clampValue(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(max(value, low), high)
    }
}

// MARK: - 🏐 Voleybol

/// Yon tomondan ko‘rinish. O‘yinchi sichqonchaga ergashadi, bosish — sakrash.
/// To‘p o‘yinchiga tegsa o‘zi qaytadi; yerga tushgan tomon ochko beradi. 7 ochkogacha yoki 3 daqiqa.
final class VolleyballGame: TeamGame {
    private struct Player {
        var x: Double
        var y: Double
        var vy: Double
        var targetX: Double
        let team: Int
    }

    private var players: [String: Player] = [:]
    private var ballX: Double = 0.25
    private var ballY: Double = 0.32
    private var ballVX: Double = 0
    private var ballVY: Double = 0
    private var pausedFor: Double = 2
    private var tickCount = 0
    private var timeLeft: Double = 180
    private let netX: Double = 0.5
    private let netHeight: Double = 0.12
    private let bodyRadius: Double = 0.034
    private let ballRadius: Double = 0.02
    private let winningScore = 7

    override init(teams: [String: Int], queue: DispatchQueue, emit: @escaping (GameEvent) -> Void, finish: @escaping () -> Void) {
        super.init(teams: teams, queue: queue, emit: emit, finish: finish)
        for team in [TeamSide.blue, TeamSide.red] {
            let list = members(team)
            for (index, id) in list.enumerated() {
                let fraction: Double = Double(index + 1) / Double(list.count + 1)
                let x: Double = team == TeamSide.blue ? 0.06 + 0.36 * fraction : 0.94 - 0.36 * fraction
                players[id] = Player(x: x, y: 0, vy: 0, targetX: x, team: team)
            }
        }
    }

    override func start() {
        super.start()
        serve(loser: Bool.random() ? TeamSide.blue : TeamSide.red)
        startTicking(hz: 30) { [weak self] dt in self?.step(dt) }
    }

    private func serve(loser: Int) {
        ballX = loser == TeamSide.blue ? 0.25 : 0.75
        ballY = 0.32
        ballVX = 0
        ballVY = 0
        pausedFor = 1.4
    }

    private func range(for team: Int) -> (Double, Double) {
        if team == TeamSide.blue {
            return (bodyRadius, netX - bodyRadius - 0.008)
        }
        return (netX + bodyRadius + 0.008, 1 - bodyRadius)
    }

    private func step(_ dt: Double) {
        tickCount += 1
        timeLeft -= dt
        if timeLeft <= 0 {
            broadcast()
            end()
            return
        }
        movePlayers(dt)
        if pausedFor > 0 {
            pausedFor -= dt
        } else {
            moveBall(dt)
        }
        broadcast()
    }

    private func movePlayers(_ dt: Double) {
        for id in Array(players.keys) {
            guard var player = players[id] else { continue }
            let maxStep: Double = 1.0 * dt
            let dx: Double = player.targetX - player.x
            player.x += clampValue(dx, -maxStep, maxStep)
            let limits = range(for: player.team)
            player.x = clampValue(player.x, limits.0, limits.1)
            if player.y > 0 || player.vy > 0 {
                player.vy -= 3.2 * dt
                player.y += player.vy * dt
                if player.y < 0 {
                    player.y = 0
                    player.vy = 0
                }
            }
            players[id] = player
        }
    }

    private func moveBall(_ dt: Double) {
        ballVY -= 1.25 * dt
        ballX += ballVX * dt
        ballY += ballVY * dt

        if ballX < ballRadius {
            ballX = ballRadius
            ballVX = abs(ballVX)
        }
        if ballX > 1 - ballRadius {
            ballX = 1 - ballRadius
            ballVX = -abs(ballVX)
        }
        let ceiling: Double = Court.height - ballRadius
        if ballY > ceiling {
            ballY = ceiling
            ballVY = -abs(ballVY)
        }

        // To‘r
        let nearNet: Bool = abs(ballX - netX) < ballRadius + 0.005
        if nearNet && ballY < netHeight {
            if ballY > netHeight - 0.015 && ballVY < 0 {
                ballY = netHeight
                ballVY = abs(ballVY) * 0.8
            } else {
                let leftSide: Bool = ballX < netX
                ballVX = leftSide ? -abs(ballVX) : abs(ballVX)
                ballX = leftSide ? netX - ballRadius - 0.006 : netX + ballRadius + 0.006
            }
        }

        for player in players.values {
            collide(with: player)
        }

        if ballY <= ballRadius {
            let scorer: Int = ballX < netX ? TeamSide.red : TeamSide.blue
            addPoint(to: scorer, text: "\(TeamSide.emoji(scorer)) \(TeamSide.name(scorer)) ochko oldi!")
            if blueScore >= winningScore || redScore >= winningScore {
                broadcast()
                end()
            } else {
                serve(loser: scorer == TeamSide.blue ? TeamSide.red : TeamSide.blue)
            }
        }
    }

    private func collide(with player: Player) {
        let centerX: Double = player.x
        let centerY: Double = player.y + bodyRadius
        let dx: Double = ballX - centerX
        let dy: Double = ballY - centerY
        let distance: Double = (dx * dx + dy * dy).squareRoot()
        let minDistance: Double = bodyRadius + ballRadius
        guard distance < minDistance, distance > 0.0001 else { return }
        let nx: Double = dx / distance
        let ny: Double = dy / distance
        let currentSpeed: Double = (ballVX * ballVX + ballVY * ballVY).squareRoot()
        let speed: Double = min(max(1.05, currentSpeed), 1.5)
        ballVX = nx * speed
        ballVY = max(ny * speed, 0.75)
        if player.vy > 0 {
            ballVY += player.vy * 0.3
        }
        ballX = centerX + nx * minDistance
        ballY = centerY + ny * minDistance
    }

    private func broadcast() {
        var bodies: [SportBody] = []
        for (id, player) in players {
            bodies.append(SportBody(id: id, x: player.x, y: player.y))
        }
        let state = SportState(bodies: bodies, ballX: ballX, ballY: ballY, blue: blueScore, red: redScore,
                               rope: 0, timeLeft: max(0, timeLeft), time: clock)
        emit(.sportState(state))
    }

    override func move(_ id: String, value: Double) {
        players[id]?.targetX = clampValue(value, 0, 1)
    }

    override func action(_ id: String, _ action: SportAction) {
        guard case .jump = action, let player = players[id], player.y <= 0.0001 else { return }
        players[id]?.vy = 1.05
    }

    override func playerLeft(_ id: String) {
        players.removeValue(forKey: id)
        super.playerLeft(id)
    }
}

// MARK: - 🏓 Stol tennisi

/// Raketkalar maydonning chap va o‘ng chetida, sichqonchaga ergashib yuqoriga-pastga yuradi.
/// Har zarbada to‘p tezlashadi. O‘tkazib yuborgan jamoa ochko beradi. 7 ochkogacha.
final class TennisGame: TeamGame {
    private struct Paddle {
        var y: Double
        var targetY: Double
        let x: Double
        let team: Int
    }

    private var paddles: [String: Paddle] = [:]
    private var ballX: Double = 0.5
    private var ballY: Double = Court.height / 2
    private var ballVX: Double = 0
    private var ballVY: Double = 0
    private var speed: Double = 0.55
    private var pausedFor: Double = 2
    private var tickCount = 0
    private var timeLeft: Double = 180
    private let paddleHalf: Double = 0.055
    private let ballRadius: Double = 0.012
    private let winningScore = 7

    override init(teams: [String: Int], queue: DispatchQueue, emit: @escaping (GameEvent) -> Void, finish: @escaping () -> Void) {
        super.init(teams: teams, queue: queue, emit: emit, finish: finish)
        for team in [TeamSide.blue, TeamSide.red] {
            for (index, id) in members(team).enumerated() {
                let offset: Double = 0.09 * Double(index % 3)
                let x: Double = team == TeamSide.blue ? 0.05 + offset : 0.95 - offset
                paddles[id] = Paddle(y: Court.height / 2, targetY: Court.height / 2, x: x, team: team)
            }
        }
    }

    override func start() {
        super.start()
        serve(toward: Bool.random() ? TeamSide.blue : TeamSide.red)
        startTicking(hz: 30) { [weak self] dt in self?.step(dt) }
    }

    private func serve(toward team: Int) {
        ballX = 0.5
        ballY = Court.height / 2
        speed = 0.55
        let angle: Double = Double.random(in: -0.35...0.35)
        let direction: Double = team == TeamSide.blue ? -1 : 1
        ballVX = cos(angle) * speed * direction
        ballVY = sin(angle) * speed
        pausedFor = 1.2
    }

    private func step(_ dt: Double) {
        tickCount += 1
        timeLeft -= dt
        if timeLeft <= 0 {
            broadcast()
            end()
            return
        }
        for id in Array(paddles.keys) {
            guard var paddle = paddles[id] else { continue }
            let maxStep: Double = 1.4 * dt
            paddle.y += clampValue(paddle.targetY - paddle.y, -maxStep, maxStep)
            paddles[id] = paddle
        }
        if pausedFor > 0 {
            pausedFor -= dt
        } else {
            moveBall(dt)
        }
        broadcast()
    }

    private func moveBall(_ dt: Double) {
        let previousX: Double = ballX
        ballX += ballVX * dt
        ballY += ballVY * dt
        if ballY < ballRadius {
            ballY = ballRadius
            ballVY = abs(ballVY)
        }
        let top: Double = Court.height - ballRadius
        if ballY > top {
            ballY = top
            ballVY = -abs(ballVY)
        }

        for paddle in paddles.values {
            if returnsBall(paddle, previousX: previousX) { break }
        }

        if ballX < -0.02 {
            point(for: TeamSide.red)
        } else if ballX > 1.02 {
            point(for: TeamSide.blue)
        }
    }

    /// To‘p raketka chizig‘ini kesib o‘tdimi va raketkaga tegdimi?
    private func returnsBall(_ paddle: Paddle, previousX: Double) -> Bool {
        let face: Double = paddle.team == TeamSide.blue ? paddle.x + ballRadius : paddle.x - ballRadius
        let movingToward: Bool = paddle.team == TeamSide.blue ? ballVX < 0 : ballVX > 0
        guard movingToward else { return false }
        let crossed: Bool = paddle.team == TeamSide.blue
            ? (previousX >= face && ballX <= face)
            : (previousX <= face && ballX >= face)
        guard crossed, abs(ballY - paddle.y) <= paddleHalf + ballRadius else { return false }
        let offset: Double = clampValue((ballY - paddle.y) / paddleHalf, -1, 1)
        speed = min(speed * 1.06, 1.35)
        let angle: Double = offset * 0.85
        let direction: Double = paddle.team == TeamSide.blue ? 1 : -1
        ballVX = cos(angle) * speed * direction
        ballVY = sin(angle) * speed
        ballX = face
        return true
    }

    private func point(for scorer: Int) {
        addPoint(to: scorer, text: "\(TeamSide.emoji(scorer)) \(TeamSide.name(scorer)) ochko oldi!")
        if blueScore >= winningScore || redScore >= winningScore {
            broadcast()
            end()
        } else {
            serve(toward: scorer == TeamSide.blue ? TeamSide.red : TeamSide.blue)
        }
    }

    private func broadcast() {
        var bodies: [SportBody] = []
        for (id, paddle) in paddles {
            bodies.append(SportBody(id: id, x: paddle.x, y: paddle.y))
        }
        let state = SportState(bodies: bodies, ballX: ballX, ballY: ballY, blue: blueScore, red: redScore,
                               rope: 0, timeLeft: max(0, timeLeft), time: clock)
        emit(.sportState(state))
    }

    override func move(_ id: String, value: Double) {
        paddles[id]?.targetY = clampValue(value, paddleHalf, Court.height - paddleHalf)
    }

    override func playerLeft(_ id: String) {
        paddles.removeValue(forKey: id)
        super.playerLeft(id)
    }
}

// MARK: - ⚽ Penalti

/// Navbat bilan: bir jamoadan tepuvchi, boshqasidan darvozabon. Ikkalasi bir vaqtda tanlaydi,
/// hakam natijani aytadi. Har jamoaga 5 zarba, teng bo‘lsa — durang bo‘lguncha qo‘shimcha.
final class PenaltyGame: TeamGame {
    private var shooterIndex: [Int] = [0, 0]
    private var keeperIndex: [Int] = [0, 0]
    private var turn = 0
    private var shooter = ""
    private var keeper = ""
    private var aimX: Double?
    private var aimY: Double?
    private var dive: Double?
    private var resolved = true
    private let turnSeconds: Double = 5

    override func start() {
        super.start()
        queue.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.nextTurn() }
    }

    private var shootingTeam: Int { turn % 2 == 0 ? TeamSide.blue : TeamSide.red }

    private func nextTurn() {
        guard running else { return }
        let shootingSide = shootingTeam
        let keepingSide = shootingSide == TeamSide.blue ? TeamSide.red : TeamSide.blue
        let shooters = members(shootingSide)
        let keepers = members(keepingSide)
        guard !shooters.isEmpty, !keepers.isEmpty else {
            end()
            return
        }
        shooter = shooters[shooterIndex[shootingSide] % shooters.count]
        shooterIndex[shootingSide] += 1
        keeper = keepers[keeperIndex[keepingSide] % keepers.count]
        keeperIndex[keepingSide] += 1
        aimX = nil
        aimY = nil
        dive = nil
        resolved = false
        let thisTurn = turn
        emit(.penaltyTurn(shooter: shooter, keeper: keeper, turn: thisTurn + 1, seconds: turnSeconds))
        queue.asyncAfter(deadline: .now() + turnSeconds + 0.2) { [weak self] in
            guard let self, self.turn == thisTurn else { return }
            self.resolve()
        }
    }

    override func action(_ id: String, _ action: SportAction) {
        guard running, !resolved else { return }
        switch action {
        case .aim(let x, let y):
            guard id == shooter, aimX == nil else { return }
            aimX = clampValue(x, 0, 1)
            aimY = clampValue(y, 0, 1)
        case .dive(let x):
            guard id == keeper, dive == nil else { return }
            dive = clampValue(x, 0, 1)
        default:
            return
        }
        if aimX != nil && dive != nil {
            let thisTurn = turn
            queue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.turn == thisTurn else { return }
                self.resolve()
            }
        }
    }

    private func resolve() {
        guard running, !resolved else { return }
        resolved = true
        let finalAimX: Double = aimX ?? Double.random(in: 0.15...0.85)
        let finalAimY: Double = aimY ?? Double.random(in: 0.1...0.7)
        let finalDive: Double = dive ?? 0.5
        var outcome = PenaltyOutcome.goal
        let nearPost: Bool = finalAimX < 0.05 || finalAimX > 0.95 || finalAimY > 0.93
        let keeperReaches: Bool = abs(finalAimX - finalDive) < 0.22 && finalAimY < 0.88
        if nearPost && Bool.random() {
            outcome = .post
        } else if keeperReaches {
            outcome = .saved
        }
        let side = shootingTeam
        if outcome == .goal {
            if side == TeamSide.blue {
                blueScore += 1
            } else {
                redScore += 1
            }
        }
        emit(.penaltyResult(shooter: shooter, keeper: keeper, aimX: finalAimX, aimY: finalAimY, diveX: finalDive,
                            outcome: outcome, blue: blueScore, red: redScore))
        turn += 1
        if isDecided() {
            queue.asyncAfter(deadline: .now() + 3) { [weak self] in self?.end() }
        } else {
            queue.asyncAfter(deadline: .now() + 3.2) { [weak self] in self?.nextTurn() }
        }
    }

    private func isDecided() -> Bool {
        let blueTaken: Int = (turn + 1) / 2
        let redTaken: Int = turn / 2
        if turn < 10 {
            let blueBest: Int = blueScore + (5 - blueTaken)
            let redBest: Int = redScore + (5 - redTaken)
            return blueBest < redScore || redBest < blueScore
        }
        guard turn % 2 == 0 else { return false }
        return blueScore != redScore || turn >= 16
    }
}

// MARK: - 🏀 Basketbol

/// Hamma bir vaqtda otadi: har raundda bittadan zarba. Savat har raundda uzoqroq va balandroq.
/// To‘p uchishini server ham, ilovalar ham BasketPhysics formulasi bilan bir xil hisoblaydi.
final class BasketballGame: TeamGame {
    private let hoops: [(x: Double, y: Double, points: Int)] = [(0.70, 0.27, 2), (0.79, 0.31, 2), (0.88, 0.35, 3)]
    private var round = 0
    private var spots: [String: Double] = [:]
    private var shot: Set<String> = []
    private var roundOpen = false
    private let roundSeconds: Double = 10

    override init(teams: [String: Int], queue: DispatchQueue, emit: @escaping (GameEvent) -> Void, finish: @escaping () -> Void) {
        super.init(teams: teams, queue: queue, emit: emit, finish: finish)
        let everyone: [String] = members(TeamSide.blue) + members(TeamSide.red)
        let count = max(everyone.count - 1, 1)
        for (index, id) in everyone.enumerated() {
            let fraction: Double = Double(index) / Double(count)
            spots[id] = 0.06 + 0.30 * fraction
        }
    }

    override func start() {
        super.start()
        queue.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.nextRound() }
    }

    private func nextRound() {
        guard running else { return }
        round += 1
        guard round <= hoops.count else {
            end()
            return
        }
        shot = []
        roundOpen = true
        let hoop = hoops[round - 1]
        emit(.basketRound(round: round, hoopX: hoop.x, hoopY: hoop.y, seconds: roundSeconds, spots: spots))
        let thisRound = round
        queue.asyncAfter(deadline: .now() + roundSeconds) { [weak self] in
            guard let self, self.round == thisRound else { return }
            self.closeRound()
        }
    }

    private func closeRound() {
        guard roundOpen else { return }
        roundOpen = false
        queue.asyncAfter(deadline: .now() + 2.8) { [weak self] in self?.nextRound() }
    }

    override func action(_ id: String, _ action: SportAction) {
        guard running, roundOpen, case .shoot(let angle, let power) = action,
              !shot.contains(id), let x0 = spots[id] else { return }
        shot.insert(id)
        let hoop = hoops[round - 1]
        let made: Bool = BasketPhysics.isMade(x0: x0, angle: angle, power: power, hoopX: hoop.x, hoopY: hoop.y)
        let points: Int = made ? hoop.points : 0
        if made {
            if teams[id] == TeamSide.red {
                redScore += points
            } else {
                blueScore += points
            }
        }
        emit(.basketShot(player: id, x0: x0, angle: angle, power: power, made: made, points: points,
                         blue: blueScore, red: redScore))
        if shot.count >= spots.count {
            closeRound()
        }
    }

    override func playerLeft(_ id: String) {
        spots.removeValue(forKey: id)
        super.playerLeft(id)
    }
}

// MARK: - 🪢 Arqon tortish

/// Hamma iloji boricha tez bosadi. Jamoaning o‘rtacha "tortish kuchi" (bir kishiga to‘g‘ri keladigan
/// bosishlar) solishtiriladi — shuning uchun kam odamli jamoa ham yuta oladi. 40 soniya.
final class TugOfWarGame: TeamGame {
    private var rope: Double = 0
    private var effort: [String: Double] = [:]
    private var lastPull: [String: Date] = [:]
    private var countdown: Double = 3
    private var timeLeft: Double = 40

    override func start() {
        super.start()
        startTicking(hz: 20) { [weak self] dt in self?.step(dt) }
    }

    private func force(of team: Int) -> Double {
        let list = members(team)
        guard !list.isEmpty else { return 0 }
        var total: Double = 0
        for id in list {
            total += effort[id] ?? 0
        }
        return total * 2.5 / Double(list.count)
    }

    private func step(_ dt: Double) {
        if countdown > 0 {
            countdown -= dt
            broadcast()
            return
        }
        timeLeft -= dt
        let decay: Double = exp(-2.5 * dt)
        for id in Array(effort.keys) {
            effort[id] = (effort[id] ?? 0) * decay
        }
        let difference: Double = force(of: TeamSide.red) - force(of: TeamSide.blue)
        rope += difference * 0.045 * dt
        rope = clampValue(rope, -1, 1)
        broadcast()
        if rope <= -1 || rope >= 1 || timeLeft <= 0 {
            if rope < 0 { blueScore = 1 }
            if rope > 0 { redScore = 1 }
            end()
        }
    }

    override func action(_ id: String, _ action: SportAction) {
        guard running, countdown <= 0, case .pull = action, teams[id] != nil else { return }
        let now = Date()
        if let last = lastPull[id], now.timeIntervalSince(last) < 0.06 { return }
        lastPull[id] = now
        effort[id, default: 0] += 1
    }

    private func broadcast() {
        let state = SportState(bodies: [], ballX: 0, ballY: 0, blue: blueScore, red: redScore,
                               rope: rope, timeLeft: countdown > 0 ? -countdown : max(0, timeLeft), time: clock)
        emit(.sportState(state))
    }
}
