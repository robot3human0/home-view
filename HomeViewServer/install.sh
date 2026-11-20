#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# HomeView serverini Mac mini'ga o‘rnatish (yoki yangilash).
#
#   ./install.sh                         — o‘rnatish / yangilash (ofis kodi saqlanib qoladi)
#   HOMEVIEW_CODE=ofis2026 ./install.sh  — ofis kodini o‘rnatish yoki almashtirish
#   HOMEVIEW_CODE= ./install.sh          — ofis kodini olib tashlash
#
# Nima qiladi:
#   1. Serverni yig‘adi (swift build).
#   2. ~/HomeViewServer papkasiga ko‘chiradi (yuklab olish papkasi ham shu yerda).
#   3. Eski "Qorli Kun" serveri bo‘lsa — to‘xtatadi va ofis kodini undan oladi.
#   4. launchd "navbatchi"siga topshiradi: Mac mini yoqilganda server o‘zi ishga tushadi,
#      to‘xtab qolsa — qayta yoqiladi.
# ─────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

LABEL="uz.homeview.server"
INSTALL_DIR="$HOME/HomeViewServer"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
OLD_LABEL="uz.qorlikun.server"
OLD_PLIST="$HOME/Library/LaunchAgents/$OLD_LABEL.plist"
BUDDY="/usr/libexec/PlistBuddy"

read_env() {  # read_env <plist> <kalit>
  "$BUDDY" -c "Print :EnvironmentVariables:$2" "$1" 2>/dev/null || true
}

# Ofis kodi: buyruqda berilgan > hozirgi o‘rnatilgan > eski Qorli Kun serveridagi > yo‘q
if [[ -n "${HOMEVIEW_CODE+x}" ]]; then
  CODE="$HOMEVIEW_CODE"
elif [[ -f "$PLIST" ]]; then
  CODE="$(read_env "$PLIST" HOMEVIEW_CODE)"
elif [[ -f "$OLD_PLIST" ]]; then
  CODE="$(read_env "$OLD_PLIST" QORLIKUN_CODE)"
else
  CODE=""
fi
PORT="${HOMEVIEW_PORT:-47777}"
DOWNLOAD_PORT="${HOMEVIEW_DOWNLOAD_PORT:-47778}"
NAME="${HOMEVIEW_NAME:-HomeView ofisi}"
if [[ -n "${HOMEVIEW_PUBLIC_HOST+x}" ]]; then
  PUBLIC_HOST="$HOMEVIEW_PUBLIC_HOST"
elif [[ -f "$PLIST" ]]; then
  PUBLIC_HOST="$(read_env "$PLIST" HOMEVIEW_PUBLIC_HOST)"
else
  PUBLIC_HOST=""
fi

echo "🏡  1/3  Server yig‘ilmoqda..."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "🏡  2/3  $INSTALL_DIR ga ko‘chirilmoqda..."
mkdir -p "$INSTALL_DIR/downloads"
cp "$BIN_DIR/HomeViewServer" "$INSTALL_DIR/HomeViewServer"

if [[ -f "$OLD_PLIST" ]]; then
  echo "        Eski Qorli Kun serveri to‘xtatilmoqda (port bo‘shasin)..."
  launchctl bootout "gui/$(id -u)/$OLD_LABEL" 2>/dev/null || true
  rm -f "$OLD_PLIST"
fi

echo "🏡  3/3  Avtomatik ishga tushish sozlanmoqda..."
mkdir -p "$HOME/Library/LaunchAgents"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
cat > "$PLIST" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/HomeViewServer</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOMEVIEW_PORT</key>
        <string>$PORT</string>
        <key>HOMEVIEW_DOWNLOAD_PORT</key>
        <string>$DOWNLOAD_PORT</string>
        <key>HOMEVIEW_NAME</key>
        <string>$NAME</string>
        <key>HOMEVIEW_CODE</key>
        <string>$CODE</string>
        <key>HOMEVIEW_PUBLIC_HOST</key>
        <string>$PUBLIC_HOST</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardOutPath</key>
    <string>$INSTALL_DIR/server.log</string>
    <key>StandardErrorPath</key>
    <string>$INSTALL_DIR/server.log</string>
</dict>
</plist>
PLISTEOF
launchctl bootstrap "gui/$(id -u)" "$PLIST"

sleep 1
HOSTNAME_LOCAL="$(scutil --get LocalHostName 2>/dev/null || hostname -s).local"
IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "noma’lum")"
SHOWN_HOST="${PUBLIC_HOST:-$HOSTNAME_LOCAL}"
echo ""
echo "✅ Server ishlayapti."
echo "   Ofis kodi: $([[ -n "$CODE" ]] && echo "bor" || echo "yo‘q")"
echo "   Ilovalar serverni o‘zi topadi (Bonjour). Qo‘lda: $IP:$PORT"
echo "   Yuklab olish sahifasi: http://$SHOWN_HOST:$DOWNLOAD_PORT/   (yoki http://$IP:$DOWNLOAD_PORT/)"
echo "   Jurnal: tail -f $INSTALL_DIR/server.log"
