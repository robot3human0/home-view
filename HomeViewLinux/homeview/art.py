"""Спрайты: загрузка PNG из HomeView/Art, перекраска и сборка человечка.

Геометрия повторяет Art.realisticWorkerParts / PeerAvatar.buildFigure из Mac-версии.
Координаты частей — в «точках» с осью Y вверх и (0,0) в pivot-е (как в Core Animation).
PNG нарисованы с плотностью 8 пикселей на точку.
"""

from __future__ import annotations

import math
import random
from dataclasses import dataclass
from functools import lru_cache

from PySide6.QtCore import QPointF, QRectF, Qt
from PySide6.QtGui import (QColor, QImage, QPainter, QPainterPath, QPixmap,
                           QRadialGradient, QTransform)

from . import paths
from .protocol import AvatarStyle

PIXELS_PER_POINT = 8


def qcolor(hex_value: int, alpha: float = 1.0) -> QColor:
    color = QColor((hex_value >> 16) & 0xFF, (hex_value >> 8) & 0xFF, hex_value & 0xFF)
    color.setAlphaF(alpha)
    return color


def blend(a: int, b: int, t: float) -> QColor:
    """Смешение цветов как Art.blend: a·(1−t) + b·t."""
    channels = []
    for shift in (16, 8, 0):
        ca = (a >> shift) & 0xFF
        cb = (b >> shift) & 0xFF
        channels.append(round(ca * (1 - t) + cb * t))
    return QColor(*channels)


@lru_cache(maxsize=None)
def image(name: str) -> QImage | None:
    path = paths.art_dir() / f"{name}.png"
    picture = QImage(str(path))
    if picture.isNull():
        return None
    return picture.convertToFormat(QImage.Format_ARGB32_Premultiplied)


def art_available() -> bool:
    return image("hv_person_leg") is not None


def tinted(picture: QImage, tint: QColor) -> QImage:
    """Серый рисунок × цвет (multiply), прозрачность — как у исходника (ArtPack.drawTinted)."""
    result = QImage(picture.size(), QImage.Format_ARGB32_Premultiplied)
    result.fill(Qt.transparent)
    painter = QPainter(result)
    painter.drawImage(0, 0, picture)
    painter.setCompositionMode(QPainter.CompositionMode_Multiply)
    painter.fillRect(result.rect(), tint)
    painter.setCompositionMode(QPainter.CompositionMode_DestinationIn)
    painter.drawImage(0, 0, picture)
    painter.end()
    return result


def composed(layers: list[tuple[str, QColor | None]]) -> QImage | None:
    """Несколько PNG одного размера в одну картинку; слои с цветом — перекрашиваются."""
    pictures = [(image(name), tint) for name, tint in layers]
    pictures = [(p, t) for p, t in pictures if p is not None]
    if not pictures:
        return None
    size = pictures[0][0].size()
    result = QImage(size, QImage.Format_ARGB32_Premultiplied)
    result.fill(Qt.transparent)
    painter = QPainter(result)
    painter.setRenderHint(QPainter.SmoothPixmapTransform)
    for picture, tint in pictures:
        layer = tinted(picture, tint) if tint is not None else picture
        painter.drawImage(QRectF(0, 0, size.width(), size.height()), layer)
    painter.end()
    return result


@dataclass
class Part:
    """Часть фигуры. `box` — прямоугольник в точках (Y вверх), (0,0) — точка вращения."""

    source: QImage
    box: QRectF

    def prepared(self, density: float) -> QPixmap:
        """Картинка, заранее уменьшенная до нужной плотности (качественнее, чем масштаб при рисовании)."""
        width = max(1, round(self.box.width() * density))
        height = max(1, round(self.box.height() * density))
        return QPixmap.fromImage(
            self.source.scaled(width, height, Qt.IgnoreAspectRatio, Qt.SmoothTransformation))


@dataclass
class PersonParts:
    leg: Part
    arm_back: Part
    arm_front: Part
    body: Part


LEG_BOX = QRectF(-2.6, -11.2, 6.4, 11.4)
ARM_BOX = QRectF(-2.4, -12.4, 4.8, 12.6)
BODY_BOX = QRectF(-9.8, 9.6, 20.6, 33.4)

# Точки крепления частей внутри фигуры (PeerAvatar.buildFigure)
LEG_LEFT_AT = QPointF(-2.6, 11)
LEG_RIGHT_AT = QPointF(2.6, 11)
ARM_BACK_AT = QPointF(-4, 22)
ARM_FRONT_AT = QPointF(3, 22)
FIGURE_HEIGHT = 46


@lru_cache(maxsize=64)
def person_parts(style: AvatarStyle) -> PersonParts | None:
    """Человечек коллеги: куртка, руки без перчаток, шапка выбранного цвета."""
    skin = qcolor(style.skin_color)
    hat = qcolor(style.hat_color)
    vest = qcolor(style.vest_color)
    vest_dark = blend(style.vest_color, 0x000000, 0.15)
    hand = ("hv_person_hand", skin)

    hat_layers: list[tuple[str, QColor | None]] = {
        "beanie": [("hv_hat_beanie", hat), ("hv_hat_beanie_pom", None)],
        "cap": [("hv_hat_cap", hat)],
        "doppi": [("hv_hat_doppi", None)],
        "strawHat": [("hv_hat_straw", None), ("hv_hat_straw_band", hat)],
    }.get(style.hat, [("hv_hat_doppi", None)])

    body_layers = [("hv_person_torso", vest), ("hv_person_jacket", None),
                   ("hv_person_head", skin), ("hv_person_face", None)] + hat_layers

    leg = image("hv_person_leg")
    arm_back = composed([("hv_person_sleeve", vest_dark), hand])
    arm_front = composed([("hv_person_sleeve", vest), hand])
    body = composed(body_layers)
    if leg is None or arm_back is None or arm_front is None or body is None:
        return None
    return PersonParts(
        leg=Part(leg, LEG_BOX),
        arm_back=Part(arm_back, ARM_BOX),
        arm_front=Part(arm_front, ARM_BOX),
        body=Part(body, BODY_BOX),
    )


def draw_part(painter: QPainter, pixmap: QPixmap, box: QRectF) -> None:
    """Рисует часть в системе координат с осью Y вверх (картинку переворачиваем обратно)."""
    painter.save()
    painter.translate(box.left(), box.bottom())
    painter.scale(1, -1)
    painter.drawPixmap(QRectF(0, 0, box.width(), box.height()), pixmap, QRectF(pixmap.rect()))
    painter.restore()


# MARK: - Частицы


def particle_frames(name: str, size_px: float, rotations: int) -> list[QPixmap]:
    """Спрайт частицы, заранее повёрнутый на `rotations` углов (рисовать без трансформаций — быстро)."""
    picture = image(name)
    if picture is None:
        picture = _fallback_flake()
    side = max(2, round(size_px))
    base = picture.scaled(side, side, Qt.KeepAspectRatio, Qt.SmoothTransformation)
    if rotations <= 1:
        return [QPixmap.fromImage(base)]
    frames = []
    for index in range(rotations):
        angle = 360.0 * index / rotations
        frames.append(QPixmap.fromImage(base.transformed(QTransform().rotate(angle), Qt.SmoothTransformation)))
    return frames


@lru_cache(maxsize=1)
def _fallback_flake() -> QImage:
    result = QImage(64, 64, QImage.Format_ARGB32_Premultiplied)
    result.fill(Qt.transparent)
    painter = QPainter(result)
    painter.setRenderHint(QPainter.Antialiasing)
    gradient = QRadialGradient(32, 32, 30)
    gradient.setColorAt(0, QColor(255, 255, 255, 255))
    gradient.setColorAt(1, QColor(255, 255, 255, 0))
    painter.setBrush(gradient)
    painter.setPen(Qt.NoPen)
    painter.drawEllipse(QRectF(2, 2, 60, 60))
    painter.end()
    return result


# MARK: - Снаряды и кляксы (в Mac-версии рисуются кодом в SeasonArt.swift)

BALL_COLORS = {
    "winter": (0xFFFFFF, 0xC9D6EA, 0x8FA3C2),
    "spring": (0xFFEEF5, 0xF59ABD, 0xD96699),
    "summer": (0xE3F4FF, 0x6EC3F2, 0x2F86C6),
    "autumn": (0xFFE0A3, 0xF08A24, 0xB5541A),
}

SPLAT_COLORS = {
    "winter": (0xFFFFFF, 0.96, 0xA9B9CF),
    "spring": (0xFCE4EC, 0.95, 0xF48FB1),
    "summer": (0xBFE6FF, 0.70, 0x4FA8E0),
    "autumn": (0xF3B35B, 0.95, 0xB5651D),
}


@lru_cache(maxsize=8)
def ball(season: str, size_px: int = 64) -> QPixmap:
    top, middle, rim = BALL_COLORS.get(season, BALL_COLORS["winter"])
    result = QPixmap(size_px, size_px)
    result.fill(Qt.transparent)
    painter = QPainter(result)
    painter.setRenderHint(QPainter.Antialiasing)
    radius = size_px / 2 - 1
    gradient = QRadialGradient(size_px * 0.38, size_px * 0.34, radius * 1.2)
    gradient.setColorAt(0, qcolor(top))
    gradient.setColorAt(0.6, qcolor(middle))
    gradient.setColorAt(1, qcolor(rim))
    painter.setBrush(gradient)
    painter.setPen(Qt.NoPen)
    painter.drawEllipse(QPointF(size_px / 2, size_px / 2), radius, radius)
    painter.setBrush(QColor(255, 255, 255, 150))
    painter.drawEllipse(QPointF(size_px * 0.36, size_px * 0.32), radius * 0.22, radius * 0.16)
    painter.end()
    return result


def splat(season: str, seed: int, size_px: int = 120) -> QPixmap:
    """Клякса от попавшего снаряда: неровное пятно с брызгами."""
    fill, alpha, rim = SPLAT_COLORS.get(season, SPLAT_COLORS["winter"])
    rng = random.Random(seed)
    result = QPixmap(size_px, size_px)
    result.fill(Qt.transparent)
    painter = QPainter(result)
    painter.setRenderHint(QPainter.Antialiasing)
    center = size_px / 2
    path = QPainterPath()
    points = 14
    base = size_px * 0.26
    for index in range(points + 1):
        angle = 2 * math.pi * index / points
        radius = base * rng.uniform(0.75, 1.25)
        point = QPointF(center + math.cos(angle) * radius, center + math.sin(angle) * radius)
        if index == 0:
            path.moveTo(point)
        else:
            mid_angle = angle - math.pi / points
            control = QPointF(center + math.cos(mid_angle) * base * 1.35, center + math.sin(mid_angle) * base * 1.35)
            path.quadTo(control, point)
    painter.setPen(qcolor(rim, 0.6))
    painter.setBrush(qcolor(fill, alpha))
    painter.drawPath(path)
    for _ in range(9):
        angle = rng.uniform(0, 2 * math.pi)
        distance = rng.uniform(base * 1.25, size_px * 0.46)
        radius = rng.uniform(2, size_px * 0.05)
        painter.drawEllipse(QPointF(center + math.cos(angle) * distance, center + math.sin(angle) * distance),
                            radius, radius)
    painter.setPen(Qt.NoPen)
    painter.setBrush(QColor(255, 255, 255, 110))
    painter.drawEllipse(QPointF(center - base * 0.3, center - base * 0.35), base * 0.35, base * 0.22)
    painter.end()
    return result
