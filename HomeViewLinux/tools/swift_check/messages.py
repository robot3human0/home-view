"""Python-часть проверки совместимости с настоящим Swift-протоколом (см. run.sh).

    python messages.py write-client <файл>   — сообщения Linux-клиента для Swift JSONDecoder
    python messages.py verify-server <файл>  — разобрать сообщения, закодированные Swift JSONEncoder
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from homeview import protocol as p  # noqa: E402


def client_messages() -> list[str]:
    """Всё, что Linux-клиент умеет отправлять, во всех вариантах."""
    avatar = p.AvatarStyle("strawHat", 0xC62828, 0x1565C0, 0xFFDBAC)
    messages = [
        p.hello("3F2504E0-4F89-11D3-9A0C-0305E82C3301", "Алишер", "Backend", avatar, "active", ""),
        p.hello("X", "Имя", "", p.STANDARD_AVATAR, "hidden", "qishki2026"),
        p.profile("Алишер И.", "Backend C++", avatar),
        p.ping("PEER-1", "wave"),
        p.ping("PEER-1", "tea"),
        p.projectile("PEER-1"),
        p.chat("PEER-1", 'Привет! 👋 "кавычки" и \\ слэш'),
        p.chat(None, "Всем привет"),
        p.respond("ROOM-1", False),
        p.respond("ROOM-1", True),
        p.leave("ROOM-1"),
    ]
    messages += [p.status(s) for s in p.STATUSES]
    messages += [p.hello("H", "Шапка", "", p.AvatarStyle(hat, 0xFFFFFF, 0, 0x123456), "active", "") for hat in p.HATS]
    return messages


def verify_server(path: Path) -> int:
    failures = 0
    lines = [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    for line in lines:
        message = p.decode(line)
        if message is None:
            failures += 1
            print(f"FAIL decode   {line[:120]}")
            continue
        try:
            detail = _check(message)
        except Exception as error:  # noqa: BLE001 — нужен любой сбой разбора
            failures += 1
            print(f"FAIL {message.case:12} {error!r}")
            continue
        print(f"OK   {message.case:12} {detail}")
    print(f"Разобрано {len(lines) - failures} из {len(lines)} сообщений сервера")
    return failures


def _check(message: p.Message) -> str:
    case = message.case
    if case == "welcome":
        peers = [p.PeerInfo.from_json(x) for x in message.data["peers"]]
        rooms = [p.RoomInfo.from_json(x) for x in message.data["rooms"]]
        assert peers[0].name == "Жасур" and peers[0].status == "away"
        assert peers[0].avatar == p.AvatarStyle("beanie", 0x7B1E1E, 0x43A047, 0xC68642)
        assert rooms[0].starts_at == 1_800_000_000.5 and rooms[0].teams == {"PEER-1": 0}
        assert rooms[1].starts_at is None and rooms[1].teams is None
        return f"{len(peers)} коллега, {len(rooms)} комнаты"
    if case in ("peerJoined", "peerUpdated"):
        peer = p.PeerInfo.from_json(message.value)
        assert (peer.name, peer.team, peer.status) == ("Жасур", "iOS", "away")
        return f"{peer.name} · {peer.team} ({peer.status})"
    if case == "room":
        room = p.RoomInfo.from_json(message.value)
        assert (room.game, room.host_id, room.phase) == ("volleyball", "PEER-1", "lobby")
        return f"{room.game} {room.phase}"
    if case == "latestApp":
        release = p.AppRelease.from_json(message.value)
        assert release.build == 14
        return f"{release.version} (build {release.build})"
    if case == "chat":
        assert isinstance(message.data["direct"], bool) and message.data["from"] == "PEER-1"
    if case == "ping":
        assert message.data["kind"] in ("wave", "tea")
    return str(message.data)[:90]


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[1] not in ("write-client", "verify-server"):
        print(__doc__)
        return 2
    path = Path(sys.argv[2])
    if sys.argv[1] == "write-client":
        messages = client_messages()
        path.write_text("\n".join(messages) + "\n", encoding="utf-8")
        print(f"Записано {len(messages)} сообщений клиента")
        return 0
    return 1 if verify_server(path) else 0


if __name__ == "__main__":
    sys.exit(main())
