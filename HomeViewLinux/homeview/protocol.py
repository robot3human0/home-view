"""Протокол HomeView (совместим с HomeViewProtocol/Protocol.swift, версия 4).

Сообщения — JSON в текстовых кадрах WebSocket, в формате синтезированного Swift `Codable`
для enum с ассоциированными значениями:

    именованные поля:   {"hello": {"id": "...", "name": "...", ...}}
    безымянное значение: {"status": {"_0": "active"}}
    без значений:        {"jump": {}}
    Optional == nil:     ключ отсутствует

Источник правды — Swift-файл. При обновлении HomeView от iOS-команды сверять diff.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import Any

PROTOCOL_VERSION = 4
DEFAULT_PORT = 47777
DOWNLOAD_PORT = 47778
SERVICE_TYPE = "_homeview._tcp.local."
MAX_CHAT_LENGTH = 200

STATUSES = ("active", "away", "busy", "hidden")
HATS = ("beanie", "cap", "doppi", "strawHat")


# MARK: - Модели


@dataclass(frozen=True)
class AvatarStyle:
    hat: str = "doppi"
    hat_color: int = 0x1E3A5F
    vest_color: int = 0x1E88E5
    skin_color: int = 0xE0AC69

    def to_json(self) -> dict[str, Any]:
        return {
            "hat": self.hat,
            "hatColor": self.hat_color,
            "vestColor": self.vest_color,
            "skinColor": self.skin_color,
        }

    @staticmethod
    def from_json(data: dict[str, Any]) -> "AvatarStyle":
        hat = data.get("hat", "doppi")
        return AvatarStyle(
            hat=hat if hat in HATS else "doppi",
            hat_color=int(data.get("hatColor", 0x1E3A5F)) & 0xFFFFFF,
            vest_color=int(data.get("vestColor", 0x1E88E5)) & 0xFFFFFF,
            skin_color=int(data.get("skinColor", 0xE0AC69)) & 0xFFFFFF,
        )


STANDARD_AVATAR = AvatarStyle()


@dataclass
class PeerInfo:
    id: str
    name: str
    team: str
    avatar: AvatarStyle
    status: str

    @staticmethod
    def from_json(data: dict[str, Any]) -> "PeerInfo":
        status = data.get("status", "active")
        return PeerInfo(
            id=str(data.get("id", "")),
            name=str(data.get("name", "")),
            team=str(data.get("team", "")),
            avatar=AvatarStyle.from_json(data.get("avatar") or {}),
            status=status if status in STATUSES else "active",
        )

    def to_json(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "team": self.team,
            "avatar": self.avatar.to_json(),
            "status": self.status,
        }


@dataclass
class RoomInfo:
    id: str
    game: str
    host_id: str
    players: list[str]
    phase: str
    starts_at: float | None = None
    teams: dict[str, int] | None = None

    @staticmethod
    def from_json(data: dict[str, Any]) -> "RoomInfo":
        return RoomInfo(
            id=str(data.get("id", "")),
            game=str(data.get("game", "")),
            host_id=str(data.get("hostID", "")),
            players=[str(p) for p in data.get("players", [])],
            phase=str(data.get("phase", "lobby")),
            starts_at=data.get("startsAt"),
            teams=data.get("teams"),
        )


@dataclass
class AppRelease:
    version: str
    build: int
    url: str
    notes: str = ""

    @staticmethod
    def from_json(data: dict[str, Any]) -> "AppRelease":
        return AppRelease(
            version=str(data.get("version", "")),
            build=int(data.get("build", 0)),
            url=str(data.get("url", "")),
            notes=str(data.get("notes", "")),
        )


# Названия игр для интерфейса (сами игры в Linux-клиенте пока не реализованы).
GAMES: dict[str, tuple[str, str]] = {
    "hotBall": ("💣", "Ледяной мяч"),
    "marksman": ("🎯", "Снайпер"),
    "volleyball": ("🏐", "Волейбол"),
    "tennis": ("🏓", "Настольный теннис"),
    "penalty": ("⚽", "Пенальти"),
    "basketball": ("🏀", "Баскетбол"),
    "tugOfWar": ("🪢", "Перетягивание каната"),
    "chessBlitz": ("♟️", "Шахматы · блиц"),
    "chessDaily": ("♟️", "Шахматы · по ходу в день"),
    "chessTeam": ("♟️", "Шахматы · командные"),
}

GAME_MAX_PLAYERS = {
    "hotBall": 10, "marksman": 12, "volleyball": 8, "tennis": 4, "penalty": 12,
    "basketball": 12, "tugOfWar": 16, "chessBlitz": 2, "chessDaily": 2, "chessTeam": 12,
}


def game_title(game: str) -> tuple[str, str]:
    return GAMES.get(game, ("🎮", game))


# MARK: - Кодирование (клиент → сервер)


def _encode(case: str, payload: dict[str, Any]) -> str:
    return json.dumps({case: payload}, ensure_ascii=False, separators=(",", ":"))


def hello(peer_id: str, name: str, team: str, avatar: AvatarStyle, status: str, code: str) -> str:
    return _encode("hello", {
        "id": peer_id,
        "name": name,
        "team": team,
        "avatar": avatar.to_json(),
        "status": status,
        "code": code,
        "version": PROTOCOL_VERSION,
    })


def status(value: str) -> str:
    return _encode("status", {"_0": value})


def profile(name: str, team: str, avatar: AvatarStyle) -> str:
    return _encode("profile", {"name": name, "team": team, "avatar": avatar.to_json()})


def ping(to: str, kind: str) -> str:
    """kind: "wave" | "tea"."""
    return _encode("ping", {"to": to, "kind": kind})


def projectile(to: str) -> str:
    return _encode("projectile", {"to": to})


def chat(to: str | None, text: str) -> str:
    payload: dict[str, Any] = {"text": text[:MAX_CHAT_LENGTH]}
    if to is not None:
        payload["to"] = to
    return _encode("chat", payload)


def respond(room_id: str, accept: bool) -> str:
    return _encode("respond", {"roomID": room_id, "accept": accept})


def leave(room_id: str) -> str:
    return _encode("leave", {"roomID": room_id})


# MARK: - Декодирование (сервер → клиент)

# Случаи с единственным безымянным значением: {"case": {"_0": value}}.
_UNNAMED = {"peerJoined", "peerUpdated", "room", "latestApp", "chess", "chessLive",
            "status", "target", "sportState"}


@dataclass
class Message:
    case: str
    data: dict[str, Any] = field(default_factory=dict)
    value: Any = None  # для безымянных случаев — содержимое "_0"


def decode(text: str) -> Message | None:
    try:
        obj = json.loads(text)
    except (json.JSONDecodeError, TypeError):
        return None
    if not isinstance(obj, dict) or len(obj) != 1:
        return None
    case, payload = next(iter(obj.items()))
    if not isinstance(payload, dict):
        return None
    if "_0" in payload and (case in _UNNAMED or len(payload) == 1):
        return Message(case=case, data=payload, value=payload["_0"])
    return Message(case=case, data=payload)
