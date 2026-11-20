#!/usr/bin/env bash
# Запуск HomeView для Linux. При первом запуске создаёт .venv и ставит зависимости.
set -euo pipefail
DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
VENV="$DIR/.venv"
# Qt ≥ 6.5 не запускается под X11 без libxcb-cursor0 — и падает с невнятной ошибкой
if ! ldconfig -p 2>/dev/null | grep -q "libxcb-cursor.so.0"; then
    echo "Не хватает системной библиотеки libxcb-cursor0. Установите её:" >&2
    echo "    sudo apt install libxcb-cursor0" >&2
    exit 1
fi
if [ ! -x "$VENV/bin/python" ]; then
    echo "Первый запуск: создаю окружение и ставлю зависимости (PySide6, zeroconf)…"
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet --upgrade pip
    "$VENV/bin/pip" install --quiet -r "$DIR/requirements.txt"
fi
cd "$DIR"
exec "$VENV/bin/python" -m homeview "$@"
