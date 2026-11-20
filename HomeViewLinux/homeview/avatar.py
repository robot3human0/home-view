"""Человечек коллеги (по мотивам PeerAvatar.swift).

Активный — гуляет вдоль низа экрана, «Отошёл» — сидит, «Занят» — полупрозрачный.
Над головой — табличка «Имя · Команда», выше — флажок лобби и облачко с репликой.
"""

from __future__ import annotations

import math
import random
import time

from PySide6.QtCore import QPointF, QRectF, Qt
from PySide6.QtGui import QColor, QFont, QFontMetricsF, QPainter, QPainterPath, QPen, QPixmap

from . import art
from .protocol import PeerInfo

TAG_FONT_PX = 11
BUBBLE_FONT_PX = 12
BUBBLE_MAX_WIDTH = 220


def _keyframes(values: list[float], times: list[float], t: float) -> float:
    if t <= times[0]:
        return values[0]
    for index in range(1, len(times)):
        if t <= times[index]:
            span = times[index] - times[index - 1]
            local = (t - times[index - 1]) / span if span > 0 else 1
            return values[index - 1] + (values[index] - values[index - 1]) * local
    return values[-1]


def _even_times(count: int) -> list[float]:
    return [i / (count - 1) for i in range(count)]


class _Clip:
    """Одноразовая анимация: значения по ключевым кадрам за `duration` секунд."""

    def __init__(self, values: list[float], times: list[float], duration: float) -> None:
        self.values = values
        self.times = times
        self.duration = duration
        self.start = time.monotonic()

    def value(self, now: float) -> float | None:
        t = (now - self.start) / self.duration
        if t >= 1:
            return None
        return _keyframes(self.values, self.times, t)


def _font(px: float, weight: QFont.Weight = QFont.DemiBold) -> QFont:
    font = QFont()
    font.setPixelSize(round(px))
    font.setWeight(weight)
    return font


def render_pill(text: str, background: QColor, pixel_ratio: float, scale: float = 1.0) -> QPixmap:
    """Табличка-«пилюля» с текстом (рисуется один раз при смене текста)."""
    font = _font(TAG_FONT_PX * scale)
    metrics = QFontMetricsF(font)
    width = math.ceil(metrics.horizontalAdvance(text) + 14 * scale)
    height = math.ceil(17 * scale)
    pixmap = QPixmap(round(width * pixel_ratio), round(height * pixel_ratio))
    pixmap.setDevicePixelRatio(pixel_ratio)
    pixmap.fill(Qt.transparent)
    painter = QPainter(pixmap)
    painter.setRenderHint(QPainter.Antialiasing)
    painter.setRenderHint(QPainter.TextAntialiasing)
    painter.setPen(QPen(QColor(255, 255, 255, 64), 0.8 * scale))
    painter.setBrush(background)
    painter.drawRoundedRect(QRectF(0.5, 0.5, width - 1, height - 1), height / 2, height / 2)
    painter.setFont(font)
    painter.setPen(QColor(255, 255, 255))
    painter.drawText(QRectF(0, 0, width, height), Qt.AlignCenter, text)
    painter.end()
    return pixmap


def render_bubble(text: str, pixel_ratio: float, scale: float = 1.0) -> QPixmap:
    """Облачко с репликой и хвостиком вниз."""
    font = _font(BUBBLE_FONT_PX * scale, QFont.Medium)
    metrics = QFontMetricsF(font)
    text_rect = metrics.boundingRect(QRectF(0, 0, BUBBLE_MAX_WIDTH * scale, 1000 * scale),
                                     Qt.TextWordWrap | Qt.AlignCenter, text)
    pad_x, pad_y, tail = 10 * scale, 6 * scale, 7 * scale
    width = math.ceil(text_rect.width() + pad_x * 2)
    height = math.ceil(text_rect.height() + pad_y * 2)
    pixmap = QPixmap(round((width + 2) * pixel_ratio), round((height + tail + 2) * pixel_ratio))
    pixmap.setDevicePixelRatio(pixel_ratio)
    pixmap.fill(Qt.transparent)
    painter = QPainter(pixmap)
    painter.setRenderHint(QPainter.Antialiasing)
    painter.setRenderHint(QPainter.TextAntialiasing)
    path = QPainterPath()
    body = QRectF(1, 1, width, height)
    path.addRoundedRect(body, 9 * scale, 9 * scale)
    tail_path = QPainterPath()
    cx = body.center().x()
    tail_path.moveTo(cx - 6 * scale, body.bottom() - 1)
    tail_path.lineTo(cx, body.bottom() + tail)
    tail_path.lineTo(cx + 6 * scale, body.bottom() - 1)
    tail_path.closeSubpath()
    path = path.united(tail_path)
    painter.setPen(QPen(QColor(15, 27, 45, 70), 1))
    painter.setBrush(QColor(255, 255, 255, 245))
    painter.drawPath(path)
    painter.setFont(font)
    painter.setPen(QColor(0x1A, 0x23, 0x33))
    painter.drawText(body.adjusted(pad_x, pad_y, -pad_x, -pad_y), Qt.TextWordWrap | Qt.AlignCenter, text)
    painter.end()
    return pixmap


class PeerAvatar:
    def __init__(self, info: PeerInfo, x: float, scale: float, pixel_ratio: float,
                 text_scale: float = 1.0) -> None:
        self.id = info.id
        self.text_scale = text_scale
        self.info = info
        self.x = x
        self.ground_y = 0.0
        self.scale = scale
        self.pixel_ratio = pixel_ratio
        self.facing = 1.0
        self.target_x = x
        self.pause = random.uniform(1, 4)
        self.walking = False
        self.walk_time = 0.0
        self.visible = True
        self.flag_label: str | None = None

        self._clips: dict[str, _Clip] = {}
        self._wave_ready_at = 0.0
        self._bubble: tuple[QPixmap, float, float] | None = None  # картинка, время появления, до какого времени
        self._tag: QPixmap | None = None
        self._flag: QPixmap | None = None
        self._flag_text: str | None = None
        self._pixmaps: dict[str, QPixmap] = {}
        self._parts = None
        self._build()
        self._update_tag()

    # MARK: - Внешний вид

    def _build(self) -> None:
        self._parts = art.person_parts(self.info.avatar)
        self._prepare()

    def _prepare(self) -> None:
        self._pixmaps.clear()
        if self._parts is None:
            return
        density = self.scale * self.pixel_ratio * 1.25  # небольшой запас резкости
        for name in ("leg", "arm_back", "arm_front", "body"):
            self._pixmaps[name] = getattr(self._parts, name).prepared(density)

    def _update_tag(self) -> None:
        label = self.info.name
        if self.info.team:
            label += f" · {self.info.team}"
        if self.info.status == "away":
            label = "☕ " + label
        elif self.info.status == "busy":
            label = "🔕 " + label
        self._tag = render_pill(label, QColor(0x0F, 0x1B, 0x2D, 199), self.pixel_ratio, self.text_scale)

    def update_info(self, info: PeerInfo) -> None:
        style_changed = info.avatar != self.info.avatar
        status_changed = info.status != self.info.status
        self.info = info
        if style_changed:
            self._build()
        if status_changed and info.status == "away":
            self.walking = False
        self._update_tag()

    def set_scale(self, scale: float) -> None:
        if abs(scale - self.scale) > 0.001:
            self.scale = scale
            self._prepare()

    def set_text_scale(self, scale: float) -> None:
        if abs(scale - self.text_scale) > 0.001:
            self.text_scale = scale
            self._update_tag()
            flag, self._flag_text = self._flag_text, None
            self.set_flag(flag)
            self._bubble = None

    def set_flag(self, text: str | None) -> None:
        if text == self._flag_text:
            return
        self._flag_text = text
        self._flag = (render_pill(text, QColor(0xF5, 0x7C, 0x00, 235), self.pixel_ratio, self.text_scale)
                      if text else None)

    @property
    def sitting(self) -> bool:
        return self.info.status == "away"

    # MARK: - Геометрия (экранные координаты, Y вниз)

    @property
    def top_y(self) -> float:
        return self.ground_y - art.FIGURE_HEIGHT * self.scale

    def hit_rect(self) -> QRectF:
        s = self.scale
        rect = QRectF(self.x - 11 * s, self.top_y, 22 * s, art.FIGURE_HEIGHT * s + 2)
        if self._tag is not None:
            ratio = self._tag.devicePixelRatio()
            w, h = self._tag.width() / ratio, self._tag.height() / ratio
            rect = rect.united(QRectF(self.x - w / 2, self.top_y - 4 * self.text_scale - h, w, h + 2))
        return rect

    def hand_point(self) -> QPointF:
        return QPointF(self.x + self.facing * 5 * self.scale, self.ground_y - 34 * self.scale)

    def chest_point(self) -> QPointF:
        return QPointF(self.x, self.ground_y - 26 * self.scale)

    # MARK: - Действия

    def wave(self) -> None:
        now = time.monotonic()
        if now < self._wave_ready_at:
            return
        self._wave_ready_at = now + 1.2
        self._clips["wave"] = _Clip([-0.4, -2.7, -2.2, -2.7, -2.2, -0.4], [0, 0.2, 0.4, 0.6, 0.8, 1], 1.0)

    def throw_motion(self) -> None:
        self._clips["throw"] = _Clip([0.15, -2.6, 0.9, 0.15], [0, 0.45, 0.64, 1], 0.55)

    def flinch(self) -> None:
        self._clips["flinch"] = _Clip([0, -0.25, 0.18, 0], _even_times(4), 0.3)

    def hop(self) -> None:
        self._clips["hop"] = _Clip([0, 14, 0], [0, 0.5, 1], 0.34)

    def say(self, text: str, duration: float = 3.0) -> None:
        short = text if len(text) <= 60 else text[:57] + "..."
        now = time.monotonic()
        self._bubble = (render_bubble(short, self.pixel_ratio, self.text_scale), now, now + duration)

    # MARK: - Шаг

    def tick(self, dt: float, width: float) -> None:
        if not self.sitting:
            if self.pause > 0:
                self.pause -= dt
                if self.pause <= 0:
                    self.target_x = min(max(self.x + random.uniform(-320, 320), 40), width - 40)
                    self.facing = 1.0 if self.target_x >= self.x else -1.0
                    self.walking = True
            else:
                dx = self.target_x - self.x
                speed = (22 if self.info.status == "busy" else 42) * math.sqrt(self.scale)
                step = speed * dt
                if abs(dx) <= step:
                    self.x = self.target_x
                    self.walking = False
                    self.pause = random.uniform(2.5, 8)
                else:
                    self.x += step if dx > 0 else -step
        if self.walking:
            self.walk_time += dt

    # MARK: - Рисование

    def paint(self, painter: QPainter) -> None:
        if not self.visible:
            return
        now = time.monotonic()
        clips = {}
        for key in list(self._clips):
            value = self._clips[key].value(now)
            if value is None:
                del self._clips[key]
            else:
                clips[key] = value

        s = self.scale
        busy = self.info.status == "busy"
        if self._pixmaps:
            # Поза (радианы, положительный угол — против часовой стрелки, как в Core Animation)
            leg_left = leg_right = arm_back = 0.0
            arm_front = 0.15
            figure_dy = 0.0
            lift = 0.0
            if self.sitting:
                leg_left, leg_right, figure_dy = 1.35, 1.2, -8.0
            elif self.walking:
                swing = math.sin(2 * math.pi * self.walk_time / 0.44)
                leg_left, leg_right, arm_back = 0.45 * swing, -0.45 * swing, -0.35 * swing
                lift = 1.1 * abs(math.sin(math.pi * self.walk_time / 0.44))
            arm_back = clips.get("wave", arm_back)
            arm_front = clips.get("throw", arm_front)
            lift += clips.get("hop", 0.0)
            figure_rot = clips.get("flinch", 0.0)

            painter.save()
            painter.setOpacity(0.55 if busy else 1.0)
            painter.translate(self.x, self.ground_y)
            painter.scale(self.facing * s, -s)  # дальше — точки, ось Y вверх
            painter.translate(0, lift + figure_dy)
            if figure_rot:
                painter.rotate(math.degrees(figure_rot))
            self._limb(painter, "leg", art.LEG_LEFT_AT, leg_left, art.LEG_BOX)
            self._limb(painter, "leg", art.LEG_RIGHT_AT, leg_right, art.LEG_BOX)
            self._limb(painter, "arm_back", art.ARM_BACK_AT, arm_back, art.ARM_BOX)
            art.draw_part(painter, self._pixmaps["body"], art.BODY_BOX)
            self._limb(painter, "arm_front", art.ARM_FRONT_AT, arm_front, art.ARM_BOX)
            painter.restore()

        # Подписи (не масштабируются вместе с фигурой)
        top = self.top_y
        k = self.text_scale
        if self._tag is not None:
            painter.setOpacity(0.7 if busy else 1.0)
            self._draw_centered(painter, self._tag, top - 10 * k)
        y = top - 30 * k
        if self._flag is not None:
            painter.setOpacity(1.0)
            self._draw_centered(painter, self._flag, y)
            y -= 20 * k
        if self._bubble is not None:
            pixmap, born, until = self._bubble
            if now >= until:
                self._bubble = None
            else:
                fade = min(1.0, (now - born) / 0.15, (until - now) / 0.3)
                painter.setOpacity(max(0.0, fade))
                h = pixmap.height() / pixmap.devicePixelRatio()
                self._draw_centered(painter, pixmap, y - h / 2 + 8 * k)
        painter.setOpacity(1.0)

    def _limb(self, painter: QPainter, name: str, at: QPointF, angle: float, box: QRectF) -> None:
        painter.save()
        painter.translate(at)
        if angle:
            painter.rotate(math.degrees(angle))
        art.draw_part(painter, self._pixmaps[name], box)
        painter.restore()

    def _draw_centered(self, painter: QPainter, pixmap: QPixmap, center_y: float) -> None:
        ratio = pixmap.devicePixelRatio()
        w = pixmap.width() / ratio
        h = pixmap.height() / ratio
        painter.drawPixmap(QPointF(round(self.x - w / 2), round(center_y - h / 2)), pixmap)
