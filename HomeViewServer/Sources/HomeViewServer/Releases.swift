import Foundation
import Network
import SystemConfiguration
import HomeViewProtocol

// MARK: - Javon: Mac mini'ga joylangan ilova versiyasi

/// `downloads/latest.json` va DMG faylini kuzatadi. deploy.sh yangi versiyani shu yerga qo‘yadi,
/// javon buni 30 soniya ichida sezadi va Hub orqali hammaga "yangi versiya chiqdi" deb aytadi.
final class ReleaseShelf {
    struct Manifest: Codable {
        let version: String
        let build: Int
        let file: String
        let notes: String?
    }

    let directory: URL
    let publicURL: String
    private let lock = NSLock()
    private var manifest: Manifest?
    private var lastStamp: Date?
    private var timer: DispatchSourceTimer?

    init(directory: URL, publicURL: String) {
        self.directory = directory
        self.publicURL = publicURL
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
    }

    /// Hozir joylangan versiya (yo‘q bo‘lsa nil).
    var current: AppRelease? {
        lock.lock()
        defer { lock.unlock() }
        guard let manifest else { return nil }
        return AppRelease(version: manifest.version, build: manifest.build, url: publicURL, notes: manifest.notes ?? "")
    }

    var currentManifest: Manifest? {
        lock.lock()
        defer { lock.unlock() }
        return manifest
    }

    /// Har 30 soniyada latest.json o‘zgarganmi, tekshiradi.
    func start(on queue: DispatchQueue, onChange: @escaping (AppRelease?) -> Void) {
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + 30, repeating: 30)
        source.setEventHandler { [weak self] in
            guard let self, self.reload() else { return }
            onChange(self.current)
        }
        source.resume()
        timer = source
        queue.async { [weak self] in onChange(self?.current) }
    }

    /// true — o‘zgarish bor edi.
    @discardableResult
    func reload() -> Bool {
        let manifestURL = directory.appendingPathComponent("latest.json")
        let attributes = try? FileManager.default.attributesOfItem(atPath: manifestURL.path)
        let stamp = attributes?[.modificationDate] as? Date
        lock.lock()
        defer { lock.unlock() }
        if stamp == lastStamp { return false }
        lastStamp = stamp
        var loaded: Manifest?
        if let data = try? Data(contentsOf: manifestURL),
           let decoded = try? JSONDecoder().decode(Manifest.self, from: data),
           ReleaseShelf.isSafeName(decoded.file),
           FileManager.default.fileExists(atPath: directory.appendingPathComponent(decoded.file).path) {
            loaded = decoded
        }
        manifest = loaded
        if let loaded {
            Log.info("Joylangan ilova: HomeView \(loaded.version) (build \(loaded.build)), fayl \(loaded.file)")
        }
        return true
    }

    /// Fayl nomi papkadan tashqariga chiqmasin (faqat oddiy nom, .dmg bilan tugaydi).
    static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.contains("..") && name.hasSuffix(".dmg")
    }

    /// Mac mini'ning ofis tarmog‘idagi nomi, masalan "build-mini.local".
    static func localHostName() -> String {
        if let cfName = SCDynamicStoreCopyLocalHostName(nil) {
            let name = cfName as String
            if !name.isEmpty { return name + ".local" }
        }
        return ProcessInfo.processInfo.hostName
    }
}

// MARK: - Yuklab olish sahifasi (oddiy HTTP)

/// Ofis tarmog‘i uchun kichik veb-sahifa: http://build-mini.local:47778/
///   /             — yuklab olish sahifasi va o‘rnatish yo‘riqnomasi
///   /latest.json  — joriy versiya haqida ma’lumot
///   /HomeView-…dmg — ilovaning o‘zi
final class DownloadServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "uz.homeview.downloads", qos: .utility)
    private let shelf: ReleaseShelf

    init(port: UInt16, shelf: ReleaseShelf) throws {
        self.shelf = shelf
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "HomeView", code: 2, userInfo: [NSLocalizedDescriptionKey: "Noto‘g‘ri port"])
        }
        listener = try NWListener(using: parameters, on: nwPort)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: Log.info("Yuklab olish sahifasi tayyor: \(shelf.publicURL)")
            case .failed(let error): Log.info("Yuklab olish sahifasi xatosi: \(error)")
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.serve(connection)
        }
    }

    func start() {
        listener.start(queue: queue)
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, collected: Data())
    }

    private func receive(_ connection: NWConnection, collected: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = collected
            if let data { buffer.append(data) }
            if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.respond(to: buffer, on: connection)
            } else if error != nil || isComplete || buffer.count > 32_768 {
                connection.cancel()
            } else {
                self.receive(connection, collected: buffer)
            }
        }
    }

    private func respond(to request: Data, on connection: NWConnection) {
        let text = String(decoding: request.prefix(4096), as: UTF8.self)
        let firstLine = text.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2, parts[0] == "GET" || parts[0] == "HEAD" else {
            send(connection, status: "405 Method Not Allowed", type: "text/plain; charset=utf-8",
                 body: Data("Faqat GET".utf8), headOnly: false)
            return
        }
        let headOnly = parts[0] == "HEAD"
        var path = parts[1]
        if let query = path.firstIndex(of: "?") {
            path = String(path[..<query])
        }
        path = path.removingPercentEncoding ?? path
        let manifest = shelf.currentManifest

        if path == "/" || path == "/index.html" {
            let html = DownloadPage.render(manifest: manifest)
            send(connection, status: "200 OK", type: "text/html; charset=utf-8", body: Data(html.utf8), headOnly: headOnly)
            return
        }

        if path == "/latest.json" {
            guard let release = shelf.current, let body = HVCoding.encode(release) else {
                send(connection, status: "404 Not Found", type: "text/plain; charset=utf-8",
                     body: Data("Hali versiya joylanmagan".utf8), headOnly: headOnly)
                return
            }
            send(connection, status: "200 OK", type: "application/json", body: body, headOnly: headOnly)
            return
        }

        if let manifest, path == "/" + manifest.file {
            let fileURL = shelf.directory.appendingPathComponent(manifest.file)
            guard let body = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
                send(connection, status: "404 Not Found", type: "text/plain; charset=utf-8",
                     body: Data("Fayl topilmadi".utf8), headOnly: headOnly)
                return
            }
            Log.info("Yuklab olindi: \(manifest.file)")
            send(connection, status: "200 OK", type: "application/x-apple-diskimage", body: body, headOnly: headOnly,
                 extra: ["Content-Disposition: attachment; filename=\"\(manifest.file)\""])
            return
        }

        send(connection, status: "404 Not Found", type: "text/plain; charset=utf-8",
             body: Data("Topilmadi".utf8), headOnly: headOnly)
    }

    private func send(_ connection: NWConnection, status: String, type: String, body: Data, headOnly: Bool,
                      extra: [String] = []) {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(type)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Cache-Control: no-cache\r\n"
        header += "Connection: close\r\n"
        for line in extra {
            header += line + "\r\n"
        }
        header += "\r\n"
        var payload = Data(header.utf8)
        if !headOnly {
            payload.append(body)
        }
        connection.send(content: payload, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

// MARK: - Sahifa matni

enum DownloadPage {
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func render(manifest: ReleaseShelf.Manifest?) -> String {
        var body = ""
        if let manifest {
            let version = escape(manifest.version)
            let file = escape(manifest.file)
            let link = manifest.file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? manifest.file
            body += "<a class=\"button\" href=\"/\(link)\">Yuklab olish · \(version)</a>\n"
            body += "<p class=\"meta\">macOS 13 yoki yangiroq · Apple Silicon va Intel</p>\n"
            if let notes = manifest.notes, !notes.isEmpty {
                body += "<section><h2>Yangiliklar</h2><p>\(escape(notes))</p></section>\n"
            }
            body += """
            <section>
            <h2>O‘rnatish (bir daqiqa)</h2>
            <ol>
            <li>Yuklangan <b>\(file)</b> faylini oching va <b>HomeView</b>ni <b>Applications</b> papkasiga torting.</li>
            <li>Applications'dan HomeView'ni oching. macOS uni tekshira olmaganini aytib to‘xtatadi — <b>Done</b> ni bosing.</li>
            <li><b>System Settings → Privacy &amp; Security</b> ni oching, pastga tushing va HomeView yonidagi <b>Open Anyway</b> ni bosing. Parol yoki Touch ID so‘raladi.</li>
            <li>Chiqqan oynada <b>Open Anyway</b> ni yana bir bor bosing. Bu faqat birinchi marta kerak.</li>
            <li>Menyu satrida ❄ belgisi paydo bo‘ladi. Undan <b>Sozlamalar → Ofis</b> ga kirib, ismingizni yozing va ofisga ulanishni yoqing.</li>
            </ol>
            <p class="note">2–4-qadamlar ilova hozircha Apple imzosisiz tarqatilgani uchun kerak. Imzo qo‘shilgach, ular kerak bo‘lmaydi.</p>
            </section>
            <section>
            <h2>Eski «Qorli Kun» bo‘lsa</h2>
            <p>HomeView sozlamalaringizni (ism, odamcha, o‘lchamlar) o‘zi ko‘chirib oladi. Keyin eski ilovani Applications'dan savatga tashlang.</p>
            </section>

            """
        } else {
            body += "<p class=\"meta\">Hozircha yuklab olish uchun versiya joylanmagan.</p>\n"
        }

        return """
        <!doctype html>
        <html lang="uz">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>HomeView — yuklab olish</title>
        <style>
        :root { --bg: #f5f7fb; --card: #ffffff; --text: #14213d; --muted: #5c677d; --accent: #1e88e5; --line: #e3e8f0; }
        @media (prefers-color-scheme: dark) {
          :root { --bg: #0f1b2d; --card: #16243a; --text: #eef2f8; --muted: #9fb0c8; --accent: #64b5f6; --line: #253752; }
        }
        * { box-sizing: border-box; }
        body { margin: 0; background: var(--bg); color: var(--text);
               font: 16px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
        main { max-width: 640px; margin: 48px auto; padding: 32px; background: var(--card);
               border: 1px solid var(--line); border-radius: 20px; }
        .logo { font-size: 56px; line-height: 1; }
        h1 { margin: 12px 0 4px; font-size: 32px; }
        h2 { font-size: 18px; margin: 28px 0 8px; }
        .lead { color: var(--muted); margin: 0 0 24px; }
        .button { display: inline-block; padding: 14px 28px; border-radius: 12px; background: var(--accent);
                  color: #fff; font-weight: 600; text-decoration: none; }
        .meta, .note { color: var(--muted); font-size: 14px; }
        ol { padding-left: 22px; }
        li { margin: 6px 0; }
        </style>
        </head>
        <body>
        <main>
        <div class="logo">🏡</div>
        <h1>HomeView</h1>
        <p class="lead">Ish stolingizdagi fasllar va hamkasblar: qor, gul, barg — va butun ofis bilan o‘yinlar.</p>
        \(body)
        </main>
        </body>
        </html>
        """
    }
}
