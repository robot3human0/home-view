import Foundation
import HomeViewProtocol

// HomeView ofis serveri.
//
// Sozlamalar (muhit o‘zgaruvchilari):
//   HOMEVIEW_PORT           — ofis serveri porti (standart: 47777)
//   HOMEVIEW_DOWNLOAD_PORT  — yuklab olish sahifasi porti (standart: 47778)
//   HOMEVIEW_NAME           — Bonjour'dagi nom (standart: "HomeView ofisi")
//   HOMEVIEW_CODE           — ofis kodi; bo‘sh bo‘lsa, ofis tarmog‘idagi har kim ulanadi
//   HOMEVIEW_PUBLIC_HOST    — havolada ko‘rinadigan manzil (standart: Mac mini nomi, masalan build-mini.local)
//   HOMEVIEW_DOWNLOADS      — DMG va latest.json turadigan papka (standart: server yonidagi downloads)

let environment = ProcessInfo.processInfo.environment
let port = UInt16(environment["HOMEVIEW_PORT"] ?? "") ?? HVProtocol.defaultPort
let downloadPort = UInt16(environment["HOMEVIEW_DOWNLOAD_PORT"] ?? "") ?? HVProtocol.downloadPort
let name = environment["HOMEVIEW_NAME"] ?? "HomeView ofisi"
let code = environment["HOMEVIEW_CODE"] ?? ""
let executableFolder = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
let downloadsPath = environment["HOMEVIEW_DOWNLOADS"] ?? executableFolder.appendingPathComponent("downloads").path
let configuredHost = environment["HOMEVIEW_PUBLIC_HOST"] ?? ""
let publicHost = configuredHost.isEmpty ? ReleaseShelf.localHostName() : configuredHost
let publicURL = "http://\(publicHost):\(downloadPort)/"

Log.info("HomeView serveri ishga tushmoqda: port \(port), nom \"\(name)\", ofis kodi \(code.isEmpty ? "yo‘q" : "bor")")

do {
    let hub = Hub(code: code, chessStore: executableFolder.appendingPathComponent("chess.json"))
    let shelf = ReleaseShelf(directory: URL(fileURLWithPath: downloadsPath), publicURL: publicURL)
    let server = try Server(port: port, serviceName: name, hub: hub)
    let downloads = try DownloadServer(port: downloadPort, shelf: shelf)
    server.start()
    downloads.start()
    shelf.start(on: hub.queue) { release in
        hub.updateRelease(release)
    }
    dispatchMain()
} catch {
    Log.info("Serverni ishga tushirib bo‘lmadi: \(error)")
    exit(1)
}
