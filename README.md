# Magpie

A small, fast macOS clipboard manager. Native Swift + SwiftUI, no Xcode required.

Magpie watches the system pasteboard, keeps a searchable history of every text, image, and file copy, and pastes (or types) the selected entry back into the previously focused app via a global hotkey.

## Highlights

- **Captures everything** — text, images (as PNG), and file references.
- **Fuzzy search** — subsequence + word-boundary scoring; finds `long apology` from `lap`.
- **⌘1–9 quick paste** — paste the Nth visible row instantly; no Enter needed.
- **Type mode** — synthesizes Unicode keystrokes via `CGEventKeyboardSetUnicodeString` for fields that block paste; leaves your clipboard untouched.
- **Pin favorites** — pinned items survive history rotation.
- **Lightweight** — ~500 KB binary, plain Swift Package Manager build, no Xcode dependency, zero external Swift dependencies.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9+ (Command Line Tools is enough — `xcode-select --install`)

## Build

```sh
git clone https://github.com/<your-account>/magpie.git
cd magpie
./bundle.sh           # builds release + assembles Magpie.app
open Magpie.app
```

For a faster dev cycle:

```sh
./bundle.sh debug
open Magpie.app
```

> The build runs with `--build-path /tmp/magpie-build` because llbuild's sqlite store can hit I/O errors when `.build/` lives under `~/Documents/` (iCloud, Spotlight, or backup providers may be the cause).

## First run

1. Magpie lives in the menu bar (clipboard icon).
2. macOS will prompt for **Accessibility** permission — grant it under System Settings → Privacy & Security → Accessibility. Required for paste-back, which posts ⌘V via `CGEvent`.
3. Press **⌃⌘V** from any app to open the history window.

## Keyboard

| Key | Action |
| --- | --- |
| `⌃⌘V` | Toggle history (global) |
| `↵` | Paste / Type the selected item |
| `⌘1`–`⌘9` | Paste / Type the Nth visible row |
| `⌘P` | Pin / unpin the selected item |
| `⌫` | Delete the selected item |
| `↑` / `↓` | Move selection |
| `esc` | Close the panel |

The footer toggle switches between **Paste** (writes to the pasteboard, posts ⌘V) and **Type** (synthesizes keystrokes character-by-character, no pasteboard write). Mode resets to Paste each time the panel closes.

## Storage

History is JSON at `~/Library/Application Support/Magpie/history.json`. Image payloads are PNG blobs in `~/Library/Application Support/Magpie/blobs/`.

## Tiling window managers

If you use [AeroSpace](https://github.com/nikitabobko/AeroSpace) or yabai, add a floating rule so the panel doesn't get tiled:

```toml
[[on-window-detected]]
if.app-id = 'local.magpie'
run = ['layout floating']
```

## Project layout

```
Magpie/
  Package.swift
  bundle.sh                  build + bundle as Magpie.app
  Sources/Magpie/
    MagpieApp.swift          @main, MenuBarExtra
    AppState.swift
    Pasteboard/              changeCount poll + paste/type back
    Models/                  Codable ClipboardItem
    Storage/                 JSON history + PNG blobs + dedup/eviction
    Hotkey/                  Carbon RegisterEventHotKey wrapper
    Search/                  Fuzzy subsequence matcher
    UI/                      SwiftUI views + NSPanel host
    Permissions/             AX permission helper
    Resources/Info.plist
```

## Why no Xcode project?

Swift macros (`@Model` from SwiftData, `#Preview`, the `KeyboardShortcuts` package) need macro plugins that ship only with Xcode. To stay buildable from the Command Line Tools alone, Magpie uses a plain SwiftPM executable plus `bundle.sh` which assembles `Magpie.app/Contents/{MacOS,Resources,Info.plist}` and ad-hoc codesigns. Persistence is plain `Codable` + JSON; the global hotkey is Carbon `RegisterEventHotKey` directly.

## License

[MIT](LICENSE)
