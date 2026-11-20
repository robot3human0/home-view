"""Настройки (QSettings → ~/.config/HomeView/HomeViewLinux.conf)."""

from __future__ import annotations

import getpass
import os
import pwd
import uuid
from pathlib import Path

from PySide6.QtCore import QObject, QSettings, Signal

from . import paths
from .protocol import STANDARD_AVATAR, STATUSES, AvatarStyle

SEASONS = ("auto", "winter", "spring", "summer", "autumn")


def _default_name() -> str:
    try:
        gecos = pwd.getpwuid(os.getuid()).pw_gecos.split(",")[0].strip()
        if gecos:
            return gecos
    except KeyError:
        pass
    return getpass.getuser()


class Settings(QObject):
    """Все настройки приложения. `changed` — после любого сохранения."""

    changed = Signal()

    def __init__(self) -> None:
        super().__init__()
        self._q = QSettings("HomeView", "HomeViewLinux")
        if not self._q.value("peerID"):
            # Как в Mac-версии: UUID в верхнем регистре
            self._q.setValue("peerID", str(uuid.uuid4()).upper())

    # MARK: - Помощники

    def _str(self, key: str, default: str = "") -> str:
        value = self._q.value(key, default)
        return str(value) if value is not None else default

    def _bool(self, key: str, default: bool) -> bool:
        value = self._q.value(key, default)
        if isinstance(value, str):
            return value.lower() in ("true", "1", "yes")
        return bool(value)

    def _float(self, key: str, default: float, lo: float, hi: float) -> float:
        try:
            value = float(self._q.value(key, default))
        except (TypeError, ValueError):
            value = default
        return min(hi, max(lo, value))

    def _int(self, key: str, default: int) -> int:
        try:
            return int(self._q.value(key, default))
        except (TypeError, ValueError):
            return default

    def save(self, **values) -> None:
        """Сохраняет несколько значений и один раз сообщает об изменении."""
        for key, value in values.items():
            setter = getattr(type(self), key, None)
            if not isinstance(setter, property) or setter.fset is None:
                raise AttributeError(key)
            setter.fset(self, value)
        self._q.sync()
        self.changed.emit()

    # MARK: - Личность

    @property
    def peer_id(self) -> str:
        return self._str("peerID")

    @property
    def first_run(self) -> bool:
        return not self._bool("configured", False)

    @property
    def configured(self) -> bool:
        return self._bool("configured", False)

    @configured.setter
    def configured(self, value: bool) -> None:
        self._q.setValue("configured", bool(value))

    @property
    def display_name(self) -> str:
        return self._str("displayName", _default_name())

    @display_name.setter
    def display_name(self, value: str) -> None:
        self._q.setValue("displayName", value.strip()[:32])

    @property
    def team(self) -> str:
        return self._str("team", "")

    @team.setter
    def team(self, value: str) -> None:
        self._q.setValue("team", value.strip()[:24])

    @property
    def avatar(self) -> AvatarStyle:
        return AvatarStyle(
            hat=self._str("avatarHat", STANDARD_AVATAR.hat),
            hat_color=self._int("avatarHatColor", STANDARD_AVATAR.hat_color),
            vest_color=self._int("avatarVestColor", STANDARD_AVATAR.vest_color),
            skin_color=self._int("avatarSkinColor", STANDARD_AVATAR.skin_color),
        )

    @avatar.setter
    def avatar(self, value: AvatarStyle) -> None:
        self._q.setValue("avatarHat", value.hat)
        self._q.setValue("avatarHatColor", value.hat_color)
        self._q.setValue("avatarVestColor", value.vest_color)
        self._q.setValue("avatarSkinColor", value.skin_color)

    @property
    def my_status(self) -> str:
        value = self._str("myStatus", "active")
        return value if value in STATUSES else "active"

    @my_status.setter
    def my_status(self, value: str) -> None:
        self._q.setValue("myStatus", value if value in STATUSES else "active")

    # MARK: - Офис

    @property
    def office_enabled(self) -> bool:
        return self._bool("officeEnabled", True)

    @office_enabled.setter
    def office_enabled(self, value: bool) -> None:
        self._q.setValue("officeEnabled", bool(value))

    @property
    def office_code(self) -> str:
        return self._str("officeCode", "")

    @office_code.setter
    def office_code(self, value: str) -> None:
        self._q.setValue("officeCode", value.strip())

    @property
    def server_address(self) -> str:
        return self._str("serverAddress", "")

    @server_address.setter
    def server_address(self, value: str) -> None:
        self._q.setValue("serverAddress", value.strip())

    @property
    def auto_away(self) -> bool:
        return self._bool("autoAway", True)

    @auto_away.setter
    def auto_away(self, value: bool) -> None:
        self._q.setValue("autoAway", bool(value))

    @property
    def hidden_peers(self) -> set[str]:
        value = self._q.value("hiddenPeers", [])
        if isinstance(value, str):
            value = [value] if value else []
        return set(value or [])

    @hidden_peers.setter
    def hidden_peers(self, value: set[str]) -> None:
        self._q.setValue("hiddenPeers", sorted(value))

    # MARK: - Экран

    @property
    def effects_enabled(self) -> bool:
        return self._bool("effectsEnabled", True)

    @effects_enabled.setter
    def effects_enabled(self, value: bool) -> None:
        self._q.setValue("effectsEnabled", bool(value))

    @property
    def season(self) -> str:
        value = self._str("season", "auto")
        return value if value in SEASONS else "auto"

    @season.setter
    def season(self, value: str) -> None:
        self._q.setValue("season", value if value in SEASONS else "auto")

    @property
    def density(self) -> float:
        """Плотность осадков, 1.0 — как в Mac-версии."""
        return self._float("density", 0.7, 0.1, 2.0)

    @density.setter
    def density(self, value: float) -> None:
        self._q.setValue("density", float(value))

    @property
    def avatar_scale(self) -> float:
        """Размер человечков; 1.0 — как точка в точку на Mac (на обычных мониторах мелковато)."""
        return self._float("avatarScale", 2.0, 0.6, 4.0)

    @avatar_scale.setter
    def avatar_scale(self, value: float) -> None:
        self._q.setValue("avatarScale", float(value))

    @property
    def renderer(self) -> str:
        """Чем рисовать: auto | discrete | integrated | cpu (см. gpu.py). Меняется с перезапуском."""
        value = self._str("renderer", "auto")
        return value if value in ("auto", "discrete", "integrated", "cpu") else "auto"

    @renderer.setter
    def renderer(self, value: str) -> None:
        self._q.setValue("renderer", value)

    @property
    def text_scale(self) -> float:
        """Размер табличек с именами и облачков с сообщениями."""
        return self._float("textScale", 2.5, 1.0, 4.0)

    @text_scale.setter
    def text_scale(self, value: float) -> None:
        self._q.setValue("textScale", float(value))

    @property
    def toast_scale(self) -> float:
        """Размер карточек-уведомлений справа вверху."""
        return self._float("toastScale", 1.5, 1.0, 3.0)

    @toast_scale.setter
    def toast_scale(self, value: float) -> None:
        self._q.setValue("toastScale", float(value))

    @property
    def fps(self) -> int:
        value = self._int("fps", 30)
        return value if value in (20, 30, 60) else 30

    @fps.setter
    def fps(self, value: int) -> None:
        self._q.setValue("fps", int(value))

    # MARK: - Автозапуск (~/.config/autostart/homeview-linux.desktop)

    @staticmethod
    def autostart_path() -> Path:
        base = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
        return base / "autostart" / "homeview-linux.desktop"

    @property
    def autostart(self) -> bool:
        return self.autostart_path().exists()

    @autostart.setter
    def autostart(self, value: bool) -> None:
        path = self.autostart_path()
        if value:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(
                "[Desktop Entry]\n"
                "Type=Application\n"
                "Name=HomeView\n"
                "Comment=Времена года и коллеги на рабочем столе\n"
                f"Exec={paths.run_script()}\n"
                f"Icon={paths.app_icon()}\n"
                "X-GNOME-Autostart-enabled=true\n"
                "X-GNOME-Autostart-Delay=5\n",
                encoding="utf-8",
            )
        elif path.exists():
            path.unlink()
