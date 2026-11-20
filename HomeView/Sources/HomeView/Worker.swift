import AppKit
import QuartzCore

/// To‘q sariq nimchali qor tozalovchi ishchi.
///
/// Holat mashinasi:
///   walk → (yetib keldi) → idle → (vazifa) → shovel / build / leave
///   o‘yin rejimida: knocked (yiqildi) → angry (qor otadi) → idle
///   qorbolasi buzilsa: react (achinadi) → qayta yasaydi / guarding (qo‘riqlaydi) / angry (javob qaytaradi)
///
/// Qatlamlar: root (yo‘nalish) → hopper (sakrash) → figure (yiqilish) → oyoq, qo‘l, gavda.
/// Oyoq-qo‘l harakatini Core Animation o‘zi chizadi; mantiq faqat sekundiga 20 marta yangi joy beradi.
final class Worker {
    enum Mode { case walk, shovel, build, idle, angry, knocked, leave, guarding }

    static let idlePhrases = [
        "Qor ko‘p-ku bugun!", "Choy ichamizmi?", "Kurakni bering!", "Sovuq-a...",
        "Ish ko‘p, vaqt oz", "Mashina qachon keladi?", "Qo‘llarim muzladi", "Qor — baraka!"
    ]
    static let angryPhrases = [
        "Hey!", "Ana senga!", "Ol-a!", "To‘xta, hozir!", "Shunaqami?!", "Qochma!", "Endi menga navbat!"
    ]
    static let greetPhrases = ["Salom!", "Assalomu alaykum!", "Qalaysiz?", "Ishlar yaxshimi?"]
    static let ticklePhrases = ["Hi-hi, qitiqlamang!", "Ishim ko‘p!", "Nima kerak?", "Ha-ha-ha!", "Vey, qo‘ying!"]
    /// Kurak bilan bitta to‘liq harakat davomiyligi va qor otiladigan payt.
    private static let shovelCycle: CGFloat = 1.13
    private static let shovelFlingAt: CGFloat = 0.66

    private(set) var mode: Mode = .idle
    private(set) var facing: CGFloat = 1
    private(set) var position: CGPoint = .zero
    private(set) var isGone = false
    /// O‘lcham (sozlamadagi "Ishchilar" slayderi). 1 — asl bo‘y (~40 pt).
    private(set) var sizeScale: CGFloat = 1
    var targetX: CGFloat = 0
    var walkSpeed: CGFloat = CGFloat.random(in: 46...62)
    var timer: CGFloat = 0
    var hoppedForPlow = false
    private var throwsLeft = 0
    private var throwCooldown: CGFloat = 0
    private var shovelPhase: CGFloat = 0
    private var flung = false
    private var onArrive: (() -> Void)?
    private var bubble: SpeechBubble?
    private var walking = false
    /// Ish rejimida (o‘yinsiz) javob qaytaryaptimi — qorbolasi qayta-qayta buzilganda.
    private(set) var retaliating = false
    private var lastWave: CFTimeInterval = 0
    private var tickleTimes: [CFTimeInterval] = []
    private var lastWarning: CFTimeInterval = 0

    let root = containerLayer()
    private let hopper = containerLayer()
    private let figure = containerLayer()
    private let legLeft: CALayer
    private let legRight: CALayer
    private let armBack: CALayer
    private let armFront: CALayer
    private let shovel: CALayer
    private let brows: CALayer
    private let blush: CALayer
    private let body: CALayer

    init(at point: CGPoint, scale: CGFloat, theme: SeasonTheme) {
        let skins: [UInt32] = [0xF1C27D, 0xE0AC69, 0xC68642, 0xFFDBAC]
        let parts = Art.workerParts(skin: skins.randomElement() ?? 0xF1C27D, hatStyle: theme.workerHat,
                                    hatColor: theme.workerHatColors.randomElement() ?? 0x1E3A5F,
                                    vest: 0xF57C00, tool: theme.tool)
        legLeft = partLayer(parts.leg, at: CGPoint(x: -2.6, y: 11))
        legRight = partLayer(parts.leg, at: CGPoint(x: 2.6, y: 11))
        armBack = partLayer(parts.armBack, at: CGPoint(x: -4, y: 22))
        armFront = partLayer(parts.armFront, at: CGPoint(x: 3, y: 22))
        shovel = partLayer(parts.shovel, at: parts.armFront.pivotInBounds)
        brows = partLayer(parts.brows, at: .zero)
        blush = partLayer(parts.blush, at: .zero)
        body = partLayer(parts.body, at: .zero)
        position = point
        sizeScale = scale
        let startTransform = CATransform3DMakeScale(scale, scale, 1)

        instant {
            root.position = point
            root.transform = startTransform
            root.zPosition = 30
            root.addSublayer(hopper)
            hopper.addSublayer(figure)
            for layer in [legLeft, legRight, armBack, body, blush, brows, armFront] {
                figure.addSublayer(layer)
            }
            armFront.addSublayer(shovel)
            brows.isHidden = true
            blush.isHidden = true
            setRotation(armFront, 0.35)
        }
    }

    // MARK: - Holat

    var hitRect: CGRect {
        CGRect(x: position.x - 10 * sizeScale, y: position.y - 2, width: 20 * sizeScale, height: 42 * sizeScale)
    }

    var handPoint: CGPoint {
        CGPoint(x: position.x + facing * 5 * sizeScale, y: position.y + 34 * sizeScale)
    }

    /// Kurak yetadigan masofa (oyoqdan oldinga).
    var reach: CGFloat { 14 * sizeScale }

    var headTop: CGPoint {
        CGPoint(x: position.x, y: position.y + 44 * sizeScale)
    }

    /// O‘lcham o‘zgarganda: Core Animation silliq kattalashtiradi yoki kichraytiradi.
    func setScale(_ scale: CGFloat) {
        guard abs(scale - sizeScale) > 0.001 else { return }
        sizeScale = scale
        root.transform = CATransform3DMakeScale(facing * scale, scale, 1)
    }

    var isAvailable: Bool { mode != .knocked && mode != .leave && !isGone }

    func face(_ direction: CGFloat) {
        let newFacing: CGFloat = direction >= 0 ? 1 : -1
        guard newFacing != facing else { return }
        facing = newFacing
        let scale = sizeScale
        instant { root.transform = CATransform3DMakeScale(newFacing * scale, scale, 1) }
    }

    // MARK: - Buyruqlar

    func walk(to x: CGFloat, then done: (() -> Void)? = nil) {
        stopWork()
        targetX = x
        onArrive = done
        mode = .walk
        face(x >= position.x ? 1 : -1)
        startWalkAnimation()
    }

    func leave(to x: CGFloat) {
        walk(to: x)
        onArrive = nil
        mode = .leave
    }

    func rest(seconds: CGFloat) {
        stopWork()
        stopWalkAnimation()
        mode = .idle
        timer = seconds
    }

    func startShoveling(duration: CGFloat) {
        stopWalkAnimation()
        stopWork()
        mode = .shovel
        timer = duration
        shovelPhase = 0
        flung = false
        let dig = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        dig.values = [0.35, 0.95, 0.95, -2.0, 0.35, 0.35]
        dig.keyTimes = [0, 0.248, 0.319, 0.584, 0.779, 1]
        dig.duration = CFTimeInterval(Worker.shovelCycle)
        dig.repeatCount = .infinity
        armFront.add(dig, forKey: "work")
    }

    func startBuilding() {
        stopWalkAnimation()
        stopWork()
        mode = .build
        instant { shovel.isHidden = true }
        let push = CABasicAnimation(keyPath: "transform.rotation.z")
        push.fromValue = 1.3
        push.toValue = 0.6
        push.duration = 0.25
        push.autoreverses = true
        push.repeatCount = .infinity
        armFront.add(push, forKey: "work")
        bounce(hopper, height: -1.5, duration: 0.5, repeats: .infinity, key: "work")
    }

    func stopBuilding() {
        let wasBuilding = mode == .build
        stopWork()
        if wasBuilding {
            mode = .idle
            timer = 1
        }
    }

    func hop() {
        guard mode != .knocked else { return }
        bounce(hopper, height: 18, duration: 0.38, repeats: 1, key: "hop")
    }

    func knockDown(_ game: SnowWorld) {
        guard isAvailable else { return }
        stopWork()
        stopWalkAnimation()
        armFront.removeAnimation(forKey: "throw")
        mode = .knocked
        timer = 1.6
        let angle = CGFloat.pi / 2 * 0.92
        instant { setRotation(figure, angle) }
        let fall = CABasicAnimation(keyPath: "transform.rotation.z")
        fall.fromValue = 0
        fall.toValue = angle
        fall.duration = 0.18
        figure.add(fall, forKey: "fall")
        say(["Voy!", "Uf!", "Ay-yay!", "Ehtiyot bo‘l!"].randomElement() ?? "Voy!", in: game)
    }

    func becomeAngry(throws count: Int, game: SnowWorld, force: Bool = false) {
        guard mode != .leave, !isGone, GameState.shared.playMode || force else { return }
        retaliating = !GameState.shared.playMode
        throwsLeft = max(throwsLeft, count)
        if mode == .knocked { return } // turgandan keyin jahli chiqadi
        stopWork()
        stopWalkAnimation()
        mode = .angry
        instant {
            shovel.isHidden = true
            brows.isHidden = false
            blush.isHidden = false
        }
        throwCooldown = CGFloat.random(in: 0.4...0.9)
        say(Worker.angryPhrases.randomElement() ?? "Hey!", in: game)
        bounce(hopper, height: 4, duration: 0.14, repeats: 2, key: "stomp")
    }

    func calm(_ game: SnowWorld, phrase: String?) {
        figure.removeAllAnimations()
        armFront.removeAllAnimations()
        hopper.removeAllAnimations()
        for layer in [legLeft, legRight, armBack] {
            layer.removeAllAnimations()
        }
        instant {
            setRotation(figure, 0)
            setRotation(armFront, 0.35)
            brows.isHidden = true
            blush.isHidden = true
            shovel.isHidden = false
        }
        throwsLeft = 0
        walking = false
        retaliating = false
        mode = .idle
        timer = CGFloat.random(in: 1...2)
        if let phrase { say(phrase, in: game) }
    }

    // MARK: - Sichqoncha va qorbola voqealariga munosabat

    /// Sichqoncha ustiga kelganda qo‘l silkitadi (har 5 sekundda ko‘pi bilan bir marta).
    func wave(in game: SnowWorld) {
        let now = CACurrentMediaTime()
        guard now - lastWave > 5, mode == .idle || mode == .walk || mode == .shovel else { return }
        lastWave = now
        let hello = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        hello.values = [-0.4, -2.7, -2.2, -2.7, -2.2, -0.4]
        hello.keyTimes = [0, 0.2, 0.4, 0.6, 0.8, 1]
        hello.duration = 1.0
        armBack.add(hello, forKey: "wave")
        if chance(0.5) { say(Worker.greetPhrases.randomElement() ?? "Salom!", in: game, duration: 1.6) }
    }

    /// Sichqoncha bilan bosilganda: kuladi va sakraydi. Tez-tez bossangiz — jahli chiqadi.
    /// true qaytarsa — ishchining sabri tugadi.
    @discardableResult
    func tickle(in game: SnowWorld) -> Bool {
        guard isAvailable else { return false }
        let now = CACurrentMediaTime()
        tickleTimes = tickleTimes.filter { now - $0 < 4 } + [now]
        if tickleTimes.count >= 4 {
            tickleTimes.removeAll()
            say(["Bas qiling!", "Endi yetar!", "Hazilni bilmaysiz-a?"].randomElement() ?? "Bas qiling!", in: game)
            bounce(hopper, height: 4, duration: 0.14, repeats: 2, key: "stomp")
            return true
        }
        hop()
        say(Worker.ticklePhrases.randomElement() ?? "Hi-hi!", in: game, duration: 1.6)
        return false
    }

    /// Qorbola buzilganini ko‘rganda: o‘sha tomonga qarab, gapiradi va oyog‘ini depsinadi.
    func react(toward x: CGFloat, phrase: String, game: SnowWorld) {
        guard isAvailable, mode != .angry, mode != .build else { return }
        if mode == .guarding { stopGuarding() }
        rest(seconds: CGFloat.random(in: 1.2...2.0))
        face(x >= position.x ? 1 : -1)
        say(phrase, in: game)
        bounce(hopper, height: 4, duration: 0.14, repeats: 2, key: "stomp")
    }

    /// Qorbola yonida qo‘riqchi bo‘lib turadi: kurakni ko‘tarib, tashqariga qaraydi.
    func startGuarding(facing direction: CGFloat, duration: CGFloat) {
        stopWalkAnimation()
        stopWork()
        mode = .guarding
        timer = duration
        face(direction)
        instant { setRotation(armFront, -1.0) }
        let ready = CABasicAnimation(keyPath: "transform.rotation.z")
        ready.fromValue = -1.2
        ready.toValue = -0.8
        ready.duration = 0.6
        ready.autoreverses = true
        ready.repeatCount = .infinity
        armFront.add(ready, forKey: "work")
    }

    func stopGuarding() {
        guard mode == .guarding else { return }
        stopWork()
        mode = .idle
        timer = 1
    }

    /// Qo‘riqchi ogohlantiradi (har 3 sekundda bir marta).
    func warn(in game: SnowWorld) {
        let now = CACurrentMediaTime()
        guard mode == .guarding, now - lastWarning > 3 else { return }
        lastWarning = now
        say(["Tegma!", "Uzoqroq!", "Qorbolaga tegmang!", "Ko‘rib turibman!"].randomElement() ?? "Tegma!", in: game, duration: 1.6)
    }

    /// Qo‘riqchi zarbani to‘sadi.
    func block(in game: SnowWorld) {
        hop()
        say(["Yo‘q-yo‘q!", "Qo‘ldan kelmaydi!", "Men bor ekanman, yo‘q!"].randomElement() ?? "Yo‘q-yo‘q!", in: game, duration: 1.6)
    }

    func say(_ text: String, in game: SnowWorld, duration: TimeInterval = 2.4) {
        bubble?.dismiss()
        let newBubble = SpeechBubble(text: text, scale: game.scale)
        let point = CGPoint(x: position.x, y: position.y + 8 + 42 * sizeScale)
        instant {
            newBubble.layer.position = point
            game.root.addSublayer(newBubble.layer)
        }
        newBubble.show(for: duration)
        bubble = newBubble
    }

    func remove() {
        guard !isGone else { return }
        isGone = true
        bubble?.dismiss()
        instant { root.removeFromSuperlayer() }
    }

    // MARK: - Har mantiqiy qadamda (sekundiga 20 marta)

    func update(dt: CGFloat, game: SnowWorld) {
        guard !isGone else { return }

        switch mode {
        case .walk, .leave:
            let dx = targetX - position.x
            let step = walkSpeed * sizeScale.squareRoot() * dt
            if abs(dx) <= step {
                position.x = targetX
                if mode == .leave {
                    remove()
                    return
                }
                stopWalkAnimation()
                mode = .idle
                timer = 0.8
                let done = onArrive
                onArrive = nil
                done?()
            } else {
                position.x += dx > 0 ? step : -step
            }

        case .idle:
            timer -= dt
            if timer <= 0 { game.assignTask(to: self) }

        case .shovel:
            timer -= dt
            shovelPhase += dt
            if shovelPhase >= Worker.shovelCycle {
                shovelPhase -= Worker.shovelCycle
                flung = false
            }
            if !flung && shovelPhase >= Worker.shovelFlingAt {
                flung = true
                game.shovelSnow(by: self)
            }
            if timer <= 0 || game.ground.height(atX: position.x + facing * reach) < 1.2 {
                rest(seconds: CGFloat.random(in: 0.6...1.6))
            }

        case .build:
            break

        case .guarding:
            timer -= dt
            if timer <= 0 {
                stopGuarding()
                if chance(0.5) { say("Navbatchilik tugadi", in: game, duration: 1.6) }
            }

        case .angry:
            throwCooldown -= dt
            if throwCooldown <= 0 {
                if throwsLeft > 0 {
                    throwsLeft -= 1
                    throwCooldown = CGFloat.random(in: 1.1...1.9)
                    throwSnowball(game)
                } else {
                    calm(game, phrase: chance(0.4) ? "Bo‘ldi, yarashdik!" : nil)
                }
            }

        case .knocked:
            timer -= dt
            if timer <= 0 { getUp(game) }
        }

        // Yangi joy: Core Animation shu qadam davomida silliq suradi
        position.y = game.groundSurface(atX: position.x)
        root.position = position
        if let current = bubble {
            if current.isAlive {
                current.layer.position = CGPoint(x: position.x, y: position.y + 8 + 42 * sizeScale)
            } else {
                bubble = nil
            }
        }
    }

    // MARK: - Ichki animatsiyalar

    private func getUp(_ game: SnowWorld) {
        instant { setRotation(figure, 0) }
        let rise = CABasicAnimation(keyPath: "transform.rotation.z")
        rise.fromValue = CGFloat.pi / 2 * 0.92
        rise.toValue = 0
        rise.duration = 0.25
        figure.add(rise, forKey: "fall")
        mode = .idle
        timer = 0.6
        if GameState.shared.playMode {
            becomeAngry(throws: max(throwsLeft, Int.random(in: 2...3)), game: game)
        }
    }

    private func throwSnowball(_ game: SnowWorld) {
        instant { setRotation(armFront, 0.2) }
        let swing = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        swing.values = [0.35, -2.6, 0.9, 0.2]
        swing.keyTimes = [0, 0.45, 0.64, 1]
        swing.duration = 0.55
        armFront.add(swing, forKey: "throw")
        after(0.35) { [weak self, weak game] in
            guard let self, let game, self.mode == .angry else { return }
            game.crewThrow(from: self)
        }
        if chance(0.45) {
            say(Worker.angryPhrases.randomElement() ?? "Ol-a!", in: game)
        }
    }

    private func stopWork() {
        armFront.removeAnimation(forKey: "work")
        hopper.removeAnimation(forKey: "work")
        let showShovel = mode != .angry
        instant {
            setRotation(armFront, 0.35)
            if showShovel { shovel.isHidden = false }
        }
    }

    private func startWalkAnimation() {
        guard !walking else { return }
        walking = true
        swingForever(legLeft, amplitude: 0.5, half: 0.2, key: "walk")
        swingForever(legRight, amplitude: -0.5, half: 0.2, key: "walk")
        swingForever(armBack, amplitude: -0.4, half: 0.2, key: "walk")
        bounce(hopper, height: 1.2, duration: 0.4, repeats: .infinity, key: "walk")
    }

    private func stopWalkAnimation() {
        guard walking else { return }
        walking = false
        for layer in [legLeft, legRight, armBack, hopper] {
            layer.removeAnimation(forKey: "walk")
        }
    }
}
