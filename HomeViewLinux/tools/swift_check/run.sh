#!/usr/bin/env bash
# Проверка совместимости Linux-клиента с настоящим Swift-протоколом HomeView (HomeViewProtocol).
#
#   1. Python- и Rust-клиенты пишут все сообщения, которые отправляют;
#   2. в Docker-контейнере swift:6.0-noble собирается HomeViewProtocol iOS-команды, и его
#      JSONDecoder декодирует эти сообщения, а JSONEncoder кодирует набор сообщений сервера;
#   3. Python и Rust разбирают сообщения сервера своими декодерами.
#
# Запуск: ./HomeViewLinux/tools/swift_check/run.sh
# Нужен Docker. Первый запуск скачает образ swift:6.0-noble (~1 ГБ).
# В рабочую копию ничего не пишется: протокол монтируется только для чтения,
# сборка — во временной папке контейнера, обмен файлами — через временный каталог.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
LINUX_DIR="$(cd "$HERE/../.." && pwd)"
REPO="$(cd "$LINUX_DIR/.." && pwd)"
PYTHON="$LINUX_DIR/.venv/bin/python"
[ -x "$PYTHON" ] || PYTHON=python3
IMAGE="${SWIFT_IMAGE:-swift:6.0-noble}"
RUST_DIR="$LINUX_DIR/rust"
RUST_CHECK="$RUST_DIR/target/release/protocol_check"

if ! command -v docker >/dev/null; then
    echo "Нужен Docker: https://docs.docker.com/engine/install/ubuntu/" >&2
    exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "== 1/3 Сообщения Linux-клиентов"
"$PYTHON" "$HERE/messages.py" write-client "$WORK/python.jsonl"
if command -v cargo >/dev/null; then
    (cd "$RUST_DIR" && cargo build --release --quiet --bin protocol_check)
    "$RUST_CHECK" write-client "$WORK/rust.jsonl"
else
    echo "cargo не найден — Rust-клиент пропускаю" >&2
    : > "$WORK/rust.jsonl"
fi
cat "$WORK/python.jsonl" "$WORK/rust.jsonl" > "$WORK/client_messages.jsonl"

echo "== 2/3 Swift ($IMAGE): сборка HomeViewProtocol и декодирование"
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$REPO/HomeViewProtocol:/HomeViewProtocol:ro" \
    -v "$HERE:/src:ro" \
    -v "$WORK:/work" \
    "$IMAGE" bash -c '
        set -e
        mkdir -p /tmp/check && cp -r /src/Package.swift /src/Sources /tmp/check/
        cd /tmp/check
        swift build -c release 2>&1 | grep -E "error|Build complete" || true
        .build/release/Check
    '

echo "== 3/3 Сообщения Swift-сервера → декодеры Linux-клиентов"
"$PYTHON" "$HERE/messages.py" verify-server "$WORK/server_messages.jsonl"
if [ -s "$WORK/rust.jsonl" ]; then
    "$RUST_CHECK" verify-server "$WORK/server_messages.jsonl"
fi

echo
echo "✅ Совместимость с HomeViewProtocol подтверждена"
