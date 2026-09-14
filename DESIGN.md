# N1 · native white

Language Relay 2.3.6 adopts the generated N1 profile. Its SSOT is
`ai-mindset-org/lab-sites`, `internal-sites/aim-product-system/mini-apps.tokens.json`.
`native/AIMMiniAppTokens.swift`, `native/AIMVoxelModels.swift` and `native/AIMVoxelView.swift` are byte-identical exports. `native/NativeWhite.swift`
maps its semantic roles into AppKit colors, geometry, font registration and controls.
Vendored and shared ShaperKit remain unchanged.

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
short red marker, and keyboard focus has an inset red ring. Escape closes the
panel. The menu glyph remains a system template image for light/dark menu bars.

## Live mark · 2026-09-14

The relay voxel character (52 voxels, one red signal) is the dynamic product mark.
`AIMVoxelView` draws it in the panel header at 44 pt next to the name, inside the same
420×488 shell (the identity column narrowed from 252 to 201 pt). Hover shifts cubes by
depth up to ±3 pt; click, Space or Return runs scatter → assemble once, 1.6 s at 16 ticks
per second, only while the popover is visible. Reduce Motion keeps the still frame and a
click only moves the red signal to a neighbouring cell. The menu bar shows the same
character as an 18 pt template image (`AIMVoxelView.image(model:size:mono:)`) beside the
active alphabet cell; the 54×18 template glyph size is unchanged. The app icon is not
redrawn in this wave.

## Generated contract

`docs/design/aim-mini-apps.receipt.json` records the exact source and asset hashes.
Run `make design-check` before shipping; update only through the documented sync
script. Native `--design-json` reports the compiled token identity and bundle version.
App `Info.plist` is the native version source; npm metadata is checked at release.

Setup disclosure uses the N1 160 ms state fade. It ends once, never loops, and
reduced motion shows the final state immediately. The OS owns popover show/hide
timing; its animation is disabled for reduced motion. The 420×488 shell and
30–36 pt native controls deliberately retain the accepted compact layout rather
than the web profile's 44 px touch targets. Native text remains 10–17 pt; the
generated web type scale does not enlarge this utility. Hover, red selection
marker and red inset focus ring are separate cues.

All controls have stable identities. Panel rebuilds restore focus to the same
control, including the setup show/hide pair. Left/Right selects adjacent segments;
Space/Return activates the focused control. UI QA dispatches events only to local
offscreen controls and never posts a system keyboard event.

The product website vendors the same CSS export and fonts. The page demo stays
browser-local and does not own native repair gestures. Shared app catalog and
shared source remain owned by the mini-apps design system task.

## Local verification · 2026-09-13

- App 2.3.5 (10), N1 2026.09.13-n1. Shared source commit `d4558e3` in lab-sites.
- Token source SHA-256 `057f940f65b14a27cb72bffc6a21cb313bb576a49c04cb2b7678cbe326af8f78`.
- Core, offscreen state/focus/local-arrow and background runtime checks pass.
- Website: English/Russian, word/phrase conversion, 1440/390 px, fonts, images,
  overflow, reduced motion and console checked in headless Chromium.
- Background update preserved preferences and the exact bridge bytes. Rollback
  snapshot: `Rollback/20260913T004322Z` in the existing Application Support path.
- Installed executable SHA-256: `d5124ddc4bb94ba4d13da67f85bc8fd8787f4cc44581cad4ef9a0d5804b93b7d`.
- Global input gestures and audible previews were not dispatched. Native OS
  popover animation was not visually exercised in the user's foreground session.

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
