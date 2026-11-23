"""Мир одного монитора: осадки, снег на земле, человечки коллег (только на основном мониторе), эффекты."""

from __future__ import annotations

import random
from typing import Callable

from PySide6.QtCore import QPointF, QRect
from PySide6.QtGui import QPainter

from . import art
from .avatar import PeerAvatar
from .effects import Burst, Effect, FlyingBall, Splat, ease_in, ease_out
from .particles import ParticleSystem
from .protocol import GAME_MAX_PLAYERS, PeerInfo, RoomInfo, game_title
from .season import HIT_REACTIONS, THROW_TAUNTS, WAVE_TEXT, Season
from .snowpile import SnowPile

# Невидимых снежинок в секунду на ширину 1440 точек при плотности 1 (baseFlakeRate в SnowWorld.swift)
BASE_FLAKE_RATE = 80.0
# Сколько снега приносит снежинка относительно Mac-версии: у нас куча растёт медленнее
# (на маке её разгребает бригада; при 1.0 куча упирается в потолок минут за 20, при 0.4 — примерно за час)
PILE_GROWTH = 0.4
PILE_FADE_SECONDS = 1.5  # старая куча растворяется при смене сезона и «Убрать снег»


class World:
    def __init__(self, geometry: QRect, available: QRect, is_primary: bool, season: Season,
                 density: float, avatar_scale: float, effects_enabled: bool, pixel_ratio: float,
                 gpu_particles: bool = False, text_scale: float = 1.0) -> None:
        self.is_primary = is_primary
        self.text_scale = text_scale
        self.gpu_particles = gpu_particles  # частицы считает и рисует видеокарта (gl_particles.py)
        self.pixel_ratio = pixel_ratio
        self.season = season
        self.density = density
        self.avatar_scale = avatar_scale
        self.effects_enabled = effects_enabled
        self.avatars: dict[str, PeerAvatar] = {}
        self.effects: list[Effect] = []
        self.particles: ParticleSystem | None = None
        self._fading_out: ParticleSystem | None = None
        self.ground: SnowPile | None = None
        self._old_ground: SnowPile | None = None
        self._old_ground_opacity = 0.0
        self._sky_carry = 0.0
        self.set_geometry(geometry, available)
        self._rebuild_particles()

    # MARK: - Геометрия и настройки

    def set_geometry(self, geometry: QRect, available: QRect) -> None:
        self.width = geometry.width()
        self.height = geometry.height()
        # «Земля» — верх нижней панели (как верх Dock в Mac-версии), иначе низ экрана
        bottom = available.intersected(geometry).bottom() + 1 if available.intersects(geometry) else geometry.bottom() + 1
        self.ground_y = float(bottom - geometry.top())
        if self.particles:
            self.particles.set_ground(self.width, self.ground_y)
        if self.ground is None:
            self.ground = self._new_pile()
        else:
            self.ground.resize(self.width, self.ground_y)
        for avatar in self.avatars.values():
            avatar.ground_y = self.ground_y

    def _rebuild_particles(self) -> None:
        if not self.effects_enabled:
            self.particles = None
            return
        self.particles = ParticleSystem(self.season, self.width, self.ground_y, self.density, self.pixel_ratio,
                                        simulate=not self.gpu_particles)

    def particle_systems(self) -> list[ParticleSystem]:
        """Для GPU-рендера: тающий набор (при смене сезона) и текущий."""
        return [s for s in (self._fading_out, self.particles) if s is not None]

    def fall_back_to_cpu_particles(self) -> None:
        """Шейдер не заработал — считаем частицы на процессоре."""
        self.gpu_particles = False
        self._fading_out = None
        self._rebuild_particles()

    def apply(self, season: Season, density: float, avatar_scale: float, effects_enabled: bool,
              text_scale: float = 1.0) -> None:
        season_changed = season.kind != self.season.kind
        rebuild = season_changed or abs(density - self.density) > 0.001 or effects_enabled != self.effects_enabled
        self.season = season
        self.density = density
        self.effects_enabled = effects_enabled
        if season_changed and self.ground is not None:
            self._fade_out_ground()  # старая куча растворяется, новая растёт с нуля
        if rebuild:
            # Плавная смена: старые осадки тают, новые проявляются
            self._fading_out = self.particles if season_changed else None
            self._rebuild_particles()
            if self.particles and self._fading_out:
                self.particles.opacity = 0.0
        if abs(text_scale - self.text_scale) > 0.001:
            self.text_scale = text_scale
            for avatar in self.avatars.values():
                avatar.set_text_scale(text_scale)
        if abs(avatar_scale - self.avatar_scale) > 0.001:
            self.avatar_scale = avatar_scale
            for avatar in self.avatars.values():
                avatar.set_scale(avatar_scale)

    # MARK: - Коллеги

    def sync_peers(self, peers: list[PeerInfo], rooms: list[RoomInfo]) -> None:
        if not self.is_primary:
            return
        wanted = {peer.id for peer in peers}
        for peer_id in list(self.avatars):
            if peer_id not in wanted:
                del self.avatars[peer_id]
        for info in peers:
            avatar = self.avatars.get(info.id)
            if avatar is not None:
                avatar.update_info(info)
            else:
                x = -30.0 if random.random() < 0.5 else self.width + 30.0
                avatar = PeerAvatar(info, x, self.avatar_scale, self.pixel_ratio, self.text_scale)
                avatar.ground_y = self.ground_y
                self.avatars[info.id] = avatar
        for peer_id, avatar in self.avatars.items():
            label = None
            for room in rooms:
                emoji, title = game_title(room.game)
                if room.host_id == peer_id and room.phase == "lobby":
                    label = f"{emoji} {title} {len(room.players)}/{GAME_MAX_PLAYERS.get(room.game, 2)}"
                    break
                if peer_id in room.players and room.phase == "playing":
                    label = f"{emoji} играет"
                    break
            avatar.set_flag(label)

    def avatar_at(self, point: QPointF) -> str | None:
        # Сверху рисуются последние — их и проверяем первыми
        for peer_id, avatar in reversed(list(self.avatars.items())):
            if avatar.visible and avatar.hit_rect().contains(point):
                return peer_id
        return None

    def input_rects(self) -> list[tuple[int, int, int, int]]:
        rects = []
        for avatar in self.avatars.values():
            if avatar.visible:
                r = avatar.hit_rect()
                rects.append((int(r.x()) - 2, int(r.y()) - 2, int(r.width()) + 4, int(r.height()) + 4))
        return rects

    # MARK: - События

    def peer_waves(self, peer_id: str) -> None:
        avatar = self.avatars.get(peer_id)
        if avatar:
            avatar.wave()
            avatar.say(WAVE_TEXT, 2.5)

    def peer_says(self, peer_id: str, text: str, from_me: bool = False) -> None:
        avatar = self.avatars.get(peer_id)
        if not avatar:
            return
        if from_me:
            avatar.hop()
        else:
            avatar.say(text, 5)

    def incoming_projectile(self, peer_id: str, cursor: QPointF | None) -> None:
        """Коллега кинул в нас: его человечек замахивается, снаряд летит «в экран» и прилипает."""
        if not self.is_primary:
            return
        avatar = self.avatars.get(peer_id)
        if avatar is not None and avatar.visible:
            avatar.throw_motion()
            avatar.say(random.choice(THROW_TAUNTS), 2)
            start = avatar.hand_point()
            delay = 0.3
        else:
            start = QPointF(random.uniform(60, self.width - 60), self.height + 40)
            delay = 0.0
        if cursor is not None:
            target = QPointF(cursor.x() + random.uniform(-60, 60), cursor.y() + random.uniform(-50, 50))
        else:
            target = QPointF(random.uniform(self.width * 0.25, self.width * 0.75),
                             random.uniform(self.height * 0.3, self.height * 0.65))
        target = QPointF(min(max(target.x(), 90), self.width - 90), min(max(target.y(), 90), self.height - 90))
        control = QPointF((start.x() + target.x()) / 2, min(start.y(), target.y()) - 160)
        season = self.season.kind

        def land() -> None:
            self.effects.append(Splat(season, target, 130))

        self.effects.append(FlyingBall(art.ball(season), start, target, control, 0.8, 0.35, 3.4, 28,
                                       ease_in, land, delay=delay))

    def throw_at(self, peer_id: str, on_hit: Callable[[], None]) -> None:
        """Мы кидаем в коллегу: снаряд летит из-за края экрана в его человечка."""
        avatar = self.avatars.get(peer_id) if self.is_primary else None
        if avatar is None or not avatar.visible:
            on_hit()
            return
        point = avatar.chest_point()
        start = QPointF(point.x() + (140 if point.x() < self.width / 2 else -140), self.height + 60)
        control = QPointF((start.x() + point.x()) / 2, min(point.y(), start.y()) - 140)
        top, middle, _ = art.BALL_COLORS.get(self.season.kind, art.BALL_COLORS["winter"])

        def hit() -> None:
            target = avatar.chest_point()
            self.effects.append(Burst(target, [art.qcolor(top), art.qcolor(middle)], count=14))
            avatar.flinch()
            avatar.say(random.choice(HIT_REACTIONS), 2)
            on_hit()

        self.effects.append(FlyingBall(art.ball(self.season.kind), start, point, control, 0.5, 3.0, 0.8, 30,
                                       ease_out, hit))

    # MARK: - Снег на земле

    def ground_surface(self, x: float) -> float:
        """Куда ставить ступни: на снег, чуть провалившись (как groundSurface в Mac-версии)."""
        return self.ground_y - self.ground.height(x) * 0.8 if self.ground else self.ground_y

    def _accumulate(self, dt: float) -> None:
        """С неба падают «невидимые» снежинки с той же частотой, что и видимые; каждая ложится на землю.
        Крупные приносят больше снега (но не линейно, иначе экран быстро заполнится)."""
        rate = BASE_FLAKE_RATE * self.density * self.width / 1440
        self._sky_carry += rate * dt
        count = min(int(self._sky_carry), 400)
        self._sky_carry -= int(self._sky_carry)
        factor = 0.32 * self.season.accumulation * PILE_GROWTH
        ground = self.ground
        width = self.width
        for _ in range(count):
            r = random.random()
            ground.deposit(random.uniform(0, width), (2.2 + r * r * 5.5) * factor)

    def _new_pile(self) -> SnowPile:
        season = self.season
        return SnowPile(self.width, self.ground_y, season.pile_fill, season.pile_stroke,
                        season.pile_sprites, season.pile_under, self.pixel_ratio)

    def _fade_out_ground(self) -> None:
        if self.ground is not None and not self.ground.is_empty:
            self._old_ground = self.ground
            self._old_ground_opacity = 1.0
        self.ground = self._new_pile()

    def clear_snow(self) -> None:
        self._fade_out_ground()

    # MARK: - Шаг и рисование

    def tick(self, dt: float) -> None:
        if self.ground:
            snowing = self.effects_enabled
            if snowing:
                self._accumulate(dt)
            self.ground.tick(dt, melting=not snowing)
        if self._old_ground is not None:
            self._old_ground_opacity -= dt / PILE_FADE_SECONDS
            if self._old_ground_opacity <= 0:
                self._old_ground = None
        if self.particles:
            self.particles.tick(dt)
            if self.particles.opacity < 1:
                self.particles.opacity = min(1.0, self.particles.opacity + dt / 2.0)
        if self._fading_out:
            self._fading_out.tick(dt)
            self._fading_out.opacity -= dt / 1.5
            if self._fading_out.opacity <= 0:
                self._fading_out = None
        for avatar in self.avatars.values():
            avatar.tick(dt, self.width)
            avatar.ground_y = self.ground_surface(avatar.x)
        for effect in list(self.effects):
            effect.tick(dt)
        self.effects = [e for e in self.effects if e.alive]

    def paint(self, painter: QPainter) -> None:
        if not self.gpu_particles:
            if self._fading_out:
                self._fading_out.paint(painter)
            if self.particles:
                self.particles.paint(painter)
        painter.setRenderHint(QPainter.SmoothPixmapTransform)
        painter.setRenderHint(QPainter.Antialiasing)
        if self._old_ground:
            self._old_ground.paint(painter, self._old_ground_opacity)
        if self.ground:
            self.ground.paint(painter)
        for avatar in self.avatars.values():
            avatar.paint(painter)
        for effect in self.effects:
            effect.paint(painter)
        painter.setRenderHint(QPainter.SmoothPixmapTransform, False)
        painter.setRenderHint(QPainter.Antialiasing, False)

    @property
    def is_idle(self) -> bool:
        """Нечего рисовать — можно не перерисовывать окно."""
        return (self.particles is None and self._fading_out is None and not self.avatars and not self.effects
                and (self.ground is None or self.ground.is_empty) and self._old_ground is None)
