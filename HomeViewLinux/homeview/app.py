"""Сборка приложения: оверлеи на всех мониторах, офис, трей, настройки."""

from __future__ import annotations

import logging
import os
import sys
import time

from PySide6.QtCore import QObject, Qt, QTimer
from PySide6.QtGui import QCursor, QGuiApplication, QScreen
from PySide6.QtNetwork import QLocalServer, QLocalSocket
from PySide6.QtWidgets import QApplication, QMessageBox

from . import art, gpu, paths, season as seasons, x11
from .office import Office
from .overlay import create_overlay
from .settings import Settings
from .settings_window import SettingsWindow
from .toasts import Toast, ToastAction, ToastManager
from .tray import Tray
from .world import World

log = logging.getLogger(__name__)

INSTANCE_KEY = f"homeview-linux-{os.getuid()}"


class HomeViewApp(QObject):
    def __init__(self, qapp: QApplication, settings: Settings, choice: gpu.Choice) -> None:
        super().__init__()
        self.qapp = qapp
        self.settings = settings
        self.choice = choice
        self.toasts = ToastManager()
        self.office = Office(self.settings, self.toasts)
        self.office.animate_throw = self._animate_throw
        self.office.peers_changed.connect(self._sync_peers)
        self.office.peer_event.connect(self._peer_event)
        self.settings.changed.connect(self._apply_settings)
        self.season = seasons.resolve(self.settings.season)
        self.overlays: list = []
        self._watched_screens: list[QScreen] = []
        self.settings_window: SettingsWindow | None = None

        self._last_frame = time.monotonic()
        self._frame_timer = QTimer(self)
        self._frame_timer.setTimerType(Qt.PreciseTimer)
        self._frame_timer.timeout.connect(self._frame)
        self._season_timer = QTimer(self)
        self._season_timer.timeout.connect(self._check_season)
        self._season_timer.start(60_000)

        qapp.screenAdded.connect(lambda _: self._rebuild_overlays())
        qapp.screenRemoved.connect(lambda _: self._rebuild_overlays())
        qapp.primaryScreenChanged.connect(lambda _: self._rebuild_overlays())

        self._rebuild_overlays()
        self.tray = Tray(self.settings, self.office, self.open_settings, self.quit)
        self._apply_settings()
        self.office.apply_settings()

        if not art.art_available():
            self.toasts.post(Toast("⚠️", "Не найдены картинки HomeView",
                                   "Ожидалась папка HomeView/Art рядом с HomeViewLinux. "
                                   "Человечки будут без фигур.", auto_dismiss=15))
        if not x11.get().can_shape:
            self.toasts.post(Toast("⚠️", "Нет X11 Shape",
                                   "Клики по человечкам работать не будут. Нужна сессия X11.", auto_dismiss=15))
        self._report_renderer()
        if self.settings.first_run:
            QTimer.singleShot(400, self.open_settings)

    # MARK: - Оверлеи

    def _rebuild_overlays(self) -> None:
        for overlay in self.overlays:
            overlay.close()
            overlay.deleteLater()
        self.overlays = []
        primary = QGuiApplication.primaryScreen()
        for screen in QGuiApplication.screens():
            world = World(screen.geometry(), screen.availableGeometry(), screen == primary, self.season,
                          self.settings.density, self.settings.avatar_scale, self.settings.effects_enabled,
                          screen.devicePixelRatio(), gpu_particles=self.choice.use_opengl,
                          text_scale=self.settings.text_scale)
            overlay = create_overlay(screen, world, self.choice.use_opengl)
            if not overlay.has_alpha:
                # Страховка: без альфа-канала оверлей закрыл бы экран чёрным — переходим на процессор
                log.warning("OpenGL-окно без альфа-канала — переключаюсь на программную отрисовку")
                overlay.destroy()
                self.choice.used = "cpu"
                self.choice.notes.append("OpenGL-окно получилось без прозрачности")
                world.fall_back_to_cpu_particles()
                overlay = create_overlay(screen, world, False)
            overlay.peer_clicked.connect(self._peer_clicked)
            if screen not in self._watched_screens:
                self._watched_screens.append(screen)
                screen.geometryChanged.connect(lambda _=None, s=screen: self._replace(s))
                screen.availableGeometryChanged.connect(lambda _=None, s=screen: self._replace(s))
            overlay.show()
            self.overlays.append(overlay)
        self._sync_peers()
        log.info("Оверлеи: %s", ", ".join(f"{o.qscreen.name()} {o.qscreen.geometry().getRect()} "
                                          f"win=0x{int(o.winId()):x}{' (основной)' if o.world.is_primary else ''}"
                                          for o in self.overlays))

    def _replace(self, screen: QScreen) -> None:
        for overlay in self.overlays:
            if overlay.qscreen is screen:
                overlay.place(screen)

    @property
    def primary(self):
        for overlay in self.overlays:
            if overlay.world.is_primary:
                return overlay
        return self.overlays[0] if self.overlays else None

    # MARK: - Кадр

    def _frame(self) -> None:
        now = time.monotonic()
        dt = min(max(now - self._last_frame, 0.0), 0.1)
        self._last_frame = now
        for overlay in self.overlays:
            world = overlay.world
            if world.is_idle:
                continue
            world.tick(dt)
            overlay.update()
            overlay.update_input_region()

    def _apply_settings(self) -> None:
        s = self.settings
        self.apply_look(s.season, s.density, s.avatar_scale, s.text_scale, s.effects_enabled, s.fps)

    def apply_look(self, season: str, density: float, avatar_scale: float, text_scale: float,
                   effects_enabled: bool, fps: int) -> None:
        """Применяет внешний вид сразу — и из сохранённых настроек, и как живой предпросмотр из окна настроек."""
        self.season = seasons.resolve(season)
        for overlay in self.overlays:
            overlay.world.apply(self.season, density, avatar_scale, effects_enabled, text_scale)
            overlay.update()
            overlay.update_input_region()
        interval = round(1000 / fps)
        if self._frame_timer.interval() != interval or not self._frame_timer.isActive():
            self._frame_timer.start(interval)

    def _check_season(self) -> None:
        if self.settings.season == "auto" and seasons.resolve("auto").kind != self.season.kind:
            self._apply_settings()
            self.tray.rebuild()

    # MARK: - Офис → мир

    def _sync_peers(self) -> None:
        peers = self.office.visible_peers()
        rooms = list(self.office.rooms.values())
        for overlay in self.overlays:
            overlay.world.sync_peers(peers, rooms)
            overlay.update_input_region()
            overlay.update()

    def _peer_event(self, kind: str, peer_id: str, text: str) -> None:
        overlay = self.primary
        if overlay is None:
            return
        world = overlay.world
        if kind == "wave":
            world.peer_waves(peer_id)
        elif kind == "say":
            world.peer_says(peer_id, text)
        elif kind == "hop":
            world.peer_says(peer_id, "", from_me=True)
        elif kind == "projectile":
            world.incoming_projectile(peer_id, overlay.cursor_local(QCursor.pos()))

    def _animate_throw(self, peer_id: str, done) -> None:
        overlay = self.primary
        if overlay is None:
            done()
            return
        overlay.world.throw_at(peer_id, done)

    def _peer_clicked(self, peer_id: str, at) -> None:
        self.office.show_peer_menu(peer_id, at, self.season.projectile_title, self.season.emoji)

    # MARK: - Окна

    def open_settings(self) -> None:
        if self.settings_window is None:
            self.settings_window = SettingsWindow(self.settings, self.office.status_line, self.choice,
                                                  self.restart, self.apply_look)
            self.settings_window.finished.connect(self._settings_closed)
        else:
            self.settings_window.load()
        self.settings_window.show()
        self.settings_window.raise_()
        self.settings_window.activateWindow()

    def _settings_closed(self) -> None:
        if self.settings_window is not None:
            self.settings_window.deleteLater()
            self.settings_window = None

    def quit(self) -> None:
        self.office.client.stop()
        for overlay in self.overlays:
            overlay.close()
        self.qapp.quit()

    def restart(self) -> None:
        """Перезапуск процесса (нужен для смены видеокарты: она выбирается до загрузки OpenGL)."""
        log.info("Перезапуск…")
        self.office.client.stop()
        for overlay in self.overlays:
            overlay.close()
        self.qapp.processEvents()
        env = dict(os.environ)
        for key in RENDER_ENV_KEYS:
            env.pop(key, None)  # переменные прошлого выбора не должны влиять на новый
        env["PYTHONPATH"] = os.pathsep.join(filter(None, [str(paths.LINUX_DIR), env.get("PYTHONPATH", "")]))
        os.execve(sys.executable, [sys.executable, "-m", "homeview", *sys.argv[1:]], env)

    # MARK: - Видеокарта

    def _report_renderer(self) -> None:
        c = self.choice
        log.info("Отрисовка: %s (%s)%s", c.used, c.renderer or "процессор",
                 f"; замечания: {'; '.join(c.notes)}" if c.notes else "")
        if c.used == "cpu":
            reason = "\n".join(c.notes) if c.notes else "Так выбрано в настройках."
            self.toasts.post(Toast(
                "🐢", "Рисуем процессором — повышенная нагрузка",
                f"{reason}\nОсадки и анимации будут заметно нагружать процессор. "
                "Можно уменьшить плотность осадков или выключить их.",
                [ToastAction("Настройки", self.open_settings, primary=True)], auto_dismiss=20, key="renderer"))
        elif c.notes:
            used = "дискретной видеокарте" if c.used == "discrete" else "встроенной графике"
            self.toasts.post(Toast("ℹ️", f"Рисуем на {used}", "\n".join(c.notes) + f"\n{c.renderer}",
                                   auto_dismiss=10, key="renderer"))


RENDER_ENV_KEYS = ("__NV_PRIME_RENDER_OFFLOAD", "__GLX_VENDOR_LIBRARY_NAME", "__VK_LAYER_NV_optimus", "DRI_PRIME")


def _already_running() -> bool:
    socket = QLocalSocket()
    socket.connectToServer(INSTANCE_KEY)
    if socket.waitForConnected(300):
        socket.write(b"settings\n")
        socket.waitForBytesWritten(300)
        socket.disconnectFromServer()
        return True
    return False


def run(argv: list[str]) -> int:
    os.environ.setdefault("QT_QPA_PLATFORM", "xcb")
    if _already_running():
        log.info("HomeView уже запущен — открываю настройки в нём")
        return 0

    # Видеокарту выбираем ДО QApplication: переменные окружения читаются при загрузке OpenGL
    settings = Settings()
    choice = gpu.choose(settings.renderer)
    os.environ.update(choice.env)

    qapp = QApplication(argv)
    qapp.setApplicationName("HomeView")
    qapp.setApplicationDisplayName("HomeView")
    qapp.setDesktopFileName("homeview-linux")
    qapp.setQuitOnLastWindowClosed(False)

    if qapp.platformName() != "xcb":
        QMessageBox.warning(None, "HomeView",
                            "HomeView для Linux работает только в сессии X11.\n"
                            f"Сейчас платформа: {qapp.platformName()}")

    app = HomeViewApp(qapp, settings, choice)

    QLocalServer.removeServer(INSTANCE_KEY)
    server = QLocalServer()
    server.listen(INSTANCE_KEY)

    def incoming() -> None:
        connection = server.nextPendingConnection()
        if connection is not None:
            connection.readyRead.connect(lambda: (connection.readAll(), app.open_settings()))
            connection.disconnected.connect(connection.deleteLater)

    server.newConnection.connect(incoming)
    return qapp.exec()
