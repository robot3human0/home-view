#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# HomeView — bitta buyruq bilan .app va .dmg yig'ish.
#
#   ./make_dmg.sh
#
# Natija: dist/HomeView-<versiya>.dmg  (versiya Resources/Info.plist'dan olinadi)
#
# Ixtiyoriy (boshqalarga tarqatish uchun imzolash + notarizatsiya):
#   DEVELOPER_ID="Developer ID Application: Ism Familiya (TEAMID)" \
#   NOTARY_PROFILE="homeview-notary" ./make_dmg.sh
# ─────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="HomeView"
EXEC_NAME="HomeView"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)"
DIST="dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/HomeView-$VERSION.dmg"

echo "❄️  1/4  Kompilyatsiya (release)..."
if swift build -c release --arch arm64 --arch x86_64 >/dev/null 2>&1; then
  BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
  echo "    Universal build tayyor (Apple Silicon + Intel)."
else
  echo "    Universal build bo'lmadi — shu Mac arxitekturasi uchun yig'yapman..."
  swift build -c release
  BIN_DIR="$(swift build -c release --show-bin-path)"
fi

echo "❄️  2/4  .app paketini yig'ish..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXEC_NAME" "$APP/Contents/MacOS/$EXEC_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Realistik rasmlar (odamlar, qorbola, Qorbobo, mashinalar, qushlar, ob-havo)
if [[ -d Art ]]; then
  mkdir -p "$APP/Contents/Resources/Art"
  cp Art/*.png "$APP/Contents/Resources/Art/"
fi
# macOS 26: Icon Composer ikonkasi (AppStore/AppIcon.icon) Liquid Glass bilan kompilyatsiya qilinadi
ICON_TMP="$(mktemp -d)"
if xcrun actool AppStore/AppIcon.icon --compile "$ICON_TMP" --platform macosx \
     --minimum-deployment-target 26.0 --app-icon AppIcon \
     --output-partial-info-plist "$ICON_TMP/partial.plist" >/dev/null 2>&1 && [[ -f "$ICON_TMP/Assets.car" ]]; then
  cp "$ICON_TMP/Assets.car" "$APP/Contents/Resources/Assets.car"
  [[ -f "$ICON_TMP/AppIcon.icns" ]] && cp "$ICON_TMP/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
  echo "    Liquid Glass ikonka qo'shildi."
else
  echo "    Liquid Glass ikonkani kompilyatsiya qilib bo'lmadi — oddiy ikonka ishlatiladi."
fi
rm -rf "$ICON_TMP"

echo "❄️  3/4  Imzolash..."
if [[ -n "${DEVELOPER_ID:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
  echo "    Developer ID bilan imzolandi."
else
  codesign --force --sign - "$APP"
  echo "    Mahalliy (ad-hoc) imzo qo'yildi — o'z Mac'ingiz uchun yetarli."
fi

echo "❄️  4/4  DMG yaratish..."
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [[ -n "${DEVELOPER_ID:-}" && -n "${NOTARY_PROFILE:-}" ]]; then
  echo "❄️  Notarizatsiya (Apple serverida tekshiruv, bir necha daqiqa)..."
  codesign --force --sign "$DEVELOPER_ID" --timestamp "$DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo ""
echo "✅ Tayyor: $DMG"
echo "   Ochib, 'HomeView'ni Applications papkasiga torting."
if [[ -z "${NO_OPEN:-}" ]]; then
  open "$DIST" 2>/dev/null || true
fi
