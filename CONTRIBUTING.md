# Contributing to Cliplight

Thanks for helping. Cliplight aims to feel like a built-in part of macOS: fast, quiet, keyboard-first, and private. Changes that keep it that way are the easiest to accept.

## Getting started

```bash
./script/build_and_run.sh   # build and launch dist/Cliplight.app
./script/check.sh           # run the core checks
```

You need Swift 6 and the macOS 26 SDK. Xcode is optional: everything builds with Command Line Tools.

## Guidelines

- **No new dependencies** without discussion. Cliplight uses only Apple frameworks.
- **Privacy first.** Never log clipboard contents, never add network calls outside opt-in sync, and keep everything stored on disk encrypted.
- **Keyboard first.** Every new action needs a shortcut or a place in the ⌘K menu.
- **Follow Apple's Human Interface Guidelines.** Use system fonts, SF Symbols and semantic colors, and check light mode, dark mode and VoiceOver labels.
- **Avoid SwiftUI macros** (`@State`, `@Observable`, `#Preview`). They need Xcode's macro plugins, which Command Line Tools builds don't have. Use `ObservableObject` instead, as the rest of the code does.
- Add a check to `Checks/ClipboardChecks.swift` for any new rule or data-handling change.

## Pull requests

Keep them focused, describe how you tested, and make sure `./script/check.sh` passes. CI validates the documentation, runs the same checks, and compiles the release configuration. Universal installer preparation runs in a separate draft-release workflow.
