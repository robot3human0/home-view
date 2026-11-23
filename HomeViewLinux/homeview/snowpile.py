"""Снег на земле (по мотивам Ledge.swift, только «земля» — без снега на окнах).

Высота снега хранится в массиве столбцов шириной 3 точки (heightmap): «сколько точек снега здесь лежит».
Снежинки, которые видно на экране, сюда не попадают — как и в Mac-версии, с неба падают
«невидимые» снежинки с той же частотой (см. World._accumulate).

Координаты Qt: Y вниз, `base_y` — уровень земли (верх нижней панели), снег растёт вверх.

Зимой сугроб — сплошная заливка, как в Mac-версии. В другие сезоны (наше дополнение) он «набран» из тех же
спрайтов, что падают: тело кучи — бесшовная текстура, по верхнему краю — торчащие листья/лепестки.
Такую кучу дорого рисовать каждый кадр, поэтому она хранится картинками по кускам шириной ~256 точек.
За кадр перерисовывается не больше одного куска и только если снег в нём заметно изменился —
иначе перерисовка всей кучи разом (4–7 мс на монитор) даёт заметный рывок анимации.
Новая картинка куска проявляется плавно поверх старой (а при уменьшении — старая растворяется поверх новой).
"""

from __future__ import annotations

import math
import operator
import random

from PySide6.QtCore import QPointF, QRectF
from PySide6.QtGui import (QBrush, QColor, QImage, QLinearGradient, QPainter, QPainterPath, QPen, QPixmap, Qt,
                           QTransform)

from . import art

COLUMN = 3.0          # ширина столбца, точек
MAX_HEIGHT = 150.0    # выше на земле снег не растёт
REPOSE = 2.0          # «угол естественного откоса»: допустимая разница соседних столбцов
SHADE_DEPTH = 60.0    # высота мягкой тени у основания
DRAW_STRIDE = 3       # каждый 3-й столбец (9 точек) — одна вершина контура
REDRAW_SECONDS = 0.2  # контур пересобирается не чаще, чем раз в 0.2 с
STEP_SECONDS = 0.05   # осыпание склонов и таяние считаются 20 раз в секунду, а не каждый кадр

# Текстура кучи (листья, лепестки, пух)
TILE = 256.0                 # сторона бесшовной плитки, точек (меньше — на высокой куче виден повтор узора)
TILE_SPRITES = 2800          # спрайтов на плитку: покрывают её в 2–3 слоя
SPRITE_SIZES = (8.0, 14.0)   # размер спрайта, точек (от и до)
EDGE_STEP = 5.0              # по краю — спрайт каждые 5 точек
EDGE_ROTATIONS = 12
EDGE_MARGIN = 8.0            # насколько спрайты торчат над контуром
CHUNK_COLUMNS = 85           # кусок кучи — 85 столбцов (255 точек)
CHUNK_THRESHOLD = 2.0        # перерисовать кусок, если снег в нём изменился больше, чем на столько точек
                             # (одна снежинка поднимает столбец на ~0.65 — это глазу не видно)
CHUNK_FADE = 0.8             # секунд на плавную смену картинки куска


class SnowPile:
    def __init__(self, width: float, base_y: float, fill: int, stroke: tuple[int, float],
                 sprites: tuple[str, ...] = (), under: int = 0, pixel_ratio: float = 1.0) -> None:
        self.width = width
        self.base_y = base_y
        self.heights = [0.0] * max(1, math.ceil(width / COLUMN))
        self._dirty = True
        self._redraw_timer = 0.0
        self._step_timer = 0.0
        self._path: QPainterPath | None = None
        self._pixel_ratio = pixel_ratio
        self._tile: QBrush | None = None
        self._edge_frames: list[tuple[QPixmap, float]] = []
        self._edge_slots: list[tuple[int, float]] = []
        self._chunks: list[tuple[QImage, float, float] | None] = []  # картинка, x, верх
        self._snapshots: list[list[float] | None] = []  # высоты, по которым кусок нарисован
        # Смена картинки куска: прежняя картинка, время начала, растёт ли куча (что поверх чего рисовать)
        self._previous: list[tuple[tuple[QImage, float, float] | None, float, bool] | None] = []
        self._clock = 0.0
        self._next_chunk = 0
        self._changed = True  # снег менялся с последней проверки кусков
        self.set_colors(fill, stroke)
        self.set_texture(sprites, under)

    def set_colors(self, fill: int, stroke: tuple[int, float]) -> None:
        """Цвет того, что накопилось: снег, лепестки, пух, листья."""
        color, alpha = stroke
        self._fill = QColor(f"#{fill:06x}")
        pen_color = QColor(f"#{color:06x}")
        pen_color.setAlphaF(alpha)
        self._pen = QPen(pen_color, 1.0)
        self._pen.setJoinStyle(Qt.RoundJoin)
        shade = QColor(f"#{color:06x}")
        shade.setAlphaF(0.34)
        self._shade_top = shade
        clear = QColor(shade)
        clear.setAlphaF(0.0)
        self._shade_clear = clear

    def set_texture(self, sprites: tuple[str, ...], under: int = 0) -> None:
        """Из каких спрайтов «набрана» куча; пусто — сплошная заливка (снег). `under` — тень между ними."""
        self._under = QColor(f"#{under:06x}")
        self._tile = None
        self._edge_frames = []
        if sprites:
            rng = random.Random(1)  # одинаковый узор при каждом запуске
            self._tile = self._make_tile(sprites, rng, self._under)
            ratio = self._pixel_ratio
            for name in sprites:
                for size in (SPRITE_SIZES[0] + 1, (SPRITE_SIZES[0] + SPRITE_SIZES[1]) / 2, SPRITE_SIZES[1]):
                    for frame in art.particle_frames(name, size * ratio, EDGE_ROTATIONS):
                        frame.setDevicePixelRatio(ratio)
                        self._edge_frames.append((frame, frame.width() / ratio / 2))
        self._make_edge_slots()
        self._reset_chunks()

    def _reset_chunks(self) -> None:
        count = math.ceil(len(self.heights) / CHUNK_COLUMNS) if self._tile is not None else 0
        self._chunks = [None] * count
        self._snapshots = [None] * count
        self._previous = [None] * count
        self._next_chunk = 0
        self._dirty = True
        self._changed = True

    def _make_tile(self, sprites: tuple[str, ...], rng: random.Random, under: QColor) -> QBrush:
        """Кисть-плитка (бесшовная: спрайты, вылезающие за край, дорисованы с противоположной стороны).
        Фон плитки — цвет тени, поэтому тело кучи рисуется одним drawPath."""
        ratio = self._pixel_ratio
        side = round(TILE * ratio)
        tile = QImage(side, side, QImage.Format_ARGB32_Premultiplied)
        tile.fill(under)
        pictures = [art.image(name) for name in sprites]
        pictures = [p for p in pictures if p is not None]
        if pictures:
            painter = QPainter(tile)
            painter.setRenderHint(QPainter.SmoothPixmapTransform)
            painter.scale(ratio, ratio)
            for _ in range(TILE_SPRITES):
                picture = rng.choice(pictures)
                size = rng.uniform(*SPRITE_SIZES)
                x, y, angle = rng.uniform(0, TILE), rng.uniform(0, TILE), rng.uniform(0, 360)
                for dx in (-TILE, 0, TILE):
                    for dy in (-TILE, 0, TILE):
                        cx, cy = x + dx, y + dy
                        if -size < cx < TILE + size and -size < cy < TILE + size:
                            painter.save()
                            painter.translate(cx, cy)
                            painter.rotate(angle)
                            painter.drawImage(QRectF(-size / 2, -size / 2, size, size), picture)
                            painter.restore()
            painter.end()
        brush = QBrush(QPixmap.fromImage(tile))
        # Плитка нарисована в пикселях экрана, а кисть применяется в точках — уменьшаем обратно;
        # узор привязан к земле (не «едет», когда куча растёт)
        brush.setTransform(QTransform().translate(0, self.base_y).scale(1 / ratio, 1 / ratio))
        return brush

    def _make_edge_slots(self) -> None:
        """Каждому месту на краю — свой постоянный спрайт и смещение (иначе край «кипел» бы при росте)."""
        if not self._edge_frames:
            self._edge_slots = []
            return
        rng = random.Random(2)
        count = int(self.width / EDGE_STEP) + 1
        self._edge_slots = [(rng.randrange(len(self._edge_frames)), rng.uniform(-1.5, 3.0)) for _ in range(count)]

    def resize(self, width: float, base_y: float) -> None:
        """Монитор изменился: снег растягивается на новую ширину."""
        self.base_y = base_y
        if self._tile is not None:
            ratio = self._pixel_ratio
            self._tile.setTransform(QTransform().translate(0, base_y).scale(1 / ratio, 1 / ratio))
        columns = max(1, math.ceil(width / COLUMN))
        if columns != len(self.heights):
            old = self.heights
            self.heights = [old[min(len(old) - 1, i * len(old) // columns)] for i in range(columns)]
        self.width = width
        self._make_edge_slots()
        self._reset_chunks()

    # MARK: - Чтение

    def column(self, x: float) -> int | None:
        if not math.isfinite(x):
            return None
        i = int(math.floor(x / COLUMN))
        return i if 0 <= i < len(self.heights) else None

    def column_x(self, i: int) -> float:
        return (i + 0.5) * COLUMN

    def height(self, x: float) -> float:
        i = self.column(x)
        return self.heights[i] if i is not None else 0.0

    def surface_y(self, x: float) -> float:
        """Верх снега в точке x (координата экрана, Y вниз)."""
        return self.base_y - self.height(x)

    @property
    def average(self) -> float:
        return sum(self.heights) / len(self.heights)

    @property
    def peak(self) -> float:
        return max(self.heights)

    @property
    def is_empty(self) -> bool:
        return (self.peak <= 0.25 and self._path is None and not any(self._chunks)
                and not any(self._previous))

    # MARK: - Добавить / убрать

    def deposit(self, x: float, amount: float) -> None:
        """Упавшая снежинка: половина — в свой столбец, по четверти — соседям."""
        i = self.column(x)
        if i is None:
            return
        self._add(i, amount * 0.5)
        self._add(i - 1, amount * 0.25)
        self._add(i + 1, amount * 0.25)
        self._dirty = True
        self._changed = True

    def _add(self, i: int, amount: float) -> None:
        if 0 <= i < len(self.heights):
            self.heights[i] = min(MAX_HEIGHT, self.heights[i] + amount)

    def deposit_around(self, x: float, amount: float) -> None:
        """Ком снега рассыпался: снег возвращается на землю полосой ±30 точек."""
        cx = x - 30
        while cx <= x + 30:
            self.deposit(cx, amount * 0.25)
            cx += 6

    def remove(self, x0: float, x1: float, depth: float, keep: float = 0.0) -> float:
        """Снимает не больше `depth` точек снега на отрезке x0…x1. Возвращает, сколько сняли всего."""
        if not (math.isfinite(x0) and math.isfinite(x1)):
            return 0.0
        a = max(0, int(math.floor(min(x0, x1) / COLUMN)))
        b = min(len(self.heights) - 1, int(math.floor(max(x0, x1) / COLUMN)))
        removed = 0.0
        for i in range(a, b + 1):
            take = max(0.0, min(depth, self.heights[i] - keep))
            self.heights[i] -= take
            removed += take
        if removed > 0:
            self._dirty = True
            self._changed = True
        return removed

    def melt(self, amount: float) -> None:
        h = self.heights
        changed = False
        for i, value in enumerate(h):
            if value > 0:
                h[i] = max(0.0, value - amount)
                changed = True
        if changed:
            self._dirty = True
            self._changed = True

    def clear(self) -> None:
        self.heights = [0.0] * len(self.heights)
        self._dirty = True
        self._changed = True

    # MARK: - Физика

    def relax(self) -> None:
        """Слишком крутой склон осыпается: разница соседних столбцов сглаживается до REPOSE."""
        h = self.heights
        n = len(h)
        changed = False
        for _ in range(2):
            for i in range(n - 1):
                diff = h[i] - h[i + 1]
                if diff > REPOSE:
                    t = (diff - REPOSE) * 0.3
                    h[i] -= t
                    h[i + 1] += t
                    changed = True
                elif diff < -REPOSE:
                    t = (-diff - REPOSE) * 0.3
                    h[i] += t
                    h[i + 1] -= t
                    changed = True
        if changed:
            self._dirty = True
            self._changed = True

    def tick(self, dt: float, melting: bool) -> None:
        self._clock += dt
        for index, previous in enumerate(self._previous):
            if previous is not None and self._clock - previous[1] >= CHUNK_FADE:
                self._previous[index] = None
        self._step_timer += dt
        if self._step_timer < STEP_SECONDS:
            return
        step = self._step_timer
        self._step_timer = 0.0
        self.relax()
        if melting:
            self.melt(step * 0.5)
        if self._tile is not None:
            self._path = None
            self._update_chunks()
            return
        self._redraw_timer += step
        if self._redraw_timer >= REDRAW_SECONDS:
            self._redraw_timer = 0.0
            if self._dirty:
                self._dirty = False
                self._path = self._build_path(0, len(self.heights))

    def _update_chunks(self) -> None:
        """Перерисовывает не больше одного куска за кадр — первый (по кругу), где снег заметно изменился."""
        if not self._changed:
            return
        h = self.heights
        count = len(self._chunks)
        for step in range(count):
            index = (self._next_chunk + step) % count
            a = index * CHUNK_COLUMNS
            b = min(len(h), a + CHUNK_COLUMNS)
            snapshot = self._snapshots[index]
            if snapshot is not None and max(map(abs, map(operator.sub, h[a:b], snapshot))) <= CHUNK_THRESHOLD:
                continue
            current = h[a:b]
            growing = snapshot is None or sum(current) >= sum(snapshot)
            old = self._chunks[index]
            self._snapshots[index] = current
            self._chunks[index] = self._render_chunk(a, b)
            if old is not None or self._chunks[index] is not None:
                self._previous[index] = (old, self._clock, growing)
            self._next_chunk = (index + 1) % count
            return
        self._changed = False  # всё нарисовано; мелкие изменения копятся до следующей мутации

    # MARK: - Рисование

    def _build_path(self, start: int, end: int) -> QPainterPath | None:
        """Контур столбцов start…end-1 из отрезков: каждый 3-й столбец — вершина
        (на глаз как кривая, а строится в разы быстрее)."""
        h = self.heights
        n = end
        base = self.base_y
        path = QPainterPath()
        i = start
        while i < n:
            if h[i] <= 0.25:
                i += 1
                continue
            j = i
            while j < n and h[j] > 0.25:
                j += 1
            last = j - 1
            x0, x1 = i * COLUMN, j * COLUMN
            path.moveTo(x0, base)
            path.lineTo(x0, base - h[i] * 0.5)
            k = i
            while k < last:
                path.lineTo((k + 0.5) * COLUMN, base - h[k])
                k += DRAW_STRIDE
            path.lineTo((last + 0.5) * COLUMN, base - h[last])
            path.lineTo(x1, base - h[last] * 0.5)
            path.lineTo(x1, base)
            path.closeSubpath()
            i = j
        return None if path.isEmpty() else path

    def _render_chunk(self, a: int, b: int) -> tuple[QImage, float, float] | None:
        """Кусок кучи (столбцы a…b-1) из спрайтов — в картинку."""
        h = self.heights
        n = len(h)
        pad = 4  # контур и спрайты берём с запасом по краям: стык кусков не видно
        lo, hi = max(0, a - pad), min(n, b + pad)
        peak = max(h[lo:hi])
        if peak <= 0.25:
            return None
        path = self._build_path(lo, hi)
        if path is None:
            return None
        ratio = self._pixel_ratio
        x0, x1 = a * COLUMN, min(b * COLUMN, self.width)
        top = self.base_y - peak - EDGE_MARGIN - 4
        height = self.base_y + 2 - top
        image = QImage(max(1, math.ceil((x1 - x0) * ratio)), max(1, math.ceil(height * ratio)),
                       QImage.Format_ARGB32_Premultiplied)
        image.fill(Qt.transparent)
        painter = QPainter(image)
        # Без сглаживания контура: его всё равно закрывают спрайты края, а рисуется в 2 раза быстрее
        painter.setRenderHint(QPainter.SmoothPixmapTransform)
        painter.scale(ratio, ratio)
        painter.translate(-x0, -top)
        painter.setPen(Qt.NoPen)
        painter.setBrush(self._tile)
        painter.drawPath(path)
        gradient = QLinearGradient(QPointF(0, self.base_y), QPointF(0, self.base_y - SHADE_DEPTH))
        gradient.setColorAt(0, self._shade_top)
        gradient.setColorAt(1, self._shade_clear)
        painter.setBrush(gradient)
        painter.drawPath(path)
        # Край: спрайты сидят на контуре и наполовину торчат над ним (и соседние, заходящие в кусок)
        reach = SPRITE_SIZES[1]
        first = max(0, int((x0 - reach) / EDGE_STEP))
        last = min(len(self._edge_slots), int((x1 + reach) / EDGE_STEP) + 1)
        for index in range(first, last):
            frame_index, dy = self._edge_slots[index]
            x = index * EDGE_STEP + EDGE_STEP / 2
            column = self.column(x)
            if column is None or h[column] < 1.5:
                continue
            frame, half = self._edge_frames[frame_index]
            y = self.base_y - h[column] + dy
            painter.drawPixmap(QPointF(x - half, y - half), frame)
        painter.end()
        image.setDevicePixelRatio(ratio)
        return image, x0, top

    def paint(self, painter: QPainter, opacity: float = 1.0) -> None:
        if self._tile is not None:
            for chunk, previous in zip(self._chunks, self._previous):
                if previous is None:
                    self._draw_chunk(painter, chunk, opacity)
                    continue
                old, start, growing = previous
                t = min(1.0, (self._clock - start) / CHUNK_FADE)
                if growing:  # новое проявляется поверх старого
                    self._draw_chunk(painter, old, opacity)
                    self._draw_chunk(painter, chunk, opacity * t)
                else:        # старое растворяется поверх нового
                    self._draw_chunk(painter, chunk, opacity)
                    self._draw_chunk(painter, old, opacity * (1 - t))
            painter.setOpacity(1.0)
            return
        path = self._path
        if path is None:
            return
        painter.setOpacity(opacity)
        painter.setPen(Qt.NoPen)
        painter.setBrush(self._fill)
        painter.drawPath(path)
        # Мягкая тень у основания — придаёт сугробу объём
        gradient = QLinearGradient(QPointF(0, self.base_y), QPointF(0, self.base_y - SHADE_DEPTH))
        gradient.setColorAt(0, self._shade_top)
        gradient.setColorAt(1, self._shade_clear)
        painter.setBrush(gradient)
        painter.drawPath(path)
        painter.setBrush(Qt.NoBrush)
        painter.setPen(self._pen)
        painter.drawPath(path)
        painter.setOpacity(1.0)

    @staticmethod
    def _draw_chunk(painter: QPainter, chunk: tuple[QImage, float, float] | None, opacity: float) -> None:
        if chunk is None or opacity <= 0.01:
            return
        image, x, top = chunk
        painter.setOpacity(opacity)
        painter.drawImage(QPointF(x, top), image)
