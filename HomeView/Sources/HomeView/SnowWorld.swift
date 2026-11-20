import AppKit
import HomeViewProtocol
import QuartzCore

/// Bitta monitordagi butun "qishki dunyo".
///
/// 2.0 dagi asosiy g‘oya — ilova har kadrda hech narsa chizmaydi:
///   • yog‘ayotgan qorni CAEmitterLayer (macOS'ning Core Animation tizimi) o‘zi harakatlantiradi;
///   • oynalar ustidagi qorning o‘sishi formula bilan hisoblanadi — har bir parchani kuzatish shart emas;
///   • ishchilar, mashina va Qorbobo sekundiga 20 marta yangi joy oladi, oradagi silliq harakatni
///     Core Animation o‘zi chizadi.
/// Shuning uchun monitor qancha ko‘p va katta bo‘lsa ham, har birida qor bir xil zichlikda va
/// to‘liq Retina sifatida ko‘rinadi.
final class SnowWorld {
    private struct IncomingBall {
        let layer: CALayer
        weak var thrower: Worker?
    }

    private struct StashedSnow {
        let width: CGFloat
        let heights: [CGFloat]
        let time: TimeInterval
    }

    /// O‘rtacha qor kuchidagi parchalar soni (1440 pt enli ekran uchun, sekundiga).
    private static let baseFlakeRate: Double = 80

    let screenFrame: CGRect
    /// Shu dunyo qaysi faslda ishlayapti (fasl almashsa, dunyo qayta yaratiladi).
    let theme: SeasonTheme
    /// Asosiy monitor: ofisdagi hamkasblarning odamchalari va tarmoq o‘yinlari faqat shu yerda.
    let isPrimary: Bool
    /// Odamcha bosilganda menyu ochish uchun.
    weak var hostView: NSView?
    let size: CGSize
    let scale: CGFloat
    let root: CALayer
    let ground: Ledge

    // Oynalar ustidagi qor
    private var ledges: [CGWindowID: Ledge] = [:]
    private var stash: [CGWindowID: StashedSnow] = [:]
    private let bucketWidth: CGFloat = 64
    private var buckets: [[Ledge]] = []
    private var lastOrder: [CGWindowID] = []

    // Yog‘ayotgan qor va shamol
    private let snowEmitter = CAEmitterLayer()
    private var skyAccumulator: CGFloat = 0
    private var wind: CGFloat = 0
    private var gustOffset: CGFloat = 0
    private var gustTimer: CGFloat = 0
    private var windApplyTimer: CGFloat = 0
    private var appliedWind: CGFloat = 10_000

    // Personajlar
    private(set) var workers: [Worker] = []
    private var snowmen: [Snowman] = []
    /// Navbatda turgan qorbolalar (menyudan so‘ralgan yoki buzilgani o‘rniga).
    private var pendingSnowmen = 0
    /// Buzilgan qorbolalarning joylari — ishchilar aynan o‘sha yerda qayta yasaydi.
    private var rebuildSpots: [CGFloat] = []
    /// Qorbola buzilgandan keyingi "shoshilinch" vaqt: tezroq yasashadi.
    private var rebuildRush: CGFloat = 0
    /// So‘nggi 3 daqiqada buzilgan qorbolalar — brigadaning jahli shunga qarab ortadi.
    private var griefTimes: [CFTimeInterval] = []
    private var snowmanCooldown: CGFloat = 45
    private var crewCooldown: CGFloat = 4
    private var plows: [Snowplow] = []
    private var plowsSpawned = 0
    private var plowCooldown: CGFloat = 20
    private weak var hoveredSnowman: Snowman?
    private weak var hoveredWorker: Worker?

    // Ofis: hamkasblarning odamchalari va tarmoq o‘yini (faqat asosiy monitorda)
    private var peerAvatars: [String: PeerAvatar] = [:]
    private var stage: NetStage?

    // Slayder surilganda darhol javob berish uchun: oldingi qiymatlar
    private var appliedCrew = Settings.shared.crewCount
    private var appliedPlows = Settings.shared.plowCount
    private var appliedSnowmen = Settings.shared.snowmanCount
    private var appliedWorkerScale = Settings.shared.workerScale
    private var appliedPlowScale = Settings.shared.plowScale
    private var appliedSnowmanScale = Settings.shared.snowmanScale
    /// Slayder surilgandan keyin bir muddat brigada ko‘chada turadi — natijani ko‘rish uchun.
    private var showcaseTimer: CGFloat = 0

    // ⌥ + g‘ildirak bilan o‘lcham o‘zgartirilganda chiqadigan belgi
    private let sizeBadge = containerLayer()
    private let sizeBadgeBackground = CAShapeLayer()
    private let sizeBadgeText = CATextLayer()
    private var sizeBadgeToken = 0
    private var santa: Visitor?
    private var santaTimer: CGFloat = CGFloat.random(in: 60...180)
    private var gifts: [Gift] = []
    private var incoming: [IncomingBall] = []

    // O‘yin paneli
    private let hud = containerLayer()
    private let scoreLayer = CATextLayer()
    private let hintLayer = CATextLayer()
    private var shownPlayer = -1
    private var shownCrew = -1
    private var playMode = false
    private var redrawTimer: CGFloat = 0

    // Ob-havo: holat va uning effektlari (yomg‘ir, tuman, sumalak...)
    private(set) var weather: WeatherKind = WeatherDirector.shared.current
    private var effects: WeatherEffects?
    private var windSign: CGFloat = Bool.random() ? 1 : -1

    init(screen: NSScreen, root: CALayer, theme: SeasonTheme, isPrimary: Bool) {
        screenFrame = screen.frame
        self.theme = theme
        self.isPrimary = isPrimary
        size = screen.frame.size
        scale = screen.backingScaleFactor
        self.root = root
        let groundY = max(0, screen.visibleFrame.minY - screen.frame.minY)
        ground = Ledge(id: 0, originX: 0, baseY: groundY, width: screen.frame.width,
                       isGround: true, scale: screen.backingScaleFactor)
        ground.setColors(fill: theme.pileFill, stroke: theme.pileStroke)
        instant {
            root.addSublayer(ground.layer)
            setupSnowEmitter()
            setupHUD()
            setupSizeBadge()
        }
        let topInset = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        let weatherLayer = WeatherEffects(root: root, size: size, scale: scale, groundY: groundY,
                                          topY: size.height - topInset)
        weatherLayer.apply(weather, animated: false)
        effects = weatherLayer
        applySettings()
    }

    /// Ob-havo almashdi: zarrachalar, shamol, to‘planish va effektlar yangilanadi.
    func applyWeather(_ kind: WeatherKind, animated: Bool) {
        guard kind != weather else { return }
        weather = kind
        windSign = Bool.random() ? 1 : -1
        appliedWind = 10_000
        applySettings()
        effects?.apply(kind, animated: animated)
    }

    // MARK: - Sozlamalar

    /// Uch qatlam qor parchalarining asosiy o‘lchami (sozlamadagi koeffitsientga ko‘paytiriladi).

    func applySettings() {
        let settings = Settings.shared
        let rate = Float(settings.flakesPerSecond / SnowWorld.baseFlakeRate)
        let flakeFactor = CGFloat(settings.flakeScale)
        let weatherRate = rate * weather.profile.particles
        effects?.intensity = CGFloat(max(0.25, min(2.0, settings.snowAmount / 0.4)))
        instant {
            snowEmitter.birthRate = weatherRate
            for layerInfo in theme.layers {
                let value = layerInfo.scale * flakeFactor
                snowEmitter.setValue(value, forKeyPath: "emitterCells.\(layerInfo.name).scale")
                snowEmitter.setValue(value * 0.3, forKeyPath: "emitterCells.\(layerInfo.name).scaleRange")
            }
        }
        // O‘lchamlar: ekrandagi hamma narsa silliq kattalashadi/kichrayadi
        let snowmanFactor = CGFloat(settings.snowmanScale)
        snowmen.forEach { $0.applySizeSetting(snowmanFactor) }
        let workerFactor = CGFloat(settings.workerScale)
        workers.forEach { $0.setScale(workerFactor) }
        let plowFactor = CGFloat(settings.plowScale)
        plows.forEach { $0.setSizeSetting(plowFactor) }
        peerAvatars.values.forEach { $0.setScale(workerFactor) }

        // Slayder surilganda ekranda ko‘rsatadigan hech kim bo‘lmasa — chaqirib kelamiz
        if settings.crewCount != appliedCrew || abs(settings.workerScale - appliedWorkerScale) > 0.001 {
            showcaseTimer = 25
            if settings.workersEnabled && workers.filter({ $0.mode != .leave }).isEmpty { crewCooldown = 0 }
        }
        appliedWorkerScale = settings.workerScale
        if abs(settings.plowScale - appliedPlowScale) > 0.001 && plows.isEmpty {
            callPlow()
        }
        appliedPlowScale = settings.plowScale
        if abs(settings.snowmanScale - appliedSnowmanScale) > 0.001 && snowmen.isEmpty
            && settings.workersEnabled && pendingSnowmen == 0 {
            pendingSnowmen = 1
            showcaseTimer = 25
            crewCooldown = 0
        }
        appliedSnowmanScale = settings.snowmanScale

        // Sonlar: slayder surilishi bilan natija darhol ko‘rinsin
        if settings.crewCount > appliedCrew { crewCooldown = 0 }
        appliedCrew = settings.crewCount
        if settings.plowCount > appliedPlows && plows.count < settings.plowCount { callPlow() }
        appliedPlows = settings.plowCount
        if settings.snowmanCount > appliedSnowmen && settings.workersEnabled {
            pendingSnowmen = min(pendingSnowmen + settings.snowmanCount - appliedSnowmen,
                                 max(0, settings.snowmanCount - snowmen.count))
            crewCooldown = 0
        } else if snowmen.count > settings.snowmanCount {
            // Ortiqchalari asta eriydi (eng eskisidan boshlab)
            snowmen.prefix(snowmen.count - settings.snowmanCount).forEach { $0.melt() }
        }
        appliedSnowmen = settings.snowmanCount
    }

    private var ballFactor: CGFloat { CGFloat(Settings.shared.ballScale) }

    // MARK: - Mantiqiy qadam (sekundiga 20 marta, AppDelegate chaqiradi)

    func tick(_ dt: CGFloat) {
        updateWind(dt)
        accumulate(dt)
        updateLedges(dt)
        updateCrew(dt)
        updateSanta(dt)
        updateGifts(dt)
        for avatar in peerAvatars.values { avatar.tick(dt: dt, world: self) }
        stage?.tick(dt)
        effects?.update(dt: dt, wind: wind)
        refreshHUD()
    }

    /// Personajlar oyog‘i qo‘yiladigan balandlik (yerdagi qor ustida, biroz botib).
    func groundSurface(atX x: CGFloat) -> CGFloat {
        ground.baseY + ground.height(atX: x) * 0.8
    }

    // MARK: - Yog‘ayotgan qor (Core Animation)

    private func setupSnowEmitter() {
        // Chiziqli emitter: emissionLongitude = 0 — pastga (qatlamning -y yo‘nalishi), π — yuqoriga.
        snowEmitter.emitterShape = .line
        snowEmitter.emitterMode = .outline
        snowEmitter.emitterPosition = CGPoint(x: size.width / 2, y: size.height + 24)
        snowEmitter.emitterSize = CGSize(width: size.width + 700, height: 1)
        snowEmitter.zPosition = 40
        // O‘tmishdan boshlangandek: ilova ochilganda ekran darhol qorga to‘la bo‘ladi.
        snowEmitter.beginTime = CACurrentMediaTime() - 40
        // Zichlik ekran eniga mutanosib — har bir monitorda qor bir xil quyuqlikda.
        let widthFactor = Float(size.width / 1440)
        snowEmitter.emitterCells = theme.layers.map { flakeCell($0, widthFactor: widthFactor) }
        root.addSublayer(snowEmitter)
    }

    /// Bir "qatlam" qor parchalari: uzoqdagilari mayda va sekin, yaqindagilari yirik va tez.
    private func flakeCell(_ style: ParticleLayerStyle, widthFactor: Float) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.name = style.name
        cell.contents = style.image ?? theme.particleImage
        cell.contentsScale = style.image != nil ? ArtPack.pixelsPerPoint : Art.scale
        cell.birthRate = style.rate * widthFactor
        cell.velocity = style.velocity
        cell.velocityRange = style.velocity * 0.25
        cell.emissionLongitude = 0
        cell.emissionRange = style.emissionRange
        cell.lifetime = Float((size.height + 120) / (style.velocity * 0.7)) + 3
        cell.scale = style.scale
        cell.scaleRange = style.scale * 0.3
        cell.alphaRange = 0.2
        cell.spinRange = style.spin
        cell.color = style.color.copy(alpha: style.alpha) ?? style.color
        return cell
    }

    private func updateWind(_ dt: CGFloat) {
        let settings = Settings.shared
        let profile = weather.profile
        let base = CGFloat(settings.windStrength) * 70 + profile.windBias * windSign
        gustTimer -= dt
        if gustTimer <= 0 {
            gustTimer = CGFloat.random(in: 3...8)
            var amplitude: CGFloat = settings.windGusty ? 70 : 6
            if settings.isBlizzard { amplitude *= 1.8 }
            amplitude *= profile.gustiness
            gustOffset = CGFloat.random(in: -amplitude...amplitude)
        }
        wind += (base + gustOffset - wind) * min(1, dt * 0.6)

        // Shamol yangi tug‘ilayotgan parchalarning yo‘nalishini qiyshaytiradi —
        // shuning uchun shamol tepadan pastga "to‘lqin" bo‘lib tarqaladi.
        windApplyTimer -= dt
        if windApplyTimer <= 0 {
            windApplyTimer = 0.5
            if abs(wind - appliedWind) > 2 {
                appliedWind = wind
                let longitude = atan2(wind, 45)
                instant {
                    for name in theme.layers.map({ $0.name }) {
                        snowEmitter.setValue(longitude, forKeyPath: "emitterCells.\(name).emissionLongitude")
                    }
                }
            }
        }
    }

    // MARK: - Qorning to‘planishi (formula bilan)

    /// Har qadamda osmondan "ko‘rinmas parchalar" tushiriladi: har biri tasodifiy x nuqtadagi
    /// eng yuqori sirtga (oyna qirrasi yoki yer) qo‘shiladi. Ko‘rinadigan qor bilan bir xil tezlikda.
    /// Yirik parchalar ko‘proq qor olib keladi (lekin chiziqli emas — aks holda ekran tez to‘lib qoladi).
    private var flakeVolume: CGFloat { CGFloat(Settings.shared.flakeScale).squareRoot() }

    private func accumulate(_ dt: CGFloat) {
        let profile = weather.profile
        let rate = CGFloat(Settings.shared.flakesPerSecond) * size.width / 1440 * CGFloat(profile.particles)
        guard rate > 0, profile.accumulation > 0 else {
            skyAccumulator = 0
            return
        }
        skyAccumulator += rate * dt
        let count = min(Int(skyAccumulator), 400)
        skyAccumulator -= CGFloat(Int(skyAccumulator))
        for _ in 0..<count {
            let x = CGFloat.random(in: 0..<size.width)
            let r = CGFloat.random(in: 0...1)
            let flakeSize = 2.2 + r * r * 5.5
            topSurface(atX: x)?.deposit(atX: x, amount: flakeSize * 0.32 * flakeVolume * theme.accumulation * profile.accumulation)
        }
    }

    /// x nuqtadagi eng yuqori qor sirti (ixtiyoriy: `limit` dan pastda, `ignore` dan tashqari).
    private func topSurface(atX x: CGFloat, below limit: CGFloat = .greatestFiniteMagnitude,
                            ignore: CGWindowID? = nil) -> Ledge? {
        var best = -CGFloat.greatestFiniteMagnitude
        var result: Ledge?
        if let s = ground.surfaceY(atX: x), s < limit {
            best = s
            result = ground
        }
        let bucket = Int(floor(x / bucketWidth))
        if bucket >= 0 && bucket < buckets.count {
            for ledge in buckets[bucket] where ledge.id != ignore {
                if let s = ledge.surfaceY(atX: x), s < limit, s > best {
                    best = s
                    result = ledge
                }
            }
        }
        return result
    }

    func depositGround(aroundX x: CGFloat, amount: CGFloat) {
        var cx = x - 30
        while cx <= x + 30 {
            ground.deposit(atX: cx, amount: amount * 0.25)
            cx += 6
        }
    }

    private func updateLedges(_ dt: CGFloat) {
        let melting = !Settings.shared.isSnowing
        for ledge in [ground] + Array(ledges.values) {
            let overflow = ledge.relax()
            if overflow.left > 0 {
                let x = ledge.originX - 2
                topSurface(atX: x, below: ledge.baseY - 1, ignore: ledge.id)?.deposit(atX: x, amount: overflow.left)
            }
            if overflow.right > 0 {
                let x = ledge.originX + ledge.width + 2
                topSurface(atX: x, below: ledge.baseY - 1, ignore: ledge.id)?.deposit(atX: x, amount: overflow.right)
            }
            if melting { ledge.melt(dt * (ledge.isGround ? 0.5 : 0.35)) }
        }
        redrawTimer += dt
        if redrawTimer >= 0.2 {
            redrawTimer = 0
            for ledge in [ground] + Array(ledges.values) {
                ledge.redrawIfNeeded(sceneWidth: size.width)
            }
        }
    }

    /// Tokchadagi qorning bir qismini (fraction: 0...1) pastga to‘kadi: ko‘rinadigan "ko‘chki"
    /// va qorning o‘zi pastdagi sirtlarga qo‘shiladi.
    private func dropSnow(from ledge: Ledge, fraction: CGFloat) {
        var total: CGFloat = 0
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var drops: [(x: CGFloat, amount: CGFloat)] = []
        for i in ledge.heights.indices where ledge.heights[i] > 0.4 {
            let amount = ledge.heights[i] * fraction
            ledge.heights[i] -= amount
            guard ledge.visible[i] else { continue }
            let x = ledge.columnX(i)
            guard x > -10, x < size.width + 10 else { continue }
            total += amount
            minX = min(minX, x)
            maxX = max(maxX, x)
            if i % 3 == 0 { drops.append((x, amount * 3)) }
        }
        ledge.dirty = true
        guard total > 2 else { return }

        let baseY = ledge.baseY
        let fallHeight = max(baseY - ground.baseY, 20)
        let lifetime = Float(clamp(sqrt(2 * fallHeight / 700), 0.4, 2.2))
        burst(at: CGPoint(x: (minX + maxX) / 2, y: baseY + 4), lineWidth: max(4, maxX - minX),
              count: min(180, Int(total / 2) + 6), velocity: 25, velocityRange: 25,
              longitude: .pi, range: .pi * 0.9, gravity: -700, lifetime: lifetime, scale: 0.42)
        let id = ledge.id
        after(Double(lifetime) * 0.6) { [weak self] in
            guard let self else { return }
            for drop in drops {
                self.topSurface(atX: drop.x, below: baseY - 1, ignore: id)?.deposit(atX: drop.x, amount: drop.amount * 0.8)
            }
        }
    }

    // MARK: - Oynalar

    /// WindowTracker ma’lumoti bilan oynalar ustidagi tokchalarni yangilaydi.
    /// true qaytarsa — qaysidir oyna siljidi (kuzatuv tezlashtiriladi).
    func applyWindows(_ windows: [TrackedWindow], now: TimeInterval) -> Bool {
        guard Settings.shared.snowOnWindows else {
            if !ledges.isEmpty {
                for ledge in ledges.values {
                    dropSnow(from: ledge, fraction: 1)
                    instant { ledge.layer.removeFromSuperlayer() }
                }
                ledges.removeAll()
                rebuildBuckets()
            }
            return false
        }

        let origin = screenFrame.origin
        let local: [(TrackedWindow, CGRect)] = windows.map { ($0, $0.frame.offsetBy(dx: -origin.x, dy: -origin.y)) }
        var seen = Set<CGWindowID>()
        var moved = false

        for (window, frame) in local {
            let top = frame.maxY
            guard top > 0, top < size.height - 2, frame.maxX > 0, frame.minX < size.width else { continue }
            seen.insert(window.id)

            if let ledge = ledges[window.id] {
                let dx = frame.minX - ledge.originX
                let dy = top - ledge.baseY
                if abs(frame.width - ledge.width) > 1.5 {
                    // Oyna o‘lchami o‘zgardi — qor to‘kiladi
                    dropSnow(from: ledge, fraction: 1)
                    ledge.resize(originX: frame.minX, baseY: top, width: frame.width)
                    moved = true
                } else if abs(dx) > 0.5 || abs(dy) > 0.5 {
                    // Sekin siljisa qor birga ketadi, keskin silkitilsa to‘kiladi
                    let elapsed = max(now - ledge.lastSeen, 1.0 / 60)
                    let speed = hypot(dx, dy) / CGFloat(elapsed)
                    if speed > 1500 {
                        dropSnow(from: ledge, fraction: 1)
                    } else if speed > 700 {
                        dropSnow(from: ledge, fraction: 0.3)
                    }
                    ledge.move(originX: frame.minX, baseY: top)
                    moved = true
                }
                ledge.lastSeen = now
            } else {
                let ledge = Ledge(id: window.id, originX: frame.minX, baseY: top, width: frame.width,
                                  isGround: false, scale: scale)
                ledge.setColors(fill: theme.pileFill, stroke: theme.pileStroke)
                if let saved = stash.removeValue(forKey: window.id),
                   abs(saved.width - frame.width) < 1.5,
                   saved.heights.count == ledge.heights.count {
                    ledge.heights = saved.heights
                    ledge.dirty = true
                }
                ledge.lastSeen = now
                ledges[window.id] = ledge
                instant { root.addSublayer(ledge.layer) }
                moved = true
            }
        }

        let gone = ledges.keys.filter { !seen.contains($0) }
        if !gone.isEmpty {
            moved = true
            // Bir vaqtda ko‘p oyna yo‘qolsa — bu Space almashishi; qorni saqlab qo‘yamiz.
            let massVanish = gone.count >= 3
            for id in gone {
                guard let ledge = ledges.removeValue(forKey: id) else { continue }
                if massVanish {
                    if ledge.total > 1 {
                        stash[id] = StashedSnow(width: ledge.width, heights: ledge.heights, time: now)
                    }
                } else {
                    dropSnow(from: ledge, fraction: 1)
                }
                instant { ledge.layer.removeFromSuperlayer() }
            }
        }
        stash = stash.filter { now - $0.value.time < 600 }

        let order = local.map { $0.0.id }
        if moved || order != lastOrder {
            lastOrder = order
            updateVisibility(local)
            rebuildBuckets()
        }
        return moved
    }

    /// Har bir oyna qirrasining qaysi qismini oldidagi oynalar yopib turganini hisoblaydi.
    private func updateVisibility(_ local: [(TrackedWindow, CGRect)]) {
        for (window, frame) in local {
            guard let ledge = ledges[window.id] else { continue }
            let y = frame.maxY + 3
            var covered: [(CGFloat, CGFloat)] = []
            for (other, otherFrame) in local where other.order < window.order {
                if otherFrame.minY <= y && otherFrame.maxY >= y {
                    covered.append((otherFrame.minX, otherFrame.maxX))
                }
            }
            ledge.setCovered(covered)
        }
    }

    /// Ekran 64 pt kenglikdagi "yo‘laklar"ga bo‘linadi: har bir nuqta faqat o‘z yo‘lagidagi oynalar bilan tekshiriladi.
    private func rebuildBuckets() {
        let count = max(1, Int(ceil(size.width / bucketWidth)))
        var result = Array(repeating: [Ledge](), count: count)
        for ledge in ledges.values {
            let first = max(0, Int(floor(ledge.originX / bucketWidth)))
            let last = min(count - 1, Int(floor((ledge.originX + ledge.width) / bucketWidth)))
            guard first <= last else { continue }
            for i in first...last { result[i].append(ledge) }
        }
        buckets = result
    }

    // MARK: - Ishchilar brigadasi

    private func updateCrew(_ dt: CGFloat) {
        let settings = Settings.shared
        let maxCrew = settings.crewCount
        let average = ground.average
        crewCooldown -= dt
        snowmanCooldown -= dt
        plowCooldown -= dt
        rebuildRush = max(0, rebuildRush - dt)
        showcaseTimer = max(0, showcaseTimer - dt)
        let now = CACurrentMediaTime()
        griefTimes = griefTimes.filter { now - $0 < 180 }

        let active = workers.filter { $0.mode != .leave }
        if maxCrew > 0 {
            // Ish bor ekan (qor yog‘yapti, yerda qor bor, qorbola kutilmoqda...) — butun brigada ko‘chada
            let unfinished = snowmen.filter { $0.stage < 4 }.count
            let hasSnowWork = average > 3 || settings.isSnowing
            let hasBuildWork = pendingSnowmen > 0 || unfinished > 0
            let hasEvents = !griefTimes.isEmpty || !plows.isEmpty
            let showingOff = playMode || showcaseTimer > 0
            let busy = hasSnowWork || hasBuildWork || hasEvents || showingOff
            let wanted = busy ? maxCrew : 0
            if active.count < wanted && crewCooldown <= 0 {
                spawnWorker()
                crewCooldown = CGFloat.random(in: 1.2...2.6)
            } else if active.count > maxCrew, let extra = active.last {
                sendHome(extra)
            }
        } else {
            for worker in active { sendHome(worker) }
            snowmen.filter { $0.stage == 0 }.forEach { $0.remove() }
            pendingSnowmen = 0
        }

        updatePlows(dt, average: average)

        for worker in workers { worker.update(dt: dt, game: self) }
        workers.removeAll { $0.isGone }

        // Qorbolalar: yasash jarayoni, qo‘riqchilar, erish
        for sm in snowmen where !sm.isGone {
            sm.settle(onY: ground.baseY + ground.height(atX: sm.position.x) * 0.6)
            sm.age += dt
            if let worker = sm.builder, !worker.isGone, worker.mode == .build, sm.stage < 4 {
                sm.buildTimer -= dt
                if sm.buildTimer <= 0 {
                    sm.buildTimer = rebuildRush > 0 ? 1.3 : 2.2
                    sm.advance()
                    ground.remove(fromX: sm.position.x - 40, toX: sm.position.x + 40, depth: 2.5)
                    if sm.stage >= 4 {
                        worker.stopBuilding()
                        let phrase = rebuildRush > 0
                            ? (["Mana, yana turibdi!", "Bu safar yanada zo‘r!", "Qayta tug‘ildi!"].randomElement() ?? "Tayyor!")
                            : (theme.buildDone.randomElement() ?? "Tayyor!")
                        worker.say(phrase, in: self)
                        worker.rest(seconds: 3)
                        sm.builder = nil
                        snowmanCooldown = 90
                    }
                }
            } else if let worker = sm.builder, builderLeft(worker) {
                sm.builder = nil
            }
            if let guardian = sm.guardian, guardian.isGone || guardian.mode != .guarding {
                sm.guardian = nil
            }
            if sm.stage >= 4 && sm.age > 600 && sm.guardian == nil { sm.melt() }
        }
        snowmen.removeAll { $0.isGone }
    }

    /// Quruvchi boshqa ishga o‘tib ketdimi?
    private func builderLeft(_ worker: Worker) -> Bool {
        if worker.isGone { return true }
        switch worker.mode {
        case .shovel, .guarding, .leave: return true
        default: return false
        }
    }

    private func randomX(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        CGFloat.random(in: min(a, b)...max(a, b))
    }

    private func spawnWorker() {
        let fromLeft = Bool.random()
        let startX: CGFloat = fromLeft ? -24 : size.width + 24
        let worker = Worker(at: CGPoint(x: startX, y: groundSurface(atX: startX)),
                            scale: CGFloat(Settings.shared.workerScale), theme: theme)
        instant { root.addSublayer(worker.root) }
        workers.append(worker)
        let target = fromLeft ? randomX(60, size.width * 0.4) : randomX(size.width * 0.6, size.width - 60)
        worker.walk(to: target)
        if chance(0.5) {
            worker.say(theme.hello.randomElement() ?? "Qani, ishga!", in: self)
        }
    }

    /// Bo‘sh turgan ishchiga yangi vazifa beradi.
    func assignTask(to worker: Worker) {
        guard Settings.shared.workersEnabled else {
            sendHome(worker)
            return
        }
        guard worker.isAvailable else { return }

        // 1. Chala qolgan qorbolani davom ettirish
        if let sm = snowmen.first(where: { $0.stage < 4 && ($0.builder == nil || $0.builder === worker) }) {
            sm.builder = worker
            let side: CGFloat = worker.position.x <= sm.position.x ? -1 : 1
            let spot = clamp(sm.position.x + side * 20 * sm.sizeFactor, 10, size.width - 10)
            worker.walk(to: spot) { [weak self, weak worker, weak sm] in
                guard let self, let worker, let sm, !sm.isGone else { return }
                worker.face(sm.position.x >= worker.position.x ? 1 : -1)
                worker.startBuilding()
                sm.buildTimer = self.rebuildRush > 0 ? 0.6 : 1.0
            }
            return
        }

        // 2. Qorbolalar qayta-qayta buzilgan bo‘lsa — qo‘riqchi qo‘yiladi
        if griefTimes.count >= 2, let sm = snowmen.first(where: { $0.stage >= 4 && $0.guardian == nil }) {
            sm.guardian = worker
            let side: CGFloat = sm.position.x < size.width / 2 ? 1 : -1
            let spot = clamp(sm.position.x + side * 26 * sm.sizeFactor, 10, size.width - 10)
            worker.walk(to: spot) { [weak self, weak worker, weak sm] in
                guard let self, let worker, let sm, !sm.isGone else { return }
                worker.startGuarding(facing: side, duration: CGFloat.random(in: 30...50))
                worker.say(["Men qo‘riqlayman!", "Endi tegib ko‘ringchi!", "Navbatchilikka turdim"].randomElement() ?? "Men qo‘riqlayman!", in: self)
            }
            return
        }

        // 3. Yangi qorbola (so‘ralgan, buzilgan o‘rniga yoki o‘z xohishi bilan)
        let limit = Settings.shared.snowmanCount
        if snowmen.count < limit,
           pendingSnowmen > 0 || (ground.average > 6 && snowmanCooldown <= 0 && chance(0.35)) {
            startSnowman(with: worker, at: rebuildSpots.popLast())
            return
        }

        // 4. Eng chuqur joyni kurash
        if let x = deepestSpot(for: worker), ground.height(atX: x) > 10 {
            let side: CGFloat = Bool.random() ? 1 : -1
            let stand = clamp(x - side * worker.reach, 15, size.width - 15)
            worker.walk(to: stand) { [weak worker] in
                guard let worker else { return }
                worker.face(side)
                worker.startShoveling(duration: CGFloat.random(in: 6...12))
            }
            return
        }

        // 5. Ish qolmagan bo‘lsa — uyga
        if ground.average < 4, plows.isEmpty, pendingSnowmen == 0, griefTimes.isEmpty, !playMode,
           !Settings.shared.isSnowing, showcaseTimer <= 0 {
            sendHome(worker)
            return
        }

        // 6. Dam olish
        worker.rest(seconds: CGFloat.random(in: 3...6))
        if chance(0.3) {
            worker.say(theme.idle.randomElement() ?? "Ish ko‘p, vaqt oz", in: self)
        }
    }

    private func startSnowman(with worker: Worker, at spot: CGFloat?) {
        var x = clamp(spot ?? (worker.position.x + worker.facing * 50), 70, size.width - 70)
        var attempts = 0
        while snowmen.contains(where: { abs($0.position.x - x) < 70 }) && attempts < 8 {
            x = randomX(80, size.width - 80)
            attempts += 1
        }
        if plows.contains(where: { abs($0.position.x - x) < 150 }) {
            x = clamp(size.width - x, 70, size.width - 70)
        }
        let sm = Snowman(at: CGPoint(x: x, y: groundSurface(atX: x)),
                         sizeSetting: CGFloat(Settings.shared.snowmanScale), theme: theme)
        instant { root.addSublayer(sm.root) }
        snowmen.append(sm)
        pendingSnowmen = max(0, pendingSnowmen - 1)
        let phrases = spot != nil
            ? theme.rebuild
            : theme.buildStart
        worker.say(phrases.randomElement() ?? "Qorbola yasaymiz!", in: self)
        assignTask(to: worker)
    }

    private func deepestSpot(for worker: Worker) -> CGFloat? {
        var bestX: CGFloat?
        var bestHeight: CGFloat = 0
        var x: CGFloat = 40
        while x < size.width - 40 {
            let height = ground.height(atX: x)
            let taken = workers.contains { $0 !== worker && $0.mode != .leave && abs($0.targetX - x) < 60 }
            let nearSnowman = snowmen.contains { abs($0.position.x - x) < 40 * $0.sizeFactor }
            if height > bestHeight && !taken && !nearSnowman {
                bestHeight = height
                bestX = x
            }
            x += 15
        }
        return bestX
    }

    private func sendHome(_ worker: Worker) {
        guard worker.mode != .leave else { return }
        for sm in snowmen {
            if sm.builder === worker { sm.builder = nil }
            if sm.guardian === worker { sm.guardian = nil }
        }
        let exitX: CGFloat = worker.position.x < size.width / 2 ? -40 : size.width + 40
        if chance(0.4) {
            worker.say(["Xayr!", "Ish tugadi!", "Choyga ketdik"].randomElement() ?? "Xayr!", in: self)
        }
        worker.leave(to: exitX)
    }

    /// Ishchi kurak bilan qor otganda chaqiriladi.
    func shovelSnow(by worker: Worker) {
        let x = worker.position.x + worker.facing * worker.reach
        let removed = ground.remove(fromX: x - 9, toX: x + 9, depth: 4)
        guard removed > 0.5 else { return }
        let top = ground.baseY + ground.height(atX: x) + 6
        burst(at: CGPoint(x: x, y: top), count: min(6, Int(removed / 6) + 2),
              velocity: 110, velocityRange: 40, longitude: .pi, range: 0.5,
              gravity: -520, xAcceleration: -worker.facing * 170, lifetime: 0.9, scale: 0.4)
    }

    // MARK: - Qor tozalovchi mashinalar

    private func updatePlows(_ dt: CGFloat, average: CGFloat) {
        let limit = Settings.shared.plowCount
        if limit > 0 && plows.count < limit && plowCooldown <= 0 {
            if plows.isEmpty {
                if groundNeedsPlow(extraTrucks: limit - 1) { callPlow() }
            } else if average > 10 {
                // Bittasi yo‘lda, qor esa hali qalin — ikkinchisi teskari tomondan yordamga keladi
                callPlow()
            }
        }
        var finished: [Snowplow] = []
        for truck in plows {
            if truck.update(dt: dt, game: self) {
                finished.append(truck)
                continue
            }
            for worker in workers where !worker.hoppedForPlow && worker.isAvailable
                && abs(worker.position.x - truck.bladeX) < 40 {
                worker.hoppedForPlow = true
                worker.hop()
                if chance(0.5) {
                    worker.say(["Voy-voy!", "Sekinroq!", "Ehtiyot bo‘ling!"].randomElement() ?? "Voy-voy!", in: self)
                }
            }
        }
        if !finished.isEmpty {
            finished.forEach { $0.remove() }
            plows.removeAll { truck in finished.contains { $0 === truck } }
            if plows.isEmpty { plowCooldown = 15 }
        }
    }

    /// Mashina qachon chiqadi — yerdagi qor ko‘zga yaqqol tashlanganda:
    /// • qor ekran enining yarmidan ko‘pini 12 px dan qalin qoplagan bo‘lsa, yoki
    /// • o‘rtacha qalinlik 14 px dan oshsa, yoki
    /// • biror joyda katta uyum (60 px) paydo bo‘lsa.
    /// Sozlamalarda mashina ko‘p bo‘lsa, chegaralar biroz pastroq — ular ertaroq chiqadi.
    private func groundNeedsPlow(extraTrucks: Int) -> Bool {
        let ease: CGFloat = CGFloat(max(0, extraTrucks)) * 2
        let depth: CGFloat = 12 - ease
        let wideCover: Bool = ground.coverage(above: depth) > 0.55
        let deepAverage: Bool = ground.average > 14 - ease
        let bigPile: Bool = ground.peak > 60
        return wideCover || deepAverage || bigPile
    }

    func callPlow() {
        guard plows.count < CountRange.plows.upperBound else { return }
        let direction: CGFloat
        if let last = plows.last {
            direction = -last.direction
        } else {
            direction = Bool.random() ? 1 : -1
        }
        let small = plowsSpawned % 2 == 1
        plowsSpawned += 1
        let truck = Snowplow(direction: direction, small: small, kind: theme.kind,
                             startX: direction > 0 ? -110 : size.width + 110,
                             groundY: ground.baseY, screenScale: scale,
                             sizeSetting: CGFloat(Settings.shared.plowScale))
        instant { root.addSublayer(truck.root) }
        plows.append(truck)
        plowCooldown = 6
        for worker in workers { worker.hoppedForPlow = false }
        workers.first(where: { $0.isAvailable })?.say(small ? "Yana bittasi keldi!" : theme.vehicleArrive, in: self)
    }

    /// Mashina kuragi o‘tgan joydagi qorni oladi (qorbolalar tagiga tegmaydi).
    func plowClear(fromX x0: CGFloat, toX x1: CGFloat) -> CGFloat {
        let standing = snowmen
        return ground.remove(fromX: x0, toX: x1, depth: .greatestFiniteMagnitude, keep: 1.2,
                             skip: { x in standing.contains { $0.covers(x) } })
    }

    // MARK: - Qorbobo va sovg‘alar

    private func updateSanta(_ dt: CGFloat) {
        if let sleigh = santa {
            if sleigh.update(dt: dt) {
                sleigh.remove()
                santa = nil
            } else if sleigh.consumeGiftRequest() {
                dropGift(at: sleigh.position)
            }
            return
        }
        guard Settings.shared.santaEnabled else { return }
        santaTimer -= dt
        if santaTimer <= 0 { callSanta() }
    }

    func callSanta() {
        guard santa == nil else { return }
        santaTimer = CGFloat.random(in: 180...420)
        let direction: CGFloat = Bool.random() ? 1 : -1
        let sleigh: Visitor
        switch theme.visitor {
        case .santa: sleigh = SantaSleigh(direction: direction, width: size.width, height: size.height)
        case .swallows: sleigh = BirdFlock(cranes: false, direction: direction, width: size.width, height: size.height,
                                           storks: chance(0.5))
        case .cranes: sleigh = BirdFlock(cranes: true, direction: direction, width: size.width, height: size.height)
        case .balloon: sleigh = HotAirBalloon(direction: direction, width: size.width, height: size.height)
        }
        instant {
            if let trail = sleigh.trailLayer { root.addSublayer(trail) }
            root.addSublayer(sleigh.root)
        }
        santa = sleigh
    }

    private func dropGift(at point: CGPoint) {
        let gift = Gift(at: point, part: theme.gift)
        instant { root.addSublayer(gift.root) }
        gifts.append(gift)
    }

    private func updateGifts(_ dt: CGFloat) {
        guard !gifts.isEmpty else { return }
        for gift in gifts {
            gift.update(dt: dt, groundY: groundSurface(atX: gift.position.x))
        }
        gifts.removeAll { $0.isGone }
    }

    private func openGift(_ gift: Gift) {
        let colors = [cg(0xE53935), cg(0xFFEB3B), cg(0x43A047), cg(0x1E88E5), cg(0xFB8C00), cg(0x8E24AA)]
        burst(at: CGPoint(x: gift.position.x, y: gift.position.y + 8), count: 36,
              velocity: 210, velocityRange: 90, longitude: .pi, range: 1.2,
              gravity: -520, lifetime: 1.2, scale: 0.4, colors: colors)
        GameState.shared.playerScore += 3
        floatText("Sovg‘a! +3", at: CGPoint(x: gift.position.x, y: gift.position.y + 30))
        gift.remove()
        gifts.removeAll { $0 === gift }
    }

    // MARK: - Menyu buyruqlari

    func requestSnowman() {
        guard Settings.shared.workersEnabled else { return }
        if snowmen.count + pendingSnowmen < Settings.shared.snowmanCount { pendingSnowmen += 1 }
        if !workers.contains(where: { $0.mode != .leave }) { crewCooldown = 0 }
    }

    func clearAllSnow() {
        ground.clear()
        for ledge in ledges.values { ledge.clear() }
        stash.removeAll()
    }

    // MARK: - Effektlar

    /// Qisqa "portlash": qor bo‘laklari, sachrash yoki konfetti. Core Animation emitteri bilan.
    func burst(at point: CGPoint, lineWidth: CGFloat = 0, count: Int, velocity: CGFloat, velocityRange: CGFloat,
               longitude: CGFloat, range: CGFloat, gravity: CGFloat = -600, xAcceleration: CGFloat = 0,
               lifetime: Float = 0.9, scale particleScale: CGFloat = 0.4, colors: [CGColor]? = nil) {
        guard count > 0 else { return }
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = point
        emitter.emitterShape = .line
        emitter.emitterMode = .outline
        emitter.emitterSize = CGSize(width: max(lineWidth, 1), height: 1)
        emitter.zPosition = 45
        emitter.beginTime = CACurrentMediaTime()
        let window: Double = 0.1
        let palette = colors ?? theme.burstColors
        emitter.emitterCells = palette.map { (color: CGColor) -> CAEmitterCell in
            let cell = CAEmitterCell()
            cell.contents = colors == nil ? theme.particleImage : Art.flake
            cell.contentsScale = Art.scale
            cell.birthRate = Float(Double(count) / window / Double(palette.count))
            cell.lifetime = lifetime
            cell.lifetimeRange = lifetime * 0.3
            cell.velocity = velocity
            cell.velocityRange = velocityRange
            cell.emissionLongitude = longitude
            cell.emissionRange = range
            cell.yAcceleration = gravity
            cell.xAcceleration = xAcceleration
            cell.scale = particleScale
            cell.scaleRange = particleScale * 0.4
            cell.alphaSpeed = -0.7 / lifetime
            cell.spinRange = 3
            cell.color = color
            return cell
        }
        instant { root.addSublayer(emitter) }
        after(window) { instant { emitter.birthRate = 0 } }
        after(window + Double(lifetime) * 1.4 + 0.2) { emitter.removeFromSuperlayer() }
    }

    func burstSnow(at point: CGPoint, count: Int) {
        burst(at: point, count: count, velocity: 140, velocityRange: 80,
              longitude: .pi, range: 1.2, gravity: -600, lifetime: 0.8, scale: 0.42)
    }

    /// Koptok uchishi: yoy bo‘ylab harakat + kattalashish/kichrayish.
    @discardableResult
    private func flyBall(from start: CGPoint, to end: CGPoint, control: CGPoint, duration: CFTimeInterval,
                         fromScale: CGFloat, toScale: CGFloat, size ballSize: CGFloat, z: CGFloat,
                         timing: CAMediaTimingFunctionName, completion: @escaping (CALayer) -> Void) -> CALayer {
        let ball = CALayer()
        ball.contents = theme.projectileImage
        ball.contentsScale = Art.scale
        ball.contentsGravity = .resize
        ball.bounds = CGRect(x: 0, y: 0, width: ballSize, height: ballSize)
        ball.zPosition = z
        instant {
            ball.position = end
            ball.transform = CATransform3DMakeScale(toScale, toScale, 1)
            root.addSublayer(ball)
        }
        let path = CGMutablePath()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = fromScale
        grow.toValue = toScale
        let group = CAAnimationGroup()
        group.animations = [move, grow]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: timing)
        CATransaction.begin()
        CATransaction.setCompletionBlock { completion(ball) }
        ball.add(group, forKey: "fly")
        CATransaction.commit()
        return ball
    }

    /// Ekranga yopishgan qor dog‘i: asta pastga sirg‘alib, eriydi.
    /// gentle = ish rejimidagi "javob": kichikroq va tezroq eriydi, ekran silkinmaydi.
    private func splat(at point: CGPoint, gentle: Bool = false) {
        guard let picture = theme.splats.randomElement() else { return }
        let holder = containerLayer()
        let image = CALayer()
        let diameter = CGFloat.random(in: 150...210) * ballFactor * (gentle ? 0.6 : 1)
        image.contents = picture
        image.contentsScale = Art.scale
        image.contentsGravity = .resize
        image.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        image.position = .zero
        let total: CFTimeInterval = gentle ? 2.6 : 4.95
        let holdUntil = NSNumber(value: (gentle ? 1.0 : 2.35) / total)
        instant {
            holder.zPosition = 75
            holder.position = CGPoint(x: point.x, y: point.y - 28)
            holder.transform = CATransform3DMakeRotation(CGFloat.random(in: -0.6...0.6), 0, 0, 1)
            image.opacity = 0
            holder.addSublayer(image)
            root.addSublayer(holder)
        }

        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [0.4, 1.08, 1.0, 1.0]
        pop.keyTimes = [0, NSNumber(value: 0.07 / total), NSNumber(value: 0.15 / total), 1]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.97, 0.97, 0]
        fade.keyTimes = [0, holdUntil, 1]
        let imageGroup = CAAnimationGroup()
        imageGroup.animations = [pop, fade]
        imageGroup.duration = total
        image.add(imageGroup, forKey: "splat")

        let slide = CAKeyframeAnimation(keyPath: "position.y")
        slide.values = [point.y, point.y, point.y - 28]
        slide.keyTimes = [0, holdUntil, 1]
        slide.duration = total
        holder.add(slide, forKey: "slide")
        after(total) { holder.removeFromSuperlayer() }

        burstSnow(at: point, count: 14)
        if !gentle { shake() }
        if chance(0.6) {
            let phrase = ["Ana senga!", "Ha-ha-ha!", "Ol-a!", "Tekkizdim!"].randomElement() ?? "Ha-ha!"
            workers.first(where: { $0.mode == .angry })?.say(phrase, in: self)
        }
    }

    private func shake() {
        guard root.animation(forKey: "shake") == nil else { return }
        let jolt = CAKeyframeAnimation(keyPath: "position")
        jolt.values = [CGPoint.zero, CGPoint(x: 4, y: -3), CGPoint(x: -4, y: 3), CGPoint(x: 3, y: 2), CGPoint.zero]
            .map { NSValue(point: $0) }
        jolt.duration = 0.12
        jolt.isAdditive = true
        root.add(jolt, forKey: "shake")
    }

    private func floatText(_ text: String, at point: CGPoint) {
        let font = NSFont(name: "HelveticaNeue-Bold", size: 16) ?? NSFont.boldSystemFont(ofSize: 16)
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let label = CATextLayer()
        label.string = text
        label.font = font
        label.fontSize = 16
        label.foregroundColor = whiteColor
        label.alignmentMode = .center
        label.contentsScale = scale
        label.bounds = CGRect(x: 0, y: 0, width: ceil(textSize.width) + 6, height: ceil(textSize.height))
        label.shadowColor = cg(0x0F1B2D)
        label.shadowOpacity = 0.7
        label.shadowRadius = 1.5
        label.shadowOffset = CGSize(width: 1, height: -1)
        instant {
            label.zPosition = 98
            label.position = CGPoint(x: point.x, y: point.y + 36)
            label.opacity = 0
            root.addSublayer(label)
        }
        let rise = CABasicAnimation(keyPath: "position.y")
        rise.fromValue = point.y
        rise.toValue = point.y + 36
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.55, 1]
        let group = CAAnimationGroup()
        group.animations = [rise, fade]
        group.duration = 0.9
        label.add(group, forKey: "float")
        after(0.95) { label.removeFromSuperlayer() }
    }

    // MARK: - Sichqoncha: ish rejimida tegish

    /// Shu nuqtada bosiladigan narsa bormi? AppDelegate har 1/30 sekundda so‘raydi:
    /// ha bo‘lsa, panel bosishni qabul qiladi, yo‘q bo‘lsa — bosish ostidagi oynaga o‘tadi.
    func isInteractive(at point: CGPoint) -> Bool {
        if let stage, stage.isInteractive(at: point) { return true }
        if peerAt(point) != nil { return true }
        if gifts.contains(where: { $0.hitRect.insetBy(dx: -4, dy: -4).contains(point) }) { return true }
        if snowmen.contains(where: { $0.stage > 0 && $0.hitRect.insetBy(dx: -4, dy: -4).contains(point) }) { return true }
        if workers.contains(where: { $0.isAvailable && $0.hitRect.insetBy(dx: -3, dy: -3).contains(point) }) { return true }
        if plows.contains(where: { $0.hitRect.contains(point) }) { return true }
        if let sleigh = santa, sleigh.hitRect.contains(point) { return true }
        return false
    }

    /// Sichqoncha ustiga kelganda: qorbola chayqaladi (qo‘riqchi ogohlantiradi), ishchi qo‘l silkitadi.
    func hover(at point: CGPoint?) {
        guard let point else {
            hoveredSnowman = nil
            hoveredWorker = nil
            return
        }
        let sm = snowmen.first(where: { $0.stage > 0 && $0.hitRect.insetBy(dx: -4, dy: -4).contains(point) })
        if let sm, sm !== hoveredSnowman {
            sm.wobble(strength: 0.35)
            sm.guardian?.warn(in: self)
        }
        hoveredSnowman = sm
        let worker = workers.first(where: { $0.isAvailable && $0.hitRect.insetBy(dx: -3, dy: -3).contains(point) })
        if let worker, worker !== hoveredWorker {
            worker.wave(in: self)
        }
        hoveredWorker = worker
    }

    /// OverlayView sichqoncha bosilganini shu yerga uzatadi.
    func handleClick(at point: CGPoint) {
        if let stage, stage.handleClick(at: point) { return }
        if let avatar = peerAt(point) {
            if playMode {
                Office.shared.throwAt(avatar.id)
            } else if let view = hostView {
                Office.shared.showMenu(for: avatar.id, at: point, in: view)
            }
            return
        }
        if playMode {
            handlePlayClick(at: point)
        } else {
            handleDirectClick(at: point)
        }
    }

    /// Ish rejimida to‘g‘ridan-to‘g‘ri bosish: qorbolaga musht, ishchini qitiqlash, sovg‘ani ochish...
    private func handleDirectClick(at point: CGPoint) {
        if let gift = gifts.first(where: { $0.hitRect.insetBy(dx: -4, dy: -4).contains(point) }) {
            openGift(gift)
            return
        }
        if let sleigh = santa, sleigh.hitRect.contains(point) {
            sleigh.getHit(in: self)
            return
        }
        if let sm = snowmen.first(where: { $0.stage > 0 && $0.hitRect.insetBy(dx: -4, dy: -4).contains(point) }) {
            punch(sm, at: point)
            return
        }
        if let worker = workers.first(where: { $0.isAvailable && $0.hitRect.insetBy(dx: -3, dy: -3).contains(point) }) {
            if worker.tickle(in: self), Settings.shared.crewFightsBack {
                worker.becomeAngry(throws: 1, game: self, force: true)
            }
            return
        }
        if let truck = plows.first(where: { $0.hitRect.contains(point) }) {
            truck.honk(in: self)
        }
    }

    /// Qorbolaga sichqoncha bilan zarba. Qo‘riqchi bo‘lsa, birinchi zarbani to‘sib qoladi.
    private func punch(_ sm: Snowman, at point: CGPoint) {
        let now = CACurrentMediaTime()
        if let guardian = sm.guardian, !guardian.isGone, guardian.mode == .guarding, now >= sm.guardReadyAt {
            sm.guardReadyAt = now + 2.5
            guardian.block(in: self)
            sm.wobble(strength: 0.3)
            return
        }
        burstSnow(at: point, count: 8)
        hitSnowman(sm)
    }

    /// Qorbolaga zarba (sichqoncha yoki qor koptok). Buzilsa — brigada munosabat bildiradi.
    private func hitSnowman(_ sm: Snowman) {
        if sm.takeHit(in: self) {
            snowmanDestroyed(sm)
        } else if chance(0.6) {
            let phrase = theme.protect.randomElement() ?? "Hey!"
            workers.filter { $0.isAvailable && $0.mode != .angry }.randomElement()?.say(phrase, in: self)
        }
    }

    /// Qorbola butunlay buzildi. Brigadaning javobi so‘nggi 3 daqiqada nechta qorbola
    /// buzilganiga qarab kuchayadi: achinadi → qo‘riqchi qo‘yadi → javob qaytaradi.
    private func snowmanDestroyed(_ sm: Snowman) {
        let now = CACurrentMediaTime()
        griefTimes.append(now)
        let level = griefTimes.count
        sm.builder?.stopBuilding()
        sm.builder = nil
        sm.guardian?.stopGuarding()
        sm.guardian = nil
        snowmen.removeAll { $0 === sm }
        snowmanCooldown = 20
        let crew = workers.filter { $0.isAvailable }

        if playMode {
            for worker in crew { worker.becomeAngry(throws: Int.random(in: 2...4), game: self) }
            crew.first?.say(theme.angryBreak, in: self)
        } else {
            let phrases = theme.grief[min(level, theme.grief.count) - 1]
            for (index, worker) in crew.enumerated() {
                worker.react(toward: sm.position.x, phrase: phrases[index % phrases.count], game: self)
            }
            if level >= 3 && Settings.shared.crewFightsBack {
                for worker in crew.prefix(2) {
                    after(1.2) { [weak self, weak worker] in
                        guard let self, let worker else { return }
                        worker.becomeAngry(throws: 1, game: self, force: true)
                    }
                }
            }
        }

        // Qayta yasash: o‘sha joyda va tezroq
        rebuildSpots.append(sm.position.x)
        if snowmen.count + pendingSnowmen < Settings.shared.snowmanCount { pendingSnowmen += 1 }
        rebuildRush = 40
        if crew.isEmpty && Settings.shared.workersEnabled { crewCooldown = 0 }
    }

    // MARK: - ⌥ + g‘ildirak: narsa ustida turib o‘lchamini surib o‘zgartirish

    /// Sichqoncha qorbola, ishchi yoki mashina ustida turganda ⌥ bosib g‘ildirak (yoki trackpadda
    /// ikki barmoq) bilan surilsa — o‘sha turdagi hamma narsa kattalashadi yoki kichrayadi.
    /// O‘yin rejimida bo‘sh joyda surilsa — qor koptoklar o‘lchami o‘zgaradi.
    func handleResizeScroll(at point: CGPoint, delta: CGFloat) {
        let settings = Settings.shared
        let title: String
        let keyPath: ReferenceWritableKeyPath<Settings, Double>
        let anchor: CGPoint
        if let sm = snowmen.first(where: { $0.stage > 0 && $0.hitRect.insetBy(dx: -4, dy: -4).contains(point) }) {
            title = "Qorbolalar"
            keyPath = \Settings.snowmanScale
            anchor = sm.topPoint
        } else if let worker = workers.first(where: { $0.isAvailable && $0.hitRect.insetBy(dx: -3, dy: -3).contains(point) }) {
            title = "Ishchilar"
            keyPath = \Settings.workerScale
            anchor = worker.headTop
        } else if let truck = plows.first(where: { $0.hitRect.contains(point) }) {
            title = "Mashinalar"
            keyPath = \Settings.plowScale
            anchor = truck.topPoint
        } else if playMode {
            title = "Qor koptoklar"
            keyPath = \Settings.ballScale
            anchor = point
        } else {
            return
        }
        let factor = exp(Double(clamp(delta, -40, 40)) * 0.012)
        settings[keyPath: keyPath] = settings[keyPath: keyPath] * factor
        showSizeBadge("\(title): \(Settings.percentTitle(settings[keyPath: keyPath]))", near: anchor)
    }

    private func setupSizeBadge() {
        sizeBadgeBackground.fillColor = cg(0x0F1B2D, 0.82)
        sizeBadgeBackground.strokeColor = cg(0xFFFFFF, 0.25)
        sizeBadgeBackground.lineWidth = 1
        sizeBadgeBackground.contentsScale = scale
        let font = NSFont(name: "HelveticaNeue-Bold", size: 13) ?? NSFont.boldSystemFont(ofSize: 13)
        sizeBadgeText.font = font
        sizeBadgeText.fontSize = 13
        sizeBadgeText.foregroundColor = whiteColor
        sizeBadgeText.alignmentMode = .center
        sizeBadgeText.contentsScale = scale
        sizeBadge.addSublayer(sizeBadgeBackground)
        sizeBadge.addSublayer(sizeBadgeText)
        sizeBadge.zPosition = 99
        sizeBadge.opacity = 0
        root.addSublayer(sizeBadge)
    }

    private func showSizeBadge(_ text: String, near point: CGPoint) {
        let font = NSFont(name: "HelveticaNeue-Bold", size: 13) ?? NSFont.boldSystemFont(ofSize: 13)
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let width = ceil(textSize.width) + 22
        let height: CGFloat = 26
        let position = CGPoint(x: clamp(point.x, width / 2 + 8, size.width - width / 2 - 8),
                               y: min(point.y + 24, size.height - 40))
        instant {
            sizeBadgeBackground.path = CGPath(roundedRect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
                                              cornerWidth: 13, cornerHeight: 13, transform: nil)
            sizeBadgeText.string = text
            sizeBadgeText.bounds = CGRect(x: 0, y: 0, width: width, height: ceil(textSize.height))
            sizeBadgeText.position = .zero
            sizeBadge.position = position
            sizeBadge.opacity = 1
        }
        sizeBadgeToken += 1
        let token = sizeBadgeToken
        after(1.2) { [weak self] in
            guard let self, self.sizeBadgeToken == token else { return }
            self.sizeBadge.opacity = 0   // odatiy 0.25 s silliq so‘nish
        }
    }

    // MARK: - Ofis: hamkasblar va tarmoq o‘yinlari (faqat asosiy monitorda)

    private func peerAt(_ point: CGPoint) -> PeerAvatar? {
        peerAvatars.values.first { !$0.root.isHidden && $0.hitRect.insetBy(dx: -3, dy: -3).contains(point) }
    }

    /// Ofisdagi hamkasblar ro‘yxati o‘zgarganda: kelganlar chetdan kirib keladi, ketganlar yo‘qoladi.
    func syncOffice(peers: [PeerInfo], rooms: [RoomInfo]) {
        guard isPrimary else { return }
        let wanted = Set(peers.map { $0.id })
        for (id, avatar) in peerAvatars where !wanted.contains(id) {
            avatar.remove()
            peerAvatars[id] = nil
        }
        let workerFactor = CGFloat(Settings.shared.workerScale)
        for info in peers {
            if let avatar = peerAvatars[info.id] {
                avatar.update(info: info)
            } else {
                let x: CGFloat = Bool.random() ? -30 : size.width + 30
                let avatar = PeerAvatar(info: info, at: CGPoint(x: x, y: groundSurface(atX: x)),
                                        scale: workerFactor, screenScale: scale)
                avatar.attach(to: root)
                peerAvatars[info.id] = avatar
            }
        }
        for (id, avatar) in peerAvatars {
            if let room = rooms.first(where: { $0.hostID == id && $0.phase == .lobby }) {
                avatar.flagLabel = "\(room.game.emoji) \(room.game.title) \(room.players.count)/\(room.game.maxPlayers)"
            } else if let room = rooms.first(where: { $0.players.contains(id) && $0.phase == .playing }) {
                avatar.flagLabel = "\(room.game.emoji) o‘ynamoqda"
            } else {
                avatar.flagLabel = nil
            }
        }
        updateStageVisibility()
    }

    /// O‘yin paytida o‘yinchilar sahnada turadi — yurib yurgan nusxalari yashiriladi.
    private func updateStageVisibility() {
        let playing = Set(stage?.playerIDs ?? [])
        for (id, avatar) in peerAvatars {
            avatar.setVisible(!playing.contains(id))
        }
    }

    func peerWaves(_ id: String) {
        guard let avatar = peerAvatars[id] else { return }
        avatar.wave()
        avatar.say("👋 Salom!", in: self, duration: 2.5)
    }

    func peerSays(_ id: String, text: String, fromMe: Bool = false) {
        guard let avatar = peerAvatars[id] else { return }
        if fromMe {
            avatar.hop()
            return
        }
        let short = text.count > 60 ? String(text.prefix(57)) + "..." : text
        avatar.say(short, in: self, duration: 5)
    }

    /// Hamkasb sizga koptok otdi: uning odamchasi otadi, koptok ekraningizga yopishadi.
    func incomingProjectile(from id: String) {
        guard isPrimary else { return }
        let avatar = peerAvatars[id].flatMap { $0.root.isHidden ? nil : $0 }
        let start: CGPoint
        if let avatar {
            avatar.throwMotion()
            avatar.say(["Ol-a!", "Ana senga!", "Tutib ol!", "Salom sizga!"].randomElement() ?? "Ol-a!", in: self, duration: 2)
            start = avatar.handPoint
        } else {
            start = CGPoint(x: randomX(60, size.width - 60), y: -40)
        }
        let mouse = NSEvent.mouseLocation
        var target: CGPoint
        if screenFrame.contains(mouse) {
            target = CGPoint(x: mouse.x - screenFrame.minX + CGFloat.random(in: -60...60),
                             y: mouse.y - screenFrame.minY + CGFloat.random(in: -50...50))
        } else {
            target = CGPoint(x: randomX(size.width * 0.25, size.width * 0.75), y: randomX(size.height * 0.35, size.height * 0.7))
        }
        target.x = clamp(target.x, 90, size.width - 90)
        target.y = clamp(target.y, 90, size.height - 90)
        let landing = target
        let control = CGPoint(x: (start.x + target.x) / 2, y: max(start.y, target.y) + 160)
        after(avatar == nil ? 0 : 0.3) { [weak self] in
            guard let self else { return }
            self.flyBall(from: start, to: landing, control: control, duration: 0.8, fromScale: 0.35, toScale: 3.4,
                         size: 28 * self.ballFactor, z: 85, timing: .easeIn) { [weak self] flown in
                flown.removeFromSuperlayer()
                self?.splat(at: landing, gentle: true)
            }
        }
    }

    /// Siz hamkasbga koptok otasiz: koptok ekraningizda uning odamchasiga uchib boradi, keyin unga yetkaziladi.
    func throwAtPeer(_ id: String, completion: @escaping () -> Void) {
        guard isPrimary, let avatar = peerAvatars[id], !avatar.root.isHidden else {
            completion()
            return
        }
        let point = CGPoint(x: avatar.position.x, y: avatar.position.y + 26 * avatar.sizeScale)
        let start = CGPoint(x: point.x + (point.x < size.width / 2 ? 140 : -140), y: -60)
        let control = CGPoint(x: (start.x + point.x) / 2, y: max(point.y, start.y) + 140)
        flyBall(from: start, to: point, control: control, duration: 0.5, fromScale: 3, toScale: 0.8,
                size: 30 * ballFactor, z: 80, timing: .easeOut) { [weak self] flown in
            flown.removeFromSuperlayer()
            guard let self else { return }
            self.burstSnow(at: point, count: 14)
            avatar.flinch()
            avatar.say(["Voy!", "Hey!", "Hozir ko‘rasiz!"].randomElement() ?? "Voy!", in: self, duration: 2)
            completion()
        }
    }

    func startStage(_ room: RoomInfo, players: [PeerInfo], myID: String) {
        guard isPrimary, stage?.roomID != room.id else { return }
        stage?.remove()
        if room.game.isSport {
            stage = SportStage(room: room, world: self, players: players, myID: myID)
        } else {
            stage = GameStage(room: room, world: self, players: players, myID: myID)
        }
        updateStageVisibility()
    }

    func endStage(_ roomID: String) {
        guard let current = stage, current.roomID == roomID else { return }
        current.remove()
        stage = nil
        updateStageVisibility()
    }

    func stageEvent(_ roomID: String, _ event: GameEvent) {
        guard let current = stage, current.roomID == roomID else { return }
        current.handle(event)
    }

    func showFloatText(_ text: String, at point: CGPoint) {
        floatText(text, at: point)
    }

    /// Sport o‘yini davomida shu monitordagi barcha bosishlar sahnaga tegishli.
    var capturesAllInput: Bool {
        stage?.capturesAllInput ?? false
    }

    func handleDrag(at point: CGPoint) {
        stage?.handleDrag(at: point)
    }

    func handleMouseUp(at point: CGPoint) {
        stage?.handleMouseUp(at: point)
    }

    func confetti(at point: CGPoint) {
        let colors = [cg(0xE53935), cg(0xFFEB3B), cg(0x43A047), cg(0x1E88E5), cg(0xFB8C00), cg(0x8E24AA)]
        burst(at: point, count: 60, velocity: 240, velocityRange: 100, longitude: .pi, range: 1.3,
              gravity: -480, lifetime: 1.5, scale: 0.45, colors: colors)
    }

    // MARK: - O‘yin rejimi

    func setPlayMode(_ on: Bool) {
        playMode = on
        shownPlayer = -1
        shownCrew = -1
        instant { hud.isHidden = !on }
        if on {
            if Settings.shared.workersEnabled {
                crewCooldown = 0
                if snowmen.isEmpty && pendingSnowmen == 0 { pendingSnowmen = 1 }
                workers.first(where: { $0.isAvailable })?.say("O‘yin boshlandi!", in: self)
            }
        } else {
            for worker in workers where worker.mode == .angry || worker.mode == .knocked {
                worker.calm(self, phrase: ["Mayli, ishlayvering!", "Yarashdik!", "Bo‘pti, keyin o‘ynaymiz"].randomElement())
            }
            let balls = incoming
            incoming.removeAll()
            for ball in balls {
                ball.layer.removeAllAnimations()
                instant { ball.layer.removeFromSuperlayer() }
            }
        }
    }

    private func handlePlayClick(at point: CGPoint) {
        // Uchib kelayotgan koptokni ushlab qolish
        let factor = ballFactor
        if let index = incoming.firstIndex(where: { ball in
            let current = ball.layer.presentation() ?? ball.layer
            let ballScale = (current.value(forKeyPath: "transform.scale") as? NSNumber).map { CGFloat($0.doubleValue) } ?? 1
            let radius = max(20, 14 * factor * ballScale + 8)
            return hypot(current.position.x - point.x, current.position.y - point.y) < radius
        }) {
            let ball = incoming.remove(at: index)
            let caughtAt = (ball.layer.presentation() ?? ball.layer).position
            ball.layer.removeAllAnimations()
            instant { ball.layer.removeFromSuperlayer() }
            burstSnow(at: caughtAt, count: 14)
            GameState.shared.playerScore += 1
            floatText("Ushladingiz! +1", at: point)
            ball.thrower?.say(["Eh!", "Qanday qilding?!", "Omading bor ekan"].randomElement() ?? "Eh!", in: self)
            return
        }
        throwPlayerBall(to: point)
    }

    /// Foydalanuvchi otgan koptok: ekranning pastidan (go‘yo qo‘lingizdan) bosilgan nuqtaga uchadi.
    private func throwPlayerBall(to point: CGPoint) {
        let start = CGPoint(x: point.x + (point.x < size.width / 2 ? 120 : -120), y: -60)
        let control = CGPoint(x: (start.x + point.x) / 2, y: max(point.y, start.y) + 120)
        flyBall(from: start, to: point, control: control, duration: 0.42, fromScale: 3.2, toScale: 0.75,
                size: 30 * ballFactor, z: 80, timing: .easeOut) { [weak self] flown in
            flown.removeFromSuperlayer()
            self?.playerBallLanded(at: point)
        }
    }

    private func playerBallLanded(at point: CGPoint) {
        let reach = 6 * ballFactor
        burstSnow(at: point, count: Int(10 * ballFactor))

        if let gift = gifts.first(where: { $0.hitRect.insetBy(dx: -8 * ballFactor, dy: -8 * ballFactor).contains(point) }) {
            openGift(gift)
            return
        }

        if let sleigh = santa, sleigh.hitRect.insetBy(dx: -reach, dy: -reach).contains(point) {
            sleigh.getHit(in: self)
            GameState.shared.playerScore += 1
            return
        }

        if let worker = workers.first(where: { $0.isAvailable && $0.hitRect.insetBy(dx: -reach, dy: -reach).contains(point) }) {
            worker.knockDown(self)
            GameState.shared.playerScore += 1
            floatText("+1", at: CGPoint(x: point.x, y: point.y + 24))
            for other in workers where other !== worker && other.isAvailable && chance(0.5) {
                other.becomeAngry(throws: Int.random(in: 1...2), game: self)
            }
            return
        }

        if let sm = snowmen.first(where: { $0.stage > 0 && $0.hitRect.insetBy(dx: -reach, dy: -reach).contains(point) }) {
            GameState.shared.playerScore += 1
            hitSnowman(sm)
            return
        }

        if let truck = plows.first(where: { $0.hitRect.insetBy(dx: -reach, dy: -reach).contains(point) }) {
            truck.honk(in: self)
            return
        }

        for ledge in Array(ledges.values) + [ground] {
            guard let top = ledge.surfaceY(atX: point.x), ledge.height(atX: point.x) > 0.5 else { continue }
            if point.y >= ledge.baseY - 8 && point.y <= top + 22 * ballFactor {
                knockSnow(on: ledge, at: point.x)
                return
            }
        }
    }

    /// Koptok tekkan joydagi qorni uchirib yuboradi.
    private func knockSnow(on ledge: Ledge, at x: CGFloat) {
        let radius = 28 * ballFactor
        var removed: CGFloat = 0
        var highest: CGFloat = 0
        var cx = x - radius
        while cx <= x + radius {
            if let i = ledge.column(at: cx), ledge.visible[i], ledge.heights[i] > 0.5 {
                let height = ledge.heights[i]
                let keep = ledge.isGround ? height * 0.55 : 0
                removed += height - keep
                highest = max(highest, height)
                ledge.heights[i] = keep
            }
            cx += ledge.colW
        }
        ledge.dirty = true
        guard removed > 1 else { return }
        burst(at: CGPoint(x: x, y: ledge.baseY + highest * 0.6), lineWidth: radius * 1.8,
              count: min(50, Int(removed / 3) + 6), velocity: 150, velocityRange: 80,
              longitude: .pi, range: 1.1, gravity: -650, lifetime: 1.0, scale: 0.45)
    }

    /// Ishchi foydalanuvchiga qarab qor otadi: koptok kattalashib kelib, "shisha"ga yopishadi.
    /// O‘yin rejimida — o‘yinning bir qismi; ish rejimida — qorbola buzilganiga javob (yumshoqroq).
    func crewThrow(from worker: Worker) {
        guard playMode || worker.retaliating else { return }
        let gentle = !playMode
        let start = worker.handPoint
        var target: CGPoint
        let mouse = NSEvent.mouseLocation
        if screenFrame.contains(mouse) {
            target = CGPoint(x: mouse.x - screenFrame.minX + CGFloat.random(in: -70...70),
                             y: mouse.y - screenFrame.minY + CGFloat.random(in: -60...60))
        } else {
            target = CGPoint(x: randomX(size.width * 0.2, size.width * 0.8),
                             y: randomX(size.height * 0.3, size.height * 0.75))
        }
        target.x = clamp(target.x, 90, size.width - 90)
        target.y = clamp(target.y, 90, size.height - 90)
        let hitPoint = target
        let control = CGPoint(x: (start.x + target.x) / 2, y: max(start.y, target.y) + 160)

        let ball = flyBall(from: start, to: target, control: control, duration: 0.8, fromScale: 0.35, toScale: 3.6,
                           size: 28 * ballFactor, z: 85, timing: .easeIn) { [weak self] flown in
            guard let self else {
                flown.removeFromSuperlayer()
                return
            }
            guard let index = self.incoming.firstIndex(where: { $0.layer === flown }) else { return }
            self.incoming.remove(at: index)
            flown.removeFromSuperlayer()
            self.splat(at: hitPoint, gentle: gentle)
            if !gentle { GameState.shared.crewScore += 1 }
        }
        incoming.append(IncomingBall(layer: ball, thrower: worker))
    }

    // MARK: - Hisob paneli

    private func setupHUD() {
        let width: CGFloat = 340
        let height: CGFloat = 54
        let background = CAShapeLayer()
        background.path = CGPath(roundedRect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
                                 cornerWidth: 16, cornerHeight: 16, transform: nil)
        background.fillColor = cg(0x0F1B2D, 0.78)
        background.strokeColor = cg(0xFFFFFF, 0.22)
        background.lineWidth = 1
        background.contentsScale = scale
        hud.addSublayer(background)
        configureText(scoreLayer, fontName: "HelveticaNeue-Bold", fontSize: 18, color: whiteColor, width: width, y: 9)
        configureText(hintLayer, fontName: "HelveticaNeue-Medium", fontSize: 11, color: cg(0xFFFFFF, 0.8), width: width, y: -13)
        hintLayer.string = "Bosing: qor oting. Ishga qaytish: ⌃⌥G yoki Esc"
        hud.position = CGPoint(x: size.width / 2, y: size.height - 72)
        hud.zPosition = 100
        hud.isHidden = true
        root.addSublayer(hud)
    }

    private func configureText(_ layer: CATextLayer, fontName: String, fontSize: CGFloat, color: CGColor,
                               width: CGFloat, y: CGFloat) {
        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        layer.font = font
        layer.fontSize = fontSize
        layer.foregroundColor = color
        layer.alignmentMode = .center
        layer.contentsScale = scale
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        layer.bounds = CGRect(x: 0, y: 0, width: width, height: lineHeight)
        layer.position = CGPoint(x: 0, y: y)
        hud.addSublayer(layer)
    }

    private func refreshHUD() {
        guard playMode else { return }
        let state = GameState.shared
        guard state.playerScore != shownPlayer || state.crewScore != shownCrew else { return }
        shownPlayer = state.playerScore
        shownCrew = state.crewScore
        let text = "Siz  \(state.playerScore)  :  \(state.crewScore)  Ishchilar"
        instant { scoreLayer.string = text }
    }
}
