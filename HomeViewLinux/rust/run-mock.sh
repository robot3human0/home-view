#!/usr/bin/env bash
# Rust-клиент с mock-сервером и ботами — без настоящего офиса.
#
#   ./run-mock.sh [секунд] [ботов]     (по умолчанию — без ограничения, 4 бота; выход — Ctrl+C)
#
# Настройки — временная копия твоих (~/.config/HomeView/HomeViewLinux.conf) с адресом mock и без
# кода офиса: имя, шапка и ID те же, а настоящий файл не меняется.
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
LINUX_DIR="$(cd "$HERE/.." && pwd)"
SECONDS_LIMIT="${1:-0}"
BOTS="${2:-4}"
PORT=47792
PYTHON="$LINUX_DIR/.venv/bin/python"
[ -x "$PYTHON" ] || PYTHON=python3

CFG="$(mktemp -d)"
trap 'kill "${MOCK:-}" 2>/dev/null || true; rm -rf "$CFG"' EXIT
mkdir -p "$CFG/HomeView"
if [ -f "$HOME/.config/HomeView/HomeViewLinux.conf" ]; then
    sed -E '/^(serverAddress|officeCode)=/d' "$HOME/.config/HomeView/HomeViewLinux.conf" > "$CFG/HomeView/HomeViewLinux.conf"
else
    echo "[General]" > "$CFG/HomeView/HomeViewLinux.conf"
fi
sed -i "/^\[General\]/a serverAddress=127.0.0.1:$PORT" "$CFG/HomeView/HomeViewLinux.conf"

(cd "$HERE" && cargo build --release --quiet --bin homeview)
"$PYTHON" "$LINUX_DIR/tools/mock_server.py" --bots "$BOTS" --port "$PORT" > "$CFG/mock.log" 2>&1 &
MOCK=$!
sleep 1.5
echo "mock: $BOTS бота на 127.0.0.1:$PORT (журнал: $CFG/mock.log)"
XDG_CONFIG_HOME="$CFG" "$HERE/target/release/homeview" --seconds "$SECONDS_LIMIT"
