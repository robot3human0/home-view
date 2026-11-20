"""Офис: коллеги, статусы, сообщения сервера и действия (аналог Office.swift)."""

from __future__ import annotations

import logging
import re
import time
from typing import Callable

from PySide6.QtCore import QObject, QPoint, QTimer, Signal
from PySide6.QtWidgets import QInputDialog, QLineEdit, QMenu

from . import protocol, x11
from .net import NetworkClient
from .protocol import Message, PeerInfo, RoomInfo, game_title
from .season import TEA_LATER, TEA_TEXT, TEA_YES
from .settings import Settings
from .toasts import Toast, ToastAction, ToastManager

log = logging.getLogger(__name__)

AWAY_AFTER_SECONDS = 300
STATUS_TITLES = {
    "active": "🟢 Активен",
    "away": "☕ Отошёл",
    "busy": "🔕 Занят",
    "hidden": "👻 Невидимка",
}

# Сервер пишет по-узбекски — переводим то, что знаем
_REJECT_REASONS = {
    "Ofis kodi noto‘g‘ri": "Неверный код офиса",
    "Ism kiritilmagan": "Не указано имя",
}


def translate_server_text(text: str) -> str:
    if text in _REJECT_REASONS:
        return _REJECT_REASONS[text]
    if text.startswith("Ilovangiz eski"):
        return "Сервер требует более новую версию протокола — обновите Linux-клиент"
    if text == "Bu hamkasb hozir tarmoqda emas":
        return "Этого коллеги сейчас нет в сети"
    match = re.match(r"^(.*) hozir band — (.*) keyinroq$", text)
    if match:
        return f"{match.group(1)} сейчас занят(а) — попробуйте позже"
    return text


class Office(QObject):
    peers_changed = Signal()
    state_changed = Signal()
    # Анимации в мире: ("wave" | "say" | "hop" | "projectile", id, текст)
    peer_event = Signal(str, str, str)

    def __init__(self, settings: Settings, toasts: ToastManager) -> None:
        super().__init__()
        self.settings = settings
        self.toasts = toasts
        self.client = NetworkClient(self._hello_message)
        self.client.message.connect(self._handle)
        self.client.state_changed.connect(self._on_client_state)
        self.peers: dict[str, PeerInfo] = {}
        self.rooms: dict[str, RoomInfo] = {}
        self.connection = "off"
        self.connection_detail = ""
        self.auto_away = False
        self._running = False
        self._last_address: str | None = None
        self._last_code: str | None = None
        self._last_profile = None
        self._last_status: str | None = None
        self._last_projectile = 0.0
        # Анимация броска в мире; по окончании вызывает переданную функцию (отправку на сервер)
        self.animate_throw: Callable[[str, Callable[[], None]], None] = lambda peer_id, done: done()

        self._idle_timer = QTimer(self)
        self._idle_timer.timeout.connect(self._check_idle)
        self._idle_timer.start(15_000)
        settings.changed.connect(self.apply_settings)

    # MARK: - Состояние

    @property
    def my_id(self) -> str:
        return self.settings.peer_id

    @property
    def effective_status(self) -> str:
        status = self.settings.my_status
        if status == "active" and self.auto_away:
            return "away"
        return status

    def visible_peers(self) -> list[PeerInfo]:
        hidden = self.settings.hidden_peers
        return [p for p in self.peers.values()
                if p.id != self.my_id and p.id not in hidden and p.status != "hidden"]

    def online_peers(self) -> list[PeerInfo]:
        return sorted((p for p in self.peers.values() if p.id != self.my_id), key=lambda p: p.name.lower())

    def name(self, peer_id: str) -> str:
        peer = self.peers.get(peer_id)
        return peer.name if peer else "Коллега"

    def status_line(self) -> str:
        if self.connection == "connected":
            count = len(self.online_peers())
            return f"● В офисе · коллег в сети: {count}"
        return {
            "off": "○ Офис выключен",
            "not_configured": "○ Укажите имя в настройках",
            "idle": "○ Не подключено",
            "searching": "◌ Ищем офисный сервер…",
            "connecting": "◌ Подключаемся…",
        }.get(self.connection, f"⚠ {self.connection_detail or 'Нет связи с офисом'}")

    # MARK: - Настройки → соединение

    def apply_settings(self) -> None:
        s = self.settings
        if not s.office_enabled:
            if self._running:
                self._running = False
                self.client.stop()
                self._clear()
            self._set_connection("off")
            return
        if not s.display_name.strip():
            if self._running:
                self._running = False
                self.client.stop()
                self._clear()
            self._set_connection("not_configured")
            return
        if not self._running or s.server_address != self._last_address or s.office_code != self._last_code:
            self._running = True
            self._last_address = s.server_address
            self._last_code = s.office_code
            self._last_profile = (s.display_name, s.team, s.avatar)
            self._last_status = self.effective_status
            self._clear()
            self.client.start(s.server_address)
            return
        profile = (s.display_name, s.team, s.avatar)
        if profile != self._last_profile:
            self._last_profile = profile
            self.client.send(protocol.profile(*profile))
        self._send_status_if_changed()
        self.peers_changed.emit()

    def _hello_message(self) -> str:
        s = self.settings
        self._last_status = self.effective_status
        return protocol.hello(self.my_id, s.display_name, s.team, s.avatar, self.effective_status, s.office_code)

    def _send_status_if_changed(self) -> None:
        status = self.effective_status
        if status != self._last_status:
            self._last_status = status
            self.client.send(protocol.status(status))
            self.state_changed.emit()

    def _check_idle(self) -> None:
        if not self._running or not self.settings.auto_away:
            if self.auto_away:
                self.auto_away = False
                self._send_status_if_changed()
            return
        idle = x11.get().idle_seconds()
        if idle is None:
            return
        self.auto_away = idle > AWAY_AFTER_SECONDS
        self._send_status_if_changed()

    def _set_connection(self, state: str, detail: str = "") -> None:
        self.connection = state
        self.connection_detail = detail
        self.state_changed.emit()

    def _clear(self) -> None:
        if self.peers or self.rooms:
            self.peers.clear()
            self.rooms.clear()
            self.peers_changed.emit()

    def _on_client_state(self, state: str, detail: str) -> None:
        if state == "idle":
            self._set_connection("searching" if self._running else "off")
        elif state == "connected":
            self._set_connection("connected", detail)
        elif state == "failed":
            self._set_connection("failed", detail)
            self._clear()
        else:
            self._set_connection(state, detail)

    def reconnect(self) -> None:
        self.client.retry_now()

    # MARK: - Сообщения сервера

    def _handle(self, message: Message) -> None:
        case, data = message.case, message.data
        if case == "welcome":
            self.peers = {}
            for raw in data.get("peers", []):
                peer = PeerInfo.from_json(raw)
                if peer.id != self.my_id:
                    self.peers[peer.id] = peer
            self.rooms = {r.id: r for r in (RoomInfo.from_json(raw) for raw in data.get("rooms", []))}
            self._set_connection("connected", self.client.server_label)
            self.peers_changed.emit()
            self.toasts.post(Toast("👋", "Вы в офисе", f"Сейчас в сети: {len(self.peers)}", auto_dismiss=4,
                                   key="welcome"))
        elif case == "rejected":
            reason = translate_server_text(str(data.get("reason", "")))
            self._set_connection("failed", reason)
            self.toasts.post(Toast("⚠️", "Не удалось подключиться к офису", reason, auto_dismiss=10, key="rejected"))
        elif case == "notice":
            self.toasts.post(Toast("ℹ️", translate_server_text(str(data.get("text", ""))), auto_dismiss=4))
        elif case in ("peerJoined", "peerUpdated"):
            if isinstance(message.value, dict):
                peer = PeerInfo.from_json(message.value)
                if peer.id != self.my_id:
                    self.peers[peer.id] = peer
                    self.peers_changed.emit()
        elif case == "peerLeft":
            if self.peers.pop(str(data.get("id", "")), None) is not None:
                self.peers_changed.emit()
        elif case == "ping":
            sender = str(data.get("from", ""))
            if data.get("kind") == "tea":
                self.peer_event.emit("say", sender, TEA_TEXT)
                self.toasts.post(Toast(
                    "☕", f"{self.name(sender)} зовёт на чай", "Небольшой перерыв?",
                    [ToastAction("Иду!", lambda: self.chat(sender, TEA_YES), primary=True),
                     ToastAction("Позже", lambda: self.chat(sender, TEA_LATER))],
                    auto_dismiss=30))
            else:
                self.peer_event.emit("wave", sender, "")
        elif case == "projectile":
            self.peer_event.emit("projectile", str(data.get("from", "")), "")
        elif case == "chat":
            sender = str(data.get("from", ""))
            text = str(data.get("text", ""))
            direct = bool(data.get("direct", True))
            self.peer_event.emit("say", sender, text)
            self.toasts.post(Toast(
                "💬" if direct else "📣", self.name(sender) + ("" if direct else " (всем)"), text,
                [ToastAction("Ответить", lambda: self.compose(sender))], auto_dismiss=12))
        elif case == "invited":
            room_id = str(data.get("roomID", ""))
            emoji, title = game_title(str(data.get("game", "")))
            self.toasts.post(Toast(
                emoji, f"{self.name(str(data.get('from', '')))} зовёт в «{title}»",
                "Игры в Linux-версии пока не поддерживаются 🙏",
                [ToastAction("Отказаться", lambda: self.client.send(protocol.respond(room_id, False)))],
                auto_dismiss=30, key=f"invite-{room_id}"))
        elif case == "declined":
            self.toasts.post(Toast("🙅", f"{self.name(str(data.get('by', '')))} сейчас не может играть",
                                   auto_dismiss=5))
        elif case == "room":
            if isinstance(message.value, dict):
                room = RoomInfo.from_json(message.value)
                self.rooms[room.id] = room
                self.peers_changed.emit()
        elif case == "roomClosed":
            room_id = str(data.get("roomID", ""))
            if self.rooms.pop(room_id, None) is not None:
                self.peers_changed.emit()
            self.toasts.dismiss_key(f"invite-{room_id}")
        elif case in ("latestApp", "chess", "chessLive", "game"):
            pass  # Mac-обновления, шахматы и игры — пока не поддерживаем
        else:
            log.debug("Неизвестное сообщение: %s", case)

    # MARK: - Действия

    def wave(self, peer_id: str) -> None:
        self.client.send(protocol.ping(peer_id, "wave"))
        self.peer_event.emit("hop", peer_id, "")

    def tea(self, peer_id: str) -> None:
        self.client.send(protocol.ping(peer_id, "tea"))
        self.toasts.post(Toast("☕", "Приглашение отправлено", f"Ждём ответа от {self.name(peer_id)}", auto_dismiss=4))

    def throw_at(self, peer_id: str) -> None:
        now = time.monotonic()
        if now - self._last_projectile < 1.3:  # сервер всё равно не пропустит чаще 1,2 с
            return
        self._last_projectile = now
        self.animate_throw(peer_id, lambda: self.client.send(protocol.projectile(peer_id)))

    def chat(self, peer_id: str | None, text: str) -> None:
        clean = text.strip()
        if clean:
            self.client.send(protocol.chat(peer_id, clean[:protocol.MAX_CHAT_LENGTH]))

    def compose(self, peer_id: str | None) -> None:
        title = f"Сообщение для {self.name(peer_id)}" if peer_id else "Сообщение всем в офисе"
        text, ok = QInputDialog.getText(None, title, "Текст (до 200 символов):", QLineEdit.Normal, "")
        if ok and text.strip():
            self.chat(peer_id, text)
            if peer_id:
                self.peer_event.emit("hop", peer_id, "")

    def set_status(self, status: str) -> None:
        self.settings.save(my_status=status)

    def set_shown(self, peer_id: str, shown: bool) -> None:
        hidden = self.settings.hidden_peers
        if shown:
            hidden.discard(peer_id)
        else:
            hidden.add(peer_id)
        self.settings.save(hidden_peers=hidden)

    # MARK: - Меню коллеги

    def fill_peer_menu(self, menu: QMenu, peer_id: str, projectile_title: str, season_emoji: str) -> None:
        info = self.peers.get(peer_id)
        if info is None:
            return
        header = menu.addAction(f"{info.name} · {info.team}" if info.team else info.name)
        header.setEnabled(False)
        status = menu.addAction(STATUS_TITLES.get(info.status, info.status))
        status.setEnabled(False)
        menu.addSeparator()
        lobby = next((r for r in self.rooms.values() if r.host_id == peer_id and r.phase == "lobby"), None)
        if lobby is not None:
            emoji, title = game_title(lobby.game)
            item = menu.addAction(f"{emoji} Лобби «{title}» — игры пока только на Mac")
            item.setEnabled(False)
            menu.addSeparator()
        menu.addAction("👋  Помахать", lambda: self.wave(peer_id))
        menu.addAction(f"{season_emoji}  Кинуть {projectile_title}", lambda: self.throw_at(peer_id))
        menu.addAction("💬  Написать…", lambda: self.compose(peer_id))
        menu.addAction("☕  Позвать на чай", lambda: self.tea(peer_id))
        menu.addSeparator()
        if peer_id in self.settings.hidden_peers:
            menu.addAction("👀  Показывать на экране", lambda: self.set_shown(peer_id, True))
        else:
            menu.addAction("🙈  Убрать с моего экрана", lambda: self._hide_with_undo(peer_id))

    def _hide_with_undo(self, peer_id: str) -> None:
        self.set_shown(peer_id, False)
        self.toasts.post(Toast(
            "🙈", f"{self.name(peer_id)} убран(а) с экрана",
            "Писать и звать на чай по-прежнему можно. Вернуть: меню в трее → Коллеги.",
            [ToastAction("Вернуть", lambda: self.set_shown(peer_id, True))], auto_dismiss=8))

    def show_peer_menu(self, peer_id: str, at: QPoint, projectile_title: str, season_emoji: str) -> None:
        menu = QMenu()
        self.fill_peer_menu(menu, peer_id, projectile_title, season_emoji)
        if not menu.isEmpty():
            menu.exec(at)
