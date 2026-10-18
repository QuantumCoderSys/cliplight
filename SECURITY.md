# Security

Cliplight handles everything users copy, including things they'd rather nobody saw. Security reports are taken seriously.

## Reporting a vulnerability

Please **don't open a public issue**. Report privately through [GitHub Security Advisories](https://github.com/QuantumCoderSys/cliplight/security/advisories/new).

## What Cliplight protects

- History on disk is sealed per clip with AES-256-GCM. In release builds the key is a Keychain item that stays on this Mac (`AfterFirstUnlockThisDeviceOnly`). Debug builds use a separate database and a user-only key file, so ad-hoc rebuilds don't trigger Keychain prompts. Never ship a debug build.
- The history folder and database use user-only permissions (0700 / 0600). The database uses SQLite `secure_delete`.
- Copies marked `org.nspasteboard.ConcealedType` or `TransientType`, and copies from password managers and user-chosen apps, are never stored.
- One-time codes and password-like text expire automatically.
- Sync files are sealed with a key derived from the user's passphrase (PBKDF2-HMAC-SHA256, 310,000 rounds, random salt). They contain only pins and snippets.
- Quick Look writes the selected clip to a private temporary folder, which is deleted when the panel closes.

## Known limits

- Anyone who can unlock your Mac account can open Cliplight and read history. This is the same trust model as the system clipboard.
- Unmarked sensitive text that doesn't look like a code or password is saved like any other text. Pause capture when needed.
- Accessibility permission lets Cliplight send keystrokes. It uses this only to press ⌘V after you choose a clip.
