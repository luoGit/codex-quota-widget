#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
APP_NAME="Codex Quota Widget"
EXECUTABLE_NAME="CodexQuotaWidget"
BUNDLE_ID="com.wendy.codex-quota-widget"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
DMG_PATH="$DIST_DIR/CodexQuotaWidget-$VERSION.dmg"
ZIP_PATH="$DIST_DIR/CodexQuotaWidget-$VERSION.zip"

if [[ ! -f "$ROOT_DIR/assets/AppIcon.icns" ]]; then
  "$SCRIPT_DIR/generate_app_icon.sh"
fi

rm -rf "$DIST_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
mkdir -p "$ROOT_DIR/.build-cache/clang/ModuleCache"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build-cache/clang/ModuleCache"

swiftc \
  -O \
  -module-name "$EXECUTABLE_NAME" \
  -o "$CONTENTS_DIR/MacOS/$EXECUTABLE_NAME" \
  "$ROOT_DIR"/Sources/CodexQuotaWidget/*.swift \
  -framework AppKit
chmod +x "$CONTENTS_DIR/MacOS/$EXECUTABLE_NAME"

cp "$ROOT_DIR/assets/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
cp "$ROOT_DIR/LICENSE" "$CONTENTS_DIR/Resources/LICENSE"

sed \
  -e "s/__VERSION__/$VERSION/g" \
  -e "s/__BUILD__/$BUILD_NUMBER/g" \
  "$ROOT_DIR/packaging/Info.plist" > "$CONTENTS_DIR/Info.plist"

plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null

xattr -cr "$APP_BUNDLE"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH" >/dev/null

echo "Packaged $APP_NAME $VERSION (build $BUILD_NUMBER)"
echo "  App: $APP_BUNDLE"
echo "  DMG: $DMG_PATH"
echo "  ZIP: $ZIP_PATH"
