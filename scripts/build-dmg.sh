#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="SK Mole.app"
APP_PATH="$DIST_DIR/$APP_NAME"
README_SOURCE="$ROOT_DIR/README.md"
INFO_PLIST="$ROOT_DIR/Resources/Bundling/Info.plist.template"
ICON_PATH="$ROOT_DIR/Resources/AppIcon.icns"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
DMG_NAME="SK-Mole-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
VOLUME_NAME="SK Mole ${VERSION}"

"$ROOT_DIR/scripts/build-app.sh"

if [[ ! -d "$APP_PATH" ]]; then
    echo "Expected app bundle at $APP_PATH but it was not found." >&2
    exit 1
fi

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/skmole-dmg.XXXXXX")"
STAGING_DIR="$TMP_ROOT/staging"
mkdir -p "$STAGING_DIR"

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

cp -R "$APP_PATH" "$STAGING_DIR/$APP_NAME"
if [[ -f "$README_SOURCE" ]]; then
    cp "$README_SOURCE" "$STAGING_DIR/README.md"
fi
ln -s /Applications "$STAGING_DIR/Applications"

if [[ -f "$ICON_PATH" ]]; then
    cp "$ICON_PATH" "$STAGING_DIR/.VolumeIcon.icns"
    SetFile -a C "$STAGING_DIR" || true
fi

rm -f "$DMG_PATH"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo "Built DMG at:"
echo "  $DMG_PATH"
