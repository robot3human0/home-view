import AppKit
import QuartzCore

/// Ishchilar yasaydigan qorbola. Har biri o‘ziga xos: shapkasi (shlyapa, chelak, do‘ppi yoki
/// popukli shapka), sharf rangi va bo‘yi har xil bo‘ladi.
/// stage: 0 — hali yo‘q, 1 — pastki shar, 2 — o‘rta shar, 3 — bosh, 4 — bezaklar.
final class Snowman {
    let root = containerLayer()
    private(set) var stage = 0
    private(set) var hitPoints = 3
    private(set) var isMelting = false
    private(set) var isGone = false
    private(set) var position: CGPoint
    var age: CGFloat = 0

    /// Uni yasayotgan ishchi va qo‘riqchisi.
    weak var builder: Worker?
    weak var guardian: Worker?
    var buildTimer: CGFloat = 0
    /// Qo‘riqchi keyingi zarbani qachon yana to‘sa oladi.
    var guardReadyAt: CFTimeInterval = 0

    /// Shaxsiy bo‘y (0.9...1.12) × sozlamadagi o‘lcham.
    private let personalScale: CGFloat = CGFloat.random(in: 0.9...1.12)
    private(set) var sizeFactor: CGFloat = 1

    private let body = containerLayer()
    private let bottom: CALayer
    private let middle = containerLayer()
    private let head = containerLayer()
    private let middleBall: CALayer
    private let middleDecor: CALayer
    private let headBall: CALayer
    private let face: CALayer
    private let hat: CALayer

    /// Bosqichlarga qarab tegish balandligi (fasl bo‘yicha farq qiladi).
    private let hitHeights: [CGFloat]

    init(at point: CGPoint, sizeSetting: CGFloat, theme: SeasonTheme) {
        let parts = Art.monumentParts(theme.kind)
        hitHeights = parts.hitHeights
        position = point
        bottom = partLayer(parts.bottom, at: .zero)
        middleBall = partLayer(parts.middleBall, at: .zero)
        middleDecor = partLayer(parts.middleDecor, at: .zero)
        headBall = partLayer(parts.headBall, at: .zero)
        face = partLayer(parts.face, at: .zero)
        hat = partLayer(parts.topper, at: .zero)
        sizeFactor = personalScale * sizeSetting
        let factor = sizeFactor

        instant {
            root.position = point
            root.zPosition = 20
            body.transform = CATransform3DMakeScale(factor, factor, 1)
            middle.position = CGPoint(x: 0, y: 34)
            head.position = CGPoint(x: 0, y: 51)
            middle.addSublayer(middleBall)
            middle.addSublayer(middleDecor)
            head.addSublayer(headBall)
            head.addSublayer(face)
            head.addSublayer(hat)
            body.addSublayer(bottom)
            body.addSublayer(middle)
            body.addSublayer(head)
            root.addSublayer(body)
            for layer in [bottom, middle, head, middleDecor, face, hat] {
                layer.isHidden = true
            }
        }
    }

    var hitRect: CGRect {
        let index = max(0, min(hitHeights.count - 1, stage - 1))
        let height = hitHeights.isEmpty ? 40 : hitHeights[index]
        return CGRect(x: position.x - 16 * sizeFactor, y: position.y,
                      width: 32 * sizeFactor, height: height * sizeFactor)
    }

    var topPoint: CGPoint {
        CGPoint(x: position.x, y: position.y + hitRect.height + 6)
    }

    /// Mashina shu oraliqdagi qorga tegmaydi.
    func covers(_ x: CGFloat) -> Bool {
        abs(x - position.x) < 20 * sizeFactor
    }

    /// Sozlamadagi o‘lcham o‘zgarsa — mavjud qorbola ham silliq kattalashadi/kichrayadi.
    func applySizeSetting(_ setting: CGFloat) {
        sizeFactor = personalScale * setting
        body.transform = CATransform3DMakeScale(sizeFactor, sizeFactor, 1)
    }

    /// Yer ustidagi qor qalinlashsa, qorbola ham shu bilan ko‘tariladi.
    func settle(onY y: CGFloat) {
        position.y = y
        root.position = position
    }

    /// Yasashning keyingi bosqichi.
    func advance() {
        guard stage < 4 else { return }
        stage += 1
        let targets: [CALayer]
        switch stage {
        case 1: targets = [bottom]
        case 2: targets = [middle]
        case 3: targets = [head]
        default: targets = [middleDecor, face, hat]
        }
        instant { targets.forEach { $0.isHidden = false } }
        targets.forEach { popIn($0) }
    }

    /// Sichqoncha ustiga kelganda ozgina chayqaladi.
    func wobble(strength: CGFloat = 1) {
        let wobble = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        wobble.values = [0, 0.16 * strength, -0.12 * strength, 0]
        wobble.keyTimes = [0, 0.26, 0.68, 1]
        wobble.duration = 0.22
        root.add(wobble, forKey: "wobble")
    }

    /// Zarba tekkanda. true qaytarsa — qorbola butunlay buzildi.
    func takeHit(in game: SnowWorld) -> Bool {
        hitPoints -= 1
        wobble()
        let direction: CGFloat = Bool.random() ? 1 : -1

        // 1-zarba: shapka uchib ketadi
        if hitPoints == 2, stage >= 4, hat.superlayer != nil {
            let holder = detach(hat, in: game)
            let start = holder.position
            let end = CGPoint(x: start.x + direction * 100, y: start.y - 220)
            instant {
                holder.position = end
                holder.opacity = 0
                setRotation(hat, direction * 4)
            }
            let path = CGMutablePath()
            path.move(to: start)
            path.addQuadCurve(to: end, control: CGPoint(x: start.x + direction * 70, y: start.y + 110))
            let fly = CAKeyframeAnimation(keyPath: "position")
            fly.path = path
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 1, 0]
            fade.keyTimes = [0, 0.6, 1]
            let group = CAAnimationGroup()
            group.animations = [fly, fade]
            group.duration = 0.95
            holder.add(group, forKey: "fly")
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = direction * 4
            spin.duration = 0.95
            hat.add(spin, forKey: "spin")
            after(1.0) { holder.removeFromSuperlayer() }
            return false
        }

        // 2-zarba: bosh yumalab tushadi
        if hitPoints == 1, stage >= 3, head.superlayer === body {
            let holder = detach(head, in: game)
            let start = holder.position
            let landX = start.x + direction * 40
            let groundY = game.groundSurface(atX: landX) + 8 * sizeFactor
            let end = CGPoint(x: landX, y: groundY)
            instant {
                holder.position = end
                setRotation(head, -direction * 2)
            }
            let roll = CAKeyframeAnimation(keyPath: "position")
            roll.values = [start, CGPoint(x: start.x + direction * 28, y: start.y + 14), end].map { NSValue(point: $0) }
            roll.keyTimes = [0, 0.36, 1]
            roll.duration = 0.5
            holder.add(roll, forKey: "fall")
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = -direction * 2
            spin.duration = 0.5
            head.add(spin, forKey: "spin")
            let amount = 5 * sizeFactor
            after(0.5) { [weak game] in
                game?.burstSnow(at: end, count: 14)
                game?.depositGround(aroundX: landX, amount: amount)
                holder.removeFromSuperlayer()
            }
            return false
        }

        // 3-zarba: hammasi to‘kiladi, qor yerga qaytadi
        if hitPoints <= 0 {
            game.burstSnow(at: CGPoint(x: position.x, y: position.y + 22 * sizeFactor), count: Int(30 * sizeFactor))
            game.depositGround(aroundX: position.x, amount: 10 * sizeFactor)
            remove()
            return true
        }
        return false
    }

    /// Qatlamni qorboladan ajratib, dunyoga o‘tkazadi (o‘lchami saqlanadi).
    private func detach(_ layer: CALayer, in game: SnowWorld) -> CALayer {
        let start = layer.superlayer?.convert(layer.position, to: game.root) ?? position
        let holder = containerLayer()
        let factor = sizeFactor
        instant {
            holder.position = start
            holder.transform = CATransform3DMakeScale(factor, factor, 1)
            holder.zPosition = 26
            layer.removeFromSuperlayer()
            layer.position = .zero
            holder.addSublayer(layer)
            game.root.addSublayer(holder)
        }
        return holder
    }

    /// Ko‘p turib qolsa, asta-sekin eriydi.
    func melt() {
        guard !isMelting else { return }
        isMelting = true
        let shrink = CABasicAnimation(keyPath: "transform.scale.y")
        shrink.fromValue = 1
        shrink.toValue = 0.05
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0.4
        let group = CAAnimationGroup()
        group.animations = [shrink, fade]
        group.duration = 25
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        root.add(group, forKey: "melt")
        after(25) { [weak self] in self?.remove() }
    }

    func remove() {
        guard !isGone else { return }
        isGone = true
        instant { root.removeFromSuperlayer() }
    }
}
