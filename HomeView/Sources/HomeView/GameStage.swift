import AppKit
import QuartzCore
import HomeViewProtocol

/// Tarmoq o‘yini sahnasi: SnowWorld bilan shu shartnoma orqali gaplashadi.
/// GameStage — ko‘ngilochar o‘yinlar, SportStage — jamoaviy sport o‘yinlari.
protocol NetStage: AnyObject {
    var roomID: String { get }
    var playerIDs: [String] { get }
    /// true bo‘lsa — shu monitordagi barcha bosishlar sahnaga tegishli (sport o‘yini davomida).
    var capturesAllInput: Bool { get }
    func handle(_ event: GameEvent)
    func isInteractive(at point: CGPoint) -> Bool
    func handleClick(at point: CGPoint) -> Bool
    func handleDrag(at point: CGPoint)
    func handleMouseUp(at point: CGPoint)
    func tick(_ dt: CGFloat)
    func remove()
}

extension NetStage {
    var capturesAllInput: Bool { false }
    func handleDrag(at point: CGPoint) {}
    func handleMouseUp(at point: CGPoint) {}
    func tick(_ dt: CGFloat) {}
}

/// Ko‘ngilochar tarmoq o‘yini sahnasi (asosiy monitorda). O‘yinchilarning odamchalari ekran pastida
/// qatorga turadi, tepada — holat va hisob paneli. Server — hakam, sahna faqat ko‘rsatadi.
final class GameStage: NetStage {
    let roomID: String
    let game: GameKind
    private weak var world: SnowWorld?
    private let myID: String
    private var avatars: [String: PeerAvatar] = [:]
    private var order: [String] = []
    private var alive: Set<String> = []
    private var holder: String?
    private let ball = CALayer()
    private let ring = CAShapeLayer()
    private var targets: [Int: CALayer] = [:]
    private let banner = containerLayer()
    private let bannerBackground = CAShapeLayer()
    private let bannerText = CATextLayer()
    private(set) var isFinished = false

    init(room: RoomInfo, world: SnowWorld, players: [PeerInfo], myID: String) {
        roomID = room.id
        game = room.game
        self.world = world
        self.myID = myID
        order = players.map { $0.id }
        alive = Set(order)

        let count = CGFloat(players.count)
        let spacing = min(110, world.size.width * 0.7 / max(count, 1))
        let startX = world.size.width / 2 - spacing * (count - 1) / 2
        let scale = max(1.1, CGFloat(Settings.shared.workerScale))
        for (index, info) in players.enumerated() {
            let x = startX + CGFloat(index) * spacing
            let avatar = PeerAvatar(info: info, at: CGPoint(x: x, y: world.groundSurface(atX: x)),
                                    scale: scale, screenScale: world.scale)
            avatar.isStaged = true
            avatar.isMe = info.id == myID
            avatar.face(x < world.size.width / 2 ? 1 : -1)
            avatar.attach(to: world.root)
            avatars[info.id] = avatar
        }

        ball.contents = world.theme.projectileImage
        ball.contentsScale = Art.scale
        ball.contentsGravity = .resize
        ball.bounds = CGRect(x: 0, y: 0, width: 30, height: 30)
        ring.path = CGPath(ellipseIn: CGRect(x: -21, y: -21, width: 42, height: 42), transform: nil)
        ring.fillColor = nil
        ring.strokeColor = cg(0xE53935, 0.9)
        ring.lineWidth = 3
        ring.contentsScale = world.scale

        bannerBackground.fillColor = cg(0x0F1B2D, 0.85)
        bannerBackground.strokeColor = cg(0xFFFFFF, 0.25)
        bannerBackground.lineWidth = 1
        bannerBackground.contentsScale = world.scale
        bannerText.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        bannerText.fontSize = 16
        bannerText.foregroundColor = whiteColor
        bannerText.alignmentMode = .center
        bannerText.contentsScale = world.scale
        let bannerPoint = CGPoint(x: world.size.width / 2, y: world.size.height - 120)
        instant {
            ball.zPosition = 88
            ball.isHidden = true
            ring.zPosition = 87
            ring.isHidden = true
            banner.zPosition = 101
            banner.position = bannerPoint
            banner.addSublayer(bannerBackground)
            banner.addSublayer(bannerText)
            world.root.addSublayer(ring)
            world.root.addSublayer(ball)
            world.root.addSublayer(banner)
        }
        setBanner("\(game.emoji) \(game.title) boshlanmoqda... \(game.rules)")
    }

    // MARK: - Ko‘rsatish

    private func name(_ id: String) -> String {
        id == myID ? "Siz" : (avatars[id]?.info.name ?? "Hamkasb")
    }

    private func setBanner(_ text: String) {
        let font = NSFont.systemFont(ofSize: 16, weight: .bold)
        let maxWidth = (world?.size.width ?? 900) * 0.8
        var size = (text as NSString).size(withAttributes: [.font: font])
        size.width = min(size.width, maxWidth)
        let width = ceil(size.width) + 36
        let height: CGFloat = 40
        instant {
            bannerBackground.path = CGPath(roundedRect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
                                           cornerWidth: 14, cornerHeight: 14, transform: nil)
            bannerText.string = text
            bannerText.truncationMode = .end
            bannerText.bounds = CGRect(x: 0, y: 0, width: width - 24, height: ceil(size.height))
            bannerText.position = .zero
        }
        popIn(banner)
    }

    private func scoreLine(_ scores: [String: Int]) -> String {
        scores.sorted { $0.value > $1.value }.prefix(3)
            .map { "\(name($0.key)) \($0.value)" }
            .joined(separator: "   ")
    }

    // MARK: - Server voqealari

    func handle(_ event: GameEvent) {
        guard let world else { return }
        switch event {
        case .hotBallHolder(let newHolder, let stillAlive):
            alive = Set(stillAlive)
            moveBall(to: newHolder)
            holder = newHolder
            if newHolder == myID {
                setBanner("💣 Koptok sizda! Boshqa o‘yinchini bosing!")
                avatars[myID]?.hop()
            } else {
                setBanner("💣 Koptok: \(name(newHolder))")
            }

        case .hotBallExploded(let loser, let stillAlive):
            alive = Set(stillAlive)
            holder = nil
            if let avatar = avatars[loser] {
                world.burstSnow(at: CGPoint(x: avatar.position.x, y: avatar.position.y + 30), count: 30)
                avatar.flinch()
                avatar.setDimmed(true)
                avatar.say(loser == myID ? "Eh, men chiqdim!" : "Voy!", in: world, duration: 2)
            }
            instant {
                ball.isHidden = true
                ring.isHidden = true
            }
            setBanner("💥 \(name(loser)) chiqib ketdi! Qoldi: \(stillAlive.count)")

        case .target(let target):
            spawnTarget(target, in: world)

        case .targetHit(let targetID, let by, let scores):
            if let layer = targets.removeValue(forKey: targetID) {
                let point = layer.position
                world.burstSnow(at: point, count: 18)
                world.showFloatText(by == myID ? "Siz! +1" : "\(name(by)) +1", at: point)
                instant { layer.removeFromSuperlayer() }
            }
            setBanner("🎯 \(scoreLine(scores))")

        case .targetMissed(let targetID):
            if let layer = targets.removeValue(forKey: targetID) {
                layer.opacity = 0
                after(0.3) { layer.removeFromSuperlayer() }
            }

        case .finished(let winner, let scores):
            isFinished = true
            instant {
                ball.isHidden = true
                ring.isHidden = true
            }
            if let winner {
                setBanner("🏆 G‘olib: \(name(winner))\(scores.isEmpty ? "" : "   •   " + scoreLine(scores))")
                if let avatar = avatars[winner] {
                    avatar.hop()
                    world.confetti(at: CGPoint(x: avatar.position.x, y: avatar.position.y + 50))
                    avatar.say(winner == myID ? "Yutdim!" : "Ura!", in: world, duration: 3)
                }
            } else {
                setBanner("🤝 Durang!")
            }

        default:
            break
        }
    }

    private func moveBall(to id: String) {
        guard let avatar = avatars[id] else { return }
        let point = CGPoint(x: avatar.position.x, y: avatar.position.y + 62 * avatar.sizeScale)
        let wasHidden = ball.isHidden
        if wasHidden {
            instant {
                ball.isHidden = false
                ring.isHidden = id != myID
                ball.position = point
                ring.position = point
            }
            popIn(ball)
        } else {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.22)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            ball.position = point
            ring.position = point
            CATransaction.commit()
            instant { ring.isHidden = id != myID }
        }
        if id == myID {
            let pulse = CABasicAnimation(keyPath: "transform.scale")
            pulse.fromValue = 0.85
            pulse.toValue = 1.15
            pulse.duration = 0.3
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            ring.add(pulse, forKey: "pulse")
        } else {
            ring.removeAnimation(forKey: "pulse")
        }
    }

    private func spawnTarget(_ target: GameTarget, in world: SnowWorld) {
        let layer = partLayer(world.theme.gift, at: CGPoint(x: target.x * world.size.width, y: target.y * world.size.height))
        let size = layer.bounds.size
        layer.bounds = CGRect(x: 0, y: 0, width: size.width * 2.6, height: size.height * 2.6)
        instant {
            layer.zPosition = 89
            world.root.addSublayer(layer)
        }
        popIn(layer)
        bounce(layer, height: 8, duration: 0.8, repeats: .infinity, key: "bob")
        targets[target.id] = layer
    }

    // MARK: - Bosish

    /// Shu nuqtada sahnaga tegishli narsa bormi (odamcha yoki nishon)?
    func isInteractive(at point: CGPoint) -> Bool {
        if targets.values.contains(where: { $0.frame.insetBy(dx: -10, dy: -10).contains(point) }) { return true }
        return avatars.values.contains { $0.hitRect.insetBy(dx: -6, dy: -6).contains(point) }
    }

    /// true qaytarsa — bosish sahnada ishlatildi.
    func handleClick(at point: CGPoint) -> Bool {
        if let entry = targets.first(where: { $0.value.frame.insetBy(dx: -10, dy: -10).contains(point) }) {
            Office.shared.hit(roomID: roomID, targetID: entry.key)
            return true
        }
        if let target = avatars.values.first(where: { $0.hitRect.insetBy(dx: -6, dy: -6).contains(point) }) {
            if game == .hotBall, holder == myID, target.id != myID, alive.contains(target.id) {
                Office.shared.pass(roomID: roomID, to: target.id)
            } else {
                target.hop()
            }
            return true
        }
        return false
    }

    var playerIDs: [String] { order }

    func remove() {
        avatars.values.forEach { $0.remove() }
        avatars.removeAll()
        for layer in targets.values { layer.removeFromSuperlayer() }
        targets.removeAll()
        instant {
            ball.removeFromSuperlayer()
            ring.removeFromSuperlayer()
            banner.removeFromSuperlayer()
        }
    }
}
