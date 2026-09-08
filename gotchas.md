---
type: core
schema: 2
---
# gotchas

- **Accessibility prompt on every relaunch** = signing identity changed. Ad-hoc
  signatures do this by design. Fix: ensure `security find-identity -v -p codesigning`
  lists "Magpie Local Codesign" and rebuild with `bundle.sh`; if the row in System
  Settings still shows enabled but paste-back fails, delete the stale Magpie row and
  re-grant. Renaming the cert or restoring from backup also invalidates grants.
- **Carbon `RegisterEventHotKey` returns noErr even when another app owns the chord.**
  ⌘⇧V/⌘⇧E/⌘⇧D are commonly grabbed by Paste, Maccy, Raycast, Alfred. A hotkey that
  silently never fires is almost always this (`Sources/Magpie/Hotkey/HotkeyManager.swift:22`).
- **`swift build` inside `~/Documents` can fail with sqlite I/O errors** from llbuild.
  Always go through `bundle.sh`, which uses `/tmp/magpie-build`.
- **Screen Recording permission only applies after relaunch** (screen-capture branch).
  Granting it while Magpie runs does nothing until quit + reopen.
- **A GUI app does not inherit the terminal `PATH`.** The screen-capture branch looks
  for `claude` in usual install locations, then asks the login shell; otherwise the
  full path must be set in Settings → Screen Capture.
- **Magpie's own pasteboard writes must not be re-ingested.** `Paster` sets
  `PasteboardWatcher.skipNextChangeCount` before writing
  (`Sources/Magpie/Pasteboard/Paster.swift:27`). Any new code path that writes to the
  pasteboard must do the same or the history gets a duplicate entry.
- **First dictation downloads ~470 MB** and can take minutes; the panel shows
  "Loading speech model…". Not a hang.
