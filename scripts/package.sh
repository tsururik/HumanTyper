#!/bin/bash
# Собирает Release (Universal: Apple Silicon + Intel) и упаковывает в dist/HumanTyper.dmg
# с ярлыком «Программы» для перетаскивания.
#
# Запуск из любой папки:  scripts/package.sh
# Папки сборки можно переопределить: BUILD_DIR=… DIST_DIR=… scripts/package.sh
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR="${BUILD_DIR:-build}"
DIST_DIR="${DIST_DIR:-dist}"
APP="$BUILD_DIR/Build/Products/Release/HumanTyper.app"
DMG="$DIST_DIR/HumanTyper.dmg"

echo "→ Сборка Release…"
xcodebuild -quiet -project HumanTyper.xcodeproj -scheme HumanTyper -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath "$BUILD_DIR" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build

echo "→ Архитектуры: $(lipo -archs "$APP/Contents/MacOS/HumanTyper")"
codesign --verify --deep --strict "$APP"

echo "→ Упаковка в DMG…"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/HumanTyper.app"
ln -s /Applications "$STAGING/Applications"
mkdir -p "$DIST_DIR"
rm -f "$DMG"
hdiutil create -quiet -volname HumanTyper -srcfolder "$STAGING" -format UDZO "$DMG"

echo "✓ Готово: $DMG ($(du -h "$DMG" | cut -f1))"
