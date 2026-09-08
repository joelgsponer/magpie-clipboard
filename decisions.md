---
type: core
schema: 2
---
# decisions

- **No Xcode project; plain SwiftPM + bundle.sh.** Swift macros (`@Model`,
  `#Preview`, the KeyboardShortcuts package) need macro plugins shipped only with
  Xcode. Staying buildable from Command Line Tools alone means: Codable + JSON for
  persistence, Carbon `RegisterEventHotKey` for hotkeys, a hand-rolled app bundle.
  (README.md "Why no Xcode project?")
- **Sign with a self-signed certificate, not ad-hoc.** macOS binds TCC grants
  (Accessibility etc.) to the signing identity. Ad-hoc signing has no certificate, so
  the grant is bound to the binary hash and dies on every rebuild. A stable local
  identity ("Magpie Local Codesign") makes grants survive rebuilds.
  (`bundle.sh`, README.md "Code signing")
- **Build path outside `~/Documents`.** llbuild's sqlite store hits I/O errors when
  `.build/` sits under Documents (iCloud/Spotlight/backup providers). Hence
  `--build-path /tmp/magpie-build` in `bundle.sh`.
- **Dictation is on-device via FluidAudio/Parakeet, batch not streaming.** Audio never
  leaves the Mac and needs only the Microphone permission (no Speech Recognition
  permission). Parakeet is ~100x realtime so batch after stop is near-instant.
  Cost: one dependency, ~18 MB binary, ~470 MB model downloaded on first use.
- **Global hotkeys moved to ⌘⇧ chords** (⌃⌘V → ⌘⇧V in commit 76c8f34). Emoji ⌘⇧E,
  dictation ⌘⇧D follow the same pattern.
- **Panels are hidden with orderOut, never torn down.** `onAppear` fires once, so
  `AppState.activationToken` is bumped on each show to re-focus search and re-select
  (`Sources/Magpie/AppState.swift:16`).
- **Type mode synthesizes Unicode keystrokes** (`CGEventKeyboardSetUnicodeString`) for
  fields that block paste, and leaves the clipboard untouched.
- **Screen capture (unmerged branch) deliberately leaves the Mac.** It shells out to
  the `claude` CLI headless (`claude -p`), asks for confirmation before the first
  capture, and is toggleable in Settings. ~$0.04 per capture.
