# Magpie

A small, fast macOS clipboard manager. Native Swift + SwiftUI, no Xcode required.

Magpie watches the system pasteboard, keeps a searchable history of every text, image, and file copy, and pastes (or types) the selected entry back into the previously focused app via a global hotkey.

## Highlights

- **Captures everything** — text, images (as PNG), and file references.
- **Fuzzy search** — subsequence + word-boundary scoring; finds `long apology` from `lap`.
- **⌘1–9 quick paste** — paste the Nth visible row instantly; no Enter needed.
- **Type mode** — synthesizes Unicode keystrokes via `CGEventKeyboardSetUnicodeString` for fields that block paste; leaves your clipboard untouched.
- **Pin favorites** — pinned items survive history rotation.
- **Emoji picker** — searchable emoji grid with recents, paste/type/copy like history.
- **Dictation** — on-device speech-to-text (Parakeet TDT via [FluidAudio](https://github.com/FluidInference/FluidAudio), CoreML on the Apple Neural Engine); toggle recording, and the transcript lands in clipboard history and on the pasteboard. Audio never leaves your Mac.
- **Lightweight-ish** — plain Swift Package Manager build, no Xcode dependency. One external dependency (FluidAudio, for on-device dictation) pulls the binary from ~500 KB to ~18 MB; the speech model itself (~470 MB) downloads separately on first dictation, cached to disk after (`~/Library/Application Support/FluidAudio/`).

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

The first build needs network access to fetch the [FluidAudio](https://github.com/FluidInference/FluidAudio) package dependency (used for on-device dictation); subsequent builds use the resolved/cached copy.

## First run

1. Magpie lives in the menu bar (clipboard icon).
2. macOS will prompt for **Accessibility** permission — grant it under System Settings → Privacy & Security → Accessibility. Required for paste-back, which posts ⌘V via `CGEvent`.
3. Press **⌘⇧V** from any app to open the history window.
4. The first time you dictate (**⌘⇧D**), macOS additionally prompts for **Microphone** access — grant it under System Settings → Privacy & Security → Microphone. Same stability guarantee as Accessibility: grant once per machine, it survives rebuilds (see [Code signing](#code-signing)). That same first dictation also downloads the ~470 MB speech model over the network (one-time; cached to disk after) — the panel shows "Loading speech model…" while this happens, which can take a few minutes depending on your connection.

> Grant Accessibility once per machine and it sticks across rebuilds — see [Code signing](#code-signing) for why that requires a one-time setup step on a fresh machine.

## Keyboard

| Key | Action |
| --- | --- |
| `⌘⇧V` | Toggle history (global) |
| `⌘⇧E` | Toggle emoji picker (global) |
| `⌘⇧D` | Toggle dictation — press to start recording, press again to stop and transcribe (global) |
| `↵` | Paste / Type the selected item |
| `⌘1`–`⌘9` | Paste / Type the Nth visible row |
| `⌘P` | Pin / unpin the selected item |
| `⌫` | Delete the selected item |
| `↑` / `↓` | Move selection |
| `esc` | Close the panel / cancel an in-progress recording |

The footer toggle switches between **Paste** (writes to the pasteboard, posts ⌘V) and **Type** (synthesizes keystrokes character-by-character, no pasteboard write). Mode resets to Paste each time the panel closes.

### Dictation

`⌘⇧D` opens a small panel and starts recording immediately (loading the speech model first, one-time per launch — see below). Speak, then press `⌘⇧D` again to stop — the panel shows "Transcribing…" briefly, then writes the result to the pasteboard **and** clipboard history. The panel stays open showing the final transcript until you close it (`⌘⇧D` again, `esc`, or click away); `esc` while still recording cancels instead, discarding the audio.

Transcription is on-device via [FluidAudio](https://github.com/FluidInference/FluidAudio)'s Parakeet TDT v3 model (CoreML, runs on the Apple Neural Engine) — audio never leaves the Mac, and no separate "Speech Recognition" permission is needed (only Microphone). It's **batch, not live-streaming**: audio is captured while recording and transcribed as one pass after you stop, rather than showing a running partial transcript — Parakeet is fast enough (~100x+ realtime) that this is still near-instant. The model itself downloads on first use and is cached under `~/Library/Application Support/FluidAudio/`; every dictation after that reuses the cached model and skips the download.

## Storage

History is JSON at `~/Library/Application Support/Magpie/history.json`. Image payloads are PNG blobs in `~/Library/Application Support/Magpie/blobs/`.

## Tiling window managers

If you use [AeroSpace](https://github.com/nikitabobko/AeroSpace) or yabai, add a floating rule so the panel doesn't get tiled:

```toml
[[on-window-detected]]
if.app-id = 'local.magpie'
run = ['layout floating']
```

## Code signing

`bundle.sh` signs `Magpie.app` with a **local self-signed certificate** ("Magpie Local Codesign"), not an ad-hoc signature (`codesign --sign -`).

This matters for Accessibility: macOS ties a TCC grant (Accessibility, and similar permissions) to the app's signing identity. An ad-hoc signature has no certificate behind it, so macOS falls back to binding the grant to a hash of the compiled binary — every rebuild produces a different hash, which silently invalidates the existing grant even though the toggle in System Settings still shows enabled. Result: Accessibility prompts on every relaunch after every rebuild. Signing with a real (if self-signed) certificate gives the app a stable identity that survives rebuilds, so the grant only needs to be made once.

### One-time setup on a new machine

Run once per machine, before the first `./bundle.sh`:

```sh
CERT_NAME="Magpie Local Codesign"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
WORKDIR="$(mktemp -d)"

cat > "$WORKDIR/codesign.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no

[dn]
CN = $CERT_NAME

[v3]
basicConstraints=critical,CA:true
keyUsage=critical,digitalSignature,keyCertSign
extendedKeyUsage=critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 \
  -keyout "$WORKDIR/codesign.key" -out "$WORKDIR/codesign.crt" \
  -days 7300 -nodes -config "$WORKDIR/codesign.cnf"
openssl x509 -in "$WORKDIR/codesign.crt" -outform der -out "$WORKDIR/codesign.cer"
openssl pkcs12 -export -out "$WORKDIR/codesign.p12" \
  -inkey "$WORKDIR/codesign.key" -in "$WORKDIR/codesign.crt" -passout pass:temporary

# Import the identity (private key + cert) into the login keychain.
security import "$WORKDIR/codesign.p12" -k "$KEYCHAIN" -P temporary -T /usr/bin/codesign -A

# Trust the certificate for code signing so `codesign` accepts it without warnings.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORKDIR/codesign.cer"

rm -rf "$WORKDIR"
security find-identity -v -p codesigning   # should list "Magpie Local Codesign"
```

macOS may show a keychain authentication prompt (password/Touch ID) during the import or trust step — that's expected; approve it.

After that, `./bundle.sh` picks up the identity by name and every build is signed with the same stable identity. Grant Accessibility once and it will keep working across rebuilds.

If you ever see the Accessibility prompt reappear unexpectedly (e.g. after renaming the certificate, or restoring a machine from backup), remove the stale "Magpie" row(s) under System Settings → Privacy & Security → Accessibility and re-grant.

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
    UI/                      SwiftUI views + NSPanel host + shared panel positioning
    Emoji/                   Emoji picker window, view, data, recents
    Dictation/               Dictation window, view, AVAudioEngine + FluidAudio (Parakeet) manager
    Permissions/             Accessibility / Microphone permission helpers
    Resources/Info.plist
```

## Why no Xcode project?

Swift macros (`@Model` from SwiftData, `#Preview`, the `KeyboardShortcuts` package) need macro plugins that ship only with Xcode. To stay buildable from the Command Line Tools alone, Magpie uses a plain SwiftPM executable plus `bundle.sh` which assembles `Magpie.app/Contents/{MacOS,Resources,Info.plist}` and signs it with a local self-signed certificate (see [Code signing](#code-signing)). Persistence is plain `Codable` + JSON; the global hotkey is Carbon `RegisterEventHotKey` directly.

## License

[MIT](LICENSE)
