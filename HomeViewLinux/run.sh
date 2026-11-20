#!/usr/bin/env bash
# Запуск HomeView для Linux. При первом запуске создаёт .venv и ставит зависимости.
set -euo pipefail
DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
VENV="$DIR/.venv"
# Qt ≥ 6.5 не запускается под X11 без libxcb-cursor0 — и падает с невнятной ошибкой.
# Не `grep -q`: с `set -o pipefail` он обрывает конвейер (SIGPIPE у ldconfig) и даёт ложную ошибку.
has_xcb_cursor() {
    local listing
    listing="$( { ldconfig -p || /sbin/ldconfig -p; } 2>/dev/null || true)"
    [[ "$listing" == *"libxcb-cursor.so.0"* ]] && return 0
    compgen -G "/usr/lib/*/libxcb-cursor.so.0*" >/dev/null || compgen -G "/lib/*/libxcb-cursor.so.0*" >/dev/null
}
if ! has_xcb_cursor; then
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
