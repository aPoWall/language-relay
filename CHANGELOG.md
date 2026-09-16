# Changelog

## 2.4.0 build 16 – 2026-09-16

- new product mark (rule 4, new idea = new symbol id): `aim-app-marks.svg` gains `relay-arch`, an arch with a
  landing chevron – the run leaves one alphabet, crosses the bridge and lands in the other; the old `relay` id
  stays in the file with the same paths so every shipped reference keeps resolving. Three variants (arch, key
  caps, exchange ring) and the reason for the choice: `docs/design/relay-mark-2.4.0.md`, contact list
  `docs/design/relay-mark-contacts.svg`;
- live character rebuilt under the new mark: 80 voxels (was 36), a stepped arch two sheets deep, mid apex,
  light body, ink feet, one red voxel on the landing foot; the gesture is `mirror` on `x`, so a click moves the
  landing foot to the other leg (on `z` two identical bars swapped and the click looked dead);
- menu bar carries the mark glyph, not the mono voxel block (rule 26): `RelayMarkGlyph.mark(size: 18)` draws
  frame, arch and signal as a template image, the alphabet cell and the status arrow keep their places (54 × 18);
- pin migrates once to transient (rule 29): `migratedPinToTransient.2.4.0` sets `pinned` back to off for an
  install that had it on, a later choice survives; the UI self-test covers both runs;
- vendored N1 exports `2026.09.16-n1` with the new models (`AIMVoxelModels.swift`, `docs/design/voxel-models.json`,
  `docs/voxel-relay.svg`); `make design-check` and the product-system `check.mjs` pass.

## 2.3.9 build 15 – 2026-09-16

- one appear transition for the AIM mini apps (AIM-APPS-RULES rule 28): the popover animates over the shared token `motion-panel-appear` (200 ms, the system popover fade), `RelayStyle` also exposes `motion-window-appear` (180 ms) and `motion-window-appear-shift` (6 pt) for framed windows; Reduce Motion turns every value into 0 and shows the finished frame at once; `language-relay design` reports `panelAppear`, `windowAppear`, `windowAppearShift`;
- closing contract (rule 29): the panel is transient by default, an outside click closes it; the header gets a pin button `◉/○` (28 pt, between `settings` and `×`, the same glyphs and wording as MEM PRISM, `dev.alex.layout-pilot.pinned`, default off); `×`, Escape, Command-W, the bar click, the outside click and the testbed `hide` route all end in `popoverDidClose`; for the non-activating testbed presentation the outside click is read by a global mouse-down monitor (fact of the click only, nothing is sent, nothing moves);
- vendored the N1 exports `2026.09.16-n1` byte for byte: `AIMMiniAppTokens.swift` (motion-panel-appear, motion-window-appear, hint-border, hint-radius) and the new shared `AIMHintCard.swift` (compiled into the app so the receipt hash and the typecheck cover it; the panel does not show a hint card yet);
- `--testbed show|hide|toggle` (build 14): the running instance presents the panel without activation, anchored in the bottom-right corner of the main screen (24 pt inset), for agent checks through `axdrive` (rule 27); the user's app stays frontmost, the cursor does not move; the anchor window is dropped when the popover closes;
- the UI self-test asserts the appear tokens, the pin default and the pin button in the header; QA table in `docs/QA-2026-09-16.md`, run on the testbed without a synthetic click.

## 2.3.8 – 2026-09-14

- Command-W closes the panel like Escape and the `×` button (window contract, rule 21); the root view handles the key equivalent because the accessory app carries no main menu;
- every panel button stays in the Tab order even when macOS Full Keyboard Access is off (`canBecomeKeyView`, Tab handled inside `RelayButton`), and the popover window gets an explicit key view loop on show and rebuild, so the focus ring is reachable from the keyboard everywhere;
- the footer names only the repair gestures that are switched on (`⇧⇧ ⌥ · repair`, `⇧⇧ · repair`, `⌥ · repair`, `gestures off`) instead of promising both keys;
- `--render-ui out.png [--expanded] [--health ready|denied|unavailable]` renders the bridge and permission states offscreen, `--key-loop` prints the Tab order; both for QA;
- the UI self-test covers the Command-W equivalent, the key view reach and the footer keys; QA table with 40 checks in `docs/QA-2026-09-14.md`;
- product page: the hero caption wraps and the SHA line breaks at 390 px (no horizontal scroll), hero screenshot of the 2.3.8 panel, download 2.3.8 with SHA-256.

## 2.3.7 – 2026-09-14

- one window contract for the AIM mini apps (AIM-APPS-RULES 21–26): the panel header is live mark 40 pt · name · version · `settings` · `×` 28 pt on one line, the footer reads keys · `esc close` · version · status in 11 pt Plex 500 muted and sits on the 16 pt grid;
- `settings` opens the same three actions as the status item's right-click menu (setup details, switch layout, quit); `×` and Escape both close the panel;
- vendored the light relay character v2 (36 voxels, two light arrows, red tip): assembles in 0.7 s after the first drawn frame, lifts 2 pt on hover, and on click scatters 0.25 s, reassembles 0.55 s and swaps the arrows; the panel content is drawn before the popover shows, nothing else moves;
- the 1/16 s timer runs only during a run and only while the popover is visible; layout switch, cue playback and the gesture leave the app at or below 2 % CPU with the panel open;
- `language-relay design` reports `markSize` and `windowContract`; the UI self-test checks the header buttons, the footer and the mark size;
- product page: `what's new` from `release-notes.txt` (five entries, EN/RU heading), the real panel screenshot in the hero, the N1 social card with the character, download of the zip with SHA-256 and date.

## 2.3.6 – 2026-09-14

- added the live product mark: the relay voxel character sits in the panel header (44 pt, inside the unchanged 420×488 shell), follows the cursor with a ±3 pt depth parallax and reassembles on click, Space or Return in one finite 1.6 s sequence; Reduce Motion keeps the still frame;
- replaced the two-cell menu glyph with the same character as an 18 pt template image next to the active alphabet cell (54×18 stays);
- vendored the shared `AIMVoxelModels.swift` and `AIMVoxelView.swift` byte for byte into `native/`, hashed by the same design receipt as `AIMMiniAppTokens.swift`; `make design-check` verifies all ten artifacts;
- `language-relay design` reports `liveMark`, `voxelModelsVersion`, `voxelModelsSHA256` and `voxelCount`;
- the UI self-test checks the header mark, the template menu image and the single red signal of the model;
- product page: one shared `aim-i18n.js` switch (en default, ру via `#lang-toggle` and `?lang=ru`), the interactive character in the hero, sections hero → one example → features → install → privacy.

## 2.3.5 – 2026-09-13

- adopted generated N1 Swift/CSS tokens with verified artifact receipts;
- kept the 420×488 native panel and bundled Plex fonts;
- preserved keyboard focus across panel refreshes and added local arrow navigation;
- added a finite setup disclosure transition with immediate reduced-motion state;
- exposed installed design identity through `language-relay design`;
- aligned the product page, package help and panel image with the native release.

## 2.3.4 – 2026-09-12

- applied the native-white G2 palette with bundled IBM Plex Mono, neutral controls and short active indicators;
- fixed the panel at 420×488 points for both collapsed and expanded setup, with 8pt controls and a 16pt shell;
- corrected false setup warnings by checking Hammerspoon's verified Accessibility/bridge state when it owns repair gestures;
- separated the unchanged 2.3.3 bridge protocol from the native app version;
- added six offscreen health/disclosure layouts and a background update lane with verified rollback copies before replacement.

## 2.3.3 – 2026-09-07

- changed the default correction scope to Last Word and added a one-time migration from the old phrase default;
- routed standard repairs through undo-friendlier edit events by default, with direct AXValue writes left as an explicit compatibility fallback;
- added background coverage for special-character suffixes, default scope, direct-AX routing, and bridge shutdown;
- made menu-bar Quit and `language-relay quit` stop the Hammerspoon repair bridge instead of leaving the system gestures active;
- refreshed the website copy and demo so word repair is the visible default.

## 2.3.2 – 2026-08-25

- expanded doctor schema with input-source, Accessibility owner, Hammerspoon IPC, LaunchAgent, and app-process health;
- bounded native `hs.ipc` calls and made settings reload complete before the next repair gesture;
- added an idempotent `language-relay setup` checklist that enables the required input sources, installs the Hammerspoon load line, guides Accessibility approval, and reports missing prerequisites;
- added staged install validation and automatic rollback snapshots;
- redesigned the menu-bar panel around one compact status/header, stable segmented controls, and progressive setup details;
- replaced the scripted repair proof with a real bidirectional U.S. ⇄ Russian–PC browser relay;
- added clean Double Shift, phrase/word scope, and four capitalization modes to the live demo;
- turned the hero demo into a compact editor with synchronized case, scope, cue, example, Double Shift, and clean Option controls;
- added a source-native 1080×1350 product poster for Telegram and social publishing;
- rewrote the product story around one concrete `ghbdtn → привет` moment, local privacy, and the agent contract;
- redesigned the developer mark, favicon, social card, and author signature as one compact identity;
- removed comparison-led positioning from the public product surface.

## 2.3.1 – 2026-08-13

- simplified the menu-bar glyph to two language cells and one compact relay;
- collapsed the input module into a readable active-state rail plus a square switch;
- redrew the application icon, favicon, and social card as one a ⇄ я identity;
- increased landing-page type sizes and rewrote the story around the concrete repair moment;
- added a background-rendered product preview and a full maker credit;
- added a repeatable terminal-input path that avoids AX selection writes and collapses stale terminal selections before repair.

## 2.3.0 – 2026-08-13

- renamed the product and public surface to **Language Relay**;
- replaced the framed app icon with a size-aware relay-core mark;
- added Prism, Tick, Fold, and Nova procedural micro-SFX;
- added Caramba trigger-owner detection and safe gesture suspension;
- added JSON status, doctor, and capabilities surfaces for agents;
- added a GitHub-backed `npx` installer shim;
- rebuilt the mini-site with RU/EN glitch localization, custom sound pads, and an interactive repair proof.

## 2.2.0 – 2026-08-13

- renamed Layout Pilot to **Type Relay**;
- introduced the **aPoWall Instruments** product family;
- replaced directional layout selection with current state plus one switch action;
- added preserve, sentence, uppercase, and lowercase modes;
- added unified phrase/word scope glyphs;
- added clean standalone Option detection tests;
- added four short generated feedback sounds and four volume presets;
- refreshed the application and menu-bar iconography;
- vendored ShaperKit for standalone builds;
- made paths portable for public GitHub installation.

## 2.1.0 – 2026-08-13

- added atomic Accessibility replacement with read-back verification;
- added guarded event fallback to prevent duplicated text;
- added Last Phrase and Last Word modes;
- added Double Shift and clean Option triggers;
- introduced the native menu-bar control panel.
