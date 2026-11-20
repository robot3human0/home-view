"""Короткие эффекты: летящий снаряд, клякса на экране, брызги."""

from __future__ import annotations

import math
import random
from typing import Callable

from PySide6.QtCore import QPointF, QRectF
from PySide6.QtGui import QColor, QPainter, QPixmap

from . import art


def ease_in(t: float) -> float:
    return t * t


def ease_out(t: float) -> float:
    return 1 - (1 - t) * (1 - t)


class Effect:
    alive = True

    def tick(self, dt: float) -> None:
        raise NotImplementedError

    def paint(self, painter: QPainter) -> None:
        raise NotImplementedError


class FlyingBall(Effect):
    """Снаряд по квадратичной кривой Безье, с изменением размера (иллюзия глубины)."""

    def __init__(self, pixmap: QPixmap, start: QPointF, end: QPointF, control: QPointF, duration: float,
                 from_scale: float, to_scale: float, size: float, easing: Callable[[float], float],
                 on_done: Callable[[], None] | None = None, delay: float = 0.0) -> None:
        self.pixmap = pixmap
        self.start, self.end, self.control = start, end, control
        self.duration = duration
        self.from_scale, self.to_scale = from_scale, to_scale
        self.size = size
        self.easing = easing
        self.on_done = on_done
        self.elapsed = -delay
        self.spin = random.uniform(-6, 6)

    def tick(self, dt: float) -> None:
        self.elapsed += dt
        if self.elapsed >= self.duration and self.alive:
            self.alive = False
            if self.on_done:
                self.on_done()

    def paint(self, painter: QPainter) -> None:
        if self.elapsed < 0:
            return
        t = self.easing(min(1.0, self.elapsed / self.duration))
        u = 1 - t
        x = u * u * self.start.x() + 2 * u * t * self.control.x() + t * t * self.end.x()
        y = u * u * self.start.y() + 2 * u * t * self.control.y() + t * t * self.end.y()
        side = self.size * (self.from_scale + (self.to_scale - self.from_scale) * t)
        painter.save()
        painter.translate(x, y)
        painter.rotate(math.degrees(self.spin * self.elapsed))
        painter.drawPixmap(QRectF(-side / 2, -side / 2, side, side), self.pixmap, QRectF(self.pixmap.rect()))
        painter.restore()


class Splat(Effect):
    """Клякса «прилипла» к экрану и через несколько секунд стекает и тает."""

    def __init__(self, season: str, center: QPointF, size: float, hold: float = 6.0, fade: float = 2.0) -> None:
        self.pixmap = art.splat(season, random.randrange(1_000_000))
        self.center = center
        self.size = size
        self.hold = hold
        self.fade = fade
        self.elapsed = 0.0
        self.rotation = random.uniform(0, 360)

    def tick(self, dt: float) -> None:
        self.elapsed += dt
        if self.elapsed >= self.hold + self.fade:
            self.alive = False

    def paint(self, painter: QPainter) -> None:
        appear = min(1.0, self.elapsed / 0.12)
        opacity = 1.0
        slide = 0.0
        if self.elapsed > self.hold:
            k = (self.elapsed - self.hold) / self.fade
            opacity = max(0.0, 1 - k)
            slide = 18 * k
        side = self.size * (0.6 + 0.4 * appear)
        painter.save()
        painter.setOpacity(opacity)
        painter.translate(self.center.x(), self.center.y() + slide)
        painter.rotate(self.rotation)
        painter.drawPixmap(QRectF(-side / 2, -side / 2, side, side), self.pixmap, QRectF(self.pixmap.rect()))
        painter.restore()


class Burst(Effect):
    """Брызги: несколько точек разлетаются и падают."""

    def __init__(self, center: QPointF, colors: list[QColor], count: int = 14, speed: float = 160,
                 gravity: float = 520, lifetime: float = 0.9) -> None:
        self.colors = colors
        self.gravity = gravity
        self.lifetime = lifetime
        self.elapsed = 0.0
        self.items = []
        for _ in range(count):
            angle = random.uniform(-math.pi, 0)  # вверх и в стороны
            v = speed * random.uniform(0.5, 1.2)
            self.items.append([center.x(), center.y(), math.cos(angle) * v, math.sin(angle) * v,
                               random.uniform(1.5, 3.2), random.choice(colors)])

    def tick(self, dt: float) -> None:
        self.elapsed += dt
        for p in self.items:
            p[0] += p[2] * dt
            p[1] += p[3] * dt
            p[3] += self.gravity * dt
        if self.elapsed >= self.lifetime:
            self.alive = False

    def paint(self, painter: QPainter) -> None:
        painter.save()
        painter.setOpacity(max(0.0, 1 - self.elapsed / self.lifetime))
        painter.setPen(QColor(0, 0, 0, 0))
        for x, y, _, _, radius, color in self.items:
            painter.setBrush(color)
            painter.drawEllipse(QPointF(x, y), radius, radius)
        painter.restore()
