import AppKit

/// Eski nusxalar bilan "uchrashuv".
///
/// DMG versiyasi (bundle uz.homeview.app): birinchi ishga tushishda Qorli Kun sozlamalarini ko‘chiradi
/// va eski ilova ishlab turgan bo‘lsa — yopadi, ikkita qor ustma-ust yog‘masin.
///
/// App Store / TestFlight versiyasi (bundle com.home-view, APPSTORE belgisi bilan yig‘iladi):
/// sandbox ichida boshqa ilovaning sozlamalarini o‘qib bo‘lmaydi, shuning uchun faqat
/// DMG'dan o‘rnatilgan HomeView yoki Qorli Kun ochiq turganini tekshiradi va ogohlantiradi.
enum LegacyMigration {
    static let oldBundleID = "uz.qorlikun.app"
    static let dmgBundleID = "uz.homeview.app"
    private static let doneKey = "migratedFromQorliKun"

    static func run() {
        #if APPSTORE
        warnAboutOtherCopies()
        #else
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: doneKey) {
            if let old = defaults.persistentDomain(forName: oldBundleID) {
                for (key, value) in old where defaults.object(forKey: key) == nil {
                    defaults.set(value, forKey: key)
                }
            }
            defaults.set(true, forKey: doneKey)
        }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: oldBundleID) {
            app.terminate()
        }
        #endif
    }

    #if APPSTORE
    private static func otherCopiesRunning() -> [NSRunningApplication] {
        [dmgBundleID, oldBundleID].flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
    }

    private static func warnAboutOtherCopies() {
        let running = otherCopiesRunning()
        guard !running.isEmpty else { return }
        for app in running {
            app.terminate()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard !otherCopiesRunning().isEmpty else { return }
            let alert = NSAlert()
            alert.messageText = "HomeView’ning eski nusxasi ham ishlayapti"
            alert.informativeText = "DMG’dan o‘rnatilgan HomeView yoki Qorli Kun ochiq turibdi — ikkalasi birga ishlasa, qor ikki qavat yog‘adi. Eskisini menyu satridagi belgidan yoping va Applications papkasidan savatga tashlang."
            alert.addButton(withTitle: "Tushunarli")
            NSApp.activate()
            alert.runModal()
        }
    }
    #endif
}
