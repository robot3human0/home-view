import Foundation
import Network
import HomeViewProtocol

/// Server bilan doimiy ulanish ("doim ochiq telefon liniyasi").
/// Hamma tarmoq ishi alohida fon navbatida bajariladi — animatsiya hech qachon qotmaydi.
final class NetworkClient {
    enum State: Equatable {
        case idle
        case searching
        case connecting
        case connected
        case failed(String)
    }

    /// Asosiy oqimda chaqiriladi.
    var onMessage: ((ServerMessage) -> Void)?
    var onState: ((State) -> Void)?
    /// Ulanish tayyor bo‘lganda yuboriladigan salom xabari (asosiy oqimda yig‘iladi).
    var helloProvider: (() -> ClientMessage)?

    private let queue = DispatchQueue(label: "uz.homeview.network", qos: .userInteractive)
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var manualAddress = ""
    private var running = false
    private var retryDelay: Double = 2
    private var generation = 0

    // MARK: - Boshqaruv

    func start(address: String) {
        queue.async {
            self.manualAddress = address
            self.running = true
            self.retryDelay = 2
            self.restart()
        }
    }

    func stop() {
        queue.async {
            self.running = false
            self.generation += 1
            self.tearDown()
            self.report(.idle)
        }
    }

    func send(_ message: ClientMessage) {
        guard let data = HVCoding.encode(message) else { return }
        queue.async {
            guard let connection = self.connection, case .ready = connection.state else { return }
            let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
            let context = NWConnection.ContentContext(identifier: "qk", metadata: [metadata])
            connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
        }
    }

    // MARK: - Ichki ish (faqat queue'da)

    private func restart() {
        tearDown()
        guard running else { return }
        generation += 1
        if manualAddress.isEmpty {
            browse()
        } else {
            connect(to: endpoint(for: manualAddress))
        }
    }

    private func tearDown() {
        browser?.cancel()
        browser = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
    }

    private func endpoint(for address: String) -> NWEndpoint {
        let parts = address.split(separator: ":", maxSplits: 1).map(String.init)
        let host = parts.first ?? address
        let port = parts.count > 1 ? (UInt16(parts[1]) ?? HVProtocol.defaultPort) : HVProtocol.defaultPort
        if let url = URL(string: "ws://\(host):\(port)/") {
            return .url(url)
        }
        return .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? 47777)
    }

    /// Ofis tarmog‘ida serverni qidirish (Bonjour).
    private func browse() {
        report(.searching)
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjour(type: HVProtocol.serviceType, domain: nil), using: parameters)
        let myGeneration = generation
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self, self.generation == myGeneration, self.connection == nil,
                  let first = results.first else { return }
            self.browser?.cancel()
            self.browser = nil
            self.connect(to: first.endpoint)
        }
        browser.stateUpdateHandler = { [weak self] state in
            guard let self, self.generation == myGeneration else { return }
            if case .failed(let error) = state {
                self.report(.failed("Qidiruv xatosi: \(error.localizedDescription)"))
                self.scheduleRetry()
            }
        }
        self.browser = browser
        browser.start(queue: queue)
        // 12 soniyada topilmasa — foydalanuvchiga aytamiz, qidiruv davom etadi
        queue.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, self.generation == myGeneration, self.connection == nil, self.running else { return }
            self.report(.failed("Ofis serveri topilmadi. Server manzilini qo‘lda kiritib ko‘ring."))
        }
    }

    private func connect(to endpoint: NWEndpoint) {
        report(.connecting)
        // noDelay: sichqoncha harakatlari navbatda kutib turmasin (Nagle algoritmi o‘chiriladi)
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.serviceClass = .responsiveData
        let webSocket = NWProtocolWebSocket.Options()
        webSocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)
        let connection = NWConnection(to: endpoint, using: parameters)
        let myGeneration = generation
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, self.generation == myGeneration else { return }
            switch state {
            case .ready:
                self.retryDelay = 2
                self.report(.connected)
                self.sendHello()
                self.receive(on: connection, generation: myGeneration)
            case .failed(let error):
                self.report(.failed("Ulanish uzildi: \(error.localizedDescription)"))
                self.scheduleRetry()
            case .waiting(let error):
                self.report(.failed("Server javob bermayapti: \(error.localizedDescription)"))
                self.scheduleRetry()
            case .cancelled:
                break
            default:
                break
            }
        }
        self.connection = connection
        connection.start(queue: queue)
    }

    private func sendHello() {
        DispatchQueue.main.async {
            guard let hello = self.helloProvider?() else { return }
            self.send(hello)
        }
    }

    private func receive(on connection: NWConnection, generation myGeneration: Int) {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self, self.generation == myGeneration else { return }
            if error != nil {
                self.scheduleRetry()
                return
            }
            if let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata,
               metadata.opcode == .close {
                self.report(.failed("Server ulanishni yopdi"))
                self.scheduleRetry()
                return
            }
            if let data, !data.isEmpty, let message = HVCoding.decode(ServerMessage.self, from: data) {
                DispatchQueue.main.async { self.onMessage?(message) }
            }
            self.receive(on: connection, generation: myGeneration)
        }
    }

    /// Uzilsa — biroz kutib, qayta ulanadi (2, 4, 8 ... 30 soniya).
    private func scheduleRetry() {
        guard running else { return }
        generation += 1
        tearDown()
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, 30)
        let myGeneration = generation
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.running, self.generation == myGeneration else { return }
            self.restart()
        }
    }

    private func report(_ state: State) {
        DispatchQueue.main.async { self.onState?(state) }
    }
}
