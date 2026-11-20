import AppKit
import QuartzCore

/// Osmondan uchib o‘tadiganlar: qishda Qorbobo, bahorda qaldirg‘ochlar, yozda havo shari, kuzda turnalar.
protocol Visitor: AnyObject {
    var root: CALayer { get }
    var trailLayer: CAEmitterLayer? { get }
    var position: CGPoint { get }
    var hitRect: CGRect { get }
    /// true qaytarsa — ekrandan chiqib ketdi.
    func update(dt: CGFloat) -> Bool
    func getHit(in game: SnowWorld)
    func consumeGiftRequest() -> Bool
    func remove()
}

extension SantaSleigh: Visitor {
    var trailLayer: CAEmitterLayer? { trail }
}

/// Qushlar galasi: qaldirg‘ochlar (tez, tarqoq) yoki turnalar (sekin, "V" shaklida).
final class BirdFlock: Visitor {
    let root = containerLayer()
    var trailLayer: CAEmitterLayer? { nil }
    let direction: CGFloat
    private(set) var position: CGPoint
    private let isCranes: Bool
    private let isStorks: Bool
    private let speed: CGFloat
    private let baseY: CGFloat
    private let flightWidth: CGFloat
    private let span: CGRect
    private var time: CGFloat = 0
    private var giftAt: CGFloat?
    private var wantsGift = false
    private var greeted = false
    private var bubble: SpeechBubble?

    init(cranes: Bool, direction: CGFloat, width: CGFloat, height: CGFloat, storks: Bool = false) {
        isCranes = cranes && !storks
        isStorks = storks
        self.direction = direction
        speed = storks ? 72 : (cranes ? 85 : 190)
        flightWidth = max(width, 1)
        baseY = height * CGFloat.random(in: 0.62...0.85)
        position = CGPoint(x: direction > 0 ? -200 : width + 200, y: baseY)
        var offsets: [CGPoint] = []
        if storks {
            // Laylaklar: ikki-uchtasi bemalol, keng oraliqda
            offsets.append(CGPoint(x: 0, y: 0))
            offsets.append(CGPoint(x: -86, y: CGFloat.random(in: 10...26)))
            if chance(0.6) { offsets.append(CGPoint(x: -168, y: CGFloat.random(in: -18...4))) }
        } else if cranes {
            // "V" shakli: oldinda bitta, orqasida ikki qanot bo‘ylab uchtadan
            offsets.append(CGPoint(x: 0, y: 0))
            for k in 1...3 {
                let dx = CGFloat(-30 * k)
                let dy = CGFloat(13 * k)
                offsets.append(CGPoint(x: dx, y: dy))
                offsets.append(CGPoint(x: dx, y: -dy))
            }
        } else {
            for _ in 0..<5 {
                let dx = CGFloat.random(in: -70...0)
                let dy = CGFloat.random(in: -22...22)
                offsets.append(CGPoint(x: dx, y: dy))
            }
        }
        let padding: CGFloat = storks ? 36 : 26
        let minX = (offsets.map { $0.x }.min() ?? 0) - padding
        let maxX = (offsets.map { $0.x }.max() ?? 0) + padding + 4
        let minY = (offsets.map { $0.y }.min() ?? 0) - 10
        let maxY = (offsets.map { $0.y }.max() ?? 0) + (storks ? 24 : 18)
        span = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        if chance(0.35) { giftAt = CGFloat.random(in: 0.25...0.75) }

        let parts = storks ? Art.stork : (cranes ? Art.crane : Art.swallow)
        let start = position
        var birds: [(CALayer, CALayer, CALayer)] = []
        for offset in offsets {
            let bird = containerLayer()
            bird.position = offset
            let back = partLayer(parts.wing, at: CGPoint(x: -1, y: 1))
            let body = partLayer(parts.body, at: .zero)
            let front = partLayer(parts.wing, at: CGPoint(x: 1, y: 1))
            back.opacity = 0.75
            bird.addSublayer(back)
            bird.addSublayer(body)
            bird.addSublayer(front)
            birds.append((bird, back, front))
        }
        instant {
            root.position = start
            root.zPosition = 35
            root.transform = CATransform3DMakeScale(direction, 1, 1)
            birds.forEach { root.addSublayer($0.0) }
        }
        let flapTime: CFTimeInterval = storks ? 0.62 : (cranes ? 0.42 : 0.13)
        for (bird, back, front) in birds {
            for wing in [back, front] {
                let flap = CABasicAnimation(keyPath: "transform.scale.y")
                flap.fromValue = 1
                flap.toValue = -0.7
                flap.duration = flapTime * Double.random(in: 0.9...1.1)
                flap.autoreverses = true
                flap.repeatCount = .infinity
                wing.add(flap, forKey: "flap")
            }
            bounce(bird, height: (cranes || storks) ? 2 : 4, duration: Double.random(in: 0.6...1.1), repeats: .infinity, key: "bob")
        }
    }

    var hitRect: CGRect {
        let x = direction > 0 ? position.x + span.minX : position.x - span.maxX
        return CGRect(x: x, y: position.y + span.minY, width: span.width, height: span.height)
    }

    func consumeGiftRequest() -> Bool {
        guard wantsGift else { return false }
        wantsGift = false
        return true
    }

    func update(dt: CGFloat) -> Bool {
        time += dt
        position.x += direction * speed * dt
        let calm = isCranes || isStorks
        position.y = baseY + sin(time * (calm ? 0.9 : 2.2)) * (calm ? 8 : 18)
        root.position = position
        if let current = bubble {
            if current.isAlive {
                current.layer.position = CGPoint(x: position.x, y: position.y + span.maxY + 14)
            } else {
                bubble = nil
            }
        }
        let progress = direction > 0 ? position.x / flightWidth : 1 - position.x / flightWidth
        if let at = giftAt, progress >= at {
            giftAt = nil
            wantsGift = true
        }
        return direction > 0 ? position.x > flightWidth + 260 : position.x < -260
    }

    func getHit(in game: SnowWorld) {
        bounce(root, height: 10, duration: 0.25, repeats: 1, key: "hit")
        bubble?.dismiss()
        let text: String
        if isStorks {
            text = greeted ? "Lak-lak!" : "Lak-lak! Laylaklar qaytdi — bahor keldi!"
        } else if isCranes {
            text = greeted ? "Kurr-kurr!" : "Kurr-kurr! Issiq o‘lkalarga ketyapmiz!"
        } else {
            text = greeted ? "Chik-chirik!" : "Chik-chirik! Bahor keldi!"
        }
        let newBubble = SpeechBubble(text: text, scale: game.scale)
        let point = CGPoint(x: position.x, y: position.y + span.maxY + 14)
        instant {
            newBubble.layer.position = point
            newBubble.layer.zPosition = 95
            game.root.addSublayer(newBubble.layer)
        }
        newBubble.show(for: 2.4)
        bubble = newBubble
        if !greeted {
            greeted = true
            wantsGift = true
        }
    }

    func remove() {
        bubble?.dismiss()
        instant { root.removeFromSuperlayer() }
    }
}

/// Yozgi havo shari: sekin suzib o‘tadi, savatdagi ikki kishi qo‘l silkitadi.
final class HotAirBalloon: Visitor {
    let root = containerLayer()
    var trailLayer: CAEmitterLayer? { nil }
    let direction: CGFloat
    private(set) var position: CGPoint
    private let baseY: CGFloat
    private let flightWidth: CGFloat
    private var time: CGFloat = 0
    private var giftAt: CGFloat?
    private var wantsGift = false
    private var greeted = false
    private var bubble: SpeechBubble?

    init(direction: CGFloat, width: CGFloat, height: CGFloat) {
        self.direction = direction
        flightWidth = max(width, 1)
        baseY = height * CGFloat.random(in: 0.5...0.7)
        position = CGPoint(x: direction > 0 ? -80 : width + 80, y: baseY)
        if chance(0.5) { giftAt = CGFloat.random(in: 0.3...0.7) }
        let body = partLayer(Art.balloon, at: .zero)
        let start = position
        instant {
            root.position = start
            root.zPosition = 35
            root.addSublayer(body)
        }
        let sway = CABasicAnimation(keyPath: "transform.rotation.z")
        sway.fromValue = -0.04
        sway.toValue = 0.04
        sway.duration = 2.2
        sway.autoreverses = true
        sway.repeatCount = .infinity
        body.add(sway, forKey: "sway")
    }

    var hitRect: CGRect {
        CGRect(x: position.x - 32, y: position.y, width: 64, height: 98)
    }

    func consumeGiftRequest() -> Bool {
        guard wantsGift else { return false }
        wantsGift = false
        return true
    }

    func update(dt: CGFloat) -> Bool {
        time += dt
        position.x += direction * 48 * dt
        position.y = baseY + sin(time * 0.6) * 14
        root.position = position
        if let current = bubble {
            if current.isAlive {
                current.layer.position = CGPoint(x: position.x, y: position.y + 110)
            } else {
                bubble = nil
            }
        }
        let progress = direction > 0 ? position.x / flightWidth : 1 - position.x / flightWidth
        if let at = giftAt, progress >= at {
            giftAt = nil
            wantsGift = true
        }
        return direction > 0 ? position.x > flightWidth + 100 : position.x < -100
    }

    func getHit(in game: SnowWorld) {
        bounce(root, height: 8, duration: 0.3, repeats: 1, key: "hit")
        bubble?.dismiss()
        let newBubble = SpeechBubble(text: greeted ? "Salom-salom!" : "Salom, pastdagilar! Mana sizga muzqaymoq!", scale: game.scale)
        let point = CGPoint(x: position.x, y: position.y + 110)
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
        instant { root.removeFromSuperlayer() }
    }
}
