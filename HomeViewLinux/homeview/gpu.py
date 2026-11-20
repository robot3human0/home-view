"""Выбор видеокарты для отрисовки.

Режимы (настройка `renderer`):
    auto       — дискретная, если есть; иначе встроенная; иначе процессор
    discrete   — дискретная (NVIDIA через PRIME offload, AMD через DRI_PRIME)
    integrated — встроенная (Intel / AMD APU, через Mesa)
    cpu        — без видеокарты: программная отрисовка (заметно грузит процессор)

Видеокарту для OpenGL выбирают переменные окружения, которые читаются при загрузке libGL —
поэтому выбор делается ДО создания QApplication, а смена режима требует перезапуска.
Каждый вариант проверяется пробным запуском в отдельном процессе: создаём OpenGL-контекст
и смотрим, кто реально рисует (не программный ли llvmpipe, не та ли карта).
"""

from __future__ import annotations

import json
import logging
import os
import shlex
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

log = logging.getLogger(__name__)

MODES = ("auto", "discrete", "integrated", "cpu")
VENDOR_NAMES = {0x10DE: "NVIDIA", 0x8086: "Intel", 0x1002: "AMD"}
SOFTWARE_MARKERS = ("llvmpipe", "softpipe", "swrast", "software rasterizer")
PROBE_TIMEOUT = 8


@dataclass(frozen=True)
class Gpu:
    slot: str
    vendor: int
    name: str
    kind: str  # "discrete" | "integrated"

    @property
    def vendor_name(self) -> str:
        return VENDOR_NAMES.get(self.vendor, f"0x{self.vendor:04x}")


@dataclass
class Choice:
    """Итог выбора: чем рисуем и почему."""

    mode: str                       # что выбрано в настройках
    used: str                       # discrete | integrated | cpu — что реально используется
    env: dict[str, str] = field(default_factory=dict)
    renderer: str = ""              # строка GL_RENDERER (пусто для cpu)
    notes: list[str] = field(default_factory=list)  # что пошло не по плану

    @property
    def use_opengl(self) -> bool:
        return self.used != "cpu"


# MARK: - Какие видеокарты есть


def _lspci_name(slot: str) -> str | None:
    try:
        out = subprocess.run(["lspci", "-mm", "-s", slot], capture_output=True, text=True, timeout=3).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    # 02:00.0 "VGA compatible controller" "NVIDIA Corporation" "GB206M [GeForce …]" -ra1 -p00 "…" "…"
    try:
        parts = [p for p in shlex.split(out.strip()) if not p.startswith("-")]
    except ValueError:
        return None
    if len(parts) >= 4:
        device = parts[3]
        # «GB206M [GeForce RTX 4060 Max-Q / Mobile]» → «GeForce RTX 4060 Max-Q / Mobile»
        if "[" in device and device.endswith("]"):
            device = device[device.index("[") + 1:-1]
        return device
    return None


def list_gpus() -> list[Gpu]:
    found: list[tuple[str, int]] = []
    for device in sorted(Path("/sys/bus/pci/devices").glob("*")):
        try:
            if not (device / "class").read_text().startswith("0x03"):
                continue
            vendor = int((device / "vendor").read_text(), 16)
        except (OSError, ValueError):
            continue
        found.append((device.name, vendor))
    has_intel = any(v == 0x8086 for _, v in found)
    has_nvidia = any(v == 0x10DE for _, v in found)
    gpus = []
    for slot, vendor in found:
        if vendor == 0x8086:
            kind = "integrated"
        elif vendor == 0x1002:
            kind = "integrated" if has_nvidia and not has_intel else "discrete"
        else:
            kind = "discrete"
        name = _lspci_name(slot.split(":", 1)[1] if slot.count(":") == 2 else slot)
        gpus.append(Gpu(slot, vendor, f"{VENDOR_NAMES.get(vendor, '')} {name}".strip() if name
                        else f"{VENDOR_NAMES.get(vendor, 'GPU')}", kind))
    return gpus


def env_for(kind: str, gpus: list[Gpu]) -> dict[str, str] | None:
    """Переменные окружения, направляющие OpenGL на нужную карту (None — такой карты нет)."""
    target = next((g for g in gpus if g.kind == kind), None)
    if target is None:
        return None
    if kind == "discrete":
        if target.vendor == 0x10DE:
            return {"__NV_PRIME_RENDER_OFFLOAD": "1", "__GLX_VENDOR_LIBRARY_NAME": "nvidia",
                    "__VK_LAYER_NV_optimus": "NVIDIA_only"}
        return {"DRI_PRIME": "1"}
    return {"__GLX_VENDOR_LIBRARY_NAME": "mesa", "DRI_PRIME": "0"}


# MARK: - Пробный запуск


_PROBE_CODE = r"""
import json, sys
from PySide6.QtGui import QGuiApplication, QOffscreenSurface, QOpenGLContext, QSurfaceFormat
app = QGuiApplication(["homeview-gpu-probe"])
fmt = QSurfaceFormat(); fmt.setAlphaBufferSize(8)
ctx = QOpenGLContext(); ctx.setFormat(fmt)
if not ctx.create():
    print(json.dumps({"ok": False, "error": "context"})); sys.exit(0)
surface = QOffscreenSurface(); surface.setFormat(ctx.format()); surface.create()
if not ctx.makeCurrent(surface):
    print(json.dumps({"ok": False, "error": "makeCurrent"})); sys.exit(0)
f = ctx.functions()
print(json.dumps({"ok": True, "renderer": f.glGetString(0x1F01) or "", "vendor": f.glGetString(0x1F00) or "",
                  "alpha": ctx.format().alphaBufferSize()}))
"""


def probe(env: dict[str, str]) -> dict:
    """Создаёт OpenGL-контекст в отдельном процессе с данными переменными окружения."""
    full_env = {**os.environ, **env, "QT_QPA_PLATFORM": "xcb"}
    try:
        result = subprocess.run([sys.executable, "-c", _PROBE_CODE], env=full_env, capture_output=True,
                                text=True, timeout=PROBE_TIMEOUT)
    except (OSError, subprocess.SubprocessError) as error:
        return {"ok": False, "error": str(error)}
    for line in reversed(result.stdout.strip().splitlines()):
        try:
            return json.loads(line)
        except json.JSONDecodeError:
            continue
    return {"ok": False, "error": (result.stderr.strip().splitlines() or ["нет ответа"])[-1][:200]}


def _acceptable(kind: str, info: dict, gpus: list[Gpu]) -> tuple[bool, str]:
    if not info.get("ok"):
        return False, f"OpenGL не запустился ({info.get('error', '?')})"
    if int(info.get("alpha", 0)) < 8:
        # Без альфа-канала окно получится непрозрачным (чёрным) — такой вариант не годится.
        # Так бывает, например, с PRIME offload, когда X-сервер и так работает на NVIDIA.
        return False, "нет прозрачности (альфа-канала) в OpenGL"
    renderer = str(info.get("renderer", ""))
    lower = renderer.lower()
    if any(marker in lower for marker in SOFTWARE_MARKERS):
        return False, f"вместо видеокарты рисует программный {renderer.split()[0]}"
    if kind == "integrated" and ("nvidia" in lower or "zink" in lower):
        return False, "встроенная графика не подключена к экрану (X-сервер работает на дискретной)"
    if kind == "discrete":
        wanted = next((g for g in gpus if g.kind == "discrete"), None)
        if wanted and wanted.vendor_name.lower() not in lower and "zink" not in lower:
            return False, f"рисует не та карта: {renderer}"
    return True, ""


# MARK: - Выбор


def choose(mode: str) -> Choice:
    mode = mode if mode in MODES else "auto"
    if mode == "cpu":
        return Choice(mode, "cpu")
    if os.environ.get("HOMEVIEW_SKIP_GPU_PROBE"):
        return Choice(mode, "discrete")
    gpus = list_gpus()
    order = {"auto": ["discrete", "integrated"],
             "discrete": ["discrete", "integrated"],
             "integrated": ["integrated", "discrete"]}[mode]
    titles = {"discrete": "Дискретная видеокарта", "integrated": "Встроенная графика"}
    notes = []
    # Сначала — как есть, без переменных: если X-сервер уже работает на нужной карте,
    # лишние переменные (PRIME offload) только вредят — например, отнимают прозрачность.
    default_info = probe({})
    log.info("OpenGL по умолчанию: %s", default_info.get("renderer") or default_info.get("error"))
    for kind in order:
        env = env_for(kind, gpus)
        if env is None:
            if mode == kind or (mode == "auto" and kind == "discrete"):
                notes.append(f"{titles[kind]} не найдена")
            continue
        reason = ""
        for candidate, info in (({}, default_info), (env, None)):
            info = info if info is not None else probe(candidate)
            ok, reason = _acceptable(kind, info, gpus)
            log.info("Проверка «%s» %s: %s", kind, candidate or "(без переменных)",
                     info.get("renderer") if ok else reason)
            if ok:
                return Choice(mode, kind, dict(candidate), str(info.get("renderer", "")), notes)
        notes.append(f"{titles[kind]}: {reason}")
    notes.append("OpenGL недоступен — рисуем процессором")
    return Choice(mode, "cpu", notes=notes)


def describe_available() -> dict[str, str | None]:
    """Для окна настроек: название карты каждого типа (None — нет)."""
    gpus = list_gpus()
    return {kind: next((g.name for g in gpus if g.kind == kind), None) for kind in ("discrete", "integrated")}
