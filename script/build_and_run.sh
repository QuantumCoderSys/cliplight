#!/usr/bin/env bash
# Development build: compiles a debug build, wraps it in dist/Cliplight.app, signs it ad hoc, and opens it.
set -euo pipefail
MODE="${1:-run}"
APP_NAME="Cliplight"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
cd "$ROOT_DIR"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
swift build
"$ROOT_DIR/script/make_app.sh" "$(swift build --show-bin-path)/$APP_NAME" "$APP_BUNDLE"
codesign --force --sign - "$APP_BUNDLE" >/dev/null
case "$MODE" in
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --build-only) ;;
  --verify) /usr/bin/open -n "$APP_BUNDLE"; sleep 1; pgrep -x "$APP_NAME" >/dev/null ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
  --logs) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "Cliplight"' ;;
  --telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "local.cliplight.app"' ;;
  *) echo "usage: $0 [run|--build-only|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
