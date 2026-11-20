"""Низкоуровневые вызовы X11 через ctypes (без компиляции и лишних зависимостей).

* XShape input region — окно принимает клики только в заданных прямоугольниках
  (над человечками), всё остальное проходит сквозь оверлей в окна под ним.
  Это аналог переключения `ignoresMouseEvents` в Mac-версии, только без опроса мыши.
* XScreenSaver — сколько миллисекунд пользователь ничего не трогал (авто-статус «Отошёл»).
"""

from __future__ import annotations

import ctypes
import ctypes.util
import logging
import os

log = logging.getLogger(__name__)

SHAPE_INPUT = 2
SHAPE_SET = 0
UNSORTED = 0


class _XRectangle(ctypes.Structure):
    _fields_ = [("x", ctypes.c_short), ("y", ctypes.c_short),
                ("width", ctypes.c_ushort), ("height", ctypes.c_ushort)]


class _XScreenSaverInfo(ctypes.Structure):
    _fields_ = [("window", ctypes.c_ulong), ("state", ctypes.c_int), ("kind", ctypes.c_int),
                ("til_or_since", ctypes.c_ulong), ("idle", ctypes.c_ulong), ("eventMask", ctypes.c_ulong)]


def _load(name: str):
    path = ctypes.util.find_library(name)
    if not path:
        return None
    try:
        return ctypes.CDLL(path)
    except OSError:
        return None


class X11:
    """Отдельное соединение с X-сервером (идентификаторы окон общие для всех соединений)."""

    def __init__(self) -> None:
        self.display = None
        self._xlib = _load("X11")
        self._xext = _load("Xext")
        self._xss = _load("Xss")
        self._ss_info = None
        if self._xlib is None or not os.environ.get("DISPLAY"):
            log.warning("X11 недоступен: клики будут проходить только в режиме «всё насквозь»")
            return
        self._xlib.XOpenDisplay.restype = ctypes.c_void_p
        self._xlib.XOpenDisplay.argtypes = [ctypes.c_char_p]
        self._xlib.XFlush.argtypes = [ctypes.c_void_p]
        self._xlib.XDefaultRootWindow.restype = ctypes.c_ulong
        self._xlib.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
        self.display = self._xlib.XOpenDisplay(None)
        if not self.display:
            log.warning("Не удалось открыть X-дисплей")
            return
        if self._xext is not None:
            self._xext.XShapeCombineRectangles.argtypes = [
                ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int, ctypes.c_int,
                ctypes.POINTER(_XRectangle), ctypes.c_int, ctypes.c_int, ctypes.c_int]
        if self._xss is not None:
            self._xss.XScreenSaverAllocInfo.restype = ctypes.POINTER(_XScreenSaverInfo)
            self._xss.XScreenSaverQueryInfo.argtypes = [ctypes.c_void_p, ctypes.c_ulong,
                                                        ctypes.POINTER(_XScreenSaverInfo)]
            self._ss_info = self._xss.XScreenSaverAllocInfo()

    @property
    def can_shape(self) -> bool:
        return bool(self.display) and self._xext is not None

    def set_input_rects(self, window_id: int, rects: list[tuple[int, int, int, int]]) -> None:
        """Область, где окно принимает мышь. Пустой список — все клики проходят насквозь."""
        if not self.can_shape:
            return
        array = (_XRectangle * max(1, len(rects)))()
        for index, (x, y, w, h) in enumerate(rects):
            array[index] = _XRectangle(max(-32768, min(32767, x)), max(-32768, min(32767, y)),
                                       max(0, min(65535, w)), max(0, min(65535, h)))
        self._xext.XShapeCombineRectangles(self.display, window_id, SHAPE_INPUT, 0, 0,
                                           array, len(rects), SHAPE_SET, UNSORTED)
        self._xlib.XFlush(self.display)

    def idle_seconds(self) -> float | None:
        if not self.display or self._ss_info is None:
            return None
        root = self._xlib.XDefaultRootWindow(self.display)
        if not self._xss.XScreenSaverQueryInfo(self.display, root, self._ss_info):
            return None
        return self._ss_info.contents.idle / 1000.0


_instance: X11 | None = None


def get() -> X11:
    global _instance
    if _instance is None:
        _instance = X11()
    return _instance
