import AppKit
import QuartzCore

/// Qor tozalovchi mashina. Ikki xil bo‘ladi: katta to‘q sariq va kichik, tezroq ko‘k.
/// Ekranning bir chetidan kirib, yerdagi qorni kurak bilan surib, ikkinchi chetidan chiqib ketadi.
final class Snowplow {
    private static let bladeOffsetBase: CGFloat = 70

    let direction: CGFloat
    let isSmall: Bool
    let root = containerLayer()
    private(set) var position: CGPoint
    /// Mashina turi bo‘yicha asosiy o‘lcham (kichik ko‘k — 0.78) × sozlamadagi "Mashinalar" slayderi.
    private let kindScale: CGFloat
    private var scale: CGFloat
    private let baseSpeed: CGFloat
    private var boostTimer: CGFloat = 0
    private var lastBladeX: CGFloat
    private var pushed: CGFloat = 0
    private let bow = CAShapeLayer()
    private let spray = CAEmitterLayer()
    private var bowTimer: CGFloat = 0
    private var spraying = false
    private var bubble: SpeechBubble?

    private let alwaysSpray: Bool

    init(direction: CGFloat, small: Bool, kind: SeasonKind, startX: CGFloat, groundY: CGFloat,
         screenScale: CGFloat, sizeSetting: CGFloat) {
        self.direction = direction
        isSmall = small
        kindScale = small ? 0.78 : 1.0
        scale = (small ? 0.78 : 1.0) * sizeSetting
        baseSpeed = small ? 145 : 110
        position = CGPoint(x: startX, y: groundY)
        lastBladeX = startX + direction * Snowplow.bladeOffsetBase * (small ? 0.78 : 1.0) * sizeSetting
        let parts = Art.vehicleParts(kind, small: small)
        alwaysSpray = parts.alwaysSpray
        let body = partLayer(parts.body, at: .zero)
        let brush = parts.brush.map { partLayer($0, at: CGPoint(x: 64, y: 9)) }
        let glow = partLayer(parts.glow, at: .zero)
        var wheels: [CALayer] = []
        for x in [CGFloat(-42), -22, 30] {
            wheels.append(partLayer(parts.wheel, at: CGPoint(x: x, y: 9)))
        }
        let start = position
        let transform = CATransform3DMakeScale(direction * scale, scale, 1)

        bow.fillColor = whiteColor
        bow.strokeColor = cg(0xA9B9CF)
        bow.lineWidth = 1
        bow.contentsScale = screenScale
        configureSpray(color: parts.sprayColor)
        if alwaysSpray {
            spray.birthRate = 1
            spraying = true
        }

        instant {
            root.position = start
            root.transform = transform
            root.zPosition = small ? 17 : 18
            root.addSublayer(body)
            root.addSublayer(glow)
            wheels.forEach { root.addSublayer($0) }
            root.addSublayer(bow)
            if let brush { root.addSublayer(brush) }
            root.addSublayer(spray)
        }
        if let brush { spinForever(brush, duration: 0.35) }
        wheels.forEach { spinForever($0, duration: small ? 0.42 : 0.55) }
        blinkForever(glow, low: 0.15, duration: 0.25)
    }

    var bladeX: CGFloat { position.x + direction * Snowplow.bladeOffsetBase * scale }

    /// "Mashinalar" slayderi surilganda — yo‘ldagi mashina ham silliq kattalashadi/kichrayadi.
    func setSizeSetting(_ setting: CGFloat) {
        let newScale = kindScale * setting
        guard abs(newScale - scale) > 0.001 else { return }
        scale = newScale
        root.transform = CATransform3DMakeScale(direction * newScale, newScale, 1)
    }

    var topPoint: CGPoint {
        CGPoint(x: position.x, y: position.y + 60 * scale)
    }

    var hitRect: CGRect {
        let width = 132 * scale
        let left = direction > 0 ? position.x - 59 * scale : position.x - 73 * scale
        return CGRect(x: left, y: position.y - 2, width: width, height: 58 * scale)
    }

    /// true qaytarsa — mashina ekrandan chiqib ketdi.
    func update(dt: CGFloat, game: SnowWorld) -> Bool {
        boostTimer = max(0, boostTimer - dt)
        let speed = baseSpeed * scale.squareRoot() * (boostTimer > 0 ? 1.8 : 1)
        position.x += direction * speed * dt
        position.y = game.ground.baseY + min(game.ground.height(atX: position.x), 4)
        root.position = position

        let blade = bladeX
        let removed = game.plowClear(fromX: min(lastBladeX, blade) - 3, toX: max(lastBladeX, blade) + 3)
        lastBladeX = blade
        pushed = min(pushed + removed, 30_000)

        let shouldSpray = removed > 1 || alwaysSpray
        if shouldSpray != spraying {
            spraying = shouldSpray
            instant { spray.birthRate = shouldSpray ? 1 : 0 }
        }
        bowTimer -= dt
        if bowTimer <= 0 {
            bowTimer = 0.1
            let w = min(8 + pushed * 0.004, 44)
            let h = min(6 + pushed * 0.0035, 38)
            let path = CGPath(ellipseIn: CGRect(x: Snowplow.bladeOffsetBase - 4, y: -2, width: w, height: h), transform: nil)
            instant { bow.path = path }
        }
        if let current = bubble {
            if current.isAlive {
                current.layer.position = CGPoint(x: position.x, y: position.y + 70 * scale)
            } else {
                bubble = nil
            }
        }
        return direction > 0 ? position.x - 130 > game.size.width : position.x + 130 < 0
    }

    /// Sichqoncha bilan bosilganda: signal chalib, bir zum tezlashadi.
    func honk(in game: SnowWorld) {
        boostTimer = 1.6
        bounce(root, height: 5, duration: 0.18, repeats: 2, key: "honk")
        bubble?.dismiss()
        let text = ["Bip-biiip!", "Yo‘l bering!", "Qor tozalanmoqda!", "Bip-bip!"].randomElement() ?? "Bip-bip!"
        let newBubble = SpeechBubble(text: text, scale: game.scale)
        let point = CGPoint(x: position.x, y: position.y + 70 * scale)
        instant {
            newBubble.layer.position = point
            game.root.addSublayer(newBubble.layer)
        }
        newBubble.show(for: 1.6)
        bubble = newBubble
    }

    func remove() {
        bubble?.dismiss()
        instant { root.removeFromSuperlayer() }
    }

    /// Kurak oldidan otilib chiqayotgan qor changi.
    private func configureSpray(color: CGColor) {
        spray.emitterPosition = CGPoint(x: Snowplow.bladeOffsetBase + 4, y: 16)
        spray.emitterShape = .line
        spray.emitterMode = .outline
        spray.emitterSize = CGSize(width: 1, height: 1)
        spray.beginTime = CACurrentMediaTime()
        spray.birthRate = 0
        let cell = CAEmitterCell()
        cell.contents = Art.flake
        cell.contentsScale = Art.scale
        cell.birthRate = 40
        cell.lifetime = 0.6
        cell.lifetimeRange = 0.2
        cell.velocity = 90
        cell.velocityRange = 40
        // Yuqoriga otiladi, oldinga esa tezlanish bilan suriladi (qatlam yo‘nalishi bilan birga aylanadi).
        cell.emissionLongitude = .pi
        cell.emissionRange = 0.5
        cell.xAcceleration = 220
        cell.yAcceleration = -520
        cell.scale = 0.35
        cell.scaleRange = 0.15
        cell.alphaSpeed = -1.2
        cell.color = color
        spray.emitterCells = [cell]
    }
}
