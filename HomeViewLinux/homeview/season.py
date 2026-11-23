"""Времена года (по мотивам Season.swift): что падает, чем кидаются, что говорят."""

from __future__ import annotations

import datetime
from dataclasses import dataclass


@dataclass(frozen=True)
class ParticleLayer:
    """Один «слой» осадков (дальний / средний / ближний) — параметры CAEmitterCell из Mac-версии."""

    image: str
    rate: float          # частиц в секунду на ширину 1440 точек
    velocity: float      # точек в секунду
    scale: float         # доля от 16 точек (128 px / 8)
    alpha: float
    spin: float          # рад/с, разброс ±spin
    emission_range: float  # рад, разброс направления падения
    sway: float          # амплитуда покачивания (наше дополнение для листьев и лепестков)


@dataclass(frozen=True)
class Season:
    kind: str
    title: str
    emoji: str
    particle_title: str
    projectile_title: str
    layers: tuple[ParticleLayer, ...]
    accumulation: float            # сколько осадков копится на земле (снег — 1)
    pile_fill: int                 # цвет сугроба 0xRRGGBB
    pile_stroke: tuple[int, float]  # цвет контура и тени, прозрачность контура
    pile_sprites: tuple[str, ...] = ()  # из чего «набрана» куча (наше дополнение; зимой и летом — сплошная)
    pile_under: int = 0                 # цвет «тени» между спрайтами кучи


SEASONS: dict[str, Season] = {
    "winter": Season(
        "winter", "Зима", "❄️", "Снег", "снежок",
        (
            ParticleLayer("hv_p_flake_dot", 36, 30, 0.26, 0.75, 0.0, 0.18, 0),
            ParticleLayer("hv_p_flake_soft", 28, 44, 0.42, 0.9, 0.0, 0.18, 0),
            ParticleLayer("hv_p_flake_crystal", 16, 64, 0.62, 1.0, 0.6, 0.18, 6),
        ),
        1.0, 0xFFFFFF, (0xA9B9CF, 0.95),
    ),
    "spring": Season(
        "spring", "Весна", "🌸", "Лепестки урюка", "цветочный шарик",
        (
            ParticleLayer("hv_p_petal_white", 14, 26, 0.34, 0.8, 1.2, 0.5, 18),
            ParticleLayer("hv_p_petal_pink", 11, 36, 0.5, 0.95, 1.6, 0.5, 24),
            ParticleLayer("hv_p_petal_pink", 6, 50, 0.7, 1.0, 2.0, 0.5, 30),
        ),
        0.7, 0xFCE4EC, (0xF48FB1, 0.9), ("hv_p_petal_pink", "hv_p_petal_white"), 0xF3A6C0,
    ),
    "summer": Season(
        "summer", "Лето", "☀️", "Тополиный пух", "водяной шарик",
        (
            ParticleLayer("hv_p_fluff", 7, 12, 0.4, 0.7, 0.3, 1.2, 26),
            ParticleLayer("hv_p_fluff", 5, 16, 0.6, 0.85, 0.4, 1.2, 34),
            ParticleLayer("hv_p_fluff", 3, 22, 0.85, 0.9, 0.5, 1.2, 40),
        ),
        0.35, 0xF7F5EE, (0xD7CCC8, 0.9),
    ),
    "autumn": Season(
        "autumn", "Осень", "🍂", "Листья", "листяной шарик",
        (
            ParticleLayer("hv_p_leaf_gold", 12, 30, 0.4, 0.85, 1.6, 0.45, 22),
            ParticleLayer("hv_p_leaf_orange", 9, 42, 0.6, 0.95, 2.0, 0.45, 30),
            ParticleLayer("hv_p_leaf_red", 5, 56, 0.82, 1.0, 2.4, 0.45, 36),
        ),
        0.8, 0xE8A04C, (0xB5651D, 0.9), ("hv_p_leaf_gold", "hv_p_leaf_orange", "hv_p_leaf_red"), 0x8A4B1C,
    ),
}

ORDER = ("winter", "spring", "summer", "autumn")


def season_for_date(date: datetime.date | None = None) -> str:
    """Декабрь–февраль зима, март–май весна, июнь–август лето, сентябрь–ноябрь осень."""
    month = (date or datetime.date.today()).month
    if month in (12, 1, 2):
        return "winter"
    if month in (3, 4, 5):
        return "spring"
    if month in (6, 7, 8):
        return "summer"
    return "autumn"


def resolve(setting: str) -> Season:
    kind = season_for_date() if setting == "auto" else setting
    return SEASONS.get(kind, SEASONS["winter"])


# Реплики человечков
HIT_REACTIONS = ("Ой!", "Эй!", "Ну, держись!", "Ай!")
THROW_TAUNTS = ("Лови!", "Держи!", "На тебе!", "Привет!")
WAVE_TEXT = "👋 Привет!"
TEA_TEXT = "☕ Пойдём на чай?"
TEA_YES = "Иду! ☕"
TEA_LATER = "Сейчас занят, давай позже"
