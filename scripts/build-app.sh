#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/SK Mole.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
LIBRARY_DIR="$CONTENTS_DIR/Library"
LAUNCH_SERVICES_DIR="$LIBRARY_DIR/LaunchServices"
LAUNCH_DAEMONS_DIR="$LIBRARY_DIR/LaunchDaemons"
LOGIN_ITEMS_DIR="$LIBRARY_DIR/LoginItems"
ICON_PATH="$ROOT_DIR/Resources/AppIcon.icns"
INFO_TEMPLATE="$ROOT_DIR/Resources/Bundling/Info.plist.template"
MENU_BAR_HELPER_INFO_TEMPLATE="$ROOT_DIR/Resources/Bundling/MenuBarHelper-Info.plist.template"
HELPER_PLIST_TEMPLATE="$ROOT_DIR/Resources/Bundling/com.siveesh.skmole.privilegedhelper.plist.template"
SOURCE_ICON="$ROOT_DIR/Resources/AppIcon-source.png"
SIGN_IDENTITY="${SKMOLE_CODESIGN_IDENTITY:--}"

mkdir -p "$DIST_DIR"

if [[ -f "$SOURCE_ICON" ]]; then
    "$ROOT_DIR/scripts/build-icon.sh" "$SOURCE_ICON"
fi

swift build -c release --package-path "$ROOT_DIR" --product SKMoleApp
swift build -c release --package-path "$ROOT_DIR" --product SKMolePrivilegedHelper
swift build -c release --package-path "$ROOT_DIR" --product SKMoleMenuBarHelper

BUILD_DIR="$(swift build -c release --show-bin-path --package-path "$ROOT_DIR")"
BINARY_PATH="$BUILD_DIR/SKMoleApp"
HELPER_BINARY_PATH="$BUILD_DIR/SKMolePrivilegedHelper"
MENU_BAR_HELPER_BINARY_PATH="$BUILD_DIR/SKMoleMenuBarHelper"
MENU_BAR_HELPER_APP_DIR="$LOGIN_ITEMS_DIR/SK Mole Companion.app"
MENU_BAR_HELPER_CONTENTS_DIR="$MENU_BAR_HELPER_APP_DIR/Contents"
MENU_BAR_HELPER_MACOS_DIR="$MENU_BAR_HELPER_CONTENTS_DIR/MacOS"
MENU_BAR_HELPER_RESOURCES_DIR="$MENU_BAR_HELPER_CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$LAUNCH_SERVICES_DIR" "$LAUNCH_DAEMONS_DIR" "$LOGIN_ITEMS_DIR" "$MENU_BAR_HELPER_MACOS_DIR" "$MENU_BAR_HELPER_RESOURCES_DIR"

cp "$BINARY_PATH" "$MACOS_DIR/SK Mole"
chmod +x "$MACOS_DIR/SK Mole"
cp "$INFO_TEMPLATE" "$CONTENTS_DIR/Info.plist"
cp "$HELPER_BINARY_PATH" "$LAUNCH_SERVICES_DIR/com.siveesh.skmole.privilegedhelper"
chmod +x "$LAUNCH_SERVICES_DIR/com.siveesh.skmole.privilegedhelper"
cp "$HELPER_PLIST_TEMPLATE" "$LAUNCH_DAEMONS_DIR/com.siveesh.skmole.privilegedhelper.plist"
cp "$MENU_BAR_HELPER_BINARY_PATH" "$MENU_BAR_HELPER_MACOS_DIR/SK Mole Companion"
chmod +x "$MENU_BAR_HELPER_MACOS_DIR/SK Mole Companion"
cp "$MENU_BAR_HELPER_INFO_TEMPLATE" "$MENU_BAR_HELPER_CONTENTS_DIR/Info.plist"

if [[ -f "$ICON_PATH" ]]; then
    cp "$ICON_PATH" "$RESOURCES_DIR/AppIcon.icns"
    cp "$ICON_PATH" "$MENU_BAR_HELPER_RESOURCES_DIR/AppIcon.icns"
fi

if command -v codesign >/dev/null 2>&1; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$LAUNCH_SERVICES_DIR/com.siveesh.skmole.privilegedhelper"
    codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$MENU_BAR_HELPER_APP_DIR"
    codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP_DIR"
fi

echo "Built app bundle at:"
echo "  $APP_DIR"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "Note: using ad-hoc signing. Set SKMOLE_CODESIGN_IDENTITY to a real Apple certificate for privileged helper registration."
fi
