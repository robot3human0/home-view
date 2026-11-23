"""Значок в трее (аналог ❄-меню в строке меню macOS).

В Ubuntu значок показывается через расширение AppIndicator (включено по умолчанию).
"""

from __future__ import annotations

from typing import Callable

from PySide6.QtCore import QObject, QRectF, Qt, QTimer
from PySide6.QtGui import QAction, QActionGroup, QCursor, QFont, QIcon, QPainter, QPixmap
from PySide6.QtWidgets import QMenu, QSystemTrayIcon

from . import paths, season as seasons
from .office import STATUS_TITLES, Office
from .profiling import measure
from .settings import Settings


def emoji_icon(emoji: str) -> QIcon:
    icon = QIcon()
    for size in (16, 22, 24, 32, 48, 64):
        pixmap = QPixmap(size, size)
        pixmap.fill(Qt.transparent)
        painter = QPainter(pixmap)
        font = QFont()
        font.setPixelSize(round(size * 0.8))
        painter.setFont(font)
        painter.drawText(QRectF(0, 0, size, size), Qt.AlignCenter, emoji)
        painter.end()
        icon.addPixmap(pixmap)
    return icon


class Tray(QObject):
    def __init__(self, settings: Settings, office: Office, open_settings: Callable[[], None],
                 quit_app: Callable[[], None], clear_snow: Callable[[], None]) -> None:
        super().__init__()
        self.settings = settings
        self.office = office
        self._open_settings = open_settings
        self._quit = quit_app
        self._clear_snow = clear_snow
        self.icon = QSystemTrayIcon(self)
        self.menu = QMenu()
        self.icon.setContextMenu(self.menu)
        self.icon.activated.connect(self._activated)
        self._submenus: list[QMenu] = []
        self._icon_emoji = ""
        self._tooltip = ""
        self._signature: tuple | None = None
        self._rebuild_timer = QTimer(self, singleShot=True, interval=150)
        self._rebuild_timer.timeout.connect(self._changed)
        for signal in (office.state_changed, office.peers_changed, settings.changed):
            signal.connect(self._rebuild_timer.start)
        # Не пересобираем меню при открытии: в Ubuntu/Zorin оно уходит в панель через D-Bus,
        # и пересборка в момент показа заставляет панель заново тянуть всё дерево — меню «фризит».
        self.rebuild()
        self.icon.show()

    def _activated(self, reason) -> None:
        # Как ведёт себя панель Ubuntu/Zorin (AppIndicator), проверено через D-Bus:
        #   правый клик → панель сама показывает наше меню (ContextMenu);
        #   левый клик  → панель вызывает Activate (Qt сообщает ItemIsMenu=false) и ничего не
        #                 показывает — меню должны открыть мы. Координаты значка неизвестны
        #                 (геометрия пустая), поэтому открываем у курсора.
        # Открываем с задержкой: в момент клика мышь ещё захвачена панелью, и мгновенно
        # открытое меню не получит захват и тут же закроется.
        if reason == QSystemTrayIcon.Trigger:
            QTimer.singleShot(150, self._popup_at_cursor)

    def _popup_at_cursor(self) -> None:
        if self.menu.isVisible():
            self.menu.close()
            return
        geometry = self.icon.geometry()
        self.menu.popup(geometry.center() if not geometry.isEmpty() else QCursor.pos())

    def _changed(self) -> None:
        self._update_icon()
        if self.menu.isVisible():
            self._rebuild_timer.start(1000)  # открытое меню не трогаем — попробуем позже
            return
        if self._menu_signature() != self._signature:
            self.rebuild()

    def _menu_signature(self) -> tuple:
        """Всё, от чего зависит содержимое меню: если не изменилось — пересборка не нужна."""
        office, settings = self.office, self.settings
        lobbies = tuple(sorted((r.host_id, r.game) for r in office.rooms.values() if r.phase == "lobby"))
        peers = tuple((p.id, p.name, p.team, p.status) for p in office.online_peers())
        return (office.status_line(), office.connection, office.effective_status, settings.my_status,
                peers, tuple(sorted(settings.hidden_peers)), lobbies, settings.season,
                seasons.resolve(settings.season).kind, settings.effects_enabled)

    def _update_icon(self) -> None:
        current = seasons.resolve(self.settings.season)
        if current.emoji != self._icon_emoji:
            self._icon_emoji = current.emoji
            icon = emoji_icon(current.emoji)
            if icon.isNull() and paths.app_icon().exists():
                icon = QIcon(str(paths.app_icon()))
            self.icon.setIcon(icon)
        tooltip = f"HomeView — {current.title}\n{self.office.status_line()}"
        if tooltip != self._tooltip:
            self._tooltip = tooltip
            self.icon.setToolTip(tooltip)

    def _submenu(self, parent: QMenu, title: str) -> QMenu:
        sub = parent.addMenu(title)
        self._submenus.append(sub)
        return sub

    @measure("трей: пересборка меню")
    def rebuild(self) -> None:
        self._update_icon()
        self._signature = self._menu_signature()
        current = seasons.resolve(self.settings.season)
        menu = self.menu
        menu.clear()
        for sub in self._submenus:
            sub.deleteLater()
        self._submenus.clear()
        header = menu.addAction(self.office.status_line())
        header.setEnabled(False)
        if self.office.connection == "failed":
            menu.addAction("🔄  Переподключиться", self.office.reconnect)
        menu.addSeparator()

        # Мой статус
        status_menu = self._submenu(menu, f"Мой статус: {STATUS_TITLES[self.office.effective_status]}")
        group = QActionGroup(status_menu)
        for key, title in STATUS_TITLES.items():
            action = QAction(title, status_menu, checkable=True)
            action.setChecked(self.settings.my_status == key)
            action.triggered.connect(lambda _=False, k=key: self.office.set_status(k))
            group.addAction(action)
            status_menu.addAction(action)

        # Коллеги
        peers = self.office.online_peers()
        people = self._submenu(menu, f"👥  Коллеги ({len(peers)})")
        if not peers:
            empty = people.addAction("Сейчас никого нет в сети")
            empty.setEnabled(False)
        hidden = self.settings.hidden_peers
        for peer in peers:
            label = f"{peer.name} · {peer.team}" if peer.team else peer.name
            if peer.id in hidden:
                label = "🙈 " + label
            sub = self._submenu(people, label)
            self.office.fill_peer_menu(sub, peer.id, current.projectile_title, current.emoji)
        connected = self.office.connection == "connected"
        broadcast = menu.addAction("📣  Написать всем…", lambda: self.office.compose(None))
        broadcast.setEnabled(connected)
        menu.addSeparator()

        # Сезон и осадки
        season_menu = self._submenu(menu, f"{current.emoji}  Сезон: {current.title}")
        season_group = QActionGroup(season_menu)
        options = [("auto", "Автоматически")] + [(k, f"{seasons.SEASONS[k].emoji} {seasons.SEASONS[k].title}")
                                                  for k in seasons.ORDER]
        for key, title in options:
            action = QAction(title, season_menu, checkable=True)
            action.setChecked(self.settings.season == key)
            action.triggered.connect(lambda _=False, k=key: self.settings.save(season=k))
            season_group.addAction(action)
            season_menu.addAction(action)
        effects = QAction(f"Осадки ({current.particle_title.lower()})", menu, checkable=True)
        effects.setChecked(self.settings.effects_enabled)
        effects.triggered.connect(lambda on: self.settings.save(effects_enabled=on))
        menu.addAction(effects)
        menu.addAction("🧹  Убрать снег", self._clear_snow)
        menu.addSeparator()
        menu.addAction("⚙  Настройки…", self._open_settings)
        menu.addAction("Выход", self._quit)
