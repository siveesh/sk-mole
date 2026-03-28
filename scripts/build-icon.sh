#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_IMAGE="${1:-$ROOT_DIR/Resources/AppIcon-source.png}"
ICONSET_DIR="$ROOT_DIR/Resources/Icon.iconset"
ICNS_PATH="$ROOT_DIR/Resources/AppIcon.icns"

mkdir -p "$ICONSET_DIR"

if [[ ! -f "$SOURCE_IMAGE" ]]; then
    echo "Source image not found: $SOURCE_IMAGE" >&2
    exit 1
fi

generate_icon() {
    local size="$1"
    local output="$2"
    sips -z "$size" "$size" "$SOURCE_IMAGE" --out "$output" >/dev/null
}

generate_icon 16 "$ICONSET_DIR/icon_16x16.png"
generate_icon 32 "$ICONSET_DIR/icon_16x16@2x.png"
generate_icon 32 "$ICONSET_DIR/icon_32x32.png"
generate_icon 64 "$ICONSET_DIR/icon_32x32@2x.png"
generate_icon 128 "$ICONSET_DIR/icon_128x128.png"
generate_icon 256 "$ICONSET_DIR/icon_128x128@2x.png"
generate_icon 256 "$ICONSET_DIR/icon_256x256.png"
generate_icon 512 "$ICONSET_DIR/icon_256x256@2x.png"
generate_icon 512 "$ICONSET_DIR/icon_512x512.png"
generate_icon 1024 "$ICONSET_DIR/icon_512x512@2x.png"

rm -f "$ICNS_PATH"
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

echo "Built icon asset at:"
echo "  $ICNS_PATH"
