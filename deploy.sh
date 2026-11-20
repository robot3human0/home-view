#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# HomeView — Mac mini'da BITTA buyruq:
#   1) ilovani yig‘adi (DMG),
#   2) uni yuklab olish sahifasiga joylaydi,
#   3) serverni yangilab, qayta ishga tushiradi.
# Ulangan hamkasblarga darhol "HomeView X chiqdi — yuklab olish" xabari boradi.
#
#   ./deploy.sh
#   ./deploy.sh "Arqon tortishda yangi jamoa ranglari"     — yangiliklar matni bilan
#   HOMEVIEW_CODE=ofis2026 ./deploy.sh                    — ofis kodini almashtirish
# ─────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

NOTES="${1:-}"
PLIST_INFO="HomeView/Resources/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST_INFO")"
BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST_INFO")"
FILE="HomeView-$VERSION.dmg"
DOWNLOADS="$HOME/HomeViewServer/downloads"

echo "━━━ 1/3  Ilova yig‘ilmoqda: HomeView $VERSION (build $BUILD)"
(cd HomeView && NO_OPEN=1 ./make_dmg.sh)

echo "━━━ 2/3  Yuklab olish sahifasiga joylanmoqda..."
mkdir -p "$DOWNLOADS"
rm -f "$DOWNLOADS"/HomeView-*.dmg
cp "HomeView/dist/$FILE" "$DOWNLOADS/$FILE"
ESCAPED_NOTES="$(printf '%s' "$NOTES" | tr '\n\r\t' '   ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
cat > "$DOWNLOADS/latest.json.tmp" << JSONEOF
{"version": "$VERSION", "build": $BUILD, "file": "$FILE", "notes": "$ESCAPED_NOTES"}
JSONEOF
mv "$DOWNLOADS/latest.json.tmp" "$DOWNLOADS/latest.json"

echo "━━━ 3/3  Server yangilanmoqda..."
(cd HomeViewServer && ./install.sh)
