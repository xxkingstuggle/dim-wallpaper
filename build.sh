#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DimWallpaper"
DIST="dist"
APP="$DIST/$APP_NAME.app"
ICONSET="$DIST/AppIcon.iconset"
ARCH="${ARCH:-$(uname -m)}"

if [[ -e "$DIST" ]]; then /usr/bin/trash "$DIST"; fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"

# --- icon ---
swiftc -O Tools/makeicon.swift -o "$DIST/makeicon"
"$DIST/makeicon" "$DIST/AppIcon_1024.png" >/dev/null

make_icon() { # size filename
    sips -z "$1" "$1" "$DIST/AppIcon_1024.png" --out "$ICONSET/$2" >/dev/null
}
make_icon 16   icon_16x16.png
make_icon 32   icon_16x16@2x.png
make_icon 32   icon_32x32.png
make_icon 64   icon_32x32@2x.png
make_icon 128  icon_128x128.png
make_icon 256  icon_128x128@2x.png
make_icon 256  icon_256x256.png
make_icon 512  icon_256x256@2x.png
make_icon 512  icon_512x512.png
make_icon 1024 icon_512x512@2x.png
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# --- binary ---
swiftc -O -whole-module-optimization \
    -swift-version 6 \
    -target "${ARCH}-apple-macos13.0" \
    Sources/DimWallpaperCore/*.swift \
    Sources/DimWallpaperApp/*.swift \
    -o "$APP/Contents/MacOS/$APP_NAME" \
    -framework AppKit \
    -framework SwiftUI \
    -framework ServiceManagement \
    -framework Carbon

cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --sign - --identifier local.zjx.DimWallpaper "$APP"

echo "built $APP"
