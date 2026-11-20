"""Значок в трее (аналог ❄-меню в строке меню macOS).

В Ubuntu значок показывается через расширение AppIndicator (включено по умолчанию).
"""

from __future__ import annotations

from typing import Callable

from PySide6.QtCore import QObject, QRectF, Qt, QTimer
from PySide6.QtGui import QAction, QActionGroup, QFont, QIcon, QPainter, QPixmap
from PySide6.QtWidgets import QMenu, QSystemTrayIcon

from . import paths, season as seasons
from .office import STATUS_TITLES, Office
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
                 quit_app: Callable[[], None]) -> None:
        super().__init__()
        self.settings = settings
        self.office = office
        self._open_settings = open_settings
        self._quit = quit_app
        self.icon = QSystemTrayIcon(self)
        self.menu = QMenu()
        self.icon.setContextMenu(self.menu)
        self.icon.activated.connect(self._activated)
        self._submenus: list[QMenu] = []
        self._icon_emoji = ""
        self._rebuild_timer = QTimer(self, singleShot=True, interval=150)
        self._rebuild_timer.timeout.connect(self._changed)
        for signal in (office.state_changed, office.peers_changed, settings.changed):
            signal.connect(self._rebuild_timer.start)
        self.menu.aboutToShow.connect(self.rebuild)
        self.rebuild()
        self.icon.show()

    def _activated(self, reason) -> None:
        if reason == QSystemTrayIcon.Trigger:
            self.menu.popup(self.icon.geometry().center())

    def _changed(self) -> None:
        if self.menu.isVisible():
            self._update_icon()  # открытое меню не трогаем — пересоберётся при следующем показе
        else:
            self.rebuild()

    def _update_icon(self) -> None:
        current = seasons.resolve(self.settings.season)
        if current.emoji != self._icon_emoji:
            self._icon_emoji = current.emoji
            icon = emoji_icon(current.emoji)
            if icon.isNull() and paths.app_icon().exists():
                icon = QIcon(str(paths.app_icon()))
            self.icon.setIcon(icon)
        self.icon.setToolTip(f"HomeView — {current.title}\n{self.office.status_line()}")

    def _submenu(self, parent: QMenu, title: str) -> QMenu:
        sub = parent.addMenu(title)
        self._submenus.append(sub)
        return sub

    def rebuild(self) -> None:
        self._update_icon()
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
        menu.addSeparator()
        menu.addAction("⚙  Настройки…", self._open_settings)
        menu.addAction("Выход", self._quit)
