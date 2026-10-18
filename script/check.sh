#!/usr/bin/env bash
# Compiles the app's non-UI sources with Checks/ClipboardChecks.swift and runs them.
# Works with Command Line Tools alone (no Xcode or XCTest needed).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p .build
swiftc -parse-as-library -swift-version 5 -o .build/ClipboardChecks \
  Sources/Cliplight/Models/*.swift \
  Sources/Cliplight/Stores/*.swift \
  Sources/Cliplight/Services/ClipboardMonitor.swift \
  Sources/Cliplight/Services/ImageText.swift \
  Sources/Cliplight/Services/Keychain.swift \
  Sources/Cliplight/Services/HotKeyManager.swift \
  Sources/Cliplight/Services/SyncService.swift \
  Checks/ClipboardChecks.swift
.build/ClipboardChecks
