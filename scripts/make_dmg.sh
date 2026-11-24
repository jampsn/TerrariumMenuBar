#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="/tmp/terrarium-build/TerrariumMenuBar.app"

if [ ! -d "$APP_PATH" ]; then
  echo "App bundle not found at $APP_PATH. Please run ./build_app.sh first." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
ICON_PATH="$APP_PATH/Contents/Resources/AppIcon.icns"
OUT_DIR="$SCRIPT_DIR/release"
DMG_PATH="$OUT_DIR/TerrariumMenuBar-${VERSION}.dmg"
STAGE_DIR="/tmp/terrarium-dmg-staging"

mkdir -p "$OUT_DIR"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

ditto "$APP_PATH" "$STAGE_DIR/TerrariumMenuBar.app"
ln -s /Applications "$STAGE_DIR/Applications"

# 设置挂载后的磁盘卷图标
if [ -f "$ICON_PATH" ]; then
  cp "$ICON_PATH" "$STAGE_DIR/.VolumeIcon.icns"
  if command -v SetFile >/dev/null 2>&1; then
    SetFile -c icnC "$STAGE_DIR/.VolumeIcon.icns"
    SetFile -a C "$STAGE_DIR"
  fi
fi

rm -f "$DMG_PATH"
hdiutil create \
  -volname "Pixel Terrarium ${VERSION}" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$STAGE_DIR"

# 为 .dmg 文件本身写入自定义 Finder 图标
if [ -f "$ICON_PATH" ]; then
  ICON_SCRIPT="/tmp/set_dmg_icon.swift"
  cat > "$ICON_SCRIPT" << 'EOF'
import AppKit
let args = CommandLine.arguments
if args.count == 3, let img = NSImage(contentsOfFile: args[1]) {
    NSWorkspace.shared.setIcon(img, forFile: args[2], options: [])
}
EOF
  swift "$ICON_SCRIPT" "$ICON_PATH" "$DMG_PATH"
  rm -f "$ICON_SCRIPT"
fi

hdiutil verify "$DMG_PATH"
echo "Created DMG with icon: $DMG_PATH"
