import AppKit
import QuartzCore
import HomeViewProtocol

/// Jamoaviy sport o‘yinlari sahnasi (asosiy monitorda).
///
/// Maydon ekran pastida chiziladi va hamma ekranda bir xil nisbatda bo‘ladi: eni 1 birlik, bo‘yi 0.45 birlik.
/// Server — hakam: fizika va hisob o‘sha yerda. Sahna faqat ko‘rsatadi va sichqonchani serverga yuboradi.
/// O‘yin davomida shu monitordagi bosishlar sahnaga tegishli (boshqa monitorlarda ishlashda davom etasiz).
final class SportStage: NetStage {
    private enum PenaltyRole {
        case shooter, keeper, watcher
    }

    let roomID: String
    let game: GameKind
    let playerIDs: [String]
    private weak var world: SnowWorld?
    private let myID: String
    private let teams: [String: Int]
    private let infos: [String: PeerInfo]
    private(set) var isFinished = false

    var capturesAllInput: Bool { !isFinished }

    // Maydon
    private let court: CGRect
    private let arena = containerLayer()
    private let ball = CALayer()
    private var avatars: [String: PeerAvatar] = [:]
    private var lastX: [String: CGFloat] = [:]
    private var paddles: [String: CALayer] = [:]

    // Yuqori panel: e’lon, hisob, chiqish tugmasi
    private let banner = containerLayer()
    private let bannerBackground = CAShapeLayer()
    private let bannerText = CATextLayer()
    private let board = containerLayer()
    private let boardBackground = CAShapeLayer()
    private let boardText = CATextLayer()
    private let leave = containerLayer()
    private let leaveBackground = CAShapeLayer()
    private let leaveText = CATextLayer()
    private var leaveRect = CGRect.zero
    private var lastBoardText = ""

    private var blue = 0
    private var red = 0
    private var timeLeft: Double = 0
    private var lastSent: Double = -10
    private var countdownEnd: CFTimeInterval = 0
    private var countdownText = ""
    private var lastShownSecond = -1

    // Penalti
    private var role = PenaltyRole.watcher
    private var locked = true
    private var goalRect = CGRect.zero
    private var keeperID: String?
    private var shooterID: String?
    private let aimMarker = CAShapeLayer()
    private let goalNet = CAShapeLayer()

    // Basketbol
    private var hoopX: Double = 0.7
    private var hoopY: Double = 0.27
    private var spots: [String: Double] = [:]
    private var canShoot = false
    private var dragStart: CGPoint?
    private let aimDots = CAShapeLayer()
    private let hoopLayer = containerLayer()
    private let heldBall = CALayer()
    private var round = 0

    // Silliq ko‘rsatish: server holatlari qisqa navbatda turadi, ekran sekundiga 60 marta
    // ikki holat orasini to‘ldirib chizadi (tarmoqdagi notekislik ko‘rinmaydi).
    private typealias Frame = (from: SportState, to: SportState, fraction: Double)
    private struct Snapshot {
        let time: Double
        let state: SportState
    }
    private var snapshots: [Snapshot] = []
    private var clockOffset: Double?
    private var renderTimer: Timer?
    private var displayLink: CADisplayLink?
    private let frameDriver = FrameDriver()
    private let renderDelay: Double = 0.075
    private var lastFrame: CFTimeInterval = 0
    private var lastInputSent: CFTimeInterval = 0
    private var lastRenderX: [String: CGFloat] = [:]
    private var stillFor: [String: Double] = [:]
    // O‘z odamcham va raketkam — serverni kutmay, darhol yuradi (mahalliy bashorat)
    private var predictedX: Double?
    private var predictedY: Double = 0
    private var predictedVY: Double = 0
    private var predictedPaddle: Double?

    // Arqon tortish
    private let ropeLayer = containerLayer()
    private var ropeBase: [String: CGFloat] = [:]
    private var pullCount = 0
    private var pullStarted = false

    init(room: RoomInfo, world: SnowWorld, players: [PeerInfo], myID: String) {
        roomID = room.id
        game = room.game
        self.world = world
        self.myID = myID
        playerIDs = players.map { $0.id }
        var teamMap: [String: Int] = [:]
        var infoMap: [String: PeerInfo] = [:]
        for info in players {
            teamMap[info.id] = room.team(of: info.id)
            infoMap[info.id] = info
        }
        teams = teamMap
        infos = infoMap
        court = SportStage.makeCourt(in: world)

        buildChrome(in: world)
        switch game {
        case .volleyball: buildVolleyball(in: world)
        case .tennis: buildTennis(in: world)
        case .penalty: buildPenalty(in: world)
        case .basketball: buildBasketball(in: world)
        case .tugOfWar: buildTug(in: world)
        default: break
        }
        setBanner("\(game.emoji) \(game.title) boshlanmoqda  ·  \(game.rules)")
        updateBoard()
        if game == .volleyball || game == .tennis || game == .tugOfWar {
            frameDriver.onFrame = { [weak self] in
                self?.renderFrame()
            }
            if let view = world.hostView {
                // Monitor qancha tez yangilansa (60 yoki 120 Hz), to‘p shuncha silliq
                let link = view.displayLink(target: frameDriver, selector: #selector(FrameDriver.step(_:)))
                link.add(to: .main, forMode: .common)
                displayLink = link
            } else {
                let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                    self?.renderFrame()
                }
                timer.tolerance = 0
                RunLoop.main.add(timer, forMode: .common)
                renderTimer = timer
            }
        }
    }

    /// Maydon: ekran eniga moslashadi, tepada e’lon va hisob uchun joy qoladi.
    private static func makeCourt(in world: SnowWorld) -> CGRect {
        let ground: CGFloat = world.groundSurface(atX: world.size.width / 2)
        let baseY: CGFloat = max(ground, 24) + 12
        let ratio = CGFloat(Court.height)
        let roomAbove: CGFloat = world.size.height - baseY - 190
        var width: CGFloat = min(world.size.width * 0.78, 1250)
        if width * ratio > roomAbove {
            width = roomAbove / ratio
        }
        width = max(width, 420)
        let x: CGFloat = (world.size.width - width) / 2
        return CGRect(x: x, y: baseY, width: width, height: width * ratio)
    }

    // MARK: - Koordinatalar va yordamchilar

    private func px(_ x: Double) -> CGFloat {
        court.minX + CGFloat(x) * court.width
    }

    private func py(_ y: Double) -> CGFloat {
        court.minY + CGFloat(y) * court.width
    }

    private func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: px(x), y: py(y))
    }

    private func teamColor(_ team: Int) -> UInt32 {
        team == TeamSide.blue ? 0x1E88E5 : 0xE53935
    }

    private func name(_ id: String) -> String {
        id == myID ? "Siz" : (infos[id]?.name ?? "Hamkasb")
    }

    private var myTeam: Int {
        teams[myID] ?? TeamSide.blue
    }

    private func members(_ team: Int) -> [String] {
        playerIDs.filter { teams[$0] == team }.sorted()
    }

    private func shape(_ world: SnowWorld) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.contentsScale = world.scale
        layer.fillColor = nil
        layer.lineCap = .round
        layer.lineJoin = .round
        return layer
    }

    private func linePath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        return path
    }

    /// To‘r katakchalari.
    private func meshPath(_ rect: CGRect, step: CGFloat) -> CGPath {
        let path = CGMutablePath()
        var x: CGFloat = rect.minX
        while x <= rect.maxX + 0.5 {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += step
        }
        var y: CGFloat = rect.minY
        while y <= rect.maxY + 0.5 {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += step
        }
        return path
    }

    private func styleText(_ text: CATextLayer, size: CGFloat, scale: CGFloat) {
        text.font = NSFont.systemFont(ofSize: size, weight: .bold)
        text.fontSize = size
        text.foregroundColor = whiteColor
        text.alignmentMode = .center
        text.truncationMode = .end
        text.contentsScale = scale
    }

    @discardableResult
    private func pill(_ background: CAShapeLayer, _ text: CATextLayer, _ string: String,
                      fontSize: CGFloat, height: CGFloat) -> CGSize {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let measured: CGSize = (string as NSString).size(withAttributes: [.font: font])
        let textWidth: CGFloat = min(ceil(measured.width), court.width + 120)
        let width: CGFloat = textWidth + 32
        let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
        instant {
            background.path = CGPath(roundedRect: rect, cornerWidth: height / 2, cornerHeight: height / 2, transform: nil)
            text.string = string
            text.bounds = CGRect(x: 0, y: 0, width: textWidth + 4, height: ceil(measured.height))
            text.position = .zero
        }
        return CGSize(width: width, height: height)
    }

    private func setBanner(_ text: String, animated: Bool = true) {
        pill(bannerBackground, bannerText, text, fontSize: 15, height: 36)
        if animated { popIn(banner) }
    }

    private func updateBoard() {
        var text = "🔵  \(blue)  :  \(red)  🔴"
        switch game {
        case .tugOfWar:
            text = "🔵 Ko‘klar   ⟵ 🪢 ⟶   Qizillar 🔴"
        case .basketball:
            if round > 0 { text += "   ·   \(round)-raund" }
        default:
            break
        }
        let timed: Bool = game == .volleyball || game == .tennis || game == .tugOfWar
        if timed && timeLeft > 0 {
            let seconds = Int(timeLeft.rounded(.up))
            text += "   ·   " + String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
        guard text != lastBoardText else { return }
        lastBoardText = text
        pill(boardBackground, boardText, text, fontSize: 17, height: 34)
    }

    private func mouseInWorld() -> CGPoint? {
        guard let world else { return nil }
        let mouse = NSEvent.mouseLocation
        let frame = world.screenFrame
        guard frame.contains(mouse) else { return nil }
        return CGPoint(x: mouse.x - frame.minX, y: mouse.y - frame.minY)
    }

    @discardableResult
    private func addAvatar(_ id: String, at spot: CGPoint, height: CGFloat, facing: CGFloat) -> PeerAvatar? {
        guard let world, var info = infos[id] else { return nil }
        info.avatar.vestColor = teamColor(teams[id] ?? TeamSide.blue)
        info.status = .active
        let avatar = PeerAvatar(info: info, at: spot, scale: height / 46, screenScale: world.scale)
        avatar.isStaged = true
        avatar.isMe = id == myID
        avatar.face(facing)
        avatar.attach(to: world.root)
        avatar.setStageDepth(90)
        avatars[id] = avatar
        lastX[id] = spot.x
        return avatar
    }

    private func setupBall(_ image: CGImage?, diameter: CGFloat, at spot: CGPoint, in world: SnowWorld) {
        ball.contents = image
        ball.contentsScale = Art.scale
        ball.contentsGravity = .resize
        ball.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        instant {
            ball.position = spot
            ball.zPosition = 95
            world.root.addSublayer(ball)
        }
    }

    // MARK: - Umumiy bezak

    private func buildChrome(in world: SnowWorld) {
        let backdrop = CAShapeLayer()
        let frame = court.insetBy(dx: -18, dy: -14)
        backdrop.path = CGPath(roundedRect: frame, cornerWidth: 22, cornerHeight: 22, transform: nil)
        backdrop.fillColor = cg(0x0F1B2D, 0.55)
        backdrop.strokeColor = cg(0xFFFFFF, 0.14)
        backdrop.lineWidth = 1
        backdrop.contentsScale = world.scale

        for background in [bannerBackground, boardBackground, leaveBackground] {
            background.fillColor = cg(0x0F1B2D, 0.88)
            background.strokeColor = cg(0xFFFFFF, 0.25)
            background.lineWidth = 1
            background.contentsScale = world.scale
        }
        leaveBackground.fillColor = cg(0x37474F, 0.92)
        styleText(bannerText, size: 15, scale: world.scale)
        styleText(boardText, size: 17, scale: world.scale)
        styleText(leaveText, size: 12, scale: world.scale)

        let top: CGFloat = court.maxY + 14
        let bannerPoint = CGPoint(x: court.midX, y: top + 68)
        let boardPoint = CGPoint(x: court.midX, y: top + 26)
        let leavePoint = CGPoint(x: court.maxX - 44, y: top + 26)
        instant {
            arena.zPosition = 84
            arena.addSublayer(backdrop)
            world.root.addSublayer(arena)
            banner.addSublayer(bannerBackground)
            banner.addSublayer(bannerText)
            board.addSublayer(boardBackground)
            board.addSublayer(boardText)
            leave.addSublayer(leaveBackground)
            leave.addSublayer(leaveText)
            banner.position = bannerPoint
            board.position = boardPoint
            leave.position = leavePoint
            for layer in [banner, board, leave] {
                layer.zPosition = 101
                world.root.addSublayer(layer)
            }
        }
        let size = pill(leaveBackground, leaveText, "✕  Chiqish", fontSize: 12, height: 26)
        leaveRect = CGRect(x: leavePoint.x - size.width / 2, y: leavePoint.y - 13, width: size.width, height: 26)
    }

    // MARK: - 🏐 Voleybol

    private func buildVolleyball(in world: SnowWorld) {
        let width = court.width
        let floor = shape(world)
        floor.path = linePath([point(0, 0), point(1, 0)])
        floor.strokeColor = cg(0xFFFFFF, 0.6)
        floor.lineWidth = 3

        let mesh = shape(world)
        let meshRect = CGRect(x: px(0.488), y: py(0.055), width: width * 0.024, height: width * 0.065)
        mesh.path = meshPath(meshRect, step: max(6, width * 0.006))
        mesh.strokeColor = cg(0xFFFFFF, 0.35)
        mesh.lineWidth = 1

        let net = shape(world)
        let post = CGRect(x: px(0.497), y: py(0), width: width * 0.006, height: width * 0.12)
        net.path = CGPath(rect: post, transform: nil)
        net.fillColor = cg(0xFFFFFF, 0.9)

        let band = shape(world)
        band.path = linePath([CGPoint(x: meshRect.minX, y: meshRect.maxY), CGPoint(x: meshRect.maxX, y: meshRect.maxY)])
        band.strokeColor = whiteColor
        band.lineWidth = 3
        instant {
            for layer in [floor, mesh, net, band] { arena.addSublayer(layer) }
        }
        setupBall(SportArt.volleyball, diameter: width * 0.04, at: point(0.25, 0.32), in: world)
        spinForever(ball, duration: 1.6)

        for team in [TeamSide.blue, TeamSide.red] {
            let ids = members(team)
            for (index, id) in ids.enumerated() {
                let fraction: Double = Double(index + 1) / Double(ids.count + 1)
                let x: Double = team == TeamSide.blue ? 0.06 + 0.36 * fraction : 0.94 - 0.36 * fraction
                let facing: CGFloat = team == TeamSide.blue ? 1 : -1
                addAvatar(id, at: point(x, 0), height: width * 0.068, facing: facing)
            }
        }
    }

    // MARK: - 🏓 Stol tennisi

    private func buildTennis(in world: SnowWorld) {
        let half: Double = Court.height / 2
        let table = shape(world)
        table.path = CGPath(roundedRect: court, cornerWidth: 10, cornerHeight: 10, transform: nil)
        table.fillColor = cg(0x1B5E20, 0.9)
        table.strokeColor = cg(0xFFFFFF, 0.9)
        table.lineWidth = 3

        let middle = shape(world)
        middle.path = linePath([point(0, half), point(1, half)])
        middle.strokeColor = cg(0xFFFFFF, 0.45)
        middle.lineWidth = 1.5

        let net = shape(world)
        net.path = linePath([point(0.5, 0), point(0.5, Court.height)])
        net.strokeColor = cg(0xFFFFFF, 0.85)
        net.lineWidth = 4
        net.lineDashPattern = [6, 4]
        instant {
            for layer in [table, middle, net] { arena.addSublayer(layer) }
        }
        setupBall(SportArt.pingPong, diameter: max(court.width * 0.024, 14), at: point(0.5, half), in: world)

        for team in [TeamSide.blue, TeamSide.red] {
            for (index, id) in members(team).enumerated() {
                let offset: Double = 0.09 * Double(index % 3)
                let x: Double = team == TeamSide.blue ? 0.05 + offset : 0.95 - offset
                paddles[id] = makePaddle(id, team: team, at: point(x, half), in: world)
            }
        }
    }

    private func makePaddle(_ id: String, team: Int, at spot: CGPoint, in world: SnowWorld) -> CALayer {
        let container = containerLayer()
        let half: CGFloat = court.width * 0.055
        let thickness: CGFloat = max(court.width * 0.012, 8)
        let blade = shape(world)
        let bladeRect = CGRect(x: -thickness / 2, y: -half, width: thickness, height: half * 2)
        blade.path = CGPath(roundedRect: bladeRect, cornerWidth: thickness / 2, cornerHeight: thickness / 2, transform: nil)
        blade.fillColor = cg(teamColor(team))
        let mine = id == myID
        blade.strokeColor = mine ? whiteColor : cg(0x0F1B2D, 0.6)
        blade.lineWidth = mine ? 2.5 : 1

        let label = CATextLayer()
        styleText(label, size: 11, scale: world.scale)
        label.string = name(id)
        label.bounds = CGRect(x: 0, y: 0, width: 96, height: 15)
        label.position = CGPoint(x: 0, y: half + 12)
        instant {
            container.addSublayer(blade)
            container.addSublayer(label)
            container.position = spot
            container.zPosition = 92
            world.root.addSublayer(container)
        }
        return container
    }

    // MARK: - ⚽ Penalti

    private func buildPenalty(in world: SnowWorld) {
        let width = court.width
        goalRect = CGRect(x: px(0.28), y: py(0.13), width: width * 0.44, height: width * 0.22)

        let grass = shape(world)
        grass.path = CGPath(rect: CGRect(x: court.minX, y: court.minY, width: width, height: width * 0.13), transform: nil)
        grass.fillColor = cg(0x2E7D32, 0.75)

        let goalLine = shape(world)
        goalLine.path = linePath([CGPoint(x: px(0.05), y: goalRect.minY), CGPoint(x: px(0.95), y: goalRect.minY)])
        goalLine.strokeColor = cg(0xFFFFFF, 0.7)
        goalLine.lineWidth = 2

        goalNet.contentsScale = world.scale
        goalNet.path = meshPath(goalRect, step: max(10, width * 0.014))
        goalNet.strokeColor = cg(0xFFFFFF, 0.28)
        goalNet.lineWidth = 1
        goalNet.fillColor = nil

        let frame = shape(world)
        frame.path = linePath([
            CGPoint(x: goalRect.minX, y: goalRect.minY),
            CGPoint(x: goalRect.minX, y: goalRect.maxY),
            CGPoint(x: goalRect.maxX, y: goalRect.maxY),
            CGPoint(x: goalRect.maxX, y: goalRect.minY)
        ])
        frame.strokeColor = whiteColor
        frame.lineWidth = max(5, width * 0.008)

        let spot = shape(world)
        spot.path = CGPath(ellipseIn: CGRect(x: px(0.5) - 4, y: py(0.02) - 4, width: 8, height: 8), transform: nil)
        spot.fillColor = whiteColor

        aimMarker.contentsScale = world.scale
        aimMarker.isHidden = true
        instant {
            for layer in [grass, goalLine, goalNet, frame, spot] { arena.addSublayer(layer) }
            aimMarker.zPosition = 97
            world.root.addSublayer(aimMarker)
        }
        setupBall(SportArt.football, diameter: width * 0.035, at: point(0.5, 0.025), in: world)

        for id in playerIDs {
            let facing: CGFloat = teams[id] == TeamSide.blue ? 1 : -1
            addAvatar(id, at: benchPoint(id), height: width * 0.075, facing: facing)
        }
    }

    /// Navbati kelmaganlar maydon chetida turadi: ko‘klar chapda, qizillar o‘ngda.
    private func benchPoint(_ id: String) -> CGPoint {
        let team = teams[id] ?? TeamSide.blue
        let index = members(team).firstIndex(of: id) ?? 0
        let step: Double = 0.042
        let x: Double = team == TeamSide.blue ? 0.03 + step * Double(index) : 0.97 - step * Double(index)
        return point(x, 0)
    }

    private func resetPenaltyPositions() {
        let normal: CGFloat = court.width * 0.075 / 46
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.35)
        for (id, avatar) in avatars {
            avatar.resetPose()
            avatar.setScale(normal)
            avatar.move(to: benchPoint(id))
            avatar.face(teams[id] == TeamSide.blue ? 1 : -1)
        }
        CATransaction.commit()
        instant {
            ball.removeAllAnimations()
            ball.transform = CATransform3DIdentity
            ball.position = point(0.5, 0.025)
            ball.opacity = 1
        }
    }

    private func configureAim(for role: PenaltyRole) {
        let path = CGMutablePath()
        switch role {
        case .shooter:
            path.addEllipse(in: CGRect(x: -16, y: -16, width: 32, height: 32))
            path.move(to: CGPoint(x: -24, y: 0))
            path.addLine(to: CGPoint(x: 24, y: 0))
            path.move(to: CGPoint(x: 0, y: -24))
            path.addLine(to: CGPoint(x: 0, y: 24))
            aimMarker.fillColor = nil
        case .keeper:
            let reach: CGFloat = goalRect.width * 0.44
            let height: CGFloat = goalRect.height * 0.9
            path.addRoundedRect(in: CGRect(x: -reach / 2, y: -height / 2, width: reach, height: height),
                                cornerWidth: 14, cornerHeight: 14)
            aimMarker.fillColor = cg(0xFFEB3B, 0.16)
        case .watcher:
            break
        }
        instant {
            aimMarker.path = path
            aimMarker.strokeColor = cg(0xFFEB3B)
            aimMarker.lineWidth = 3
            aimMarker.isHidden = role == .watcher
            aimMarker.position = CGPoint(x: goalRect.midX, y: goalRect.midY)
            aimMarker.removeAllAnimations()
        }
    }

    private func followAim() {
        guard role != .watcher, !locked, let mouse = mouseInWorld() else { return }
        let x: CGFloat = clamp(mouse.x, goalRect.minX, goalRect.maxX)
        let y: CGFloat = role == .shooter ? clamp(mouse.y, goalRect.minY, goalRect.maxY) : goalRect.midY
        instant { aimMarker.position = CGPoint(x: x, y: y) }
    }

    private func penaltyClick(at clickPoint: CGPoint) {
        guard role != .watcher, !locked else { return }
        let x: CGFloat = clamp(clickPoint.x, goalRect.minX, goalRect.maxX)
        let y: CGFloat = clamp(clickPoint.y, goalRect.minY, goalRect.maxY)
        let relativeX = Double((x - goalRect.minX) / goalRect.width)
        let relativeY = Double((y - goalRect.minY) / goalRect.height)
        locked = true
        if role == .shooter {
            Office.shared.sportAction(roomID: roomID, action: .aim(x: relativeX, y: relativeY))
            instant { aimMarker.position = CGPoint(x: x, y: y) }
            countdownText = "⚽ Nishon tanlandi — darvozabonni kutamiz"
        } else {
            Office.shared.sportAction(roomID: roomID, action: .dive(x: relativeX))
            instant { aimMarker.position = CGPoint(x: x, y: goalRect.midY) }
            countdownText = "🧤 Tayyor — zarbani kutamiz"
        }
        instant { aimMarker.strokeColor = cg(0x66BB6A) }
        lastShownSecond = -1
    }

    private func penaltyTurn(shooter: String, keeper: String, seconds: Double) {
        resetPenaltyPositions()
        shooterID = shooter
        keeperID = keeper
        let keeperScale: CGFloat = goalRect.height * 0.58 / 46
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.45)
        if let avatar = avatars[shooter] {
            avatar.move(to: point(0.45, 0))
            avatar.face(1)
        }
        if let avatar = avatars[keeper] {
            avatar.setScale(keeperScale)
            avatar.move(to: CGPoint(x: goalRect.midX, y: goalRect.minY))
        }
        CATransaction.commit()

        if shooter == myID {
            role = .shooter
            countdownText = "⚽ Siz tepasiz! Darvozaning bir joyini bosing"
        } else if keeper == myID {
            role = .keeper
            countdownText = "🧤 Siz darvozabonsiz! Qayerga sakrashni bosing"
        } else {
            role = .watcher
            countdownText = "⚽ \(name(shooter)) tepadi  ·  🧤 \(name(keeper)) darvozada"
        }
        locked = role == .watcher
        configureAim(for: role)
        countdownEnd = CACurrentMediaTime() + seconds
        lastShownSecond = -1
        setBanner(countdownText)
    }

    private func penaltyResult(shooter: String, keeper: String, aimX: Double, aimY: Double, diveX: Double,
                               outcome: PenaltyOutcome) {
        guard let world else { return }
        role = .watcher
        locked = true
        countdownEnd = 0
        instant { aimMarker.isHidden = true }

        let target = CGPoint(x: goalRect.minX + CGFloat(aimX) * goalRect.width,
                             y: goalRect.minY + CGFloat(aimY) * goalRect.height)
        let diveSpot = CGPoint(x: goalRect.minX + CGFloat(diveX) * goalRect.width, y: goalRect.minY)
        avatars[shooter]?.kick()

        // Darvozabon sakraydi
        if let avatar = avatars[keeper] {
            let direction: CGFloat = diveX < 0.5 ? -1 : 1
            let lifted = CGPoint(x: diveSpot.x, y: diveSpot.y + goalRect.height * 0.12)
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.32)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            avatar.move(to: lifted)
            avatar.dive(direction)
            CATransaction.commit()
        }

        // To‘p uchadi
        let start = ball.position
        var path: [CGPoint] = [start]
        let reboundY: CGFloat = goalRect.minY - court.width * 0.05
        switch outcome {
        case .goal:
            path.append(target)
            path.append(CGPoint(x: target.x, y: max(target.y - 12, goalRect.minY + 6)))
        case .saved:
            let glove = CGPoint(x: diveSpot.x, y: min(target.y, goalRect.maxY - 10))
            path.append(glove)
            path.append(CGPoint(x: glove.x + CGFloat.random(in: -60...60), y: reboundY))
        case .post:
            let postX: CGFloat = aimX < 0.5 ? goalRect.minX : goalRect.maxX
            let postPoint = CGPoint(x: postX, y: target.y)
            let outward: CGFloat = aimX < 0.5 ? -1 : 1
            path.append(postPoint)
            path.append(CGPoint(x: postX + outward * court.width * 0.07, y: reboundY))
        }
        let values: [NSValue] = path.map { NSValue(point: $0) }
        let final = path.last ?? start
        instant {
            ball.position = final
            ball.transform = CATransform3DMakeScale(0.7, 0.7, 1)
        }
        let flight = CAKeyframeAnimation(keyPath: "position")
        flight.values = values
        flight.keyTimes = [0, 0.55, 1]
        flight.duration = 0.75
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1
        shrink.toValue = 0.7
        shrink.duration = 0.4
        ball.add(flight, forKey: "flight")
        ball.add(shrink, forKey: "shrink")

        after(0.45) { [weak self] in
            guard let self else { return }
            switch outcome {
            case .goal:
                self.setBanner("⚽ GOOOL!  \(self.name(shooter))")
                world.confetti(at: target)
                let shake = CAKeyframeAnimation(keyPath: "transform.translation.y")
                shake.values = [0, -5, 3, -2, 0]
                shake.duration = 0.4
                self.goalNet.add(shake, forKey: "shake")
            case .saved:
                self.setBanner("🧤 \(self.name(keeper)) qaytardi!")
            case .post:
                self.setBanner("🥅 Ustunga tegdi!")
            }
            self.updateBoard()
        }
    }

    // MARK: - 🏀 Basketbol

    private func buildBasketball(in world: SnowWorld) {
        let width = court.width
        let floor = shape(world)
        floor.path = linePath([point(0, 0), point(1, 0)])
        floor.strokeColor = cg(0xFFFFFF, 0.6)
        floor.lineWidth = 3

        aimDots.contentsScale = world.scale
        aimDots.fillColor = cg(0xFFFFFF, 0.85)
        heldBall.contents = SportArt.basketball
        heldBall.contentsScale = Art.scale
        heldBall.contentsGravity = .resize
        heldBall.bounds = CGRect(x: 0, y: 0, width: width * 0.03, height: width * 0.03)
        instant {
            arena.addSublayer(floor)
            hoopLayer.zPosition = 93
            aimDots.zPosition = 97
            heldBall.zPosition = 96
            heldBall.isHidden = true
            world.root.addSublayer(hoopLayer)
            world.root.addSublayer(aimDots)
            world.root.addSublayer(heldBall)
        }
        drawHoop()

        let everyone: [String] = members(TeamSide.blue) + members(TeamSide.red)
        let count = max(everyone.count - 1, 1)
        for (index, id) in everyone.enumerated() {
            let x: Double = 0.06 + 0.30 * Double(index) / Double(count)
            spots[id] = x
            addAvatar(id, at: point(x, 0), height: width * 0.075, facing: 1)
        }
    }

    private func drawHoop() {
        guard let world else { return }
        let width = court.width
        let poleX: Double = hoopX + 0.065
        let armY: Double = hoopY + 0.05

        let pole = shape(world)
        pole.path = linePath([point(poleX, 0), point(poleX, armY), point(hoopX + 0.036, armY)])
        pole.strokeColor = cg(0x90A4AE)
        pole.lineWidth = max(5, width * 0.007)

        let backboard = shape(world)
        let boardRect = CGRect(x: px(hoopX + 0.03), y: py(hoopY - 0.015), width: width * 0.007, height: width * 0.09)
        backboard.path = CGPath(rect: boardRect, transform: nil)
        backboard.fillColor = cg(0xFFFFFF, 0.95)
        backboard.strokeColor = cg(0x37474F)
        backboard.lineWidth = 1

        let net = shape(world)
        let netPath = CGMutablePath()
        let topLeft = point(hoopX - 0.03, hoopY)
        let topRight = point(hoopX + 0.03, hoopY)
        let bottomLeft = point(hoopX - 0.018, hoopY - 0.045)
        let bottomRight = point(hoopX + 0.018, hoopY - 0.045)
        netPath.addLines(between: [topLeft, bottomLeft, bottomRight, topRight])
        netPath.move(to: topLeft)
        netPath.addLine(to: bottomRight)
        netPath.move(to: topRight)
        netPath.addLine(to: bottomLeft)
        net.path = netPath
        net.strokeColor = cg(0xFFFFFF, 0.85)
        net.lineWidth = 1.5

        let rim = shape(world)
        rim.path = linePath([topLeft, topRight])
        rim.strokeColor = cg(0xFF6D00)
        rim.lineWidth = max(4, width * 0.006)

        instant {
            hoopLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
            for layer in [pole, backboard, net, rim] { hoopLayer.addSublayer(layer) }
        }
    }

    private func basketRound(number: Int, hoopX newX: Double, hoopY newY: Double, seconds: Double, spots newSpots: [String: Double]) {
        round = number
        hoopX = newX
        hoopY = newY
        spots = newSpots
        drawHoop()
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.4)
        for (id, x) in newSpots {
            avatars[id]?.move(to: point(x, 0))
        }
        CATransaction.commit()

        let points = number >= 3 ? 3 : 2
        if let mySpot = newSpots[myID] {
            canShoot = true
            instant {
                heldBall.position = point(mySpot, BasketPhysics.startY)
                heldBall.isHidden = false
            }
            popIn(heldBall)
            countdownText = "🏀 \(number)-raund (\(points) ochko) · Sichqonchani bosib orqaga torting va qo‘yib yuboring"
        } else {
            canShoot = false
            countdownText = "🏀 \(number)-raund (\(points) ochko)"
        }
        countdownEnd = CACurrentMediaTime() + seconds
        lastShownSecond = -1
        setBanner(countdownText)
        updateBoard()
    }

    private func shotParameters(from start: CGPoint, to current: CGPoint) -> (angle: Double, power: Double, length: CGFloat) {
        let dx: CGFloat = start.x - current.x
        let dy: CGFloat = start.y - current.y
        let length: CGFloat = (dx * dx + dy * dy).squareRoot()
        let angle = Double(atan2(dy, dx))
        let power = Double(min(length / (court.width * 0.32), 1))
        return (angle, power, length)
    }

    private func showAim(angle: Double, power: Double) {
        guard let x0 = spots[myID] else { return }
        let path = CGMutablePath()
        for index in 1...9 {
            let t: Double = Double(index) * 0.05
            let spot = BasketPhysics.point(x0: x0, angle: angle, power: power, t: t)
            let center = point(spot.x, spot.y)
            let radius: CGFloat = 3.5 - CGFloat(index) * 0.2
            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
        instant { aimDots.path = path }
    }

    private func animateShot(player: String, x0: Double, angle: Double, power: Double, made: Bool, points: Int) {
        guard let world else { return }
        let flightTime: Double = BasketPhysics.flightTime(x0: x0, angle: angle, power: power, hoopX: hoopX, made: made)
        var values: [NSValue] = []
        let steps = 28
        for index in 0...steps {
            let t: Double = flightTime * Double(index) / Double(steps)
            let spot = BasketPhysics.point(x0: x0, angle: angle, power: power, t: t)
            values.append(NSValue(point: point(spot.x, max(spot.y, 0.012))))
        }
        if made {
            values.append(NSValue(point: point(hoopX, hoopY - 0.07)))
        }
        let layer = CALayer()
        layer.contents = SportArt.basketball
        layer.contentsScale = Art.scale
        layer.contentsGravity = .resize
        let diameter: CGFloat = court.width * 0.03
        layer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        let final = values.last?.pointValue ?? .zero
        instant {
            layer.position = final
            layer.zPosition = 92
            world.root.addSublayer(layer)
        }
        let flight = CAKeyframeAnimation(keyPath: "position")
        flight.values = values
        flight.calculationMode = .linear
        flight.duration = flightTime + (made ? 0.25 : 0)
        layer.add(flight, forKey: "flight")
        spinForever(layer, duration: 0.7)

        let rimPoint = point(hoopX, hoopY + 0.03)
        let label: String = made ? "+\(points)  \(name(player))" : "✗ \(name(player))"
        after(flight.duration) { [weak self] in
            if made {
                world.showFloatText(label, at: rimPoint)
                world.burstSnow(at: rimPoint, count: 10)
            } else {
                world.showFloatText(label, at: final)
            }
            self?.updateBoard()
            layer.opacity = 0
            after(0.5) { layer.removeFromSuperlayer() }
        }
    }

    // MARK: - 🪢 Arqon tortish

    private func buildTug(in world: SnowWorld) {
        let width = court.width
        let ropeY: Double = 0.045
        let floor = shape(world)
        floor.path = linePath([point(0, 0), point(1, 0)])
        floor.strokeColor = cg(0xFFFFFF, 0.6)
        floor.lineWidth = 3

        let center = shape(world)
        center.path = linePath([point(0.5, 0), point(0.5, 0.03)])
        center.strokeColor = whiteColor
        center.lineWidth = 3

        let blueMark = shape(world)
        blueMark.path = linePath([point(0.32, 0), point(0.32, 0.1)])
        blueMark.strokeColor = cg(teamColor(TeamSide.blue))
        blueMark.lineWidth = 3
        blueMark.lineDashPattern = [6, 5]

        let redMark = shape(world)
        redMark.path = linePath([point(0.68, 0), point(0.68, 0.1)])
        redMark.strokeColor = cg(teamColor(TeamSide.red))
        redMark.lineWidth = 3
        redMark.lineDashPattern = [6, 5]

        let ropeBaseLayer = shape(world)
        ropeBaseLayer.path = linePath([point(0.03, ropeY), point(0.97, ropeY)])
        ropeBaseLayer.strokeColor = cg(0x6D4C41)
        ropeBaseLayer.lineWidth = max(6, width * 0.008)

        let ropeTwist = shape(world)
        ropeTwist.path = ropeBaseLayer.path
        ropeTwist.strokeColor = cg(0xBCAAA4)
        ropeTwist.lineWidth = max(2, width * 0.003)
        ropeTwist.lineDashPattern = [8, 6]

        let flag = shape(world)
        let flagTop = point(0.5, ropeY)
        let flagPath = CGMutablePath()
        flagPath.addLines(between: [
            flagTop,
            CGPoint(x: flagTop.x - 9, y: flagTop.y - 26),
            CGPoint(x: flagTop.x + 9, y: flagTop.y - 26)
        ])
        flagPath.closeSubpath()
        flag.path = flagPath
        flag.fillColor = cg(0xFFEB3B)
        flag.strokeColor = cg(0x0F1B2D, 0.6)
        flag.lineWidth = 1

        instant {
            for layer in [floor, center, blueMark, redMark] { arena.addSublayer(layer) }
            ropeLayer.zPosition = 91
            for layer in [ropeBaseLayer, ropeTwist, flag] { ropeLayer.addSublayer(layer) }
            world.root.addSublayer(ropeLayer)
        }

        for team in [TeamSide.blue, TeamSide.red] {
            for (index, id) in members(team).enumerated() {
                let offset: Double = 0.05 * Double(index)
                let x: Double = team == TeamSide.blue ? 0.44 - offset : 0.56 + offset
                let spot = point(x, 0)
                let facing: CGFloat = team == TeamSide.blue ? 1 : -1
                if let avatar = addAvatar(id, at: spot, height: width * 0.075, facing: facing) {
                    avatar.lean(0.3)
                    avatar.holdRope()
                }
                ropeBase[id] = spot.x
            }
        }
    }

    private func applyRope(_ value: Double) {
        let offset: CGFloat = CGFloat(value) * 0.18 * court.width
        ropeLayer.position = CGPoint(x: offset, y: 0)
        for (id, baseX) in ropeBase {
            guard let avatar = avatars[id] else { continue }
            avatar.move(to: CGPoint(x: baseX + offset, y: avatar.position.y))
        }
    }

    private func tugCountdown(_ value: Double) {
        if value < 0 {
            let seconds = Int((-value).rounded(.up))
            if seconds != lastShownSecond {
                lastShownSecond = seconds
                setBanner("🪢 Tayyorlaning… \(seconds)")
            }
        } else if !pullStarted {
            pullStarted = true
            setBanner("🪢 BOSING! Qancha tez bossangiz — shuncha kuchli tortasiz")
            for avatar in avatars.values { avatar.setRunning(true) }
        }
    }

    private func pull(at clickPoint: CGPoint) {
        guard pullStarted, let world else { return }
        Office.shared.sportAction(roomID: roomID, action: .pull)
        pullCount += 1
        if pullCount % 6 == 0 {
            world.showFloatText("💪", at: clickPoint)
        }
    }

    // MARK: - Server voqealari

    func handle(_ event: GameEvent) {
        guard let world else { return }
        switch event {
        case .sportState(let state):
            applyState(state)

        case .sportPoint(let team, let blueScore, let redScore, let text):
            blue = blueScore
            red = redScore
            setBanner(text)
            updateBoard()
            world.burstSnow(at: ball.position, count: 16)
            for (id, avatar) in avatars where teams[id] == team {
                avatar.hop()
            }

        case .penaltyTurn(let shooter, let keeper, _, let seconds):
            penaltyTurn(shooter: shooter, keeper: keeper, seconds: seconds)

        case .penaltyResult(let shooter, let keeper, let aimX, let aimY, let diveX, let outcome, let blueScore, let redScore):
            blue = blueScore
            red = redScore
            penaltyResult(shooter: shooter, keeper: keeper, aimX: aimX, aimY: aimY, diveX: diveX, outcome: outcome)

        case .basketRound(let number, let x, let y, let seconds, let newSpots):
            basketRound(number: number, hoopX: x, hoopY: y, seconds: seconds, spots: newSpots)

        case .basketShot(let player, let x0, let angle, let power, let made, let points, let blueScore, let redScore):
            blue = blueScore
            red = redScore
            if player != myID { avatars[player]?.throwMotion() }
            animateShot(player: player, x0: x0, angle: angle, power: power, made: made, points: points)

        case .teamFinished(let winner, let blueScore, let redScore):
            finish(winner: winner, blueScore: blueScore, redScore: redScore)

        default:
            break
        }
    }

    private func applyState(_ state: SportState) {
        blue = state.blue
        red = state.red
        timeLeft = state.timeLeft
        let now = CACurrentMediaTime()
        let serverTime: Double = state.time ?? now
        let sample: Double = now - serverTime
        // Server va bu Mac soatlari orasidagi farq: eng tez kelgan xabarga tayanamiz, sekin moslashamiz
        if let offset = clockOffset {
            clockOffset = sample < offset ? sample : offset + (sample - offset) * 0.02
        } else {
            clockOffset = sample
        }
        snapshots.append(Snapshot(time: serverTime, state: state))
        if snapshots.count > 40 {
            snapshots.removeFirst(snapshots.count - 40)
        }
        if game == .tugOfWar {
            tugCountdown(state.timeLeft)
        }
        updateBoard()
    }

    // MARK: - Silliq chizish (60 Hz)

    private func renderFrame() {
        guard !snapshots.isEmpty, let offset = clockOffset else { return }
        let now = CACurrentMediaTime()
        let dt: Double = lastFrame > 0 ? min(now - lastFrame, 0.1) : 1.0 / 60
        lastFrame = now
        let frame = bracket(now - offset - renderDelay)
        sendInput(now: now)
        instant {
            switch game {
            case .volleyball: renderVolleyball(frame, dt: dt)
            case .tennis: renderTennis(frame, dt: dt)
            case .tugOfWar: applyRope(mix(frame.from.rope, frame.to.rope, frame.fraction))
            default: break
            }
        }
    }

    /// Ko‘rsatish vaqtini o‘rab turgan ikki holat va ular orasidagi ulush (0...1).
    private func bracket(_ time: Double) -> Frame {
        let last = snapshots[snapshots.count - 1]
        if time >= last.time {
            return (last.state, last.state, 0)
        }
        var index = snapshots.count - 1
        while index > 0 && snapshots[index - 1].time > time {
            index -= 1
        }
        if index == 0 {
            return (snapshots[0].state, snapshots[0].state, 0)
        }
        let older = snapshots[index - 1]
        let newer = snapshots[index]
        let span: Double = newer.time - older.time
        let fraction: Double = span > 0.0001 ? (time - older.time) / span : 1
        return (older.state, newer.state, min(max(fraction, 0), 1))
    }

    private func mix(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    private func body(_ id: String, in state: SportState) -> SportBody? {
        state.bodies.first { $0.id == id }
    }

    /// To‘p sakrab ketgan bo‘lsa (yangi xizmat) — oraliqni to‘ldirmaymiz, darhol yangi joy.
    private func ballPoint(_ frame: Frame) -> CGPoint {
        let distance: Double = abs(frame.to.ballX - frame.from.ballX) + abs(frame.to.ballY - frame.from.ballY)
        if distance > 0.3 {
            return point(frame.to.ballX, frame.to.ballY)
        }
        let x: Double = mix(frame.from.ballX, frame.to.ballX, frame.fraction)
        let y: Double = mix(frame.from.ballY, frame.to.ballY, frame.fraction)
        return point(x, y)
    }

    private func renderVolleyball(_ frame: Frame, dt: Double) {
        ball.position = ballPoint(frame)
        for target in frame.to.bodies {
            guard let avatar = avatars[target.id] else { continue }
            let start = body(target.id, in: frame.from) ?? target
            var x: Double = mix(start.x, target.x, frame.fraction)
            var y: Double = mix(start.y, target.y, frame.fraction)
            if target.id == myID {
                let predicted = predictSelf(serverX: x, dt: dt)
                x = predicted.x
                y = predicted.y
            }
            let spot = point(x, y)
            updateRunning(target.id, avatar: avatar, x: spot.x, onGround: y < 0.001, dt: dt)
            avatar.move(to: spot)
        }
    }

    private func renderTennis(_ frame: Frame, dt: Double) {
        ball.position = ballPoint(frame)
        for target in frame.to.bodies {
            guard let paddle = paddles[target.id] else { continue }
            let start = body(target.id, in: frame.from) ?? target
            var y: Double = mix(start.y, target.y, frame.fraction)
            if target.id == myID {
                y = predictPaddle(serverY: y, dt: dt)
            }
            paddle.position = point(target.x, y)
        }
    }

    /// Voleybolda o‘z odamcham: sichqonchaga server bilan bir xil tezlikda yuguradi va sakraydi.
    private func predictSelf(serverX: Double, dt: Double) -> (x: Double, y: Double) {
        let isBlue: Bool = (teams[myID] ?? TeamSide.blue) == TeamSide.blue
        let low: Double = isBlue ? 0.034 : 0.542
        let high: Double = isBlue ? 0.458 : 0.966
        var x: Double = predictedX ?? serverX
        if let mouse = mouseInWorld() {
            let target = Double((mouse.x - court.minX) / court.width)
            let step: Double = 1.0 * dt
            x += min(max(target - x, -step), step)
        }
        x = min(max(x, low), high)
        if abs(x - serverX) > 0.2 {
            x = serverX
        }
        predictedX = x
        if predictedY > 0 || predictedVY > 0 {
            predictedVY -= 3.2 * dt
            predictedY += predictedVY * dt
            if predictedY < 0 {
                predictedY = 0
                predictedVY = 0
            }
        }
        return (x, predictedY)
    }

    /// Tennisda o‘z raketkam: sichqonchaga server bilan bir xil tezlikda ergashadi.
    private func predictPaddle(serverY: Double, dt: Double) -> Double {
        let half: Double = 0.055
        var y: Double = predictedPaddle ?? serverY
        if let mouse = mouseInWorld() {
            let wanted = Double((mouse.y - court.minY) / court.width)
            let target: Double = min(max(wanted, half), Court.height - half)
            let step: Double = 1.4 * dt
            y += min(max(target - y, -step), step)
        }
        if abs(y - serverY) > 0.2 {
            y = serverY
        }
        predictedPaddle = y
        return y
    }

    private func updateRunning(_ id: String, avatar: PeerAvatar, x: CGFloat, onGround: Bool, dt: Double) {
        let previous: CGFloat = lastRenderX[id] ?? x
        lastRenderX[id] = x
        let speed: CGFloat = abs(x - previous) / CGFloat(max(dt, 0.001))
        if speed > 25 && onGround {
            stillFor[id] = 0
            avatar.setRunning(true)
        } else {
            let still: Double = (stillFor[id] ?? 0) + dt
            stillFor[id] = still
            if still > 0.15 {
                avatar.setRunning(false)
            }
        }
    }

    /// Sichqoncha holatini serverga — sekundiga ko‘pi bilan 30 marta, o‘zgargandagina.
    private func sendInput(now: CFTimeInterval) {
        guard now - lastInputSent >= 1.0 / 30 else { return }
        guard game == .volleyball || game == .tennis, teams[myID] != nil, !isFinished,
              let mouse = mouseInWorld() else { return }
        let value: Double
        if game == .volleyball {
            value = Double((mouse.x - court.minX) / court.width)
        } else {
            value = Double((mouse.y - court.minY) / court.width)
        }
        guard abs(value - lastSent) > 0.002 else { return }
        lastSent = value
        lastInputSent = now
        Office.shared.sportMove(roomID: roomID, value: value)
    }

    private func finish(winner: Int?, blueScore: Int, redScore: Int) {
        guard let world else { return }
        isFinished = true
        blue = blueScore
        red = redScore
        timeLeft = 0
        canShoot = false
        role = .watcher
        countdownEnd = 0
        dragStart = nil
        instant {
            aimMarker.isHidden = true
            aimDots.path = nil
            heldBall.isHidden = true
        }
        renderFrame()
        renderTimer?.invalidate()
        renderTimer = nil
        displayLink?.invalidate()
        displayLink = nil
        for avatar in avatars.values { avatar.setRunning(false) }
        updateBoard()
        guard let winner else {
            setBanner("🤝 Durang!  \(blue) : \(red)")
            return
        }
        let mine: Bool = winner == myTeam && teams[myID] != nil
        let suffix: String = mine ? "  Tabriklaymiz!" : ""
        setBanner("🏆 \(TeamSide.emoji(winner)) \(TeamSide.name(winner)) yutdi!\(suffix)")
        var burstPoints: [CGPoint] = []
        for (id, avatar) in avatars where teams[id] == winner {
            avatar.hop()
            burstPoints.append(CGPoint(x: avatar.position.x, y: avatar.position.y + 50))
        }
        for (id, paddle) in paddles where teams[id] == winner {
            burstPoints.append(paddle.position)
        }
        if burstPoints.isEmpty {
            burstPoints.append(CGPoint(x: court.midX, y: court.midY))
        }
        for burstPoint in burstPoints.prefix(4) {
            world.confetti(at: burstPoint)
        }
    }

    // MARK: - Sichqoncha

    func tick(_ dt: CGFloat) {
        guard !isFinished else { return }
        updateCountdown()
        if game == .penalty { followAim() }
    }

    private func updateCountdown() {
        guard countdownEnd > 0 else { return }
        let left: Double = countdownEnd - CACurrentMediaTime()
        if left <= 0 {
            countdownEnd = 0
            return
        }
        let seconds = Int(left.rounded(.up))
        guard seconds != lastShownSecond else { return }
        lastShownSecond = seconds
        setBanner("\(countdownText)  ·  \(seconds)", animated: false)
    }

    func isInteractive(at point: CGPoint) -> Bool {
        leaveRect.insetBy(dx: -4, dy: -4).contains(point) || !isFinished
    }

    func handleClick(at clickPoint: CGPoint) -> Bool {
        if leaveRect.insetBy(dx: -4, dy: -4).contains(clickPoint) {
            Office.shared.leave(roomID: roomID)
            return true
        }
        guard !isFinished else { return false }
        switch game {
        case .volleyball:
            if predictedY <= 0.0001 {
                predictedVY = 1.05
                predictedY = 0.0001
            }
            Office.shared.sportAction(roomID: roomID, action: .jump)
        case .tugOfWar:
            pull(at: clickPoint)
        case .penalty:
            penaltyClick(at: clickPoint)
        case .basketball:
            if canShoot { dragStart = clickPoint }
        default:
            break
        }
        return true
    }

    func handleDrag(at dragPoint: CGPoint) {
        guard game == .basketball, canShoot, let start = dragStart else { return }
        let shot = shotParameters(from: start, to: dragPoint)
        if shot.length < 8 {
            instant { aimDots.path = nil }
            return
        }
        showAim(angle: shot.angle, power: shot.power)
    }

    func handleMouseUp(at upPoint: CGPoint) {
        guard game == .basketball, let start = dragStart else { return }
        dragStart = nil
        instant { aimDots.path = nil }
        let shot = shotParameters(from: start, to: upPoint)
        guard canShoot, shot.length >= 12 else { return }
        canShoot = false
        instant { heldBall.isHidden = true }
        avatars[myID]?.throwMotion()
        Office.shared.sportAction(roomID: roomID, action: .shoot(angle: shot.angle, power: shot.power))
        countdownText = "🏀 Otildi! Boshqalarni kutamiz"
        lastShownSecond = -1
    }

    func remove() {
        renderTimer?.invalidate()
        renderTimer = nil
        displayLink?.invalidate()
        displayLink = nil
        avatars.values.forEach { $0.remove() }
        avatars.removeAll()
        let layers: [CALayer] = [arena, ball, banner, board, leave, aimMarker, aimDots, hoopLayer, heldBall, ropeLayer]
        let paddleLayers: [CALayer] = Array(paddles.values)
        instant {
            for layer in layers { layer.removeFromSuperlayer() }
            for layer in paddleLayers { layer.removeFromSuperlayer() }
        }
        paddles.removeAll()
    }
}

/// Display link "nishoni": CADisplayLink Objective-C selektor kutadi, sahna esa oddiy Swift klass.
final class FrameDriver: NSObject {
    var onFrame: (() -> Void)?

    @objc func step(_ link: CADisplayLink) {
        onFrame?()
    }
}
