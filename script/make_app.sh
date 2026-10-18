#!/usr/bin/env bash
# Assembles Cliplight.app around a built executable.
# usage: script/make_app.sh <executable> <output .app path>
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY="$1"
APP_BUNDLE="$2"
APP_NAME="Cliplight"
BUNDLE_ID="${BUNDLE_ID:-local.cliplight.app}"
VERSION="${VERSION:-$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)}"
YEAR="$(date +%Y)"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundleDisplayName</key><string>$APP_NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>© $YEAR Sarthak Rawool. MIT License.</string>
<key>NSPasteboardUsageDescription</key><string>Cliplight remembers copied items so you can search and paste them again.</string>
</dict></plist>
PLIST
ICONSET="$ROOT_DIR/.build/AppIcon.iconset"
ICNS="$ROOT_DIR/.build/AppIcon.icns"
if [[ ! -f "$ICNS" || "$ROOT_DIR/script/CreateIcon.swift" -nt "$ICNS" ]]; then
  swift "$ROOT_DIR/script/CreateIcon.swift" "$ICONSET"
  iconutil -c icns "$ICONSET" -o "$ICNS"
fi
cp "$ICNS" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
