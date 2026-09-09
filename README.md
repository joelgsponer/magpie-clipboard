# Magpie

A macOS cockpit behind one key. Native Swift + SwiftUI, no Xcode required.

Press **⌘Space** and a tool chooser appears — a row of cards, each with a
letter, like a weapon wheel in a game. Press the letter and that tool opens
on top of whatever you were doing; when it is done it pastes its result back
into the app you came from. ⌘Space takes over the chord from Spotlight (see
[The leader key](#the-leader-key)).

| Key | Tool | What it does |
| --- | --- | --- |
| `⌘Space` **C** | Clipboard | searchable history of every text, image, and file copy; paste or type it back |
| `⌘Space` **E** | Emoji | searchable emoji grid with recents |
| `⌘Space` **D** | Dictate | on-device speech-to-text, transcript to clipboard and history |
| `⌘Space` **X** | Capture | drag a screen region, get its text plus a description (via Claude) |
| `⌘Space` **A** | Apps | application launcher with fuzzy search and frequency ranking |
| `⌘Space` **S** | Search | Spotlight-backed file, folder, and content search |
| `⌘Space` **M** | Math | expression calculator; Enter pastes the result |

The clipboard manager is where Magpie started, and it is still the heart of
it: everything the other tools produce lands in the same history.

## Highlights

- **Captures everything** — text, images (as PNG), and file references.
- **Fuzzy search** — subsequence + word-boundary scoring; finds `long apology` from `lap`.
- **⌘1–9 quick paste** — paste the Nth visible row instantly; no Enter needed.
- **Type mode** — synthesizes Unicode keystrokes via `CGEventKeyboardSetUnicodeString` for fields that block paste; leaves your clipboard untouched.
- **Pin favorites** — pinned items survive history rotation.
- **Emoji picker** — searchable emoji grid with recents, paste/type/copy like history.
- **Dictation** — on-device speech-to-text (Parakeet TDT via [FluidAudio](https://github.com/FluidInference/FluidAudio), CoreML on the Apple Neural Engine); toggle recording, and the transcript lands in clipboard history and on the pasteboard. Audio never leaves your Mac.
- **Screen capture** — drag-select a region and get back the text in it *plus* a short description of what it is and where it came from, so screenshots are recognisable and searchable in history. Unlike dictation, this one **does** leave your Mac — see [Screen capture](#screen-capture).
- **App launcher** — walks the application folders (including the system cryptex where Safari lives), fuzzy-matches names, and ranks by how often you launch each app. Running apps show a green dot.
- **File search** — `NSMetadataQuery` over the Spotlight index: display names for short queries, plus indexed text content once you have typed three letters. Open, reveal in Finder, or copy the path.
- **Calculator** — `2^10/3 + sqrt(2)`, `80*15%`, `fact(20)`, `ans*2`. Enter pastes the plain result back into the previous app and adds it to history; a tape keeps the session's calculations.
- **Lightweight-ish** — plain Swift Package Manager build, no Xcode dependency. One external dependency (FluidAudio, for on-device dictation) pulls the binary from ~500 KB to ~18 MB; the speech model itself (~470 MB) downloads separately on first dictation, cached to disk after (`~/Library/Application Support/FluidAudio/`).

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9+ (Command Line Tools is enough — `xcode-select --install`)
- [Claude Code](https://claude.com/claude-code) on `PATH`, for the screen-capture feature only. Everything else works without it.

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
3. Press **⌘Space** from any app to open the cockpit, then **C** for the history window. (The direct chords still work: **⌘⇧V** opens history without the chooser.)
4. The first time you dictate (**⌘⇧D**), macOS additionally prompts for **Microphone** access — grant it under System Settings → Privacy & Security → Microphone. Same stability guarantee as Accessibility: grant once per machine, it survives rebuilds (see [Code signing](#code-signing)). That same first dictation also downloads the ~470 MB speech model over the network (one-time; cached to disk after) — the panel shows "Loading speech model…" while this happens, which can take a few minutes depending on your connection.

5. The first time you capture (**⌘⇧X**), Magpie asks for confirmation before sending anything to Claude, and macOS prompts for **Screen Recording** access. Unlike the other two, that grant only takes effect after you quit and reopen Magpie.

> Grant Accessibility once per machine and it sticks across rebuilds — see [Code signing](#code-signing) for why that requires a one-time setup step on a fresh machine.

## The leader key

Spotlight owns ⌘Space as a system-level hotkey, and an ordinary Carbon
`RegisterEventHotKey` for the same chord loses to it silently. Magpie instead
installs a `CGEvent` tap at the HID level, at the head of the event pipeline:
it sees the key-down before the symbolic-hotkey layer does, swallows it, and
Spotlight never fires. The same tap grabs the keyboard while the chooser is
up, so the letter you press never leaks into the app underneath, and the
chooser itself never has to become the key window (Magpie is not activated;
the app you were in stays frontmost, which is how every tool knows where to
paste back).

The tap needs the Accessibility permission Magpie already requires for
paste-back. If it cannot be created, Magpie falls back to a Carbon hotkey
and the Settings pane says so — in that case turn off Spotlight's shortcut
under System Settings › Keyboard › Keyboard Shortcuts › Spotlight so the
fallback wins. Spotlight itself stays reachable from the menu bar icon, and
`⌘Space` **S** is Magpie's own search over the same index.

Two ways to chord, both work: press `⌘Space`, let go, press the letter; or
hold `⌘`, tap Space, tap the letter, release. `esc` or a second `⌘Space`
closes the chooser; `←` `→` and `↵` browse it; clicking a card opens it.
The toggle under Settings › Cockpit hands ⌘Space back to Spotlight.

## Keyboard

| Key | Action |
| --- | --- |
| `⌘Space` | Open the tool chooser (global) — then `C` `E` `D` `X` `A` `S` `M` |
| `⌘⇧V` | Toggle history (global) |
| `⌘⇧E` | Toggle emoji picker (global) |
| `⌘⇧D` | Toggle dictation — press to start recording, press again to stop and transcribe (global) |
| `⌘⇧X` | Capture a screen region and extract its text + context (global) |
| `↵` | Paste / Type the selected item |
| `⌘1`–`⌘9` | Paste / Type the Nth visible row |
| `⌘P` | Pin / unpin the selected item |
| `⌫` | Delete the selected item |
| `↑` / `↓` | Move selection |
| `esc` | Close the panel / cancel an in-progress recording |

The footer toggle switches between **Paste** (writes to the pasteboard, posts ⌘V) and **Type** (synthesizes keystrokes character-by-character, no pasteboard write). Mode resets to Paste each time the panel closes.

### Apps, Search, Math

All three follow the history panel's conventions: a search field on top,
`↑` `↓` to move, `↵` to act, `⌘1`–`⌘9` to act on the Nth row, `esc` to close.

| Panel | `↵` | `⌘↵` | Other |
| --- | --- | --- | --- |
| Apps | launch | reveal in Finder | `⌘R` rescan the application folders |
| Search | open | reveal in Finder | `⌘C` copy the path (also lands in history) |
| Math | paste the result | copy the result | `⇧↵` keep the result on the tape and continue; `⌘K` clear the tape |

Math understands `+ - * / ^ %`, parentheses, `1,000`-style thousands
separators, `x%` as a percentage, `1e6`, the functions `sqrt cbrt abs floor
ceil round ln log log2 exp sin cos tan asin acos atan min max avg sum fact`,
the constants `pi e tau`, and `ans` for the previous result. Results are
pasted plain (no grouping) so they drop straight into a spreadsheet cell.

Search waits for two characters before querying — one letter against the
whole index gathers tens of thousands of rows before anything can show.

### Dictation

`⌘⇧D` opens a small panel and starts recording immediately (loading the speech model first, one-time per launch — see below). Speak, then press `⌘⇧D` again to stop — the panel shows "Transcribing…" briefly, then writes the result to the pasteboard **and** clipboard history. The panel stays open showing the final transcript until you close it (`⌘⇧D` again, `esc`, or click away); `esc` while still recording cancels instead, discarding the audio.

Transcription is on-device via [FluidAudio](https://github.com/FluidInference/FluidAudio)'s Parakeet TDT v3 model (CoreML, runs on the Apple Neural Engine) — audio never leaves the Mac, and no separate "Speech Recognition" permission is needed (only Microphone). It's **batch, not live-streaming**: audio is captured while recording and transcribed as one pass after you stop, rather than showing a running partial transcript — Parakeet is fast enough (~100x+ realtime) that this is still near-instant. The model itself downloads on first use and is cached under `~/Library/Application Support/FluidAudio/`; every dictation after that reuses the cached model and skips the download.

### Screen capture

`⌘⇧X` puts up the standard macOS crosshair. Drag a region and Magpie hands the
PNG to the `claude` CLI in headless mode, which returns two things:

- **text** — every character visible in the region, transcribed verbatim.
- **context** — a couple of sentences on what kind of content it is, which app
  or site it looks like it came from, and what it's about.

The result panel shows both. `↵` pastes into whatever app you were in before,
`⌘↵` copies without pasting, and a **Text / Text + context** toggle controls
which of the two goes on the pasteboard. Either way the screenshot itself is
stored in history, annotated with both fields — so a capture is findable weeks
later by searching for something that was *in* it, or for the description of it.
If a region has no legible text (a photo, an unlabelled chart), the toggle is
disabled and you get the context alone.

> **This feature sends your screen content to Anthropic.** It is the one part of
> Magpie that is not local. Whatever is inside the region you select — including
> passwords, private messages, or confidential material — is transmitted to the
> API. Magpie asks for confirmation before the first capture, and you can
> disable it again under Settings → Screen Capture. Each capture costs roughly
> $0.04 against your Claude account.

Requires **Screen Recording** permission (System Settings → Privacy & Security →
Screen Recording). Note that macOS only applies this grant on relaunch, so quit
and reopen Magpie after granting it.

Magpie looks for `claude` in the usual install locations and, failing that, by
asking your login shell. A GUI app doesn't inherit your terminal's `PATH`, so if
it can't find it, set the full path under Settings → Screen Capture.

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
    Cockpit/                 Tool registry, ⌘Space leader (CGEvent tap + Carbon fallback), chooser HUD
    Launcher/                Application index + launcher panel
    Spotlight/               NSMetadataQuery wrapper + file search panel
    Calculator/              Expression evaluator + calculator panel
    UI/                      SwiftUI views + NSPanel host + shared panel positioning
    Emoji/                   Emoji picker window, view, data, recents
    Dictation/               Dictation window, view, AVAudioEngine + FluidAudio (Parakeet) manager
    ScreenCapture/           Region capture, claude -p adapter, result window + view
    Permissions/             Accessibility / Microphone / Screen Recording helpers
    Resources/Info.plist
```

## Why no Xcode project?

Swift macros (`@Model` from SwiftData, `#Preview`, the `KeyboardShortcuts` package) need macro plugins that ship only with Xcode. To stay buildable from the Command Line Tools alone, Magpie uses a plain SwiftPM executable plus `bundle.sh` which assembles `Magpie.app/Contents/{MacOS,Resources,Info.plist}` and signs it with a local self-signed certificate (see [Code signing](#code-signing)). Persistence is plain `Codable` + JSON; the global hotkey is Carbon `RegisterEventHotKey` directly.

## License

[MIT](LICENSE)
