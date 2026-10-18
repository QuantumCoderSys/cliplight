## Cliplight 1.0.0

A little Spotlight for everything you copy. Open your clipboard history with **⇧⌘V**, find the useful thing, and paste it back into your flow.

### In this release

- A native floating panel with date-grouped history and light/dark appearances.
- Search across copied text, source apps, snippet names, and text recognized in images.
- Color, link, code, image, and file previews; Quick Look and drag-and-drop.
- Direct paste, plain-text paste, multi-selection, and a customizable global shortcut.
- A **⌘K** actions menu for case changes, whitespace cleanup, JSON formatting, and cleaner links.
- Pinned clips and named snippets.
- Encrypted local history, configurable retention, per-app exclusions, and automatic expiry for detected codes and password-like clips.
- Optional passphrase-encrypted iCloud Drive sync for pins and snippets.

### Requirements

macOS 14 or newer. Universal build for Apple silicon and Intel. Liquid Glass is used on macOS 26+.

### Draft distribution status

**The attached preparation builds are ad-hoc signed and are not notarized by Apple. This draft is not a stable public installer release.** Developer ID signing and notarization must be completed, and these assets replaced, before this draft is published.

Source builds are available now; see the README. Direct paste requires Accessibility permission. Without it, Cliplight copies the chosen item for manual pasting.

### Verification

The release includes `SHA256SUMS.txt` and `BUILD-INFO.txt`. The build runs 15 source-level checks covering encryption, migration, privacy markers, retention, snippets, text recognition, transforms, selection, and clipboard round trips on named test pasteboards. Real cross-device iCloud delivery is not covered by those automated checks.
