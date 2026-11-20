import Foundation
import HomeViewProtocol

// 1) Сообщения Linux-клиента (по одному JSON на строку) → JSONDecoder настоящего протокола.
var failures = 0
let input = try String(contentsOfFile: "/work/client_messages.jsonl", encoding: .utf8)
for line in input.split(separator: "\n") where !line.isEmpty {
    do {
        let message = try JSONDecoder().decode(ClientMessage.self, from: Data(line.utf8))
        print("DECODE OK   \(String(describing: message).prefix(110))")
    } catch {
        failures += 1
        print("DECODE FAIL \(line)\n            \(error)")
    }
}

// 2) Сообщения сервера, закодированные настоящим JSONEncoder → файл для Python-декодера.
let avatar = AvatarStyle(hat: .beanie, hatColor: 0x7B1E1E, vestColor: 0x43A047, skinColor: 0xC68642)
let peer = PeerInfo(id: "PEER-1", name: "Жасур", team: "iOS", avatar: avatar, status: .away)
let room = RoomInfo(id: "ROOM-1", game: .volleyball, hostID: "PEER-1", players: ["PEER-1"], phase: .lobby,
                    startsAt: 1_800_000_000.5, teams: ["PEER-1": 0])
let roomNoOptionals = RoomInfo(id: "ROOM-2", game: .hotBall, hostID: "PEER-1", players: ["PEER-1"], phase: .playing,
                               startsAt: nil, teams: nil)
let server: [ServerMessage] = [
    .welcome(you: "ME", peers: [peer], rooms: [room, roomNoOptionals]),
    .rejected(reason: "Ofis kodi noto‘g‘ri"),
    .notice(text: "Bu hamkasb hozir tarmoqda emas"),
    .peerJoined(peer),
    .peerUpdated(peer),
    .peerLeft(id: "PEER-1"),
    .ping(from: "PEER-1", kind: .wave),
    .ping(from: "PEER-1", kind: .tea),
    .projectile(from: "PEER-1"),
    .chat(from: "PEER-1", text: "Salom! 👋", direct: true),
    .chat(from: "PEER-1", text: "Hammaga", direct: false),
    .invited(roomID: "ROOM-1", from: "PEER-1", game: .chessBlitz),
    .declined(roomID: "ROOM-1", by: "PEER-1"),
    .room(room),
    .roomClosed(roomID: "ROOM-1"),
    .latestApp(AppRelease(version: "1.0.0", build: 14, url: "http://x/", notes: "")),
]
var out = ""
for message in server {
    out += String(decoding: try JSONEncoder().encode(message), as: UTF8.self) + "\n"
}
try out.write(toFile: "/work/server_messages.jsonl", atomically: true, encoding: .utf8)
print("ENCODED \(server.count) server messages")
print(failures == 0 ? "ALL CLIENT MESSAGES DECODED" : "FAILURES: \(failures)")
exit(failures == 0 ? 0 : 1)
