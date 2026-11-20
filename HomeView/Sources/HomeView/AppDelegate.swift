import AppKit
import Carbon.HIToolbox
import QuartzCore
import ServiceManagement

/// Ilovaning "miyasi": menyu satridagi ❄ belgisi, har bir ekran uchun overlay,
/// oynalarni kuzatish taymeri va global klaviatura yorliqlari.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var overlays: [OverlayController] = []
    private let tracker = WindowTracker()
    private let pollQueue = DispatchQueue(label: "uz.homeview.windows", qos: .utility)
    private var pollTimer: Timer?
    private var logicTimer: Timer?
    private var pollInFlight = false
    private var lastPoll: CFTimeInterval = 0
    private var lastLogic: CFTimeInterval = 0
    private var activeUntil: CFTimeInterval = 0

    /// Mantiqiy qadam: sekundiga 20 marta. Oradagi silliq harakatni Core Animation chizadi.
    private static let logicInterval: CFTimeInterval = 1.0 / 20

    private let hotKeyToggleGame: UInt32 = 1
    private let hotKeyEscape: UInt32 = 2

    // MARK: - Ishga tushish

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        WeatherDirector.shared.refresh(season: SeasonTheme.current.kind)
        setupStatusItem()
        buildOverlays()
        ToastCenter.shared.start()
        Office.shared.applySettings()

        // Avtomatik faslda — sana o‘zgarishini kuzatib turamiz
        let seasonTimer = Timer(timeInterval: 600, repeats: true) { [weak self] _ in self?.checkSeason() }
        RunLoop.main.add(seasonTimer, forMode: .common)

        // Avtomatik ob-havo — har daqiqada tekshiriladi (holat 20–45 daqiqada almashadi)
        let weatherTimer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.refreshWeather(announce: true) }
        RunLoop.main.add(weatherTimer, forMode: .common)

        let poll = Timer(timeInterval: 1.0 / 30, target: self, selector: #selector(pollTick),
                         userInfo: nil, repeats: true)
        RunLoop.main.add(poll, forMode: .common)
        pollTimer = poll

        lastLogic = CACurrentMediaTime()
        let logic = Timer(timeInterval: AppDelegate.logicInterval, target: self, selector: #selector(logicTick),
                          userInfo: nil, repeats: true)
        RunLoop.main.add(logic, forMode: .common)
        logicTimer = logic

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(screensChanged),
                           name: NSApplication.didChangeScreenParametersNotification, object: nil)
        center.addObserver(self, selector: #selector(settingsChanged),
                           name: .qorSettingsChanged, object: nil)
        center.addObserver(self, selector: #selector(hotKeyPressed(_:)),
                           name: .qorHotKey, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged),
                                                          name: NSWorkspace.activeSpaceDidChangeNotification,
                                                          object: nil)

        HotKeys.shared.register(id: hotKeyToggleGame,
                                keyCode: UInt32(kVK_ANSI_G),
                                modifiers: UInt32(controlKey | optionKey))
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeys.shared.unregisterAll()
        pollTimer?.invalidate()
        logicTimer?.invalidate()
    }

    // MARK: - Ekranlar

    private func buildOverlays() {
        overlays.forEach { $0.close() }
        overlays = NSScreen.screens.enumerated().map { OverlayController(screen: $0.element, isPrimary: $0.offset == 0) }
        Office.shared.world = overlays.first?.world
        if GameState.shared.playMode {
            overlays.forEach { $0.setPlayMode(true) }
        }
        lastPoll = 0
    }

    @objc private func screensChanged() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(rebuildOverlaysNow), object: nil)
        perform(#selector(rebuildOverlaysNow), with: nil, afterDelay: 0.6)
    }

    @objc private func rebuildOverlaysNow() {
        buildOverlays()
    }

    @objc private func spaceChanged() {
        lastPoll = 0
        activeUntil = CACurrentMediaTime() + 1
    }

    @objc private func settingsChanged() {
        if Settings.shared.resolvedSeason != SeasonTheme.current.kind {
            switchSeason()
        } else {
            overlays.forEach { $0.applySettings() }
            refreshWeather(announce: false)
        }
        Office.shared.applySettings()
    }

    /// Ob-havo holati o‘zgargan bo‘lsa — barcha monitorlarga silliq o‘tkazadi.
    private func refreshWeather(announce: Bool) {
        let director = WeatherDirector.shared
        guard director.refresh(season: SeasonTheme.current.kind) else { return }
        let kind = director.current
        overlays.forEach { $0.world.applyWeather(kind, animated: true) }
        if announce && director.isAuto {
            Office.shared.post(Toast(icon: kind.emoji, title: kind.title, message: kind.summary, autoDismiss: 5))
        }
    }

    private func checkSeason() {
        if Settings.shared.resolvedSeason != SeasonTheme.current.kind { switchSeason() }
    }

    /// Fasl almashganda: ekran sekin so‘nadi, yangi fasl bilan qayta paydo bo‘ladi.
    private func switchSeason() {
        let kind = Settings.shared.resolvedSeason
        SeasonTheme.current = SeasonTheme.theme(kind)
        WeatherDirector.shared.refresh(season: kind)
        updateStatusIcon()
        let panels = overlays.map { $0.panel }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.5
            panels.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.buildOverlays()
            let fresh = self.overlays.map { $0.panel }
            fresh.forEach { $0.alphaValue = 0 }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.8
                fresh.forEach { $0.animator().alphaValue = 1 }
            }
            let theme = SeasonTheme.current
            Office.shared.post(Toast(icon: kind.emoji, title: "\(kind.title) keldi!",
                                     message: "Endi \(theme.particleTitle.lowercased()) yog‘adi, brigada \(theme.monumentTitle.lowercased()) yasaydi.",
                                     autoDismiss: 5))
        })
    }

    /// Oynalarni kuzatish: tinch paytda sekundiga ~8 marta, oyna siljiyotganda ~20 marta.
    /// Ro‘yxat fon oqimida olinadi — asosiy oqim (animatsiya) bir lahza ham to‘xtamaydi.
    @objc private func pollTick() {
        updateMouseCapture()
        let now = CACurrentMediaTime()
        let interval = now < activeUntil ? 1.0 / 20 : 1.0 / 8
        guard !pollInFlight, now - lastPoll >= interval - 0.002 else { return }
        lastPoll = now
        pollInFlight = true
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let tracker = self.tracker
        pollQueue.async { [weak self] in
            let windows = tracker.snapshot(primaryHeight: primaryHeight)
            DispatchQueue.main.async {
                self?.applyWindows(windows)
            }
        }
    }

    /// Har 1/30 sekundda: sichqoncha qorbola, ishchi, sovg‘a yoki mashina ustidami?
    /// Ha bo‘lsa — panel bosishni qabul qiladi; yo‘q bo‘lsa — bosish ostidagi ilovaga o‘tadi.
    /// Shuning uchun qorbolani bemalol bosish mumkin, ish esa hech qachon to‘silmaydi.
    private func updateMouseCapture() {
        let playing = GameState.shared.playMode
        let allowed = Settings.shared.mouseInWorkMode
        let mouse = NSEvent.mouseLocation
        for overlay in overlays {
            let frame = overlay.screen.frame
            var capture = playing
            if frame.contains(mouse) {
                let local = CGPoint(x: mouse.x - frame.minX, y: mouse.y - frame.minY)
                if overlay.world.capturesAllInput {
                    capture = true
                } else if !playing && allowed {
                    capture = overlay.world.isInteractive(at: local)
                }
                overlay.world.hover(at: allowed || playing ? local : nil)
            } else {
                overlay.world.hover(at: nil)
            }
            let shouldIgnore = !capture
            if overlay.panel.ignoresMouseEvents != shouldIgnore {
                overlay.panel.ignoresMouseEvents = shouldIgnore
            }
        }
    }

    private func applyWindows(_ windows: [TrackedWindow]) {
        pollInFlight = false
        let now = CACurrentMediaTime()
        var moved = false
        for overlay in overlays where overlay.world.applyWindows(windows, now: now) {
            moved = true
        }
        if moved { activeUntil = now + 1.2 }
    }

    /// Barcha monitorlardagi dunyolarni bir qadam oldinga suradi. Shu qadamda berilgan
    /// yangi joylarga Core Animation keyingi 1/20 sekund davomida silliq olib boradi.
    @objc private func logicTick() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(max(now - lastLogic, 0), 0.1))
        lastLogic = now
        CATransaction.begin()
        CATransaction.setAnimationDuration(AppDelegate.logicInterval)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        for overlay in overlays { overlay.world.tick(dt) }
        CATransaction.commit()
    }

    /// Sichqoncha turgan ekran sahnasi (menyu buyruqlari shu ekranda bajariladi).
    private var currentWorld: SnowWorld? {
        let mouse = NSEvent.mouseLocation
        return (overlays.first(where: { $0.screen.frame.contains(mouse) }) ?? overlays.first)?.world
    }

    // MARK: - O‘yin rejimi

    private func setPlayMode(_ on: Bool) {
        let state = GameState.shared
        guard state.playMode != on else { return }
        state.playMode = on
        if on {
            state.resetScore()
            HotKeys.shared.register(id: hotKeyEscape, keyCode: UInt32(kVK_Escape), modifiers: 0)
        } else {
            HotKeys.shared.unregister(id: hotKeyEscape)
        }
        overlays.forEach { $0.setPlayMode(on) }
        updateStatusIcon()
    }

    @objc private func hotKeyPressed(_ note: Notification) {
        let id = (note.userInfo?["id"] as? NSNumber)?.uint32Value ?? (note.userInfo?["id"] as? UInt32) ?? 0
        if id == hotKeyToggleGame {
            setPlayMode(!GameState.shared.playMode)
        } else if id == hotKeyEscape {
            setPlayMode(false)
        }
    }

    // MARK: - Menyu satri

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let symbol = GameState.shared.playMode ? "gamecontroller.fill" : SeasonTheme.current.kind.menuBarSymbol
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "HomeView") {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = GameState.shared.playMode ? "🎮" : "❄︎"
        }
    }

    /// Menyu har ochilganda yangidan yig‘iladi. Slayderlarni surgan zahoti ekrandagi
    /// qor, qorbolalar, odamlar va mashinalar o‘zgaradi — menyuni yopish shart emas.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = Settings.shared

        let theme = SeasonTheme.current
        let header = NSMenuItem(title: "HomeView — \(theme.kind.emoji) \(theme.kind.title)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let chessWaiting = Office.shared.chessTurnsWaiting
        if chessWaiting > 0 {
            menu.addItem(ClosureMenuItem("♟  Shaxmat — navbat sizda (\(chessWaiting))") {
                ChessWindowController.shared.show()
            })
        }
        if let update = Office.shared.availableUpdate {
            menu.addItem(ClosureMenuItem("🆕  Yangi versiya: HomeView \(update.version) — yuklab olish") {
                Office.shared.openDownloadPage()
            })
        }
        menu.addItem(.separator())

        // Fasl
        let seasonItem = NSMenuItem(title: "\(theme.kind.emoji)  Fasl: \(settings.seasonChoice == 0 ? "avtomatik" : theme.kind.title)",
                                    action: nil, keyEquivalent: "")
        let seasonMenu = NSMenu()
        seasonMenu.autoenablesItems = false
        let today = SeasonKind.current()
        let autoItem = ClosureMenuItem("Avtomatik — sanaga qarab (hozir \(today.emoji) \(today.title))") { Settings.shared.seasonChoice = 0 }
        autoItem.state = settings.seasonChoice == 0 ? .on : .off
        seasonMenu.addItem(autoItem)
        seasonMenu.addItem(.separator())
        for (index, kind) in SeasonKind.allCases.enumerated() {
            let item = ClosureMenuItem("\(kind.emoji)  \(kind.title)") { Settings.shared.seasonChoice = index + 1 }
            item.state = settings.seasonChoice == index + 1 ? .on : .off
            seasonMenu.addItem(item)
        }
        seasonItem.submenu = seasonMenu
        menu.addItem(seasonItem)

        // Ob-havo
        let director = WeatherDirector.shared
        let weatherNow = director.current
        let weatherTitle = director.isAuto
            ? "avtomatik (hozir: \(weatherNow.emoji) \(weatherNow.title.lowercased()))"
            : "\(weatherNow.emoji) \(weatherNow.title)"
        let weatherItem = NSMenuItem(title: "🌦  Ob-havo: \(weatherTitle)", action: nil, keyEquivalent: "")
        let weatherMenu = NSMenu()
        weatherMenu.autoenablesItems = false
        let autoWeather = ClosureMenuItem("Avtomatik — vaqti-vaqti bilan o‘zi almashadi") {
            Settings.shared.weatherChoice = "auto"
        }
        autoWeather.state = director.isAuto ? .on : .off
        weatherMenu.addItem(autoWeather)
        weatherMenu.addItem(.separator())
        for option in WeatherKind.options(for: theme.kind) {
            let item = ClosureMenuItem("\(option.emoji)  \(option.title)") {
                Settings.shared.weatherChoice = option.rawValue
            }
            item.state = (!director.isAuto && weatherNow == option) ? .on : .off
            item.toolTip = option.summary
            weatherMenu.addItem(item)
        }
        weatherItem.submenu = weatherMenu
        menu.addItem(weatherItem)

        // Ofis
        let office = Office.shared
        let officeTitle: String
        if !settings.officeEnabled {
            officeTitle = "🏢  Ofis: o‘chirilgan"
        } else if office.isConnected {
            officeTitle = "🏢  Ofis: \(office.peers.count) kishi onlayn"
        } else {
            officeTitle = "🏢  Ofis: \(office.connection.text)"
        }
        let officeItem = NSMenuItem(title: officeTitle, action: nil, keyEquivalent: "")
        if settings.officeEnabled {
            officeItem.submenu = office.buildStatusMenu()
        } else {
            officeItem.action = #selector(openSettings)
            officeItem.target = self
        }
        menu.addItem(officeItem)
        menu.addItem(.separator())

        // Ob-havo
        menu.addItem(caption("Ob-havo"))
        menu.addItem(slider("\(theme.particleEmoji)  \(theme.particleTitle)", value: settings.snowAmount, range: 0...1,
                            format: Settings.snowTitle) { Settings.shared.snowAmount = $0 })
        menu.addItem(slider("💨  Shamol", value: settings.windStrength, range: -1...1,
                            format: Settings.windTitle) { Settings.shared.windStrength = $0 })
        menu.addItem(.separator())

        // O‘lchamlar
        menu.addItem(caption("O‘lchamlar"))
        menu.addItem(slider("\(theme.particleEmoji)  \(theme.particleTitle)", value: settings.flakeScale, range: SizeRange.flake,
                            format: Settings.percentTitle) { Settings.shared.flakeScale = $0 })
        menu.addItem(slider("\(theme.monumentEmoji)  \(theme.monumentPlural)", value: settings.snowmanScale, range: SizeRange.snowman,
                            format: Settings.percentTitle) { Settings.shared.snowmanScale = $0 })
        menu.addItem(slider("👷  Ishchilar", value: settings.workerScale, range: SizeRange.worker,
                            format: Settings.percentTitle) { Settings.shared.workerScale = $0 })
        menu.addItem(slider("🚜  Mashinalar", value: settings.plowScale, range: SizeRange.plow,
                            format: Settings.percentTitle) { Settings.shared.plowScale = $0 })
        menu.addItem(slider("⚪  \(theme.projectileTitle)", value: settings.ballScale, range: SizeRange.ball,
                            format: Settings.percentTitle) { Settings.shared.ballScale = $0 })
        menu.addItem(makeItem("Asl o‘lchamlarga qaytarish", #selector(resetSizes)))
        menu.addItem(.separator())

        // Brigada
        menu.addItem(caption("Brigada"))
        menu.addItem(slider("👷  Ishchilar soni", value: Double(settings.crewCount),
                            range: Double(CountRange.crew.lowerBound)...Double(CountRange.crew.upperBound), step: 1,
                            format: { $0 < 0.5 ? "Yo‘q" : "\(Int($0.rounded())) kishi" }) {
            Settings.shared.crewCount = Int($0.rounded())
        })
        menu.addItem(slider("🚜  Mashinalar soni", value: Double(settings.plowCount),
                            range: Double(CountRange.plows.lowerBound)...Double(CountRange.plows.upperBound), step: 1,
                            format: { $0 < 0.5 ? "Yo‘q" : "\(Int($0.rounded())) ta" }) {
            Settings.shared.plowCount = Int($0.rounded())
        })
        menu.addItem(slider("\(theme.monumentEmoji)  \(theme.monumentPlural) soni", value: Double(settings.snowmanCount),
                            range: Double(CountRange.snowmen.lowerBound)...Double(CountRange.snowmen.upperBound), step: 1,
                            format: { "\(Int($0.rounded())) ta" }) {
            Settings.shared.snowmanCount = Int($0.rounded())
        })
        menu.addItem(.separator())

        // O‘yin
        let gameItem = makeItem(GameState.shared.playMode ? "O‘yindan chiqish" : "O‘yin rejimi",
                                #selector(togglePlayMode), on: GameState.shared.playMode)
        gameItem.keyEquivalent = "g"
        gameItem.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(gameItem)
        menu.addItem(.separator())

        // Chaqiruvlar
        let visitorCall: String
        switch theme.visitor {
        case .santa: visitorCall = "Qorboboni chaqirish"
        case .swallows: visitorCall = "Qaldirg‘ochlarni chaqirish"
        case .balloon: visitorCall = "Havo sharini chaqirish"
        case .cranes: visitorCall = "Turnalarni chaqirish"
        }
        menu.addItem(makeItem("\(theme.monumentTitle) yasating", #selector(requestSnowman), enabled: settings.workersEnabled))
        menu.addItem(makeItem("\(theme.vehicleTitle)ni chaqirish", #selector(callPlow)))
        menu.addItem(makeItem(visitorCall, #selector(callSanta)))
        menu.addItem(makeItem("Hammasini tozalash", #selector(clearSnow)))
        menu.addItem(.separator())

        let settingsItem = makeItem("Sozlamalar va jonli ko‘rinish…", #selector(openSettings))
        settingsItem.keyEquivalent = ","
        menu.addItem(settingsItem)
        menu.addItem(caption("Maslahat: ⌥ tugmasini bosib turib, qorbola, ishchi yoki mashina ustida g‘ildirakni aylantiring (yoki trackpadda ikki barmoqni suring) — o‘lchami o‘sha yerning o‘zida o‘zgaradi."))
        menu.addItem(.separator())

        menu.addItem(makeItem("HomeView haqida", #selector(showAbout)))
        let quit = makeItem("Chiqish", #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func slider(_ title: String, value: Double, range: ClosedRange<Double>, step: Double? = nil,
                        format: @escaping (Double) -> String, onChange: @escaping (Double) -> Void) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = MenuSliderView(title: title, value: value, range: range, step: step,
                                   format: format, onChange: onChange)
        return item
    }

    private func caption(_ text: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = MenuCaptionView(text)
        return item
    }

    private func makeItem(_ title: String, _ action: Selector, on: Bool? = nil, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let on { item.state = on ? .on : .off }
        item.isEnabled = enabled
        return item
    }

    // MARK: - Menyu amallari

    @objc private func togglePlayMode() {
        setPlayMode(!GameState.shared.playMode)
    }

    @objc private func requestSnowman() { currentWorld?.requestSnowman() }
    @objc private func callPlow() { currentWorld?.callPlow() }
    @objc private func callSanta() { currentWorld?.callSanta() }
    @objc private func clearSnow() { overlays.forEach { $0.world.clearAllSnow() } }

    // MARK: - Spotlight va Shortcuts amallari (Intents.swift)

    func clearSnowFromIntent() {
        overlays.forEach { $0.world.clearAllSnow() }
    }

    func togglePlayModeFromIntent() {
        setPlayMode(!GameState.shared.playMode)
    }
    @objc private func resetSizes() { Settings.shared.resetSizes() }
    @objc private func openSettings() { SettingsWindowController.shared.show() }

    @objc private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        showAlert(title: "HomeView \(version)",
                  text: """
                  Ish stolingizga qish olib keladi: qor oynalar ustiga yog‘adi, ishchilar uni kuraydi, \
                  qorbola yasashadi, mashinalar yo‘lni tozalaydi, Qorbobo esa Qorqiz bilan uchib o‘tadi.

                  Ish paytida (sichqoncha bilan)
                  • Qorbolani bosing — avval shapkasi uchadi, keyin boshi tushadi, uchinchisida buziladi.
                  • Brigada achinadi va qayta yasaydi; yana buzsangiz, qo‘riqchi qo‘yadi; \
                  uchinchi marta — sizga qor otishadi.
                  • Ishchini bossangiz — kuladi; tez-tez bossangiz, jahli chiqadi.
                  • Mashinani bossangiz — signal chalib, tezlashadi.
                  • Qolgan joylarda bosish odatdagidek ostidagi ilovaga o‘tadi.

                  O‘yin rejimi — ⌃⌥G
                  • Bosgan joyingizga qor koptok otasiz.
                  • Uchib kelayotgan koptokni bosib ushlab qolsangiz, ochko olasiz.
                  • Qorbobo tashlagan sovg‘ani ursangiz — +3.

                  Ishga qaytish — ⌃⌥G yoki Esc.

                  O‘lchamlar va sonlar
                  • ❄ menyusidagi slayderlarni suring — hammasi darhol o‘zgaradi.
                  • Yoki ⌥ bosib turib, qorbola, ishchi yoki mashina ustida g‘ildirakni aylantiring.
                  • Hamma sozlamalar va jonli ko‘rinish — ⌘, (Sozlamalar oynasi).
                  """)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showAlert(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "Yaxshi")
        NSApp.activate()
        alert.runModal()
    }
}
