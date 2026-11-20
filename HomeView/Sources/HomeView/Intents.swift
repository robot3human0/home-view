import AppIntents
import AppKit
import HomeViewProtocol

// Spotlight (⌘ + Space) va Shortcuts ilovasi uchun amallar.
// macOS 26 da Spotlight bularni menyuni ochmasdan, to‘g‘ridan-to‘g‘ri bajaradi:
// masalan "HomeView band" yoki "HomeView qish".

// MARK: - Tanlovlar

enum SeasonOption: String, AppEnum {
    case automatic, winter, spring, summer, autumn

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Fasl"
    static var caseDisplayRepresentations: [SeasonOption: DisplayRepresentation] = [
        .automatic: "Avtomatik (sanaga qarab)",
        .winter: "Qish",
        .spring: "Bahor",
        .summer: "Yoz",
        .autumn: "Kuz",
    ]

    /// Settings.seasonChoice: 0 — avtomatik, 1...4 — SeasonKind tartibida.
    var choice: Int {
        switch self {
        case .automatic: return 0
        case .winter: return 1
        case .spring: return 2
        case .summer: return 3
        case .autumn: return 4
        }
    }
}

enum StatusOption: String, AppEnum {
    case active, busy, hidden

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Holat"
    static var caseDisplayRepresentations: [StatusOption: DisplayRepresentation] = [
        .active: "Faol",
        .busy: "Band",
        .hidden: "Ko‘rinmas",
    ]

    var peerStatus: PeerStatus {
        switch self {
        case .active: return .active
        case .busy: return .busy
        case .hidden: return .hidden
        }
    }
}

// MARK: - Amallar

struct SetSeasonIntent: AppIntent {
    static var title: LocalizedStringResource = "Faslni tanlash"
    static var description = IntentDescription("Ish stolidagi faslni almashtiradi: qish, bahor, yoz, kuz yoki sanaga qarab avtomatik.")

    @Parameter(title: "Fasl")
    var season: SeasonOption

    @MainActor
    func perform() async throws -> some IntentResult {
        Settings.shared.seasonChoice = season.choice
        return .result()
    }
}

struct SetStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Ofisdagi holatim"
    static var description = IntentDescription("Hamkasblarga ko‘rinadigan holatingiz: faol, band (takliflar kelmaydi) yoki ko‘rinmas.")

    @Parameter(title: "Holat")
    var status: StatusOption

    @MainActor
    func perform() async throws -> some IntentResult {
        Settings.shared.myStatus = status.peerStatus
        return .result()
    }
}

struct ClearSnowIntent: AppIntent {
    static var title: LocalizedStringResource = "Ekrandagi qorni tozalash"
    static var description = IntentDescription("Oynalar ustida va ekran pastida yig‘ilgan qor (gul, barg) bir zumda tozalanadi.")

    @MainActor
    func perform() async throws -> some IntentResult {
        (NSApp.delegate as? AppDelegate)?.clearSnowFromIntent()
        return .result()
    }
}

struct TogglePlayModeIntent: AppIntent {
    static var title: LocalizedStringResource = "O‘yin rejimi"
    static var description = IntentDescription("Qor otish rejimini yoqadi yoki o‘chiradi (⌃⌥G bilan bir xil).")

    @MainActor
    func perform() async throws -> some IntentResult {
        (NSApp.delegate as? AppDelegate)?.togglePlayModeFromIntent()
        return .result()
    }
}

struct OpenChessIntent: AppIntent {
    static var title: LocalizedStringResource = "Shaxmat partiyalarim"
    static var description = IntentDescription("Shaxmat oynasini ochadi: navbati sizda bo‘lgan partiyalar birinchi turadi.")

    @MainActor
    func perform() async throws -> some IntentResult {
        ChessWindowController.shared.show()
        return .result()
    }
}

struct OpenColleaguesIntent: AppIntent {
    static var title: LocalizedStringResource = "Hamkasblar ro‘yxati"
    static var description = IntentDescription("Kim ekraningizda yurishini tanlaydigan oynani ochadi.")

    @MainActor
    func perform() async throws -> some IntentResult {
        PeopleWindowController.shared.show()
        return .result()
    }
}

// MARK: - Spotlight va Siri iboralari

struct HomeViewShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SetSeasonIntent(),
                    phrases: ["\(.applicationName) faslini almashtir",
                              "\(.applicationName) \(\.$season)"],
                    shortTitle: "Fasl",
                    systemImageName: "leaf")
        AppShortcut(intent: SetStatusIntent(),
                    phrases: ["\(.applicationName) holatimni o‘zgartir",
                              "\(.applicationName) \(\.$status)"],
                    shortTitle: "Holatim",
                    systemImageName: "person.crop.circle.badge.checkmark")
        AppShortcut(intent: ClearSnowIntent(),
                    phrases: ["\(.applicationName) qorni tozala"],
                    shortTitle: "Qorni tozalash",
                    systemImageName: "wind.snow")
        AppShortcut(intent: TogglePlayModeIntent(),
                    phrases: ["\(.applicationName) o‘yin rejimi"],
                    shortTitle: "O‘yin rejimi",
                    systemImageName: "gamecontroller")
        AppShortcut(intent: OpenChessIntent(),
                    phrases: ["\(.applicationName) shaxmat"],
                    shortTitle: "Shaxmat",
                    systemImageName: "checkerboard.rectangle")
        AppShortcut(intent: OpenColleaguesIntent(),
                    phrases: ["\(.applicationName) hamkasblar"],
                    shortTitle: "Hamkasblar",
                    systemImageName: "person.2")
    }
}
