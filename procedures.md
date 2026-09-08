---
type: core
schema: 2
---
# procedures

## Build and run

```sh
./bundle.sh           # swift build -c release + assemble + codesign Magpie.app
./bundle.sh debug     # faster dev cycle
open Magpie.app
```

`bundle.sh` builds with `--build-path /tmp/magpie-build` (not `.build/`), copies the
binary and `Sources/Magpie/Resources/Info.plist` into `Magpie.app/Contents/`, then
runs `codesign --force --deep --sign "Magpie Local Codesign"`. The first build needs
network access to fetch FluidAudio.

Requirements: macOS 14+, Swift 5.9+ (Command Line Tools suffice).

## One-time code-signing identity per machine

Before the first `./bundle.sh` on a new machine, create the self-signed
"Magpie Local Codesign" certificate and import it into the login keychain. The full
openssl + `security import` + `security add-trusted-cert` script is in README.md
under "Code signing". Verify with:

```sh
security find-identity -v -p codesigning   # must list "Magpie Local Codesign"
```

## Permissions to grant on first run

- Accessibility (paste-back posts ⌘V via CGEvent).
- Microphone (dictation, prompted on first ⌘⇧D).
- Screen Recording (screen-capture branch only; takes effect only after relaunch).

If the Accessibility prompt reappears after a rebuild, remove the stale Magpie rows
under System Settings → Privacy & Security → Accessibility and re-grant. See
[[gotchas]].

## Regenerate emoji data

`Scripts/gen_emoji.py` produces `Sources/Magpie/Emoji/EmojiData.swift`.

## Tests

None in the repo as of 2026-09-09. Verification is manual: build, open, exercise the
hotkeys.

## Tiling window managers

AeroSpace/yabai users add a floating rule for app-id `local.magpie` (README.md).
