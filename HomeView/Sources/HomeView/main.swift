import AppKit

// HomeView — kirish nuqtasi.
// Ilova Dock'da ko‘rinmaydi, faqat menyu satrida ❄ belgisi bo‘ladi.
LegacyMigration.run()
let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.setActivationPolicy(.accessory)
app.run()
