# Language Relay

![Language Relay](docs/language-relay-social.png)

**Language Relay** is a local macOS layout bridge for people and agents. It repairs text typed in the wrong layout, switches the active source, and exposes deterministic JSON commands. It belongs to **aPoWall Instruments** – focused productivity tools by Alex Povaliaev.

Current pair: `U.S.` ⇄ `Russian – PC`. Conversion, settings, and the transient typing buffer stay on the Mac. There is no telemetry, account, typed-text log, database, or runtime network request.

[Interactive website](https://apps.aimindset.org/language-relay/) · [GitHub Pages mirror](https://apowall.github.io/language-relay/) · [Latest release](https://github.com/aPoWall/language-relay/releases/latest)

## What ships

- `⇧ ⇧` repairs the latest wrong-layout word by default, with phrase repair as an explicit mode;
- clean standalone `⌥` repairs text, or switches the layout when there is nothing to repair;
- Option with Command, Shift, Control, or another key stays untouched;
- Caps / Hyper switching can remain in Karabiner-Elements;
- the default repair route uses normal edit events so editor undo stacks keep working in the common path;
- direct Accessibility replacement is available as an opt-in compatibility fallback and is read back before success is reported;
- guarded web/Electron fallback avoids duplicated text and restores the clipboard;
- Orca and terminal inputs use a repeatable buffered path that never writes an Accessibility selection;
- preserve, sentence, uppercase, and lowercase modes;
- eight short feedback cues and four volume levels;
- menu-bar state, local diagnostics, and JSON CLI.

## Install

One command from GitHub:

```bash
npx github:aPoWall/language-relay install
```

Or build directly:

```bash
git clone https://github.com/aPoWall/language-relay.git
cd language-relay
make install
```

Installation runs setup and prints a checklist for Hammerspoon, the bridge, input sources, Accessibility, and the background app. It exits non-zero until every prerequisite is complete. Re-run it safely at any time:

```bash
language-relay setup
```

`setup` enables `U.S.` and `Russian – PC` when they are available, appends the bridge load line without changing your existing Hammerspoon configuration, and opens Accessibility settings when permission is missing. It never removes or reorders your input sources. If Hammerspoon is missing, install it with:

```bash
brew install --cask hammerspoon
```

As a manual fallback, add this once to `~/.hammerspoon/init.lua`, then reload Hammerspoon:

```lua
dofile(os.getenv("HOME") .. "/.config/language-relay/hammerspoon.lua")
```

Requirements: macOS 13+, Apple Command Line Tools, [Hammerspoon](https://www.hammerspoon.org/) with Accessibility permission, and both supported input sources enabled. In bridge mode, grant Accessibility to Hammerspoon; Language Relay only needs its own Accessibility approval when running without the Hammerspoon bridge.

## Controls

| Module | Choices |
| --- | --- |
| Scope | Last word · Last phrase |
| Case | `aA` Preserve · `Aa` Sentence · `AA` Uppercase · `aa` Lowercase |
| Triggers | Double Shift · clean Option |
| Feedback | Pulse · Relay · Scan · Flux · Prism · Tick · Fold · Nova |
| Level | Mute 00 · Low 25 · Mid 55 · High 82 |

Given `hELLO`, the case modes produce `hELLO`, `Hello`, `HELLO`, and `hello`.

## Agent CLI

The native binary and the npm shim return stable JSON without logging input text:

```bash
language-relay convert ghbdtn
language-relay setup
language-relay status
language-relay doctor
language-relay design
language-relay capabilities
language-relay quit
language-relay switch
```

Direct native surface:

```bash
"$HOME/Applications/Language Relay.app/Contents/MacOS/LanguageRelay" --convert-json ghbdtn
"$HOME/Applications/Language Relay.app/Contents/MacOS/LanguageRelay" --setup
"$HOME/Applications/Language Relay.app/Contents/MacOS/LanguageRelay" --doctor-json
"$HOME/Applications/Language Relay.app/Contents/MacOS/LanguageRelay" --capabilities-json
"$HOME/Applications/Language Relay.app/Contents/MacOS/LanguageRelay" --quit
"$HOME/Applications/Language Relay.app/Contents/MacOS/LanguageRelay" --testbed show   # or hide | toggle
```

`--testbed show|hide|toggle` (build 14, AIM-APPS-RULES rule 27) tells the running instance to present the panel without activation, anchored to an invisible 2 pt window in the bottom-right corner of the main screen (24 pt inset); the user's app stays frontmost, the cursor does not move, key focus is not taken. Driver and rules: `lab-sites/internal-sites/aim-product-system/testbed/`.

Panel appear and close (2.3.9, rules 28–29): the popover animates over the shared token `motion-panel-appear` (200 ms; 0 under Reduce Motion); the panel is transient by default and an outside click closes it, the header pin `◉/○` keeps it open (`defaults write dev.alex.layout-pilot dev.alex.layout-pilot.pinned -bool true` does the same); `×`, Escape, Command-W, the status-item click and `--testbed hide` close it the same way.

The bundle identifier and preferences domain remain `dev.alex.layout-pilot` so existing settings survive the rename. Version 2.3.3 migrates the old phrase default to Last Word once; choose Last Phrase in the panel when you want the longer tail.

Use `language-relay quit` or the menu-bar Quit item to stop both the menu app and the Hammerspoon repair bridge. Running `language-relay install` starts them again.

## Gesture ownership and Karabiner

Karabiner transforms hardware events before macOS posts its virtual-keyboard output, so Language Relay can coexist with Caps / Hyper rules when those rules do not emit a clean standalone Option or Double Shift.

If another layout utility owns Double Shift or Option, keep one gesture owner active. Language Relay suspends its repair gestures when it detects a known owner and keeps menu, Caps / Hyper, and CLI access.

## Other languages

Version 2.3 supports only `U.S. ⇄ Russian – PC`. The Carbon mapping engine can be generalized to deterministic keyboard-layout pairs such as Latin/Cyrillic, Latin/Greek, or Latin/Hebrew. Same-script pairs are harder to detect, while IME, dead-key, and compose layouts need a separate architecture. The site does not claim universal language support yet.

## Build and QA

Native version 2.3.9 uses the generated N1 native-white profile: a fixed 420×488 panel,
bundled IBM Plex Mono, inline setup details and the shared AIM window contract
(header: live mark 40 pt · name · version · settings · ×; footer: keys · esc close · version · status). The bridge protocol remains
2.3.3. In bridge mode the panel checks Hammerspoon's permission and active tap.

The runtime version comes from the bundle's `Info.plist`. `language-relay design`
reports the installed app version and exact N1 token source digest. The controls
keep keyboard focus when settings or setup details refresh; Left/Right chooses
adjacent segments and Space/Return activates a focused control.

The panel header and the menu bar carry the live product mark, the relay voxel
character from the shared `AIMVoxelView.swift` / `AIMVoxelModels.swift` exports
(cursor parallax, one finite reassemble on click, still frame under Reduce Motion).

`make design-check` verifies vendored design assets against their receipt.
To update them, run `node scripts/sync-design-tokens.mjs <export-directory>` with
the reviewed `sites/apps/assets` export from `ai-mindset-org/lab-sites`.
See [DESIGN.md](DESIGN.md) for the adapter and compact native exceptions.

For an existing configured installation, `make test` followed by
`./install-runtime.sh update-background` updates the app without opening setup
or changing input sources. It requires an unchanged installed bridge and verifies
the previous bundle and runtime files before replacement.

```bash
make test
make install
make integration-test
make shutdown-test
```

`make install` stages and validates the bundle before replacing the running copy. It stores the previous app, LaunchAgent, and Hammerspoon bridge under `~/Library/Application Support/Language Relay/Rollback/`; `make rollback` restores the latest snapshot.

The default suite stays in the background: no app window, focus change, keyboard event, or sound playback. `make live-integration-test` is the separate manual lane.

## Architecture

- Swift/AppKit menu-bar app and CLI;
- Carbon `UCKeyTranslate` layout maps;
- Hammerspoon clean-modifier state machine and verified fallback;
- LaunchAgent background startup;
- vendored ShaperKit primitives;
- MIT code and documented sound provenance.

See [SECURITY.md](SECURITY.md), [ASSET-LICENSES.md](ASSET-LICENSES.md), and [CONTRIBUTING.md](CONTRIBUTING.md).
