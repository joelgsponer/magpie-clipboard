---
type: core
schema: 2
---
# lessons

- Every side-feature (emoji, dictation, screen capture) follows the same shape: a
  `*Window` NSPanel host singleton with `show()`/`toggle()`, a SwiftUI `*View`, a
  `*Manager`/`*Store` for state, a `Hotkey` enum case registered in
  `AppDelegate.applicationDidFinishLaunching`, and a menu item in `MenuContent`.
  Add new features by copying that shape.
- Any new macOS permission needs three things: a usage-description key in
  `Sources/Magpie/Resources/Info.plist`, a helper in `Sources/Magpie/Permissions/`, and
  a README "First run" step. Grants persist across rebuilds only because of the
  self-signed identity; never switch back to `--sign -`.
- Verification is manual (no tests): build with `./bundle.sh debug`, `open Magpie.app`,
  and check `NSLog` output via Console.app or `log stream --process Magpie`.
