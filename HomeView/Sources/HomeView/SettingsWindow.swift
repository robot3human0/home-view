import AppKit
import HomeViewProtocol
import ServiceManagement
import SwiftUI

// MARK: - Model: sozlamalar oynasi ↔ Settings (ikki tomonlama)

/// Oynadagi slayderlar shu modelga bog‘langan. Slayder surilsa — Settings darhol yangilanadi
/// (ekrandagi qor va personajlar jonli o‘zgaradi). Menyudan yoki ⌥ + g‘ildirak bilan o‘zgartirilsa —
/// oyna ham o‘zini yangilaydi.
final class SettingsModel: ObservableObject {
    @Published var snowAmount: Double = 0.4 { didSet { if !syncing { Settings.shared.snowAmount = snowAmount } } }
    @Published var windStrength: Double = 0 { didSet { if !syncing { Settings.shared.windStrength = windStrength } } }
    @Published var windGusty = true { didSet { if !syncing { Settings.shared.windGusty = windGusty } } }

    @Published var flakeScale: Double = 1 { didSet { if !syncing { Settings.shared.flakeScale = flakeScale } } }
    @Published var snowmanScale: Double = 1 { didSet { if !syncing { Settings.shared.snowmanScale = snowmanScale } } }
    @Published var workerScale: Double = 1 { didSet { if !syncing { Settings.shared.workerScale = workerScale } } }
    @Published var plowScale: Double = 1 { didSet { if !syncing { Settings.shared.plowScale = plowScale } } }
    @Published var ballScale: Double = 1 { didSet { if !syncing { Settings.shared.ballScale = ballScale } } }

    @Published var crewCount: Double = 4 { didSet { if !syncing { Settings.shared.crewCount = Int(crewCount.rounded()) } } }
    @Published var plowCount: Double = 1 { didSet { if !syncing { Settings.shared.plowCount = Int(plowCount.rounded()) } } }
    @Published var snowmanCount: Double = 2 { didSet { if !syncing { Settings.shared.snowmanCount = Int(snowmanCount.rounded()) } } }

    @Published var mouseInWorkMode = true { didSet { if !syncing { Settings.shared.mouseInWorkMode = mouseInWorkMode } } }
    @Published var crewFightsBack = true { didSet { if !syncing { Settings.shared.crewFightsBack = crewFightsBack } } }
    @Published var santaEnabled = true { didSet { if !syncing { Settings.shared.santaEnabled = santaEnabled } } }
    @Published var snowOnWindows = true { didSet { if !syncing { Settings.shared.snowOnWindows = snowOnWindows } } }
    @Published var showInFullScreen = false { didSet { if !syncing { Settings.shared.showInFullScreen = showInFullScreen } } }
    @Published var hideFromCapture = true { didSet { if !syncing { Settings.shared.hideFromCapture = hideFromCapture } } }
    @Published var launchAtLogin = false { didSet { if !syncing { applyLaunchAtLogin() } } }
    @Published var loginError: String?

    // Fasl
    @Published var seasonChoice: Int = 0 { didSet { if !syncing { Settings.shared.seasonChoice = seasonChoice } } }
    @Published var weatherChoice = "auto" { didSet { if !syncing { Settings.shared.weatherChoice = weatherChoice } } }

    // Ofis
    @Published var officeEnabled = false { didSet { if !syncing { Settings.shared.officeEnabled = officeEnabled } } }
    @Published var displayName = "" { didSet { if !syncing { Settings.shared.displayName = displayName } } }
    @Published var team = "" { didSet { if !syncing { Settings.shared.team = team } } }
    @Published var avatar = AvatarStyle.standard { didSet { if !syncing { Settings.shared.avatar = avatar } } }
    @Published var myStatus: PeerStatus = .active { didSet { if !syncing { Settings.shared.myStatus = myStatus } } }
    @Published var serverAddress = ""
    @Published var officeCode = ""

    var resolvedSeason: SeasonKind {
        seasonChoice == 0 ? SeasonKind.current() : SeasonKind.allCases[max(0, min(3, seasonChoice - 1))]
    }

    /// Server manzili va ofis kodi har harfda emas, "Saqlash" bosilganda qo‘llanadi.
    func applyServer(address: String, code: String) {
        Settings.shared.serverAddress = address
        Settings.shared.officeCode = code
    }

    private var syncing = false
    private var observer: NSObjectProtocol?

    init() {
        pull()
        observer = NotificationCenter.default.addObserver(forName: .qorSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.pull()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func resetSizes() {
        Settings.shared.resetSizes()
    }

    /// Settings → model. Faqat haqiqatan o‘zgargan qiymatlar yangilanadi (surish paytida titramasligi uchun).
    private func pull() {
        syncing = true
        defer { syncing = false }
        let s = Settings.shared
        if abs(snowAmount - s.snowAmount) > 0.0005 { snowAmount = s.snowAmount }
        if abs(windStrength - s.windStrength) > 0.0005 { windStrength = s.windStrength }
        if abs(flakeScale - s.flakeScale) > 0.0005 { flakeScale = s.flakeScale }
        if abs(snowmanScale - s.snowmanScale) > 0.0005 { snowmanScale = s.snowmanScale }
        if abs(workerScale - s.workerScale) > 0.0005 { workerScale = s.workerScale }
        if abs(plowScale - s.plowScale) > 0.0005 { plowScale = s.plowScale }
        if abs(ballScale - s.ballScale) > 0.0005 { ballScale = s.ballScale }
        if Int(crewCount.rounded()) != s.crewCount { crewCount = Double(s.crewCount) }
        if Int(plowCount.rounded()) != s.plowCount { plowCount = Double(s.plowCount) }
        if Int(snowmanCount.rounded()) != s.snowmanCount { snowmanCount = Double(s.snowmanCount) }
        if windGusty != s.windGusty { windGusty = s.windGusty }
        if mouseInWorkMode != s.mouseInWorkMode { mouseInWorkMode = s.mouseInWorkMode }
        if crewFightsBack != s.crewFightsBack { crewFightsBack = s.crewFightsBack }
        if santaEnabled != s.santaEnabled { santaEnabled = s.santaEnabled }
        if snowOnWindows != s.snowOnWindows { snowOnWindows = s.snowOnWindows }
        if showInFullScreen != s.showInFullScreen { showInFullScreen = s.showInFullScreen }
        if hideFromCapture != s.hideFromCapture { hideFromCapture = s.hideFromCapture }
        if seasonChoice != s.seasonChoice { seasonChoice = s.seasonChoice }
        if weatherChoice != s.weatherChoice { weatherChoice = s.weatherChoice }
        if officeEnabled != s.officeEnabled { officeEnabled = s.officeEnabled }
        if displayName != s.displayName { displayName = s.displayName }
        if team != s.team { team = s.team }
        if avatar != s.avatar { avatar = s.avatar }
        if myStatus != s.myStatus { myStatus = s.myStatus }
        if serverAddress != s.serverAddress { serverAddress = s.serverAddress }
        if officeCode != s.officeCode { officeCode = s.officeCode }
        let loginEnabled = SMAppService.mainApp.status == .enabled
        if launchAtLogin != loginEnabled { launchAtLogin = loginEnabled }
    }

    private func applyLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if launchAtLogin {
                try service.register()
            } else {
                try service.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Yoqib bo‘lmadi: ilovani Applications papkasiga ko‘chirib, qaytadan urinib ko‘ring."
            syncing = true
            launchAtLogin = service.status == .enabled
            syncing = false
        }
    }
}

// MARK: - Oyna

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "HomeView — sozlamalar"
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            newWindow.setContentSize(NSSize(width: 600, height: 800))
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Ko‘rinish

struct SettingsView: View {
    @StateObject private var model = SettingsModel()
    @ObservedObject private var office = Office.shared
    @State private var addressDraft = ""
    @State private var codeDraft = ""

    var body: some View {
        let theme = SeasonTheme.theme(model.resolvedSeason)
        Form {
            Section {
                SeasonPreview(model: model, theme: theme)
                Picker("Fasl", selection: $model.seasonChoice) {
                    Text("Avto").tag(0)
                    ForEach(Array(SeasonKind.allCases.enumerated()), id: \.offset) { index, kind in
                        Text("\(kind.emoji) \(kind.title)").tag(index + 1)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(model.seasonChoice == 0
                     ? "Avtomatik: fasl sanaga qarab o‘zi almashadi (hozir \(SeasonKind.current().title.lowercased()))."
                     : "\(theme.kind.title): \(theme.particleTitle.lowercased()) yog‘adi, brigada \(theme.monumentTitle.lowercased()) yasaydi, osmondan \(theme.visitorTitle.lowercased()) uchib o‘tadi.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Holat", selection: weatherBinding(for: theme.kind)) {
                    Text("Avtomatik").tag("auto")
                    ForEach(WeatherKind.options(for: theme.kind), id: \.self) { kind in
                        Text("\(kind.emoji) \(kind.title)").tag(kind.rawValue)
                    }
                }
                SliderRow(icon: theme.particleEmoji, title: theme.particleTitle, value: $model.snowAmount, range: 0...1,
                          text: Settings.snowTitle(model.snowAmount))
                SliderRow(icon: "💨", title: "Shamol", value: $model.windStrength, range: -1...1,
                          text: Settings.windTitle(model.windStrength))
                Toggle("O‘zgaruvchan shamol (vaqti-vaqti bilan bo‘ron)", isOn: $model.windGusty)
            } header: {
                Text("Ob-havo")
            } footer: {
                Text(weatherFooter(for: theme.kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                SliderRow(icon: theme.particleEmoji, title: theme.particleTitle, value: $model.flakeScale, range: SizeRange.flake,
                          text: Settings.percentTitle(model.flakeScale))
                SliderRow(icon: theme.monumentEmoji, title: theme.monumentPlural, value: $model.snowmanScale, range: SizeRange.snowman,
                          text: Settings.percentTitle(model.snowmanScale))
                SliderRow(icon: "👷", title: "Ishchilar", value: $model.workerScale, range: SizeRange.worker,
                          text: Settings.percentTitle(model.workerScale))
                SliderRow(icon: "🚜", title: "Mashinalar", value: $model.plowScale, range: SizeRange.plow,
                          text: Settings.percentTitle(model.plowScale))
                SliderRow(icon: "⚪", title: theme.projectileTitle, value: $model.ballScale, range: SizeRange.ball,
                          text: Settings.percentTitle(model.ballScale))
                HStack {
                    Spacer()
                    Button("Asl o‘lchamlarga qaytarish") { model.resetSizes() }
                }
            } header: {
                Text("O‘lchamlar")
            } footer: {
                Text("Ish stolida tezroq: ⌥ tugmasini bosib turib, odamcha, \(theme.monumentTitle.lowercased()) yoki mashina ustida g‘ildirakni aylantiring.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Brigada") {
                SliderRow(icon: "👷", title: "Ishchilar soni", value: $model.crewCount,
                          range: Double(CountRange.crew.lowerBound)...Double(CountRange.crew.upperBound), step: 1,
                          text: model.crewCount < 0.5 ? "Yo‘q" : "\(Int(model.crewCount.rounded())) kishi")
                SliderRow(icon: "🚜", title: "Mashinalar soni", value: $model.plowCount,
                          range: Double(CountRange.plows.lowerBound)...Double(CountRange.plows.upperBound), step: 1,
                          text: model.plowCount < 0.5 ? "Yo‘q" : "\(Int(model.plowCount.rounded())) ta")
                SliderRow(icon: theme.monumentEmoji, title: "\(theme.monumentPlural) soni", value: $model.snowmanCount,
                          range: Double(CountRange.snowmen.lowerBound)...Double(CountRange.snowmen.upperBound), step: 1,
                          text: "\(Int(model.snowmanCount.rounded())) ta")
                Toggle("Ish paytida sichqoncha bilan tegish", isOn: $model.mouseInWorkMode)
                Toggle("Yasaganlari qayta-qayta buzilsa, ishchilar javob qaytarsin", isOn: $model.crewFightsBack)
            }

            officeSection

            Section("Umumiy") {
                Toggle("\(theme.visitorTitle) uchib o‘tsin", isOn: $model.santaEnabled)
                Toggle("Oynalar ustiga ham yog‘sin", isOn: $model.snowOnWindows)
                Toggle("To‘liq ekranli ilovalarda ham ko‘rinsin", isOn: $model.showInFullScreen)
                Toggle("Skrinshot va ekran ulashishda ko‘rinmasin", isOn: $model.hideFromCapture)
                Toggle("Kompyuter yonganda ishga tushsin", isOn: $model.launchAtLogin)
                if let error = model.loginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 560, idealWidth: 620, minHeight: 600, idealHeight: 860)
        .onAppear {
            addressDraft = model.serverAddress
            codeDraft = model.officeCode
        }
    }

    // MARK: Ofis bo‘limlari
    // macOS'dagi grouped Form har qatorni "nom — boshqaruv" ko‘rinishida tekislaydi.
    // Shuning uchun har qatorda faqat bitta boshqaruv turadi — hech narsa ustma-ust tushmaydi.

    @ViewBuilder
    private var officeSection: some View {
        Section {
            Toggle("Ofisga ulanish", isOn: $model.officeEnabled)
            if model.officeEnabled {
                connectionRow
            }
        } header: {
            Text("Ofis")
        } footer: {
            Text("Hamkasblaringiz odamchalari, xabarlar va tarmoq o‘yinlari. Ofis tarmog‘idagi Mac mini'da HomeView serveri ishlayotgan bo‘lsa, ilova uni o‘zi topadi.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if model.officeEnabled {
            Section("Profil") {
                TextField("Ism", text: $model.displayName, prompt: Text("Masalan: Jasur"))
                TextField("Jamoa", text: $model.team, prompt: Text("Masalan: iOS"))
                Picker("Holatim", selection: $model.myStatus) {
                    Text("🟢 Faol").tag(PeerStatus.active)
                    Text("🔕 Band").tag(PeerStatus.busy)
                    Text("👻 Ko‘rinmas").tag(PeerStatus.hidden)
                }
                .pickerStyle(.segmented)
                LabeledContent("Ekrandagi hamkasblar") {
                    HStack(spacing: 10) {
                        Text(peopleSummary)
                            .foregroundStyle(.secondary)
                        Button("Tanlash…") { PeopleWindowController.shared.show() }
                    }
                }
            }

            Section("Odamcha") {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        AvatarPreview(style: model.avatar)
                        Text(avatarCaption)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
                Picker("Bosh kiyim", selection: $model.avatar.hat) {
                    Text("Do‘ppi").tag(HatStyle.doppi)
                    Text("Kepka").tag(HatStyle.cap)
                    Text("Shapka").tag(HatStyle.beanie)
                    Text("Shlyapa").tag(HatStyle.strawHat)
                }
                .pickerStyle(.segmented)
                LabeledContent("Bosh kiyim rangi") {
                    SwatchPicker(colors: [0x1E3A5F, 0x1B1B1B, 0xC62828, 0x2E7D32, 0x6A1B9A, 0xEF6C00],
                                 selection: $model.avatar.hatColor)
                }
                LabeledContent("Nimcha rangi") {
                    SwatchPicker(colors: [0x1E88E5, 0xF57C00, 0x43A047, 0xE53935, 0x8E24AA, 0x00897B],
                                 selection: $model.avatar.vestColor)
                }
                LabeledContent("Yuz rangi") {
                    SwatchPicker(colors: [0xFFDBAC, 0xF1C27D, 0xE0AC69, 0xC68642, 0x8D5524],
                                 selection: $model.avatar.skinColor)
                }
            }

            Section {
                TextField("Server manzili", text: $addressDraft, prompt: Text("Bo‘sh qoldiring — o‘zi topadi"))
                TextField("Ofis kodi", text: $codeDraft, prompt: Text("Agar o‘rnatilgan bo‘lsa"))
                HStack {
                    Spacer()
                    Button("Saqlash va qayta ulanish") {
                        model.applyServer(address: addressDraft, code: codeDraft)
                    }
                    .disabled(!serverDraftChanged)
                }
            } header: {
                Text("Server")
            } footer: {
                Text("Manzilni faqat server o‘zi topilmasa kiriting, masalan: 192.168.1.20")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var connectionRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connectionColor)
                .frame(width: 9, height: 9)
            Text(connectionText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
    }

    private var connectionColor: Color {
        switch office.connection {
        case .connected: return .green
        case .off, .notConfigured: return .gray
        case .failed: return .red
        case .searching, .connecting: return .orange
        }
    }

    private var connectionText: String {
        if office.connection == .connected {
            return "Ulangan — \(office.peers.count) kishi onlayn"
        }
        return office.connection.text
    }

    private var avatarCaption: String {
        let name = model.displayName.isEmpty ? "Ismingiz" : model.displayName
        if model.team.isEmpty { return name }
        return name + " · " + model.team
    }

    /// Boshqa faslning holati tanlangan bo‘lsa — "Avtomatik" ko‘rinadi.
    private func weatherBinding(for season: SeasonKind) -> Binding<String> {
        let options = WeatherKind.options(for: season).map { $0.rawValue }
        return Binding(
            get: { options.contains(model.weatherChoice) ? model.weatherChoice : "auto" },
            set: { model.weatherChoice = $0 }
        )
    }

    private func weatherFooter(for season: SeasonKind) -> String {
        if let kind = WeatherKind(rawValue: model.weatherChoice), kind.season == season {
            return kind.summary
        }
        let now = WeatherDirector.shared.current
        if now.season == season {
            return "Avtomatik: holatlar 20–45 daqiqada o‘zi almashadi. Hozir — \(now.emoji) \(now.title.lowercased())."
        }
        return "Avtomatik: holatlar 20–45 daqiqada o‘zi almashadi, kechasi o‘ziga xos holatlar chiqadi."
    }

    private var peopleSummary: String {
        let everyone = office.colleagues
        let shown = everyone.filter { $0.shown }.count
        return "\(shown) / \(everyone.count)"
    }

    private var serverDraftChanged: Bool {
        addressDraft != model.serverAddress || codeDraft != model.officeCode
    }
}

/// Rang tanlash: bir qator dumaloq namunalar, tanlangani ta’kidlanadi.
struct SwatchPicker: View {
    let colors: [UInt32]
    @Binding var selection: UInt32

    var body: some View {
        HStack(spacing: 10) {
            ForEach(colors, id: \.self) { hex in
                SwatchDot(color: Color(cgColor: cg(hex)), selected: selection == hex)
                    .onTapGesture { selection = hex }
            }
        }
    }
}

struct SwatchDot: View {
    let color: Color
    let selected: Bool

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 22, height: 22)
            .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
            .overlay(
                Circle()
                    .stroke(Color.accentColor, lineWidth: 2.5)
                    .padding(-4)
                    .opacity(selected ? 1 : 0)
            )
            .contentShape(Circle())
            .animation(.easeOut(duration: 0.15), value: selected)
    }
}

/// Odamchangiz qanday ko‘rinishi.
struct AvatarPreview: View {
    let style: AvatarStyle

    var body: some View {
        let part = Art.avatarPreview(style)
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.2, green: 0.33, blue: 0.53), Color(red: 0.45, green: 0.6, blue: 0.8)],
                                     startPoint: .top, endPoint: .bottom))
            if let image = part.image {
                Image(decorative: image, scale: Art.scale)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: part.box.width * 2.2, height: part.box.height * 2.2)
                    .padding(.bottom, 8)
            }
        }
        .frame(width: 96, height: 120)
    }
}

/// Bitta slayder qatori: [belgi] [nom] [━━━●━━] [qiymat].
struct SliderRow: View {
    let icon: String
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Text(icon)
                .frame(width: 24)
            Text(title)
                .frame(width: 140, alignment: .leading)
            if let step {
                Slider(value: $value, in: range, step: step)
            } else {
                Slider(value: $value, in: range)
            }
            Text(text)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .trailing)
        }
    }
}

// MARK: - Jonli ko‘rinish

/// Tanlangan faslning kichik manzarasi: yog‘ayotgan narsa, ishchi, yodgorlik, mashina va to‘p.
struct SeasonPreview: View {
    @ObservedObject var model: SettingsModel
    let theme: SeasonTheme
    private let previewScale: CGFloat = 0.7

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(red: theme.skyTop.0, green: theme.skyTop.1, blue: theme.skyTop.2),
                                    Color(red: theme.skyBottom.0, green: theme.skyBottom.1, blue: theme.skyBottom.2)],
                           startPoint: .top, endPoint: .bottom)
            FallingSnow(image: theme.particleImage, tints: theme.kind == .winter ? [] : theme.layers.map { Color(cgColor: $0.color) },
                        spin: theme.layers.last?.spin ?? 0, amount: model.snowAmount,
                        flakeScale: model.flakeScale, wind: model.windStrength, slow: theme.kind == .summer)
            Rectangle()
                .fill(Color(cgColor: theme.pileFill))
                .frame(height: 16)
            HStack(alignment: .bottom, spacing: 20) {
                ArtImage(part: theme.workerPreview, scale: CGFloat(model.workerScale) * previewScale)
                ArtImage(part: theme.monumentPreview, scale: CGFloat(model.snowmanScale) * previewScale)
                ArtImage(part: theme.vehiclePreview, scale: CGFloat(model.plowScale) * previewScale)
                BallImage(image: theme.projectileImage, scale: CGFloat(model.ballScale) * previewScale)
            }
            .padding(.bottom, 11)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: model.workerScale)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: model.snowmanScale)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: model.plowScale)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: model.ballScale)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(.easeInOut(duration: 0.4), value: theme.kind)
    }
}

struct ArtImage: View {
    let part: Part
    let scale: CGFloat

    var body: some View {
        if let image = part.image {
            Image(decorative: image, scale: Art.scale)
                .resizable()
                .interpolation(.high)
                .frame(width: part.box.width * scale, height: part.box.height * scale)
        }
    }
}

struct BallImage: View {
    let image: CGImage?
    let scale: CGFloat

    var body: some View {
        if let image {
            Image(decorative: image, scale: Art.scale)
                .resizable()
                .interpolation(.high)
                .frame(width: 28 * scale, height: 28 * scale)
                .padding(.bottom, 4)
        }
    }
}

/// Jonli ko‘rinishdagi yog‘ayotgan narsalar (Canvas + TimelineView, ilovaning o‘z rasmlari bilan).
struct FallingSnow: View {
    let image: CGImage?
    let tints: [Color]
    let spin: CGFloat
    let amount: Double
    let flakeScale: Double
    let wind: Double
    let slow: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                guard let image, amount >= 0.02 else { return }
                var resolved: [GraphicsContext.ResolvedImage] = []
                if tints.isEmpty {
                    resolved = [context.resolve(Image(decorative: image, scale: Art.scale))]
                } else {
                    for tint in tints {
                        var shaded = context.resolve(Image(decorative: image, scale: Art.scale))
                        shaded.shading = .color(tint)
                        resolved.append(shaded)
                    }
                }
                let time = timeline.date.timeIntervalSinceReferenceDate
                let width = Double(size.width)
                let height = Double(size.height)
                let count = Int((slow ? 6 : 12) + amount * (slow ? 30 : 100))
                for i in 0..<count {
                    let seed = Double(i) * 0.6180339887
                    let fallSpeed = (slow ? 8.0 : 20.0) + Double(i % 5) * (slow ? 3.0 : 9.0)
                    let phase = (Double(i) * 0.3779).truncatingRemainder(dividingBy: 1)
                    let progress = (time * fallSpeed / height + phase).truncatingRemainder(dividingBy: 1)
                    let baseX: Double = seed.truncatingRemainder(dividingBy: 1) * width
                    let drift: Double = wind * 70 * progress
                    let sway: Double = sin(time * 1.3 + seed * 6) * 6
                    var x = baseX + drift + sway
                    x = x.truncatingRemainder(dividingBy: width)
                    if x < 0 { x += width }
                    let y = progress * height
                    let diameter = (4.0 + Double(i % 3) * 2.4) * flakeScale
                    var copy = context
                    copy.translateBy(x: x, y: y)
                    if spin > 0 {
                        copy.rotate(by: .radians(time * Double(spin) * (i % 2 == 0 ? 1 : -1) + seed * 6))
                    }
                    copy.draw(resolved[i % resolved.count], in: CGRect(x: -diameter / 2, y: -diameter / 2, width: diameter, height: diameter))
                }
            }
        }
    }
}
