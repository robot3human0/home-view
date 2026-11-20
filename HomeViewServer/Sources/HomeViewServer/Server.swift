import Foundation
import Network
import HomeViewProtocol

enum Log {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func info(_ text: String) {
        print("[\(formatter.string(from: Date()))] \(text)")
        fflush(stdout)
    }
}

/// Tarmoq eshigi: ulanishlarni qabul qiladi va ofis tarmog‘iga Bonjour orqali "server shu yerda" deb e’lon qiladi.
final class Server {
    private let listener: NWListener
    private let hub: Hub

    init(port: UInt16, serviceName: String, hub: Hub) throws {
        self.hub = hub
        // noDelay: kichik xabarlar navbatda kutib turmasin (Nagle algoritmi o‘chiriladi)
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.serviceClass = .responsiveData
        let webSocket = NWProtocolWebSocket.Options()
        webSocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)
        parameters.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "HomeView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Noto‘g‘ri port"])
        }
        listener = try NWListener(using: parameters, on: nwPort)
        listener.service = NWListener.Service(name: serviceName, type: HVProtocol.serviceType)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: Log.info("Server tayyor, ulanishlarni kutmoqda")
            case .failed(let error): Log.info("Server xatosi: \(error)")
            default: break
            }
        }
        listener.newConnectionHandler = { [weak hub] connection in
            hub?.accept(connection)
        }
    }

    func start() {
        listener.start(queue: hub.queue)
    }
}

/// Bitta ulangan ilova.
final class Session {
    let connection: NWConnection
    var peer: PeerInfo?
    var lastProjectile = Date.distantPast
    var lastChat = Date.distantPast

    init(connection: NWConnection) {
        self.connection = connection
    }
}
