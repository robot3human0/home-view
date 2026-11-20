import AppKit
import QuartzCore

/// Bug‘ular tortgan chanada uchib o‘tadigan Qorbobo va Qorqiz.
final class SantaSleigh {
    let direction: CGFloat
    let root = containerLayer()
    /// Uchqunli iz — dunyo qatlamida turadi, shuning uchun chana ortida qoladi.
    let trail = CAEmitterLayer()
    private let body = containerLayer()
    private(set) var position: CGPoint
    private let flySpeed: CGFloat = 150
    private let flightWidth: CGFloat
    private let baseY: CGFloat
    private var time: CGFloat = 0
    private var giftAtProgress: CGFloat?
    private var wantsGift = false
    private var greeted = false
    private var bubble: SpeechBubble?

    init(direction: CGFloat, width: CGFloat, height: CGFloat) {
        self.direction = direction
        flightWidth = max(width, 1)
        baseY = height * CGFloat.random(in: 0.6...0.82)
        position = CGPoint(x: direction > 0 ? -260 : width + 260, y: baseY)
        if chance(0.3) { giftAtProgress = CGFloat.random(in: 0.25...0.75) }

        let parts = Art.santa
        var reindeerLayers: [CALayer] = []
        var legLayers: [CALayer] = []
        var shine: CALayer?
        for i in 0..<3 {
            let deer = containerLayer()
            deer.position = CGPoint(x: 64 + CGFloat(i) * 42, y: 0)
            for (index, x) in [CGFloat(-9), -5, 6, 10].enumerated() {
                let leg = partLayer(parts.leg, at: CGPoint(x: x, y: 2))
                leg.setValue(index % 2 == 0 ? 0.6 : -0.6, forKeyPath: "transform.rotation.z")
                deer.addSublayer(leg)
                legLayers.append(leg)
            }
            deer.addSublayer(partLayer(parts.reindeer, at: .zero))
            if i == 2 {
                let glow = partLayer(parts.shine, at: .zero)
                deer.addSublayer(glow)
                shine = glow
            }
            reindeerLayers.append(deer)
        }
        let sleighBody = partLayer(parts.body, at: .zero)
        let start = position

        configureTrail()
        instant {
            root.position = start
            root.zPosition = 35
            root.transform = CATransform3DMakeScale(direction, 1, 1)
            root.addSublayer(body)
            reindeerLayers.forEach { body.addSublayer($0) }
            body.addSublayer(sleighBody)
        }
        for (index, leg) in legLayers.enumerated() {
            swingForever(leg, amplitude: index % 2 == 0 ? 0.6 : -0.6, half: 0.18, key: "gallop")
        }
        for deer in reindeerLayers {
            bounce(deer, height: 2.5, duration: 0.36, repeats: .infinity, key: "gallop")
        }
        if let shine { blinkForever(shine, low: 0.15, duration: 0.35) }
    }

    private var rearPoint: CGPoint {
        CGPoint(x: position.x - direction * 52, y: position.y + 6)
    }

    var hitRect: CGRect {
        direction > 0
            ? CGRect(x: position.x - 60, y: position.y - 12, width: 255, height: 68)
            : CGRect(x: position.x - 195, y: position.y - 12, width: 255, height: 68)
    }

    /// Sovg‘a tashlash vaqti keldimi? (bir marta true qaytaradi)
    func consumeGiftRequest() -> Bool {
        guard wantsGift else { return false }
        wantsGift = false
        return true
    }

    /// true qaytarsa — ekrandan uchib chiqib ketdi.
    func update(dt: CGFloat) -> Bool {
        time += dt
        position.x += direction * flySpeed * dt
        position.y = baseY + sin(time * 1.7) * 16
        root.position = position
        trail.emitterPosition = rearPoint
        if let current = bubble {
            if current.isAlive {
                current.layer.position = CGPoint(x: position.x, y: position.y + 66)
            } else {
                bubble = nil
            }
        }
        let progress = direction > 0 ? position.x / flightWidth : 1 - position.x / flightWidth
        if let at = giftAtProgress, progress >= at {
            giftAtProgress = nil
            wantsGift = true
        }
        return direction > 0 ? position.x > flightWidth + 300 : position.x < -300
    }

    /// O‘yin rejimida qor tekkanda.
    func getHit(in game: SnowWorld) {
        bounce(body, height: 12, duration: 0.22, repeats: 1, key: "hit")
        bubble?.dismiss()
        let newBubble = SpeechBubble(text: greeted ? "Ho-ho-ho!" : "Ho-ho-ho! Yangi yilingiz bilan!", scale: game.scale)
        let point = CGPoint(x: position.x, y: position.y + 66)
        instant {
            newBubble.layer.position = point
            newBubble.layer.zPosition = 95
            game.root.addSublayer(newBubble.layer)
        }
        newBubble.show(for: 2.6)
        bubble = newBubble
        if !greeted {
            greeted = true
            wantsGift = true
        }
    }

    func remove() {
        bubble?.dismiss()
        instant {
            trail.birthRate = 0
            root.removeFromSuperlayer()
        }
        let oldTrail = trail
        after(2.0) { oldTrail.removeFromSuperlayer() }
    }

    private func configureTrail() {
        trail.emitterShape = .line
        trail.emitterMode = .outline
        trail.emitterSize = CGSize(width: 1, height: 1)
        trail.emitterPosition = rearPoint
        trail.beginTime = CACurrentMediaTime()
        trail.zPosition = 34
        let cell = CAEmitterCell()
        cell.contents = Art.sparkle
        cell.contentsScale = Art.scale
        cell.birthRate = 45
        cell.lifetime = 1.3
        cell.lifetimeRange = 0.5
        cell.velocity = 30
        cell.velocityRange = 20
        // Uchqunlar sekin pastga to‘kiladi; chana tezroq uchgani uchun ular ortda qoladi.
        cell.emissionLongitude = 0
        cell.emissionRange = 0.8
        cell.yAcceleration = -25
        cell.alphaSpeed = -0.8
        cell.scale = 0.6
        cell.scaleRange = 0.4
        cell.scaleSpeed = -0.3
        cell.color = cg(0xFFF59D)
        trail.emitterCells = [cell]
    }
}
