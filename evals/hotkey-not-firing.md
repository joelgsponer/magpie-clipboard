---
type: eval
born: 2026-09-09 synthetic cov
tests: [gotchas]
schema: 2
---
# the global hotkey does nothing, why?
evidence: newborn brain; HotkeyManager.swift comment documents the silent failure
expect:
- `RegisterEventHotKey`
- noErr
