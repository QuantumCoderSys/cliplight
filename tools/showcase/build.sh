#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"
APP="$ROOT_DIR/.build/Cliplight Showcase.app"
mkdir -p "$APP/Contents/MacOS"
swiftc -g -parse-as-library -swift-version 5 -D DEBUG -o "$APP/Contents/MacOS/CliplightShowcase" \
  Sources/Cliplight/Models/*.swift Sources/Cliplight/Stores/*.swift \
  Sources/Cliplight/Services/*.swift Sources/Cliplight/Views/*.swift tools/showcase/Showcase.swift
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>CliplightShowcase</string><key>CFBundleIdentifier</key><string>local.cliplight.showcase</string><key>CFBundleName</key><string>Cliplight Showcase</string><key>CFBundlePackageType</key><string>APPL</string><key>NSPrincipalClass</key><string>NSApplication</string><key>LSMinimumSystemVersion</key><string>14.0</string></dict></plist>
PLIST
codesign --force --sign - "$APP"
printf '%s\n' "$APP"
