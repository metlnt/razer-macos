#!/bin/zsh
# Builds NagaControl.app into ./build
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release --package-path NagaControl
APP=build/NagaControl.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp NagaControl/.build/release/NagaControl "$APP/Contents/MacOS/"

# App icon from NagaControl/Icon/icon-1024.png (regenerate with: swift NagaControl/Icon/make-icon.swift <png>)
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s NagaControl/Icon/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) NagaControl/Icon/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Naga Control</string>
  <key>CFBundleIdentifier</key><string>local.nagacontrol</string>
  <key>CFBundleExecutable</key><string>NagaControl</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force -s - "$APP"
echo "Built $APP"
