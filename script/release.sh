#!/usr/bin/env bash
# Builds a release of Cliplight: universal (Apple silicon + Intel) app, signed, optionally notarized,
# packaged as a zip and a dmg with SHA-256 checksums in dist/release/.
#
# Environment:
#   DEVELOPER_ID    "Developer ID Application: Name (TEAMID)". Without it the app is signed ad hoc
#                   (fine for testing; users will see Gatekeeper warnings).
#   NOTARY_PROFILE  Keychain profile created with `xcrun notarytool store-credentials`. Requires DEVELOPER_ID.
#   BUNDLE_ID       Defaults to local.cliplight.app (changing it resets users' settings and history key).
#   VERSION         Defaults to the VERSION file.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
APP_NAME="Cliplight"
VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"
OUT="$ROOT_DIR/dist/release"
APP="$OUT/$APP_NAME.app"
export VERSION
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || { echo "Invalid VERSION" >&2; exit 1; }
if [[ -n "${NOTARY_PROFILE:-}" && -z "${DEVELOPER_ID:-}" ]]; then
  echo "NOTARY_PROFILE requires DEVELOPER_ID" >&2; exit 1
fi

echo "==> Checks"
./script/check.sh

echo "==> Building $APP_NAME $VERSION (arm64 + x86_64)"
rm -rf "$OUT"; mkdir -p "$OUT"
for arch in arm64 x86_64; do
  swift build -c release --triple "$arch-apple-macosx14.0" --scratch-path ".build/release-$arch"
done
lipo -create -output "$OUT/$APP_NAME" \
  "$(swift build -c release --triple arm64-apple-macosx14.0 --scratch-path .build/release-arm64 --show-bin-path)/$APP_NAME" \
  "$(swift build -c release --triple x86_64-apple-macosx14.0 --scratch-path .build/release-x86_64 --show-bin-path)/$APP_NAME"
lipo -info "$OUT/$APP_NAME"
./script/make_app.sh "$OUT/$APP_NAME" "$APP"
rm "$OUT/$APP_NAME"

echo "==> Signing"
if [[ -n "${DEVELOPER_ID:-}" ]]; then
  codesign --force --timestamp --options runtime --sign "$DEVELOPER_ID" "$APP"
else
  echo "    DEVELOPER_ID not set: signing ad hoc. Draft verification only: do not publish as a stable installer."
  codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"

ZIP="$OUT/$APP_NAME-$VERSION.zip"
DMG="$OUT/$APP_NAME-$VERSION.dmg"
ditto -c -k --keepParent "$APP" "$ZIP"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  [[ -n "${DEVELOPER_ID:-}" ]] || { echo "NOTARY_PROFILE needs DEVELOPER_ID" >&2; exit 1; }
  echo "==> Notarizing app"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"
fi

echo "==> Disk image"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
if [[ -n "${DEVELOPER_ID:-}" ]]; then
  codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "==> Notarizing disk image"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

SIGNING_STATUS="AD-HOC / NOT NOTARIZED — draft verification only"
if [[ -n "${DEVELOPER_ID:-}" ]]; then SIGNING_STATUS="Developer ID signed / NOT NOTARIZED"; fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then SIGNING_STATUS="Developer ID signed / NOTARIZED AND STAPLED"; fi
{
  printf 'Cliplight %s\n' "$VERSION"
  printf 'Source: https://github.com/QuantumCoderSys/cliplight\n'
  printf 'Commit: %s\n' "$(git rev-parse HEAD 2>/dev/null || echo uncommitted)"
  printf 'Signing: %s\n' "$SIGNING_STATUS"
  printf 'Architectures: %s\n' "$(lipo -archs "$APP/Contents/MacOS/Cliplight")"
  printf 'Deployment target: macOS 14.0\n'
  printf 'Built (UTC): %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  swift --version
} > "$OUT/BUILD-INFO.txt"
(cd "$OUT" && shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" BUILD-INFO.txt > SHA256SUMS.txt)
echo "==> Done"
cat "$OUT/SHA256SUMS.txt"
echo "Homebrew cask sha256 (zip): $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
