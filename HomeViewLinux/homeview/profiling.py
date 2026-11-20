"""Встроенный профилировщик: HOMEVIEW_PROFILE=1 ./run.sh

Раз в 5 секунд пишет в журнал:
* задержку цикла событий — насколько опаздывает таймер на 10 мс (столько ждут клики и меню);
* среднее и максимальное время помеченных участков (кадр, отрисовка окон, меню трея…).
"""

from __future__ import annotations

import functools
import logging
import os
import time
from collections import defaultdict

from PySide6.QtCore import QObject, Qt, QTimer

log = logging.getLogger("homeview.profile")

ENABLED = bool(os.environ.get("HOMEVIEW_PROFILE"))
REPORT_SECONDS = 5.0
PROBE_MS = 10

_stats: dict[str, list[float]] = defaultdict(list)


def measure(label: str):
    """Декоратор: учитывает время вызова функции (без накладных расходов, если профилирование выключено)."""
    def wrap(function):
        if not ENABLED:
            return function

        @functools.wraps(function)
        def timed(*args, **kwargs):
            start = time.perf_counter()
            try:
                return function(*args, **kwargs)
            finally:
                _stats[label].append(time.perf_counter() - start)
        return timed
    return wrap


class Profiler(QObject):
    def __init__(self) -> None:
        super().__init__()
        self._expected = time.perf_counter() + PROBE_MS / 1000
        self._probe = QTimer(self)
        self._probe.setTimerType(Qt.PreciseTimer)
        self._probe.timeout.connect(self._tick)
        self._probe.start(PROBE_MS)
        self._report = QTimer(self)
        self._report.timeout.connect(self._print)
        self._report.start(int(REPORT_SECONDS * 1000))
        log.info("Профилирование включено")

    def _tick(self) -> None:
        now = time.perf_counter()
        _stats["задержка цикла событий"].append(max(0.0, now - self._expected))
        self._expected = now + PROBE_MS / 1000

    def _print(self) -> None:
        lines = []
        for label, values in sorted(_stats.items(), key=lambda kv: -max(kv[1], default=0)):
            if not values:
                continue
            avg = sum(values) / len(values) * 1000
            peak = max(values) * 1000
            slow = sum(1 for v in values if v > 0.05)
            lines.append(f"  {label:28} ср {avg:6.1f} мс   макс {peak:7.1f} мс   "
                         f"{len(values) / REPORT_SECONDS:6.1f}/с   >50мс: {slow}")
        _stats.clear()
        if lines:
            log.info("Профиль за %.0f с:\n%s", REPORT_SECONDS, "\n".join(lines))


_profiler: Profiler | None = None


def start() -> None:
    global _profiler
    if ENABLED and _profiler is None:
        _profiler = Profiler()
