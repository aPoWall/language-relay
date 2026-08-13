# Type Relay

**Type Relay** is a tiny native macOS instrument that repairs text typed in the wrong keyboard layout. It is part of **aPoWall Instruments** – a family of focused productivity tools by Alex Povaliaev.

It currently supports this exact pair:

- `U.S.` – `com.apple.keylayout.US`
- `Russian – PC` – `com.apple.keylayout.RussianWin`

All text conversion happens locally. There is no telemetry, typed-text log, account, database, or network request at runtime.

## What it does

- `⇧ ⇧` – repair the latest wrong-layout text;
- clean `⌥` tap – repair text, or switch layout when there is nothing to repair;
- `⌥` combined with Command, Shift, Control, or a typed key is ignored;
- optional Caps Lock mapping can switch the input source directly;
- current layout is visible in a compact `A ⇄ РУ` menu-bar glyph;
- left click opens controls, right click opens quick actions;
- writable Accessibility fields are replaced atomically and verified;
- web/Electron fallback verifies deletion before paste, avoiding duplicated text;
- clipboard contents are restored after fallback paste.

## Controls

### Scope

| Mode | Result |
| --- | --- |
| **Last phrase** | repairs the current language run before the cursor |
| **Last word** | repairs one token before the cursor |

### Letter case

Given `hELLO`, the four modes are explicit:

| UI | Mode | Result |
| --- | --- | --- |
| `aA` | Preserve | `hELLO` |
| `Aa` | Sentence | `Hello` |
| `AA` | Uppercase | `HELLO` |
| `aa` | Lowercase | `hello` |

### Feedback

Four generated micro-SFX are included: **Pulse**, **Relay**, **Scan**, and **Flux**. Volume presets are **Mute 00**, **Low 25**, **Mid 55**, and **High 82**. Selecting a sound previews it; successful verified repairs use the selected sound.

## Requirements

- macOS 13 or newer;
- Apple Command Line Tools (`swiftc`);
- [Hammerspoon](https://www.hammerspoon.org/) with Accessibility permission;
- both U.S. and Russian – PC input sources enabled in System Settings.

## Install

```bash
git clone https://github.com/aPoWall/type-relay.git
cd type-relay
make install
```

`make install` builds and ad-hoc signs the app, installs it to `~/Applications/Type Relay.app`, installs the LaunchAgent, and copies the bridge to `~/.config/type-relay/hammerspoon.lua`.

Add this once to `~/.hammerspoon/init.lua`:

```lua
dofile(os.getenv("HOME") .. "/.config/type-relay/hammerspoon.lua")
```

Then reload Hammerspoon:

```bash
/opt/homebrew/bin/hs -c 'hs.reload()'
```

## Build and background QA

```bash
make test
make install
make integration-test
```

The default suite stays in the background: no app window, focus change, keyboard event, or sound playback. `make live-integration-test` is a separate manual lane that intentionally drives a temporary text field.

Useful diagnostics:

```bash
"$HOME/Applications/Type Relay.app/Contents/MacOS/LayoutPilot" --self-test
"$HOME/Applications/Type Relay.app/Contents/MacOS/LayoutPilot" --ui-self-test
"$HOME/Applications/Type Relay.app/Contents/MacOS/LayoutPilot" --convert-json GHBDTN --capitalization lowercase
"$HOME/Applications/Type Relay.app/Contents/MacOS/LayoutPilot" --status
```

## Architecture

- **Swift/AppKit** – menu-bar app, settings panel, layout conversion, CLI test surface;
- **Carbon `UCKeyTranslate`** – builds the real mapping from installed keyboard layouts;
- **Hammerspoon** – clean modifier state machine, in-memory typing buffer, Accessibility replacement and verified fallback;
- **LaunchAgent** – background startup without a Dock icon;
- **ShaperKit** – vendored visual primitives for deterministic standalone builds.

The bundle identifier remains `dev.alex.layout-pilot` to preserve settings during the rename from Layout Pilot.

## Privacy and security

Typed text remains in memory only and is cleared on app/focus/mouse/navigation changes and Secure Input. See [SECURITY.md](SECURITY.md) for reporting and the trust boundary.

## Sounds

The bundled sounds were generated with ElevenLabs Sound Effects and edited into short mono AIFF feedback cues. Provenance and attribution are recorded in [ASSET-LICENSES.md](ASSET-LICENSES.md).

## License

Code is released under the [MIT License](LICENSE). Generated audio follows the terms listed in `ASSET-LICENSES.md`.
