# Cliplight showcase

This standalone presentation app renders the production SwiftUI views with fictional sample data. It uses an ephemeral store and a named, isolated pasteboard. It does not start clipboard polling, register a global shortcut, use the Keychain, or start iCloud sync.

```sh
./tools/showcase/build.sh
open ".build/Cliplight Showcase.app"
```

Use **1** for the light/color view, **2** for the dark/code view, **3** for the actions menu, and **4** for snippets. Capture the window at its native size. The README uses:

- `docs/showcase-light.png`
- `docs/showcase-dark.png`
- `docs/showcase-actions.png`
- `docs/showcase-snippets.png`

The native app view, text, icons, selection, and menu are rendered from the same components as the shipping app. The surrounding headline and background are presentation framing. Dates and times are illustrative. No personal clipboard content is included.
