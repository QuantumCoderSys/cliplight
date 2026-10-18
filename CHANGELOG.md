# Changelog

All notable changes to Cliplight are documented here. This project follows [Semantic Versioning](https://semver.org).

## [1.0.0] - 2026-10-18

First public release.

### Added
- Spotlight-style panel with Liquid Glass (macOS 26+), date-grouped results, and a live preview.
- New default shortcut **⇧⌘V**, plus a recorder for any custom shortcut. Users of the old ⌃⇧V default move to ⇧⌘V automatically.
- Direct paste into the previous app (Accessibility permission), ⇧↩ plain-text paste, and ⌥↩ copy only.
- Multi-select with ⌘-click and ⇧↑/↓, pasted one clip per line.
- On-device text recognition for images, so screenshots are searchable.
- Content detection for colors, links, emails, addresses and code, with matching filters and previews.
- ⌘K actions menu with quick fixes: change case, trim, format or minify JSON, remove link tracking.
- Snippets, saved with ⌘S and found by name.
- Automatic deletion of one-time codes and password-like clips.
- Per-app "never save" list.
- Quick Look (Space / ⌘Y) and drag-and-drop out of the panel.
- Optional iCloud Drive sync for pins and snippets, end-to-end encrypted with a passphrase.

### Changed
- History is stored in an encrypted SQLite database (AES-GCM, key in Keychain) instead of plain JSON. Existing history is migrated and the old file is deleted.
- History length is now set by time (a day to forever) instead of a fixed 150 clips.
- Clipboard polling adapts to activity and pauses while the screen sleeps.
