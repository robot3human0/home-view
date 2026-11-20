import AppKit
import QuartzCore

/// Bitta monitordagi ob-havo effektlari.
///
/// Hammasi Core Animation qatlamlari va emitterlari: ularni GPU chizadi, ilova faqat sozlab qo‘yadi.
/// `update` sekundiga 20 marta chaqiriladi va faqat taymerlarni sanaydi (chaqmoq, ko‘lmak to‘lqinlari)
/// hamda yomg‘ir qiyaligini shamolga moslaydi — shuning uchun ekran qotmaydi.
///
/// Oyna ish stoli ustida turgani uchun effektlar yumshoq: yomg‘ir shaffof, tuman va qirov xira,
/// chaqmoq yorug‘ligi qisqa va kuchsiz — ishingizga xalaqit bermaydi.
final class WeatherEffects {
    private let root: CALayer
    private let size: CGSize
    private let scale: CGFloat
    private let groundY: CGFloat
    private let topY: CGFloat
    private var widthFactor: Float { Float(size.width / 1440) }

    /// Foydalanuvchining "qor miqdori" slayderi (yomg‘irga ham ta’sir qiladi).
    var intensity: CGFloat = 1 {
        didSet {
            guard abs(intensity - oldValue) > 0.01 else { return }
            let value = Float(intensity)
            instant {
                rain?.birthRate = value
                splashes?.birthRate = value
            }
        }
    }

    private var kind: WeatherKind = .snowfall
    private var layers: [CALayer] = []
    private var rain: CAEmitterLayer?
    private var splashes: CAEmitterLayer?
    private var puddleSpots: [CGRect] = []
    private var rainAngle: CGFloat = 0
    private var rippleTimer: CGFloat = 0
    private var lightningTimer: CGFloat = 0

    init(root: CALayer, size: CGSize, scale: CGFloat, groundY: CGFloat, topY: CGFloat) {
        self.root = root
        self.size = size
        self.scale = scale
        self.groundY = groundY
        self.topY = topY
    }

    // MARK: - Holatni almashtirish

    func apply(_ newKind: WeatherKind, animated: Bool) {
        kind = newKind
        let old = layers
        layers = []
        rain = nil
        splashes = nil
        puddleSpots = []
        rainAngle = 0
        if animated {
            for layer in old {
                fade(layer, to: 0, duration: 2.5)
            }
            after(2.7) {
                instant { old.forEach { $0.removeFromSuperlayer() } }
            }
        } else {
            instant { old.forEach { $0.removeFromSuperlayer() } }
        }
        build(newKind.profile)
        if animated {
            for layer in layers {
                let target = layer.opacity
                instant { layer.opacity = 0 }
                fade(layer, to: target, duration: 3)
            }
        }
    }

    private func build(_ profile: WeatherProfile) {
        let effects = profile.effects
        if effects.contains(.sunGlare) { makeSun(cold: false) }
        if effects.contains(.coldSun) { makeSun(cold: true) }
        if effects.contains(.rainbow) { makeRainbow() }
        if effects.contains(.puddles) { makePuddles() }
        if effects.contains(.iceSheen) { makeIceSheen() }
        if effects.contains(.icicles) { makeIcicles() }
        if profile.rain > 0 { makeRain(profile.rain) }
        if effects.contains(.splashes) { makeSplashes(profile.rain) }
        if effects.contains(.diamondDust) { makeDiamondDust() }
        if effects.contains(.fireflies) { makeFireflies() }
        if effects.contains(.fog) { makeFog() }
        if effects.contains(.whiteout) { makeWhiteout() }
        if effects.contains(.frost) { makeFrost() }
        if effects.contains(.lightning) { lightningTimer = CGFloat.random(in: 5...12) }
    }

    private func add(_ layer: CALayer, z: CGFloat) {
        instant {
            layer.zPosition = z
            root.addSublayer(layer)
        }
        layers.append(layer)
    }

    // MARK: - Har kadr (20 Hz): faqat taymerlar

    func update(dt: CGFloat, wind: CGFloat) {
        if let rain {
            let angle = atan2(wind, 900)
            if abs(angle - rainAngle) > 0.008 {
                rainAngle = angle
                rain.setAffineTransform(CGAffineTransform(rotationAngle: angle))
            }
        }
        if !puddleSpots.isEmpty, rain != nil {
            rippleTimer -= dt
            if rippleTimer <= 0 {
                rippleTimer = CGFloat.random(in: 0.1...0.3) / max(intensity, 0.3)
                ripple()
            }
        }
        if kind.profile.effects.contains(.lightning) {
            lightningTimer -= dt
            if lightningTimer <= 0 {
                lightningTimer = CGFloat.random(in: 9...28)
                strike()
            }
        }
    }

    // MARK: - Rasmlar

    private func sprite(_ name: String) -> (CGImage?, CGFloat) {
        if let picture = ArtPack.image(name) {
            return (picture, ArtPack.pixelsPerPoint)
        }
        switch name {
        case "hv_w_rain":
            let picture = Art.image(CGSize(width: 2, height: 28)) { ctx in
                Art.rect(ctx, CGRect(x: 0.6, y: 1, width: 0.8, height: 26), Art.color(0.9, 0.95, 1, 0.7), radius: 0.4)
            }
            return (picture, Art.scale)
        case "hv_w_drop":
            let picture = Art.image(CGSize(width: 8, height: 8)) { ctx in
                Art.circle(ctx, 2.2, at: CGPoint(x: 4, y: 4), Art.color(0.85, 0.92, 1, 0.9))
            }
            return (picture, Art.scale)
        case "hv_w_firefly":
            let picture = Art.image(CGSize(width: 24, height: 24)) { ctx in
                Art.circle(ctx, 6, at: CGPoint(x: 12, y: 12), Art.color(0.85, 1, 0.45, 0.25))
                Art.circle(ctx, 1.8, at: CGPoint(x: 12, y: 12), Art.color(1, 1, 0.85, 1))
            }
            return (picture, Art.scale)
        default:
            return (Art.sparkle, Art.scale)
        }
    }

    // MARK: - Yomg‘ir va sachrashlar

    private func makeRain(_ strength: Float) {
        let emitter = CAEmitterLayer()
        emitter.bounds = CGRect(origin: .zero, size: size)
        emitter.position = CGPoint(x: size.width / 2, y: size.height / 2)
        emitter.emitterShape = .line
        emitter.emitterMode = .outline
        emitter.emitterPosition = CGPoint(x: size.width / 2, y: size.height + 60)
        emitter.emitterSize = CGSize(width: size.width * 1.7, height: 1)
        emitter.beginTime = CACurrentMediaTime() - 3
        emitter.birthRate = Float(intensity)
        let (picture, pictureScale) = sprite("hv_w_rain")
        let cell = CAEmitterCell()
        cell.name = "rain"
        cell.contents = picture
        cell.contentsScale = pictureScale
        cell.birthRate = 330 * strength * widthFactor
        cell.velocity = 950
        cell.velocityRange = 200
        cell.emissionLongitude = 0
        cell.emissionRange = 0.02
        cell.lifetime = Float((size.height + 120) / 760)
        cell.scale = 1
        cell.scaleRange = 0.35
        cell.alphaRange = 0.35
        cell.color = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.6)
        emitter.emitterCells = [cell]
        add(emitter, z: 41)
        rain = emitter
    }

    private func makeSplashes(_ strength: Float) {
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .line
        emitter.emitterMode = .outline
        emitter.emitterPosition = CGPoint(x: size.width / 2, y: groundY + 3)
        emitter.emitterSize = CGSize(width: size.width, height: 1)
        emitter.birthRate = Float(intensity)
        let (picture, pictureScale) = sprite("hv_w_drop")
        let cell = CAEmitterCell()
        cell.name = "splash"
        cell.contents = picture
        cell.contentsScale = pictureScale
        cell.birthRate = 140 * strength * widthFactor
        cell.velocity = 48
        cell.velocityRange = 26
        cell.emissionLongitude = .pi
        cell.emissionRange = 0.9
        cell.yAcceleration = -320
        cell.lifetime = 0.38
        cell.lifetimeRange = 0.12
        cell.scale = 0.42
        cell.scaleRange = 0.18
        cell.alphaSpeed = -1.8
        cell.color = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.75)
        emitter.emitterCells = [cell]
        add(emitter, z: 41)
        splashes = emitter
    }

    // MARK: - Ko‘lmaklar va to‘lqinlar

    private func makePuddles() {
        let count = max(3, Int(size.width / 320))
        for index in 0..<count {
            let slot = size.width / CGFloat(count)
            let width = CGFloat.random(in: 70...150)
            let height = CGFloat.random(in: 5...9)
            let x = slot * CGFloat(index) + CGFloat.random(in: 20...max(21, slot - width - 20))
            let frame = CGRect(x: x, y: groundY - height * 0.2, width: width, height: height)
            let puddle = CAShapeLayer()
            puddle.contentsScale = scale
            puddle.path = CGPath(ellipseIn: frame, transform: nil)
            puddle.fillColor = cg(0xB8D4EC, 0.28)
            puddle.strokeColor = cg(0xFFFFFF, 0.42)
            puddle.lineWidth = 1
            let shine = CAShapeLayer()
            shine.contentsScale = scale
            let shineRect = CGRect(x: frame.minX + width * 0.18, y: frame.midY + height * 0.05,
                                   width: width * 0.28, height: height * 0.22)
            shine.path = CGPath(ellipseIn: shineRect, transform: nil)
            shine.fillColor = cg(0xFFFFFF, 0.55)
            puddle.addSublayer(shine)
            add(puddle, z: 13)
            puddleSpots.append(frame)
        }
    }

    private func ripple() {
        guard let spot = puddleSpots.randomElement() else { return }
        let center = CGPoint(x: CGFloat.random(in: spot.minX + spot.width * 0.2...spot.maxX - spot.width * 0.2),
                             y: spot.midY)
        let ring = CAShapeLayer()
        ring.contentsScale = scale
        ring.bounds = CGRect(x: -8, y: -2, width: 16, height: 4)
        ring.path = CGPath(ellipseIn: CGRect(x: -7, y: -1.6, width: 14, height: 3.2), transform: nil)
        ring.fillColor = nil
        ring.strokeColor = cg(0xFFFFFF, 0.7)
        ring.lineWidth = 0.7
        instant {
            ring.position = center
            ring.zPosition = 14
            ring.opacity = 0
            root.addSublayer(ring)
        }
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.3
        grow.toValue = 2.2
        let vanish = CABasicAnimation(keyPath: "opacity")
        vanish.fromValue = 0.8
        vanish.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, vanish]
        group.duration = 0.9
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.add(group, forKey: "ripple")
        after(0.95) {
            instant { ring.removeFromSuperlayer() }
        }
    }

    // MARK: - Chaqmoq

    private func strike() {
        let flash = CALayer()
        flash.frame = CGRect(origin: .zero, size: size)
        flash.backgroundColor = cg(0xEEF3FF)
        instant {
            flash.opacity = 0
            flash.zPosition = 47
            root.addSublayer(flash)
        }
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [0, 0.15, 0.02, 0.1, 0]
        blink.keyTimes = [0, 0.08, 0.2, 0.32, 1]
        blink.duration = 0.75
        flash.add(blink, forKey: "flash")

        let bolt = CAShapeLayer()
        bolt.contentsScale = scale
        let boltPath = CGMutablePath()
        var point = CGPoint(x: CGFloat.random(in: size.width * 0.15...size.width * 0.85), y: size.height)
        let bottom = size.height * CGFloat.random(in: 0.35...0.6)
        boltPath.move(to: point)
        var branchFrom: CGPoint?
        while point.y > bottom {
            point = CGPoint(x: point.x + CGFloat.random(in: -34...34), y: point.y - CGFloat.random(in: 26...58))
            boltPath.addLine(to: point)
            if branchFrom == nil && chance(0.35) { branchFrom = point }
        }
        if var branch = branchFrom {
            boltPath.move(to: branch)
            for _ in 0..<4 {
                branch = CGPoint(x: branch.x + CGFloat.random(in: 10...36) * (chance(0.5) ? 1 : -1),
                                 y: branch.y - CGFloat.random(in: 18...40))
                boltPath.addLine(to: branch)
            }
        }
        bolt.path = boltPath
        bolt.fillColor = nil
        bolt.strokeColor = cg(0xFFFFFF, 0.95)
        bolt.lineWidth = 2
        bolt.lineJoin = .round
        bolt.shadowColor = cg(0xB3C7FF)
        bolt.shadowRadius = 9
        bolt.shadowOpacity = 1
        bolt.shadowOffset = .zero
        instant {
            bolt.opacity = 0
            bolt.zPosition = 3
            root.addSublayer(bolt)
        }
        let show = CAKeyframeAnimation(keyPath: "opacity")
        show.values = [0, 1, 0.25, 0.9, 0]
        show.keyTimes = [0, 0.06, 0.2, 0.3, 1]
        show.duration = 0.6
        bolt.add(show, forKey: "bolt")
        after(0.8) {
            instant {
                flash.removeFromSuperlayer()
                bolt.removeFromSuperlayer()
            }
        }
    }

    // MARK: - Tuman, oq to‘zon

    private func makeFog() {
        guard let picture = ArtPack.image("hv_w_fog") else { return }
        for index in 0..<5 {
            let cloud = CALayer()
            cloud.contents = picture
            cloud.contentsGravity = .resize
            let width = CGFloat.random(in: 640...1100)
            cloud.bounds = CGRect(x: 0, y: 0, width: width, height: width * 0.375)
            let y = groundY + (size.height - groundY) * (0.08 + CGFloat(index) * 0.16)
            let direction: CGFloat = chance(0.5) ? 1 : -1
            let from = direction > 0 ? -width : size.width + width
            let to = direction > 0 ? size.width + width : -width
            cloud.position = CGPoint(x: from, y: y)
            cloud.opacity = Float.random(in: 0.14...0.26)
            let drift = CABasicAnimation(keyPath: "position.x")
            drift.fromValue = from
            drift.toValue = to
            drift.duration = Double.random(in: 150...260)
            drift.repeatCount = .infinity
            drift.timeOffset = Double.random(in: 0...drift.duration)
            cloud.add(drift, forKey: "drift")
            add(cloud, z: 44)
        }
    }

    private func makeWhiteout() {
        let veil = CALayer()
        veil.frame = CGRect(origin: .zero, size: size)
        veil.backgroundColor = cg(0xF4F8FC)
        veil.opacity = 0.05
        let gust = CABasicAnimation(keyPath: "opacity")
        gust.fromValue = 0.03
        gust.toValue = 0.11
        gust.duration = 2.6
        gust.autoreverses = true
        gust.repeatCount = .infinity
        gust.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        veil.add(gust, forKey: "gust")
        add(veil, z: 45)
    }

    // MARK: - Qish: qirov, sumalaklar, muz

    private func makeFrost() {
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0),
                       CGPoint(x: 0, y: topY), CGPoint(x: size.width, y: topY)]
        let radius = min(size.width, size.height) * 0.32
        for corner in corners {
            let frost = CAGradientLayer()
            frost.type = .radial
            frost.frame = CGRect(x: corner.x - radius, y: corner.y - radius, width: radius * 2, height: radius * 2)
            frost.colors = [cg(0xF2F7FC, 0.42), cg(0xDCE8F4, 0.16), cg(0xFFFFFF, 0)]
            frost.locations = [0, 0.45, 1]
            frost.startPoint = CGPoint(x: 0.5, y: 0.5)
            frost.endPoint = CGPoint(x: 1, y: 1)
            add(frost, z: 46)
        }
        if let crystal = ArtPack.image("hv_p_flake_crystal") {
            for corner in corners {
                for _ in 0..<5 {
                    let flake = CALayer()
                    flake.contents = crystal
                    flake.contentsGravity = .resize
                    let side = CGFloat.random(in: 14...30)
                    flake.bounds = CGRect(x: 0, y: 0, width: side, height: side)
                    let dx = CGFloat.random(in: 8...radius * 0.45) * (corner.x > 0 ? -1 : 1)
                    let dy = CGFloat.random(in: 8...radius * 0.45) * (corner.y > 0 ? -1 : 1)
                    flake.position = CGPoint(x: corner.x + dx, y: corner.y + dy)
                    flake.opacity = Float.random(in: 0.35...0.6)
                    flake.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat.random(in: 0...1)))
                    add(flake, z: 46)
                }
            }
        }
    }

    private func makeIcicles() {
        let shape = CGMutablePath()
        var x: CGFloat = 4
        var tips: [CGPoint] = []
        while x < size.width - 4 {
            let width = CGFloat.random(in: 4...9)
            let length = chance(0.15) ? CGFloat.random(in: 22...40) : CGFloat.random(in: 5...18)
            shape.move(to: CGPoint(x: x, y: topY))
            shape.addQuadCurve(to: CGPoint(x: x + width * 0.55, y: topY - length),
                               control: CGPoint(x: x + width * 0.2, y: topY - length * 0.5))
            shape.addQuadCurve(to: CGPoint(x: x + width, y: topY),
                               control: CGPoint(x: x + width * 0.85, y: topY - length * 0.45))
            shape.closeSubpath()
            if length > 16 { tips.append(CGPoint(x: x + width * 0.55, y: topY - length)) }
            x += width + CGFloat.random(in: 2...22)
        }
        shape.addRoundedRect(in: CGRect(x: 0, y: topY - 2, width: size.width, height: 4), cornerWidth: 2, cornerHeight: 2)

        let mask = CAShapeLayer()
        mask.path = shape
        mask.fillColor = whiteColor
        let ice = CAGradientLayer()
        ice.frame = CGRect(x: 0, y: 0, width: size.width, height: topY + 4)
        ice.colors = [cg(0xBFD9F2, 0.35), cg(0xEAF4FF, 0.75), cg(0xFFFFFF, 0.95)]
        ice.locations = [0, 0.7, 1]
        ice.startPoint = CGPoint(x: 0.5, y: max(0, (topY - 42) / (topY + 4)))
        ice.endPoint = CGPoint(x: 0.5, y: 1)
        ice.mask = mask
        add(ice, z: 13)

        let outline = CAShapeLayer()
        outline.contentsScale = scale
        outline.path = shape
        outline.fillColor = nil
        outline.strokeColor = cg(0x9DB8D6, 0.45)
        outline.lineWidth = 0.6
        add(outline, z: 13)

        // Sumalaklar uchidan vaqti-vaqti bilan tomchi tushadi
        guard !tips.isEmpty else { return }
        let (picture, pictureScale) = sprite("hv_w_drop")
        for tip in tips.prefix(12) {
            let cell = CAEmitterCell()
            cell.contents = picture
            cell.contentsScale = pictureScale
            cell.birthRate = Float.random(in: 0.05...0.18)
            cell.velocity = 0
            cell.yAcceleration = -520
            cell.lifetime = Float((tip.y - groundY) / 300) + 1
            cell.scale = 0.38
            cell.color = CGColor(srgbRed: 0.9, green: 0.96, blue: 1, alpha: 0.85)
            let holder = CAEmitterLayer()
            holder.emitterPosition = tip
            holder.emitterShape = .point
            holder.emitterCells = [cell]
            add(holder, z: 13)
        }
    }

    private func makeIceSheen() {
        let count = max(2, Int(size.width / 520))
        for index in 0..<count {
            let slot = size.width / CGFloat(count)
            let width = CGFloat.random(in: 120...240)
            let height = CGFloat.random(in: 6...10)
            let x = slot * CGFloat(index) + CGFloat.random(in: 10...max(11, slot - width - 10))
            let frame = CGRect(x: x, y: groundY - height * 0.15, width: width, height: height)
            let mask = CAShapeLayer()
            mask.path = CGPath(ellipseIn: CGRect(origin: .zero, size: frame.size), transform: nil)
            let ice = CAGradientLayer()
            ice.frame = frame
            ice.colors = [cg(0xA9CBEA, 0.4), cg(0xFFFFFF, 0.75), cg(0xA9CBEA, 0.35)]
            ice.startPoint = CGPoint(x: 0, y: 0.5)
            ice.endPoint = CGPoint(x: 1, y: 0.5)
            ice.mask = mask
            add(ice, z: 13)
            let glint = CAShapeLayer()
            glint.contentsScale = scale
            glint.path = CGPath(ellipseIn: CGRect(x: frame.minX + width * 0.3, y: frame.midY,
                                                 width: width * 0.22, height: 1.4), transform: nil)
            glint.fillColor = cg(0xFFFFFF, 0.9)
            let twinkle = CABasicAnimation(keyPath: "opacity")
            twinkle.fromValue = 0.2
            twinkle.toValue = 1
            twinkle.duration = Double.random(in: 1.4...2.6)
            twinkle.autoreverses = true
            twinkle.repeatCount = .infinity
            glint.add(twinkle, forKey: "twinkle")
            add(glint, z: 13)
        }
    }

    // MARK: - Quyosh, muz uchqunlari, kamalak

    private func makeSun(cold: Bool) {
        let center = CGPoint(x: size.width - 90, y: topY - 50)
        let radius = max(size.width, size.height) * 0.42
        let glow = CAGradientLayer()
        glow.type = .radial
        glow.frame = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        glow.colors = cold
            ? [cg(0xFFFFFF, 0.28), cg(0xDDEBFF, 0.09), cg(0xFFFFFF, 0)]
            : [cg(0xFFF2C2, 0.34), cg(0xFFD978, 0.1), cg(0xFFFFFF, 0)]
        glow.locations = [0, 0.3, 1]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        add(glow, z: 2)

        let rays = CAShapeLayer()
        rays.contentsScale = scale
        rays.bounds = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
        rays.position = center
        let path = CGMutablePath()
        for index in 0..<11 {
            let angle = CGFloat(index) / 11 * .pi * 2 + CGFloat.random(in: -0.1...0.1)
            let length = radius * CGFloat.random(in: 0.55...1.0)
            let spread: CGFloat = 0.035
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: cos(angle - spread) * length, y: sin(angle - spread) * length))
            path.addLine(to: CGPoint(x: cos(angle + spread) * length, y: sin(angle + spread) * length))
            path.closeSubpath()
        }
        rays.path = path
        rays.fillColor = cold ? cg(0xFFFFFF, 0.05) : cg(0xFFF1B8, 0.06)
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = -0.12
        turn.toValue = 0.12
        turn.duration = 26
        turn.autoreverses = true
        turn.repeatCount = .infinity
        turn.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        rays.add(turn, forKey: "turn")
        add(rays, z: 2)
    }

    private func makeDiamondDust() {
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .rectangle
        emitter.emitterMode = .surface
        emitter.emitterPosition = CGPoint(x: size.width / 2, y: size.height / 2)
        emitter.emitterSize = size
        let (picture, pictureScale) = sprite("hv_w_sparkle")
        let cell = CAEmitterCell()
        cell.contents = picture
        cell.contentsScale = pictureScale
        cell.birthRate = 7 * widthFactor
        cell.lifetime = 3.2
        cell.lifetimeRange = 1.4
        cell.velocity = 8
        cell.velocityRange = 6
        cell.emissionRange = .pi * 2
        cell.yAcceleration = -3
        cell.scale = 0.32
        cell.scaleRange = 0.2
        cell.spin = 0.6
        cell.spinRange = 1.2
        cell.alphaSpeed = -0.28
        cell.color = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95)
        emitter.emitterCells = [cell]
        add(emitter, z: 41)
    }

    private func makeFireflies() {
        let height = (size.height - groundY) * 0.55
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .rectangle
        emitter.emitterMode = .surface
        emitter.emitterPosition = CGPoint(x: size.width / 2, y: groundY + height / 2)
        emitter.emitterSize = CGSize(width: size.width, height: height)
        let (picture, pictureScale) = sprite("hv_w_firefly")
        let cell = CAEmitterCell()
        cell.contents = picture
        cell.contentsScale = pictureScale
        cell.birthRate = 1.8 * widthFactor
        cell.lifetime = 8
        cell.lifetimeRange = 3
        cell.velocity = 12
        cell.velocityRange = 9
        cell.emissionRange = .pi * 2
        cell.yAcceleration = 1.5
        cell.scale = 0.6
        cell.scaleRange = 0.25
        cell.alphaRange = 0.4
        cell.alphaSpeed = -0.1
        cell.color = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        emitter.emitterCells = [cell]
        add(emitter, z: 42)
    }

    private func makeRainbow() {
        let colors: [UInt32] = [0xE53935, 0xFB8C00, 0xFDD835, 0x43A047, 0x1E88E5, 0x3949AB, 0x8E24AA]
        let center = CGPoint(x: size.width * 0.3, y: groundY - size.width * 0.12)
        let outer = size.width * 0.55
        let band = max(9, size.width * 0.007)
        let rainbow = containerLayer()
        for (index, hex) in colors.enumerated() {
            let arc = CAShapeLayer()
            arc.contentsScale = scale
            let radius = outer - CGFloat(index) * band
            let path = CGMutablePath()
            path.addArc(center: center, radius: radius, startAngle: .pi * 0.12, endAngle: .pi * 0.88, clockwise: false)
            arc.path = path
            arc.fillColor = nil
            arc.strokeColor = cg(hex, 0.17)
            arc.lineWidth = band + 0.5
            rainbow.addSublayer(arc)
        }
        let breathe = CABasicAnimation(keyPath: "opacity")
        breathe.fromValue = 0.65
        breathe.toValue = 1
        breathe.duration = 14
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        rainbow.add(breathe, forKey: "breathe")
        add(rainbow, z: 3)
    }

    // MARK: - Yordamchi

    private func fade(_ layer: CALayer, to target: Float, duration: CFTimeInterval) {
        let current = layer.presentation()?.opacity ?? layer.opacity
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = current
        animation.toValue = target
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        instant { layer.opacity = target }
        layer.add(animation, forKey: "weatherFade")
    }
}
