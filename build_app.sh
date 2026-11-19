#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="/tmp/terrarium-build"
APP_DIR="$BUILD_DIR/TerrariumMenuBar.app"

swift build -c release --package-path "$SCRIPT_DIR" --scratch-path "$BUILD_DIR"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/release/TerrariumMenuBar" "$APP_DIR/Contents/MacOS/TerrariumMenuBar"
strip -x "$APP_DIR/Contents/MacOS/TerrariumMenuBar"

if [ -x "/Applications/Xcode.app/Contents/Developer/usr/bin/actool" ]; then
  python3 "$SCRIPT_DIR/scripts/compile_assets_car.py" \
    "$SCRIPT_DIR/Sources/TerrariumMenuBar/Resources/Pixel" \
    "$APP_DIR/Contents/Resources"
else
  echo "WARNING: Xcode actool not found, falling back to raw resource bundle"
  cp -R "$BUILD_DIR/release/TerrariumMenuBar_TerrariumMenuBar.bundle" "$APP_DIR/Contents/Resources/"
fi

if [ -f "$SCRIPT_DIR/Sources/TerrariumMenuBar/Resources/AppIcon.icns" ]; then
  cp "$SCRIPT_DIR/Sources/TerrariumMenuBar/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>TerrariumMenuBar</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.ccgs.TerrariumMenuBar</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>TerrariumMenuBar</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>100</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$APP_DIR"
echo "Built app bundle: $APP_DIR"
