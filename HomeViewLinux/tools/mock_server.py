#!/usr/bin/env python3
"""Мок офисного сервера HomeView для проверки Linux-клиента без Mac mini.

Повторяет поведение HomeViewServer/Sources/HomeViewServer/Hub.swift в части «офиса»
(подключение, статусы, помахать, снежок, чат, чай) и **строго проверяет формат**
входящих сообщений — каждое отклонение от того, что ждёт Swift `Codable`, пишется в журнал
как ОШИБКА ФОРМАТА.

Боты (--bots N) изображают коллег: сами машут, кидаются, пишут, зовут на чай и в игры,
а на ваши действия отвечают тем же.

    python tools/mock_server.py --bots 4               # ws://localhost:47777
    python tools/mock_server.py --bots 4 --advertise   # + объявление через mDNS
    python tools/mock_server.py --code secret          # требовать код офиса
"""

from __future__ import annotations

import argparse
import json
import logging
import random
import signal
import socket
import sys
import uuid

from PySide6.QtCore import QCoreApplication, QTimer
from PySide6.QtNetwork import QHostAddress
from PySide6.QtWebSockets import QWebSocket, QWebSocketServer

PROTOCOL_VERSION = 4
STATUSES = {"active", "away", "busy", "hidden"}
HATS = {"beanie", "cap", "doppi", "strawHat"}
GAMES = {"hotBall", "marksman", "volleyball", "tennis", "penalty", "basketball", "tugOfWar",
         "chessBlitz", "chessDaily", "chessTeam"}

# Ожидаемые поля каждого сообщения клиента (как синтезирует Swift Codable)
CLIENT_SCHEMA: dict[str, dict[str, type | tuple]] = {
    "hello": {"id": str, "name": str, "team": str, "avatar": dict, "status": str, "code": str, "version": int},
    "status": {"_0": str},
    "profile": {"name": str, "team": str, "avatar": dict},
    "ping": {"to": str, "kind": str},
    "projectile": {"to": str},
    "chat": {"to": (str, type(None)), "text": str},
    "invite": {"to": str, "game": str},
    "respond": {"roomID": str, "accept": bool},
    "join": {"roomID": str},
    "leave": {"roomID": str},
    "start": {"roomID": str},
}
OPTIONAL = {("chat", "to")}
AVATAR_SCHEMA = {"hat": str, "hatColor": int, "vestColor": int, "skinColor": int}

BOT_NAMES = [("Жасур", "iOS"), ("Малика", "Android"), ("Тимур", "Design"), ("Нигора", "iOS"),
             ("Азиз", "QA"), ("Дильноза", "Product"), ("Шерзод", "Android"), ("Камола", "HR")]
BOT_PHRASES = ["Всем привет! 👋", "Кто на обед?", "Билд упал 😅", "Ура, пятница!", "Код-ревью глянешь?",
               "Снег пошёл!", "Кофе кончился ☕", "Деплой прошёл ✅"]

log = logging.getLogger("mock")
format_errors = 0


def check_format(case: str, payload: dict) -> list[str]:
    errors = []
    schema = CLIENT_SCHEMA.get(case)
    if schema is None:
        return [f"неизвестный случай «{case}» (Swift не декодирует)"]
    for key, kind in schema.items():
        if key not in payload:
            if (case, key) not in OPTIONAL:
                errors.append(f"нет поля «{key}»")
            continue
        value = payload[key]
        if (case, key) in OPTIONAL and value is None:
            errors.append(f"«{key}»: null вместо отсутствующего ключа (Swift так не пишет)")
        elif kind is int and isinstance(value, bool):
            errors.append(f"«{key}»: bool вместо числа")
        elif not isinstance(value, kind):
            errors.append(f"«{key}»: тип {type(value).__name__}")
    for key in payload:
        if key not in schema:
            errors.append(f"лишнее поле «{key}»")
    avatar = payload.get("avatar")
    if isinstance(avatar, dict):
        for key, kind in AVATAR_SCHEMA.items():
            if not isinstance(avatar.get(key), kind) or isinstance(avatar.get(key), bool):
                errors.append(f"avatar.{key}: неверный тип или нет поля")
        if avatar.get("hat") not in HATS:
            errors.append(f"avatar.hat: неизвестное значение {avatar.get('hat')!r}")
        for key in ("hatColor", "vestColor", "skinColor"):
            value = avatar.get(key)
            if isinstance(value, int) and not 0 <= value <= 0xFFFFFFFF:
                errors.append(f"avatar.{key}: вне диапазона UInt32")
    status = payload.get("status") if case == "hello" else payload.get("_0") if case == "status" else None
    if status is not None and status not in STATUSES:
        errors.append(f"статус {status!r} не из {sorted(STATUSES)}")
    if case == "ping" and payload.get("kind") not in ("wave", "tea"):
        errors.append(f"ping.kind {payload.get('kind')!r}")
    if case == "invite" and payload.get("game") not in GAMES:
        errors.append(f"invite.game {payload.get('game')!r}")
    return errors


def encode(case: str, payload: dict) -> str:
    return json.dumps({case: payload}, ensure_ascii=False, separators=(",", ":"))


class Bot:
    def __init__(self, name: str, team: str) -> None:
        self.info = {
            "id": str(uuid.uuid4()).upper(),
            "name": name,
            "team": team,
            "avatar": {
                "hat": random.choice(sorted(HATS)),
                "hatColor": random.choice([0x1E3A5F, 0x7B1E1E, 0x2E4D2E, 0xC62828, 0xF9A825]),
                "vestColor": random.choice([0x1E88E5, 0xE53935, 0x43A047, 0xFB8C00, 0x8E24AA]),
                "skinColor": random.choice([0xFFDBAC, 0xF1C27D, 0xE0AC69, 0xC68642, 0x8D5524]),
            },
            "status": "active",
        }

    @property
    def id(self) -> str:
        return self.info["id"]


class Session:
    def __init__(self, socket: QWebSocket) -> None:
        self.socket = socket
        self.peer: dict | None = None


class MockHub:
    def __init__(self, port: int, code: str, bots: int, quiet: bool) -> None:
        self.code = code
        self.quiet = quiet
        self.sessions: dict[int, Session] = {}
        self.by_peer: dict[str, Session] = {}
        self.bots = [Bot(*BOT_NAMES[i % len(BOT_NAMES)]) for i in range(bots)]
        if self.bots[1:2]:
            self.bots[1].info["status"] = "away"
        self.rooms: dict[str, dict] = {}
        self.server = QWebSocketServer("HomeView mock", QWebSocketServer.NonSecureMode)
        if not self.server.listen(QHostAddress.Any, port):
            raise SystemExit(f"Порт {port} занят: {self.server.errorString()}")
        self.server.newConnection.connect(self._accept)
        self._timer = QTimer(singleShot=True)
        self._timer.timeout.connect(self._bot_action)
        if self.bots and not quiet:
            self._schedule()

    # MARK: - Соединения

    def _accept(self) -> None:
        socket = self.server.nextPendingConnection()
        session = Session(socket)
        self.sessions[id(socket)] = session
        socket.textMessageReceived.connect(lambda text, s=session: self._receive(s, text))
        socket.disconnected.connect(lambda s=session: self._drop(s))
        log.info("Подключение с %s:%s", socket.peerAddress().toString(), socket.peerPort())

    def _drop(self, session: Session) -> None:
        self.sessions.pop(id(session.socket), None)
        peer = session.peer
        if peer and self.by_peer.get(peer["id"]) is session:
            del self.by_peer[peer["id"]]
            log.info("Отключился: %s", peer["name"])
            if peer["status"] != "hidden":
                self._broadcast("peerLeft", {"id": peer["id"]})
        session.socket.deleteLater()

    def _send(self, session: Session, case: str, payload: dict) -> None:
        text = encode(case, payload)
        log.debug("→ %s", text)
        session.socket.sendTextMessage(text)

    def _broadcast(self, case: str, payload: dict, except_id: str | None = None) -> None:
        for peer_id, session in list(self.by_peer.items()):
            if peer_id != except_id:
                self._send(session, case, payload)

    def _visible(self, except_id: str) -> list[dict]:
        peers = [s.peer for s in self.by_peer.values() if s.peer and s.peer["id"] != except_id]
        peers += [b.info for b in self.bots]
        return [p for p in peers if p["status"] != "hidden"]

    # MARK: - Сообщения

    def _receive(self, session: Session, text: str) -> None:
        global format_errors
        log.debug("← %s", text)
        try:
            obj = json.loads(text)
        except json.JSONDecodeError:
            format_errors += 1
            log.error("ОШИБКА ФОРМАТА: не JSON: %s", text[:200])
            return
        if not isinstance(obj, dict) or len(obj) != 1 or not isinstance(next(iter(obj.values())), dict):
            format_errors += 1
            log.error("ОШИБКА ФОРМАТА: ожидался {\"случай\": {...}}: %s", text[:200])
            return
        case, payload = next(iter(obj.items()))
        errors = check_format(case, payload)
        if errors:
            format_errors += 1
            log.error("ОШИБКА ФОРМАТА в «%s»: %s — %s", case, "; ".join(errors), text[:300])
            return  # настоящий сервер такое сообщение тоже молча проигнорирует
        log.info("← %s %s", case, {k: v for k, v in payload.items() if k != "avatar"})

        if case == "hello":
            self._hello(session, payload)
            return
        me = session.peer
        if me is None:
            return
        if case == "status":
            self._update(session, status=payload["_0"])
        elif case == "profile":
            self._update(session, name=payload["name"][:32], team=payload["team"][:24], avatar=payload["avatar"])
        elif case == "ping":
            self._deliver(session, payload["to"], "ping", {"from": me["id"], "kind": payload["kind"]})
        elif case == "projectile":
            self._deliver(session, payload["to"], "projectile", {"from": me["id"]})
        elif case == "chat":
            text_value = payload["text"].strip()[:200]
            if not text_value:
                return
            if "to" in payload:
                self._deliver(session, payload["to"], "chat", {"from": me["id"], "text": text_value, "direct": True})
            else:
                self._broadcast("chat", {"from": me["id"], "text": text_value, "direct": False}, except_id=me["id"])
        elif case == "respond":
            room = self.rooms.get(payload["roomID"])
            if room and not payload["accept"]:
                host = room["hostID"]
                log.info("%s отказался от игры", me["name"])
                self._send(session, "notice", {"text": "Mock: отказ принят"})
                if host in self.by_peer:
                    self._send(self.by_peer[host], "declined", {"roomID": room["id"], "by": me["id"]})

    def _hello(self, session: Session, payload: dict) -> None:
        if self.code and payload["code"] != self.code:
            self._send(session, "rejected", {"reason": "Ofis kodi noto‘g‘ri"})
            return
        if payload["version"] < PROTOCOL_VERSION:
            self._send(session, "rejected", {"reason": "Ilovangiz eski — HomeView'ning yangi versiyasini o‘rnating"})
            return
        if not payload["id"] or not payload["name"].strip():
            self._send(session, "rejected", {"reason": "Ism kiritilmagan"})
            return
        old = self.by_peer.get(payload["id"])
        if old is not None and old is not session:
            old.peer = None
            old.socket.close()
        peer = {k: payload[k] for k in ("id", "name", "team", "avatar", "status")}
        session.peer = peer
        self.by_peer[peer["id"]] = session
        self._send(session, "welcome", {"you": peer["id"], "peers": self._visible(peer["id"]),
                                        "rooms": list(self.rooms.values())})
        if peer["status"] != "hidden":
            self._broadcast("peerJoined", {"_0": peer}, except_id=peer["id"])
        log.info("Подключился: %s (%s), статус %s", peer["name"], peer["team"], peer["status"])

    def _update(self, session: Session, **changes) -> None:
        peer = session.peer
        was_hidden = peer["status"] == "hidden"
        peer.update(changes)
        hidden = peer["status"] == "hidden"
        if was_hidden and not hidden:
            self._broadcast("peerJoined", {"_0": peer}, except_id=peer["id"])
        elif not was_hidden and hidden:
            self._broadcast("peerLeft", {"id": peer["id"]}, except_id=peer["id"])
        elif not hidden:
            self._broadcast("peerUpdated", {"_0": peer}, except_id=peer["id"])

    def _deliver(self, sender: Session, to: str, case: str, payload: dict) -> None:
        bot = next((b for b in self.bots if b.id == to), None)
        if bot is not None:
            if bot.info["status"] == "busy":
                self._send(sender, "notice", {"text": f"{bot.info['name']} hozir band — xabar keyinroq"})
                return
            QTimer.singleShot(1500, lambda: self._bot_reply(bot, sender, case, payload))
            return
        target = self.by_peer.get(to)
        if target is None or target.peer is None or target.peer["status"] == "hidden":
            self._send(sender, "notice", {"text": "Bu hamkasb hozir tarmoqda emas"})
            return
        self._send(target, case, payload)

    # MARK: - Боты

    def _bot_reply(self, bot: Bot, session: Session, case: str, payload: dict) -> None:
        if session.peer is None:
            return
        if case == "ping" and payload["kind"] == "wave":
            self._send(session, "ping", {"from": bot.id, "kind": "wave"})
        elif case == "ping":
            self._send(session, "chat", {"from": bot.id, "text": "Иду, ставь чайник! ☕", "direct": True})
        elif case == "projectile":
            self._send(session, "projectile", {"from": bot.id})
        elif case == "chat":
            self._send(session, "chat", {"from": bot.id, "text": f"Получил: «{payload['text'][:40]}»", "direct": True})

    def _schedule(self) -> None:
        self._timer.start(random.randint(6000, 14000))

    def _bot_action(self) -> None:
        self._schedule()
        clients = [s for s in self.by_peer.values() if s.peer and s.peer["status"] not in ("busy", "hidden")]
        if not clients or not self.bots:
            return
        bot = random.choice(self.bots)
        target = random.choice(clients)
        action = random.choices(["wave", "projectile", "chat", "tea", "status", "invite", "broadcast"],
                                weights=[3, 3, 2, 1, 2, 1, 1])[0]
        log.info("Бот %s → %s: %s", bot.info["name"], target.peer["name"], action)
        if action == "wave":
            self._send(target, "ping", {"from": bot.id, "kind": "wave"})
        elif action == "tea":
            self._send(target, "ping", {"from": bot.id, "kind": "tea"})
        elif action == "projectile":
            self._send(target, "projectile", {"from": bot.id})
        elif action == "chat":
            self._send(target, "chat", {"from": bot.id, "text": random.choice(BOT_PHRASES), "direct": True})
        elif action == "broadcast":
            self._broadcast("chat", {"from": bot.id, "text": random.choice(BOT_PHRASES), "direct": False})
        elif action == "status":
            bot.info["status"] = random.choice(["active", "active", "away", "busy"])
            self._broadcast("peerUpdated", {"_0": bot.info})
        elif action == "invite":
            game = random.choice(["hotBall", "volleyball", "tennis", "chessBlitz"])
            room = {"id": str(uuid.uuid4()).upper(), "game": game, "hostID": bot.id, "players": [bot.id],
                    "phase": "lobby"}
            self.rooms[room["id"]] = room
            self._broadcast("room", {"_0": room})
            self._send(target, "invited", {"roomID": room["id"], "from": bot.id, "game": game})

            def close() -> None:
                if self.rooms.pop(room["id"], None):
                    self._broadcast("roomClosed", {"roomID": room["id"]})

            QTimer.singleShot(25_000, close)


def advertise(port: int):
    from zeroconf import ServiceInfo, Zeroconf

    host = socket.gethostname()
    addresses = sorted({info[4][0] for info in socket.getaddrinfo(host, None, socket.AF_INET)
                        if not info[4][0].startswith("127.")})
    if not addresses:
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            probe.connect(("10.255.255.255", 1))
            addresses = [probe.getsockname()[0]]
        except OSError:
            addresses = ["127.0.0.1"]
        finally:
            probe.close()
    info = ServiceInfo("_homeview._tcp.local.", "HomeView mock._homeview._tcp.local.",
                       addresses=[socket.inet_aton(a) for a in addresses], port=port,
                       server=f"{host}.local.")
    zeroconf = Zeroconf()
    zeroconf.register_service(info)
    log.info("mDNS: объявлен «HomeView mock» на %s:%d", ", ".join(addresses), port)
    return zeroconf, info


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, default=47777)
    parser.add_argument("--code", default="", help="код офиса (пусто — без кода)")
    parser.add_argument("--bots", type=int, default=3, help="сколько ботов-коллег")
    parser.add_argument("--quiet", action="store_true", help="боты сами ничего не делают, только отвечают")
    parser.add_argument("--advertise", action="store_true",
                        help="объявить сервер через mDNS (НЕ в офисной сети: Mac-клиенты коллег могут подключиться к моку)")
    parser.add_argument("--debug", action="store_true", help="печатать весь JSON")
    args = parser.parse_args()
    logging.basicConfig(level=logging.DEBUG if args.debug else logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s")
    app = QCoreApplication(sys.argv)
    hub = MockHub(args.port, args.code, args.bots, args.quiet)
    log.info("Мок-сервер HomeView: ws://0.0.0.0:%d/, ботов: %d, код: %s", args.port, len(hub.bots),
             args.code or "нет")
    registered = advertise(args.port) if args.advertise else None

    def stop(*_):
        if registered:
            registered[0].unregister_service(registered[1])
            registered[0].close()
        log.info("Остановлен. Ошибок формата: %d", format_errors)
        app.quit()

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)
    pulse = QTimer()  # даём Python обработать Ctrl+C
    pulse.timeout.connect(lambda: None)
    pulse.start(300)
    app.exec()
    return 1 if format_errors else 0


if __name__ == "__main__":
    sys.exit(main())
