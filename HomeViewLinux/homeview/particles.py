"""Падающие осадки: снег, лепестки, пух, листья.

В Mac-версии это CAEmitterLayer (считает GPU). Здесь — простая симуляция на Python:
каждый спрайт заранее отрисован в 24 углах поворота и 3 размерах, поэтому в кадре —
только `drawPixmap` без трансформаций (≈2 мс на 2500 частиц).
"""

from __future__ import annotations

import math
import random

from PySide6.QtCore import QPointF
from PySide6.QtGui import QPainter

from . import art
from .season import Season

ROTATIONS = 24
SIZE_VARIANTS = (0.7, 1.0, 1.3)
BASE_POINTS = 16  # 128 px / 8 px на точку
SPAWN_MARGIN = 40


class _Layer:
    def __init__(self, style, density_px: float) -> None:
        self.style = style
        rotations = ROTATIONS if style.spin > 0 else 1
        self.frames = []
        for variant in SIZE_VARIANTS:
            size = BASE_POINTS * style.scale * variant * density_px
            pixmaps = art.particle_frames(style.image, size, rotations)
            for pixmap in pixmaps:
                pixmap.setDevicePixelRatio(density_px)
            self.frames.append([(p, p.width() / p.devicePixelRatio() / 2, p.height() / p.devicePixelRatio() / 2)
                                for p in pixmaps])
        self.rotations = rotations
        # частица: [x, y, vx, vy, angle, spin, variant, phase, sway]
        self.items: list[list[float]] = []
        self.carry = 0.0


class ParticleSystem:
    def __init__(self, season: Season, width: float, ground_y: float, density: float,
                 pixel_ratio: float = 1.0, simulate: bool = True) -> None:
        """simulate=False — частицы считает видеокарта (gl_particles), здесь только параметры и время."""
        self.season = season
        self.width = width
        self.ground_y = ground_y
        self.density = density
        self.opacity = 1.0
        self.time = 0.0
        self.simulate = simulate
        self.layers = [_Layer(style, pixel_ratio) for style in season.layers] if simulate else []
        if simulate:
            self._prewarm()

    # MARK: - Рождение

    def _rate(self, layer: _Layer) -> float:
        return layer.style.rate * (self.width + 2 * SPAWN_MARGIN) / 1440 * self.density

    def _spawn(self, layer: _Layer, y: float | None = None) -> None:
        style = layer.style
        speed = style.velocity * random.uniform(0.75, 1.25)
        direction = random.uniform(-style.emission_range / 2, style.emission_range / 2)
        layer.items.append([
            random.uniform(-SPAWN_MARGIN, self.width + SPAWN_MARGIN),
            -24.0 if y is None else y,
            math.sin(direction) * speed,
            math.cos(direction) * speed,
            random.uniform(0, 2 * math.pi),
            random.uniform(-style.spin, style.spin),
            random.randrange(len(SIZE_VARIANTS)),
            random.uniform(0, 2 * math.pi),
            style.sway * random.uniform(0.5, 1.0),
        ])

    def _prewarm(self) -> None:
        """Сразу заполняем экран, чтобы не ждать, пока первые снежинки долетят донизу."""
        for layer in self.layers:
            on_screen_seconds = self.ground_y / max(layer.style.velocity, 1)
            count = int(self._rate(layer) * on_screen_seconds)
            for _ in range(count):
                self._spawn(layer, y=random.uniform(-24, self.ground_y))

    # MARK: - Шаг

    def tick(self, dt: float) -> None:
        self.time += dt
        if not self.simulate:
            return
        limit = self.ground_y + 8
        left = -SPAWN_MARGIN * 3
        right = self.width + SPAWN_MARGIN * 3
        for layer in self.layers:
            layer.carry += self._rate(layer) * dt
            while layer.carry >= 1:
                layer.carry -= 1
                self._spawn(layer)
            alive = []
            for p in layer.items:
                p[0] += p[2] * dt
                p[1] += p[3] * dt
                p[4] += p[5] * dt
                if left < p[0] < right and p[1] < limit:
                    alive.append(p)
            layer.items = alive

    def set_ground(self, width: float, ground_y: float) -> None:
        self.width = width
        self.ground_y = ground_y

    # MARK: - Рисование

    def paint(self, painter: QPainter) -> None:
        if self.opacity <= 0 or not self.simulate:
            return
        t = self.time
        two_pi = 2 * math.pi
        for layer in self.layers:
            painter.setOpacity(layer.style.alpha * self.opacity)
            frames = layer.frames
            rotations = layer.rotations
            draw = painter.drawPixmap
            for p in layer.items:
                x = p[0]
                if p[8]:
                    x += math.sin(t * 1.3 + p[7]) * p[8]
                if rotations > 1:
                    index = int((p[4] % two_pi) / two_pi * rotations) % rotations
                else:
                    index = 0
                pixmap, half_w, half_h = frames[int(p[6])][index]
                draw(QPointF(x - half_w, p[1] - half_h), pixmap)
        painter.setOpacity(1.0)

    @property
    def count(self) -> int:
        return sum(len(layer.items) for layer in self.layers)
