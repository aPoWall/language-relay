# Language Relay

![Language Relay](docs/language-relay-social.png)

**Language Relay** is a local macOS layout bridge for people and agents. It repairs text typed in the wrong layout, switches the active source, and exposes deterministic JSON commands. It belongs to **aPoWall Instruments** – focused productivity tools by Alex Povaliaev.

Default pair: `U.S.` ⇄ `Russian – PC`. Pick a different pair from any of your currently enabled keyboard input sources in the panel's `02 · layout pair` picker — `Russian` and `Russian – PC` show up as distinct entries. Conversion, settings, and the transient typing buffer stay on the Mac. There is no telemetry, account, typed-text log, database, or runtime network request.

[Interactive website](https://apowall.github.io/language-relay/) · [Latest release](https://github.com/aPoWall/language-relay/releases/latest)

## What ships

- `⇧ ⇧` repairs the latest wrong-layout phrase or word;
- clean standalone `⌥` repairs text, or switches the layout when there is nothing to repair;
- Option with Command, Shift, Control, or another key stays untouched;
- Caps / Hyper switching can remain in Karabiner-Elements;
- Accessibility replacement is read back before success is reported;
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

Add this once to `~/.hammerspoon/init.lua`, then reload Hammerspoon:

```lua
dofile(os.getenv("HOME") .. "/.config/language-relay/hammerspoon.lua")
```

Requirements: macOS 13+, Apple Command Line Tools, [Hammerspoon](https://www.hammerspoon.org/) with Accessibility permission, and both layout-pair input sources enabled (`U.S.` and `Russian – PC` by default; `language-relay setup` enables whichever pair is configured).

## Controls

| Module | Choices |
| --- | --- |
| Scope | Last phrase · Last word |
| Case | `aA` Preserve · `Aa` Sentence · `AA` Uppercase · `aa` Lowercase |
| Triggers | Double Shift · clean Option |
| Feedback | Pulse · Relay · Scan · Flux · Prism · Tick · Fold · Nova |
| Level | Mute 00 · Low 25 · Mid 55 · High 82 |

Given `hELLO`, the case modes produce `hELLO`, `Hello`, `HELLO`, and `hello`.

## Agent CLI

The native binary and the npm shim return stable JSON without logging input text:

```bash
language-relay setup
language-relay convert ghbdtn
language-relay status
language-relay doctor
language-relay capabilities
language-relay switch
```

`language-relay setup` enables the configured pair (default or picked in the panel) as active macOS input sources; `doctor` reports the configured pair and a `blocker` explaining why it fell back to the default pair, if it did.

Direct native surface:

```bash
"$HOME/Applications/Language Relay.app/Contents/MacOS/LanguageRelay" --convert-json ghbdtn
"$HOME/Applications/Language Relay.app/Contents/MacOS/LanguageRelay" --doctor-json
"$HOME/Applications/Language Relay.app/Contents/MacOS/LanguageRelay" --capabilities-json
```

The bundle identifier and preferences domain remain `dev.alex.layout-pilot` so existing settings survive the rename.

## Gesture ownership and Karabiner

Karabiner transforms hardware events before macOS posts its virtual-keyboard output, so Language Relay can coexist with Caps / Hyper rules when those rules do not emit a clean standalone Option or Double Shift.

If another layout utility owns Double Shift or Option, keep one gesture owner active. Language Relay suspends its repair gestures when it detects a known owner and keeps menu, Caps / Hyper, and CLI access.

## Other languages

The layout pair is configurable: pick any two of your currently enabled keyboard input sources from the panel picker, stored as `sourceLayoutID` / `targetLayoutID` under `dev.alex.layout-pilot`. The Carbon mapping engine works with any deterministic keyboard-layout pair — Latin/Cyrillic, Latin/Greek, Latin/Hebrew, Apple's standard `Russian` instead of `Russian – PC`, and so on — because it builds its stroke tables from whatever `TISInputSource` you pick, not from a fixed identifier. Same-script pairs are harder to detect automatically, while IME, dead-key, and compose layouts need a separate architecture and are out of scope.

## Build and QA

```bash
make test
make install
make integration-test
```

The default suite stays in the background: no app window, focus change, keyboard event, or sound playback. `make live-integration-test` is the separate manual lane.

## Architecture

- Swift/AppKit menu-bar app and CLI;
- Carbon `UCKeyTranslate` layout maps;
- Hammerspoon clean-modifier state machine and verified fallback;
- LaunchAgent background startup;
- vendored ShaperKit primitives;
- MIT code and documented sound provenance.

See [SECURITY.md](SECURITY.md), [ASSET-LICENSES.md](ASSET-LICENSES.md), and [CONTRIBUTING.md](CONTRIBUTING.md).
