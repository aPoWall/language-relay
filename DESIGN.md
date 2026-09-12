# N1 · native white

Language Relay 2.3.4 adopts the Native White tools profile dated 2026-09-12,
based on Calendar Control G2. `native/NativeWhite.swift` owns this app's palette,
font registration and controls. Vendored and shared ShaperKit remain unchanged.

| Role | Value |
| --- | --- |
| Canvas | #ffffff |
| Ink / secondary | #202124 / #6b6e75 |
| Divider | #e8e9ed |
| Hover / selection | #f5f6f8 |
| Data surface | #f2f3f5 |
| Active indicator | #db303d, 16×2 pt |
| Type | Bundled IBM Plex Mono 400/500/600, OFL |
| Controls / shell | 8 / 16 pt radius |
| Footprint | 420×488 pt, including expanded setup |

The panel keeps layout, repair scope, case, gestures and feedback visible. Setup
expands inside reserved space. Hover uses a neutral fill; selection also has a
short red marker, and keyboard focus has an inset ink ring. Escape closes the
panel. The menu glyph remains a system template image for light/dark menu bars.

Health follows the active permission owner. A verified Hammerspoon bridge can be
ready even when the native app lacks Accessibility approval. Unavailable IPC,
missing permission and an inactive/stale bridge retain an actionable setup state.

## Local release verification · 2026-09-12

- Native 2.3.4, build 9; unchanged Hammerspoon bridge protocol 2.3.3.
- `make test`: conversion/setup tests and six offscreen health/disclosure layouts;
  bounds, accessible labels, exclusive groups and all three font weights pass.
- `tests/background.sh`: built/installed bundles, JSON conversion, capitalization,
  UTF-16 boundaries, clean/dirty modifier states, fallback decisions, signature,
  staging, runtime count and stderr pass. No global gesture or audio playback.
- Eight audio assets inspected: mono 44.1 kHz, 16-bit, 70–220 ms.
- Updated the existing app with `install-runtime.sh update-background`.
  Backup `~/Library/Application Support/Language Relay/Rollback/20260912T140359Z`
  passed recursive comparison and signature verification before replacement.
- Preferences before/after are equal. Doctor reports ready, no blockers and an
  active trusted Hammerspoon bridge. One accessory runtime; no visible panel.
- Local installation only. No site, GitHub release or messages published.

Live global shortcuts, focused-field repair and audible cues remain the manual
integration lane. Automated QA did not request or change system permissions.
