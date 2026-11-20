"""Прозрачное окно поверх всех окон на одном мониторе (аналог OverlayPanel из Mac-версии).

* override-redirect (X11BypassWindowManagerHint): оконный менеджер его не трогает —
  нет рамки, нет в панели задач, виден на всех рабочих столах, выше обычных окон;
* ARGB-фон: прозрачность обеспечивает композитор GNOME;
* клики проходят насквозь везде, кроме прямоугольников человечков (XShape input region).

Два варианта отрисовки (выбор — в gpu.py):
* GLOverlayWindow — QPainter поверх OpenGL: рисует видеокарта, буфер окна живёт в видеопамяти,
  композитор забирает его без копирования через процессор;
* RasterOverlayWindow — программная отрисовка в памяти (запасной вариант, заметно грузит CPU).
"""

from __future__ import annotations

from PySide6.QtCore import QPoint, QPointF, QRect, Qt, Signal
from PySide6.QtGui import QMouseEvent, QPainter, QScreen, QSurfaceFormat
from PySide6.QtOpenGL import QOpenGLWindow
from PySide6.QtWidgets import QWidget

from . import x11
from .gl_particles import GLParticleRenderer
from .world import World

WINDOW_FLAGS = (Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool | Qt.X11BypassWindowManagerHint
                | Qt.WindowDoesNotAcceptFocus | Qt.NoDropShadowWindowHint)


class _OverlayMixin:
    """Общее для обоих вариантов: геометрия, область ввода, клики, рисование мира."""

    world: World

    def _init_overlay(self, screen: QScreen, world: World) -> None:
        self.world = world
        self._screen = screen
        self._input_rects: list[tuple[int, int, int, int]] | None = None

    @property
    def qscreen(self) -> QScreen:
        return self._screen

    def place(self, screen: QScreen) -> None:
        self._screen = screen
        self.setScreen(screen)
        self.setGeometry(screen.geometry())
        self.world.set_geometry(screen.geometry(), screen.availableGeometry())

    def update_input_region(self, force: bool = False) -> None:
        ratio = self.devicePixelRatio()
        rects = self.world.input_rects()
        if ratio != 1:
            rects = [(round(x * ratio), round(y * ratio), round(w * ratio), round(h * ratio)) for x, y, w, h in rects]
        if force or rects != self._input_rects:
            self._input_rects = rects
            x11.get().set_input_rects(int(self.winId()), rects)

    def _handle_press(self, event: QMouseEvent) -> bool:
        if event.button() in (Qt.LeftButton, Qt.RightButton):
            peer_id = self.world.avatar_at(event.position())
            if peer_id:
                self.peer_clicked.emit(peer_id, event.globalPosition().toPoint())
                return True
        return False

    def cursor_local(self, global_pos: QPoint) -> QPointF | None:
        geometry = self._screen.geometry()
        if not geometry.contains(global_pos):
            return None
        return QPointF(global_pos - geometry.topLeft())

    def _paint_world(self, painter: QPainter, rect: QRect) -> None:
        painter.setCompositionMode(QPainter.CompositionMode_Source)
        painter.fillRect(rect, Qt.transparent)
        painter.setCompositionMode(QPainter.CompositionMode_SourceOver)
        self.world.paint(painter)


class GLOverlayWindow(QOpenGLWindow, _OverlayMixin):
    peer_clicked = Signal(str, QPoint)

    def __init__(self, screen: QScreen, world: World) -> None:
        super().__init__(QOpenGLWindow.NoPartialUpdate)
        self._init_overlay(screen, world)
        self._particles = GLParticleRenderer()
        fmt = QSurfaceFormat()
        fmt.setAlphaBufferSize(8)
        fmt.setSwapInterval(0)  # не ждать вертикальную синхронизацию: окон несколько, частоту задаёт таймер
        self.setFormat(fmt)
        self.setFlags(WINDOW_FLAGS)
        self.setTitle("HomeView overlay")
        self.setCursor(Qt.PointingHandCursor)  # виден только там, где окно принимает мышь
        self.place(screen)
        self.create()
        self.update_input_region(force=True)

    def paintGL(self) -> None:
        painter = QPainter(self)
        painter.setCompositionMode(QPainter.CompositionMode_Source)
        painter.fillRect(QRect(0, 0, self.width(), self.height()), Qt.transparent)
        painter.setCompositionMode(QPainter.CompositionMode_SourceOver)
        if self.world.gpu_particles:
            painter.beginNativePainting()
            ok = self._particles.draw(self.world.particle_systems(), self.width(), self.height(),
                                      self.devicePixelRatio())
            painter.endNativePainting()
            if not ok:
                self.world.fall_back_to_cpu_particles()
        self.world.paint(painter)
        painter.end()

    def closeEvent(self, event) -> None:
        if self.context() is not None:
            self.makeCurrent()
            self._particles.destroy()
            self.doneCurrent()
        super().closeEvent(event)

    def mousePressEvent(self, event: QMouseEvent) -> None:
        if not self._handle_press(event):
            event.ignore()

    @property
    def has_alpha(self) -> bool:
        """Реально ли окно получило альфа-канал (иначе вместо прозрачности будет чёрный экран)."""
        return self.format().alphaBufferSize() >= 8

    def renderer_info(self) -> str:
        context = self.context()
        if context is None:
            return ""
        return context.functions().glGetString(0x1F01) or ""


class RasterOverlayWindow(QWidget, _OverlayMixin):
    peer_clicked = Signal(str, QPoint)

    def __init__(self, screen: QScreen, world: World) -> None:
        super().__init__(None)
        self._init_overlay(screen, world)
        self.setWindowFlags(WINDOW_FLAGS)
        self.setAttribute(Qt.WA_TranslucentBackground)
        self.setAttribute(Qt.WA_ShowWithoutActivating)
        self.setAttribute(Qt.WA_NoSystemBackground)
        self.setWindowTitle("HomeView overlay")
        self.setCursor(Qt.PointingHandCursor)
        self.place(screen)
        self.winId()  # нативное окно заранее, чтобы задать область ввода до показа
        self.update_input_region(force=True)

    has_alpha = True

    def devicePixelRatio(self) -> float:  # noqa: N802 — единый интерфейс с QWindow
        return self.devicePixelRatioF()

    def paintEvent(self, event) -> None:
        painter = QPainter(self)
        self._paint_world(painter, event.rect())
        painter.end()

    def mousePressEvent(self, event: QMouseEvent) -> None:
        if self._handle_press(event):
            event.accept()
        else:
            event.ignore()


def create_overlay(screen: QScreen, world: World, use_opengl: bool):
    return GLOverlayWindow(screen, world) if use_opengl else RasterOverlayWindow(screen, world)
