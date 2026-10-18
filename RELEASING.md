# Releasing Cliplight

The repository is `QuantumCoderSys/cliplight`. The app bundle identifier remains `local.cliplight.app` to preserve existing settings and encryption-key access.

## Current distribution status

Version 1.0.0 is staged for a first release. Universal installers can be built locally, but no Developer ID Application certificate is installed on the preparation Mac. Ad-hoc artifacts may be attached to a **draft** for verification. Publish the stable installer only after Developer ID signing and notarization.

Source builds are available independently of installer distribution. Homebrew is not advertised because no tap has been published.

## Prepare a version

1. Set the semantic version in `VERSION` and add its notes to `CHANGELOG.md`.
2. Run `./script/check.sh` and `swift build`.
3. Smoke-test capture, ⇧⌘V, direct paste into an editable app, ⇧ Return, ⌘K, Quick Look, snippets, and expiry. Do not enable iCloud sync with personal data for a release test.
4. Refresh the images with the isolated [showcase renderer](tools/showcase).
5. Commit the final source, documentation, and images.

## Build and validate

```sh
./script/release.sh
```

This runs the checks, builds arm64 and x86_64 in release mode, creates a universal app, verifies its signature, and produces:

```text
dist/release/Cliplight.app
dist/release/Cliplight-1.0.0.zip
dist/release/Cliplight-1.0.0.dmg
dist/release/SHA256SUMS.txt
dist/release/BUILD-INFO.txt
```

Without a Developer ID, the artifacts are marked `AD-HOC / NOT NOTARIZED`. Keep them in a draft. `BUILD-INFO.txt` records the source revision, toolchain, architectures, and signing status.

```sh
(cd dist/release && shasum -a 256 -c SHA256SUMS.txt)
lipo -archs dist/release/Cliplight.app/Contents/MacOS/Cliplight
codesign --verify --strict dist/release/Cliplight.app
hdiutil verify dist/release/Cliplight-1.0.0.dmg
```

## Sign and notarize

A paid Apple Developer account, Developer ID Application certificate, and notarization credentials are required. Set up the certificate on the signing Mac; never commit it or any private key.

Store notarization credentials once using Apple's `xcrun notarytool store-credentials`, then build:

```sh
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=cliplight-notary \
./script/release.sh
```

The script signs with hardened runtime, submits the app and DMG to Apple's notary service, and staples both. Confirm `spctl --assess --type execute --verbose=2 dist/release/Cliplight.app` accepts the final app before publishing. Review the report in `BUILD-INFO.txt` and verify the checksums again.

## Prepare the GitHub draft

After committing, dispatch **Prepare release draft** from the Actions tab. It validates the version, runs the universal build, and creates or updates the draft with installer files, checksums, provenance, and release notes. It never publishes a stable release automatically.

The workflow is deliberately ad-hoc unless the release is rebuilt on a configured signing Mac. Replace draft assets with the signed, notarized outputs before publication.

Manual equivalent from the source commit being released:

```sh
gh release create v1.0.0 --repo QuantumCoderSys/cliplight --draft --target main \
  --title "Cliplight 1.0.0" --notes-file packaging/release-notes.md \
  dist/release/Cliplight-1.0.0.zip dist/release/Cliplight-1.0.0.dmg \
  dist/release/SHA256SUMS.txt dist/release/BUILD-INFO.txt
```

## Publish

1. Replace all draft assets with signed, notarized outputs from the exact release commit.
2. Remove the draft's unsigned-build notice and verify every download.
3. Update the README's installation status.
4. Publish the draft and mark it as the latest stable release.

Homebrew distribution can be added after the first signed release. Create a cask using the final signed ZIP URL and checksum, and publish it to a tap before documenting a Homebrew install command.
