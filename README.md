# Layout Pilot

Personal native macOS status-bar utility for Alex's exact input-source pair:

- `com.apple.keylayout.US` – U.S.
- `com.apple.keylayout.RussianWin` – Russian – PC

## Behavior

- tap `Caps Lock` – Karabiner toggles U.S. / Russian – PC through `~/bin/input-source-toggle`;
- press `Shift` twice or tap `Option` alone – Layout Pilot converts selected text, or the last wrong-layout phrase before the cursor;
- an `Option` tap with no correctable text switches the input source; `Option` combined with another key never triggers;
- after conversion, the system input source follows the converted language;
- the menu bar shows an elongated `A ⇄ РУ` glyph; left click opens the Shaper control panel, right click opens quick actions;
- correction first replaces a writable `AXValue` and verifies the read-back without creating a selection; web/Electron fallback verifies deletion before a clipboard-preserving paste, preventing duplicated text;
- capitalization is configurable as `preserve`, `sentence`, or `uppercase`;
- success feedback is configurable as `Pop`, `Glass`, `Ping`, `Purr`, or silent;
- all conversion is local; there is no network, telemetry, typed-text log, SQLite, or notification history.

The character map is generated from the two installed macOS layouts through Carbon `UCKeyTranslate`. It therefore uses the actual Russian – PC punctuation map rather than a hard-coded generic Russian table.

## Build and test

```bash
make test
make install
```

Full Xcode is not required. The build uses the Apple Swift compiler from Command Line Tools.

## Runtime

Installed app:

```text
~/Applications/Layout Pilot.app
```

LaunchAgent:

```text
~/Library/LaunchAgents/dev.alex.layout-pilot.plist
```

The input bridge runs inside the already trusted Hammerspoon process. Layout Pilot itself therefore needs no additional Accessibility grant. The bridge never persists typed text, never creates its own visible selection, verifies writable AX fields before reporting success, stops any previous event tap when reloaded, and preserves every pasteboard item when an app requires the event fallback.

Caramba Switcher is disabled in Login Items while Layout Pilot is active, avoiding two simultaneous keyboard event monitors. The Caramba app remains installed for rollback.

## Background verification

```bash
make integration-test
```

The default suite never takes keyboard focus. It checks both conversion directions, phrase conversion, code signature, Hammerspoon bridge health, LaunchAgent state, process count, and the disabled Caramba conflict.

The separate `make live-integration-test` target drives a temporary Cocoa field and is reserved for manual QA when taking focus is acceptable.

## Diagnostic commands

```bash
"$HOME/Applications/Layout Pilot.app/Contents/MacOS/LayoutPilot" --self-test
"$HOME/Applications/Layout Pilot.app/Contents/MacOS/LayoutPilot" --ui-self-test
"$HOME/Applications/Layout Pilot.app/Contents/MacOS/LayoutPilot" --convert ghbdtn
"$HOME/Applications/Layout Pilot.app/Contents/MacOS/LayoutPilot" --convert-json ghbdtn --capitalization sentence
"$HOME/Applications/Layout Pilot.app/Contents/MacOS/LayoutPilot" --status
"$HOME/Applications/Layout Pilot.app/Contents/MacOS/LayoutPilot" --switch
```

## Rollback

Unload `dev.alex.layout-pilot`, remove the app from `~/Applications`, then re-enable Caramba Switcher in Login Items if desired. Caramba itself remains installed and untouched.
