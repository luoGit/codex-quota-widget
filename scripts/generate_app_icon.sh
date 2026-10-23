#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build-cache"
PNG_PATH="$BUILD_DIR/AppIcon-1024.png"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
OUTPUT="$ROOT_DIR/assets/AppIcon.icns"

mkdir -p "$BUILD_DIR"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

xcrun swift "$SCRIPT_DIR/AppIconGenerator.swift" "$PNG_PATH"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$PNG_PATH" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$PNG_PATH" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT"
echo "Generated $OUTPUT"
