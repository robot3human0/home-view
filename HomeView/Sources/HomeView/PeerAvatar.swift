import AppKit
import QuartzCore
import HomeViewProtocol

/// Ofisdagi hamkasbning odamchasi: ismi tepasida yozilgan, o‘zi tanlagan shapka va nimchada.
/// Faol bo‘lsa — yurib yuradi, uzoqda bo‘lsa — o‘tirib choy ichadi, band bo‘lsa — xira ko‘rinadi.
final class PeerAvatar {
    let id: String
    private(set) var info: PeerInfo
    let root = containerLayer()
    private let hopper = containerLayer()
    private let figure = containerLayer()
    private var limbs: (legLeft: CALayer, legRight: CALayer, armBack: CALayer, armFront: CALayer)?
    private let tag = containerLayer()
    private let tagBackground = CAShapeLayer()
    private let tagText = CATextLayer()
    private let flag = containerLayer()
    private let flagBackground = CAShapeLayer()
    private let flagText = CATextLayer()
    private let screenScale: CGFloat

    private(set) var position: CGPoint
    private(set) var facing: CGFloat = 1
    private(set) var sizeScale: CGFloat
    private(set) var isGone = false
    private var targetX: CGFloat
    private var pause: CGFloat = CGFloat.random(in: 1...4)
    private var walking = false
    private var sitting = false
    private var bubble: SpeechBubble?
    private var waveReadyAt: CFTimeInterval = 0
    /// O‘yin sahnasida joyida turadi (yurmaydi).
    var isStaged = false
    /// "Siz" yorlig‘i uchun.
    var isMe = false { didSet { updateTag() } }
    var flagLabel: String? { didSet { if oldValue != flagLabel { updateFlag() } } }

    init(info: PeerInfo, at point: CGPoint, scale: CGFloat, screenScale: CGFloat) {
        id = info.id
        self.info = info
        position = point
        targetX = point.x
        sizeScale = scale
        self.screenScale = screenScale
        let startTransform = CATransform3DMakeScale(scale, scale, 1)
        instant {
            root.position = point
            root.transform = startTransform
            root.zPosition = 32
            root.addSublayer(hopper)
            hopper.addSublayer(figure)
        }
        buildFigure()
        setupLabels()
        applyStatus()
    }

    // MARK: - Ko‘rinish

    private func buildFigure() {
        let style = info.avatar
        let parts = Art.workerParts(skin: style.skinColor, hatStyle: style.hat, hatColor: style.hatColor,
                                    vest: style.vestColor, tool: .none, worker: false)
        let legLeft = partLayer(parts.leg, at: CGPoint(x: -2.6, y: 11))
        let legRight = partLayer(parts.leg, at: CGPoint(x: 2.6, y: 11))
        let armBack = partLayer(parts.armBack, at: CGPoint(x: -4, y: 22))
        let armFront = partLayer(parts.armFront, at: CGPoint(x: 3, y: 22))
        let body = partLayer(parts.body, at: .zero)
        instant {
            figure.sublayers?.forEach { $0.removeFromSuperlayer() }
            for layer in [legLeft, legRight, armBack, body, armFront] { figure.addSublayer(layer) }
            setRotation(armFront, 0.15)
        }
        limbs = (legLeft, legRight, armBack, armFront)
        walking = false
    }

    private func setupLabels() {
        for (background, text, fontSize) in [(tagBackground, tagText, CGFloat(10.5)), (flagBackground, flagText, CGFloat(10))] {
            background.fillColor = cg(0x0F1B2D, 0.78)
            background.strokeColor = cg(0xFFFFFF, 0.25)
            background.lineWidth = 0.8
            background.contentsScale = screenScale
            text.font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
            text.fontSize = fontSize
            text.foregroundColor = whiteColor
            text.alignmentMode = .center
            text.contentsScale = screenScale
        }
        flagBackground.fillColor = cg(0xF57C00, 0.92)
        instant {
            tag.addSublayer(tagBackground)
            tag.addSublayer(tagText)
            tag.zPosition = 33
            flag.addSublayer(flagBackground)
            flag.addSublayer(flagText)
            flag.zPosition = 34
            flag.isHidden = true
        }
        updateTag()
    }

    /// Dunyoga qo‘shish (ism yorlig‘i alohida — u odamcha bilan birga kattalashmaydi).
    func attach(to world: CALayer) {
        instant {
            world.addSublayer(root)
            world.addSublayer(tag)
            world.addSublayer(flag)
        }
        layoutLabels()
    }

    private func pill(_ background: CAShapeLayer, _ text: CATextLayer, string: String, fontSize: CGFloat) {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let size = (string as NSString).size(withAttributes: [.font: font])
        let width = ceil(size.width) + 14
        let height: CGFloat = 17
        instant {
            background.path = CGPath(roundedRect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
                                     cornerWidth: height / 2, cornerHeight: height / 2, transform: nil)
            text.string = string
            text.bounds = CGRect(x: 0, y: 0, width: width, height: ceil(size.height))
            text.position = .zero
        }
    }

    private func updateTag() {
        var label = isMe ? "Siz" : info.name
        if !info.team.isEmpty && !isMe { label += " · \(info.team)" }
        switch info.status {
        case .away: label = "☕ " + label
        case .busy: label = "🔕 " + label
        default: break
        }
        pill(tagBackground, tagText, string: label, fontSize: 10.5)
    }

    private func updateFlag() {
        if let flagLabel {
            pill(flagBackground, flagText, string: flagLabel, fontSize: 10)
            instant { flag.isHidden = false }
        } else {
            instant { flag.isHidden = true }
        }
    }

    private func layoutLabels() {
        let top = position.y + 46 * sizeScale
        tag.position = CGPoint(x: position.x, y: top + 10)
        flag.position = CGPoint(x: position.x, y: top + 30)
        if let current = bubble {
            if current.isAlive {
                current.layer.position = CGPoint(x: position.x, y: top + (flag.isHidden ? 34 : 54))
            } else {
                bubble = nil
            }
        }
    }

    // MARK: - Ma’lumot yangilanishi

    func update(info newInfo: PeerInfo) {
        let styleChanged = newInfo.avatar != info.avatar
        info = newInfo
        if styleChanged { buildFigure() }
        updateTag()
        applyStatus()
    }

    func setScale(_ scale: CGFloat) {
        guard abs(scale - sizeScale) > 0.001 else { return }
        sizeScale = scale
        root.transform = CATransform3DMakeScale(facing * scale, scale, 1)
    }

    private func applyStatus() {
        let away = info.status == .away && !isStaged
        if away != sitting {
            sitting = away
            stopWalking()
            guard let limbs else { return }
            instant {
                setRotation(limbs.legLeft, away ? 1.35 : 0)
                setRotation(limbs.legRight, away ? 1.2 : 0)
                figure.position = away ? CGPoint(x: 0, y: -8) : .zero
            }
        }
        root.opacity = info.status == .busy ? 0.55 : 1
        tag.opacity = info.status == .busy ? 0.7 : 1
    }

    // MARK: - Harakat

    var hitRect: CGRect {
        CGRect(x: position.x - 11 * sizeScale, y: position.y - 2, width: 22 * sizeScale, height: 46 * sizeScale)
    }

    var headTop: CGPoint {
        CGPoint(x: position.x, y: position.y + 46 * sizeScale)
    }

    var handPoint: CGPoint {
        CGPoint(x: position.x + facing * 5 * sizeScale, y: position.y + 34 * sizeScale)
    }

    func place(at point: CGPoint) {
        position = point
        targetX = point.x
        instant {
            root.position = point
        }
        layoutLabels()
    }

    func face(_ direction: CGFloat) {
        let newFacing: CGFloat = direction >= 0 ? 1 : -1
        guard newFacing != facing else { return }
        facing = newFacing
        let scale = sizeScale
        instant { root.transform = CATransform3DMakeScale(newFacing * scale, scale, 1) }
    }

    func tick(dt: CGFloat, world: SnowWorld) {
        guard !isGone else { return }
        if !isStaged && info.status != .away {
            if pause > 0 {
                pause -= dt
                if pause <= 0 {
                    // Yangi manzil: hozirgi joyidan uncha uzoq emas
                    targetX = clamp(position.x + CGFloat.random(in: -320...320), 40, world.size.width - 40)
                    face(targetX >= position.x ? 1 : -1)
                    startWalking()
                }
            } else {
                let dx = targetX - position.x
                let speed: CGFloat = (info.status == .busy ? 22 : 42) * sizeScale.squareRoot()
                let step = speed * dt
                if abs(dx) <= step {
                    position.x = targetX
                    stopWalking()
                    pause = CGFloat.random(in: 2.5...8)
                } else {
                    position.x += dx > 0 ? step : -step
                }
            }
        }
        position.y = world.groundSurface(atX: position.x)
        root.position = position
        layoutLabels()
    }

    private func startWalking() {
        guard !walking, !sitting, let limbs else { return }
        walking = true
        swingForever(limbs.legLeft, amplitude: 0.45, half: 0.22, key: "walk")
        swingForever(limbs.legRight, amplitude: -0.45, half: 0.22, key: "walk")
        swingForever(limbs.armBack, amplitude: -0.35, half: 0.22, key: "walk")
        bounce(hopper, height: 1.1, duration: 0.44, repeats: .infinity, key: "walk")
    }

    private func stopWalking() {
        guard walking, let limbs else { return }
        walking = false
        for layer in [limbs.legLeft, limbs.legRight, limbs.armBack, hopper] {
            layer.removeAnimation(forKey: "walk")
        }
    }

    /// To‘xtab, qo‘l silkitadi.
    func wave() {
        let now = CACurrentMediaTime()
        guard now >= waveReadyAt, let limbs else { return }
        waveReadyAt = now + 1.2
        let hello = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        hello.values = [-0.4, -2.7, -2.2, -2.7, -2.2, -0.4]
        hello.keyTimes = [0, 0.2, 0.4, 0.6, 0.8, 1]
        hello.duration = 1.0
        limbs.armBack.add(hello, forKey: "wave")
    }

    /// Qor (suv, barg...) koptok otish harakati.
    func throwMotion() {
        guard let limbs else { return }
        let swing = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        swing.values = [0.15, -2.6, 0.9, 0.15]
        swing.keyTimes = [0, 0.45, 0.64, 1]
        swing.duration = 0.55
        limbs.armFront.add(swing, forKey: "throw")
    }

    func hop() {
        bounce(hopper, height: 14, duration: 0.34, repeats: 1, key: "hop")
    }

    /// Koptok tekkanda chayqaladi.
    func flinch() {
        let shake = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        shake.values = [0, -0.25, 0.18, 0]
        shake.duration = 0.3
        figure.add(shake, forKey: "flinch")
    }

    func say(_ text: String, in world: SnowWorld, duration: TimeInterval = 3) {
        bubble?.dismiss()
        let newBubble = SpeechBubble(text: text, scale: world.scale)
        instant { world.root.addSublayer(newBubble.layer) }
        bubble = newBubble
        layoutLabels()
        newBubble.show(for: duration)
    }

    /// O‘yinda chiqib ketganda xiralashadi.
    func setDimmed(_ dimmed: Bool) {
        root.opacity = dimmed ? 0.35 : (info.status == .busy ? 0.55 : 1)
    }

    // MARK: - Sport sahnasi uchun

    /// Yangi joy. Joriy CATransaction ichida chaqirilsa — o‘sha davomiylikda silliq siljiydi.
    func move(to point: CGPoint) {
        position = point
        targetX = point.x
        root.position = point
        layoutLabels()
    }

    /// Sahnada maydon ustida chizilishi uchun chuqurlik (yorliqlar ham birga ko‘tariladi).
    func setStageDepth(_ z: CGFloat) {
        instant {
            root.zPosition = z
            tag.zPosition = z + 1
            flag.zPosition = z + 2
        }
    }

    /// Yugurish (oyoqlar harakati).
    func setRunning(_ running: Bool) {
        if running {
            startWalking()
        } else {
            stopWalking()
        }
    }

    /// Arqon tortishda orqaga engashish.
    func lean(_ angle: CGFloat) {
        instant { setRotation(figure, angle) }
    }

    /// Ikkala qo‘l oldinga — arqonni ushlab turibdi.
    func holdRope() {
        guard let limbs else { return }
        instant {
            setRotation(limbs.armFront, 1.25)
            setRotation(limbs.armBack, 1.1)
        }
    }

    /// Penaltida to‘pni tepish.
    func kick() {
        guard let limbs else { return }
        let swing = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        swing.values = [0, -0.7, 1.0, 0]
        swing.keyTimes = [0, 0.4, 0.65, 1]
        swing.duration = 0.45
        limbs.legRight.add(swing, forKey: "kick")
    }

    /// Darvozabon yon tomonga sakraydi (direction: -1 chapga, 1 o‘ngga).
    /// Chaqiruvchi CATransaction davomiyligini belgilaydi.
    func dive(_ direction: CGFloat) {
        let angle: CGFloat = -direction * facing * 1.2
        setRotation(figure, angle)
        guard let limbs else { return }
        setRotation(limbs.armFront, 2.6)
        setRotation(limbs.armBack, 2.4)
    }

    /// Sakrash, engashish, qo‘llarni oddiy holatga qaytarish.
    func resetPose() {
        instant {
            setRotation(figure, 0)
            figure.position = .zero
            if let limbs {
                setRotation(limbs.armFront, 0.15)
                setRotation(limbs.armBack, 0)
            }
        }
    }

    func setVisible(_ visible: Bool) {
        instant {
            root.isHidden = !visible
            tag.isHidden = !visible
            flag.isHidden = !visible || flagLabel == nil
        }
        if !visible { bubble?.dismiss() }
    }

    func remove() {
        guard !isGone else { return }
        isGone = true
        bubble?.dismiss()
        instant {
            root.removeFromSuperlayer()
            tag.removeFromSuperlayer()
            flag.removeFromSuperlayer()
        }
    }
}
