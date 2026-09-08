---
type: core
schema: 2
---
# project

Magpie is a small macOS menu-bar clipboard manager written in Swift + SwiftUI, built
with plain SwiftPM (no Xcode project) and assembled into `Magpie.app` by
`bundle.sh`. It watches the system pasteboard, keeps a searchable history of text,
image, and file copies, and pastes (or types) a selected entry back into the
previously focused app via global hotkeys. It has grown side-features that share the
same "panel + paste back" pattern: an emoji picker and on-device dictation. A remote
branch `origin/screen-capture` adds a fourth (screen-region capture with text
extraction through the `claude` CLI); it is not merged into `main` as of 2026-09-09.

## Architecture sketch

- Entry: `Sources/Magpie/MagpieApp.swift:5` — `@main`, a `MenuBarExtra` (menu style)
  plus a `Settings` scene. `AppDelegate.applicationDidFinishLaunching`
  (`Sources/Magpie/MagpieApp.swift:61`) sets accessory activation policy, applies the
  `historyCap` UserDefault, starts the pasteboard watcher, registers hotkeys, and
  prompts for Accessibility if untrusted.
- Pasteboard: `Sources/Magpie/Pasteboard/PasteboardWatcher.swift` polls
  `NSPasteboard.changeCount` on a 0.5 s Timer (line 21) and ingests new content.
  `Paster.swift` pastes back by re-activating the previous app then posting ⌘V via
  `CGEvent` (line 140), or "types" by synthesizing Unicode keystrokes with
  `keyboardSetUnicodeString` (line 154). Writes set
  `PasteboardWatcher.skipNextChangeCount` so Magpie's own writes are not re-ingested.
- Storage: `Sources/Magpie/Storage/HistoryStore.swift` — JSON at
  `~/Library/Application Support/Magpie/history.json`, image payloads as PNG blobs in
  `.../blobs/`. Dedup by content hash (line 166), debounced save (line 115), sort +
  cap with pinned items surviving eviction (line 135).
- Hotkeys: `Sources/Magpie/Hotkey/HotkeyManager.swift` — Carbon `RegisterEventHotKey`,
  enum of ⌘⇧V (history), ⌘⇧E (emoji), ⌘⇧D (dictation). No rebind UI.
- Search: `Sources/Magpie/Search/FuzzyMatcher.swift` — subsequence + word-boundary
  scoring.
- UI: `Sources/Magpie/UI/` — SwiftUI views hosted in an `NSPanel` (`HistoryWindow`),
  hidden with orderOut rather than torn down (see `AppState.activationToken`,
  `Sources/Magpie/AppState.swift:19`). `PanelPositioning.swift` persists panel
  positions shared across panels.
- Emoji: `Sources/Magpie/Emoji/` — generated `EmojiData.swift` (from
  `Scripts/gen_emoji.py`), recents store, picker window.
- Dictation: `Sources/Magpie/Dictation/` — AVAudioEngine capture + FluidAudio
  (Parakeet TDT v3, CoreML on the Neural Engine). Batch transcription after stop, not
  streaming. Model (~470 MB) downloads on first use to
  `~/Library/Application Support/FluidAudio/`.
- Permissions: `Sources/Magpie/Permissions/` — Accessibility and Microphone helpers.
- Bundle identity: `local.magpie`, `LSUIElement` true, version 0.1.0
  (`Sources/Magpie/Resources/Info.plist`).

## Dependencies

One external package: FluidAudio (from 0.15.6) in `Package.swift`. It moves the
binary from ~500 KB to ~18 MB.

## Remote

GitHub `joelgsponer/magpie-clipboard`. Branches: `main`, `screen-capture`.
