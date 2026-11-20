"""Пути к ресурсам. Спрайты берём из оригинального Mac-проекта (HomeView/Art), не копируем."""

from __future__ import annotations

import os
from pathlib import Path

PACKAGE_DIR = Path(__file__).resolve().parent
LINUX_DIR = PACKAGE_DIR.parent
REPO_ROOT = LINUX_DIR.parent


def art_dir() -> Path:
    override = os.environ.get("HOMEVIEW_ART")
    if override:
        return Path(override)
    return REPO_ROOT / "HomeView" / "Art"


def app_icon() -> Path:
    return REPO_ROOT / "HomeView" / "Resources" / "AppIcon.png"


def run_script() -> Path:
    return LINUX_DIR / "run.sh"
