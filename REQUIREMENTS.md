# Language Relay · requirements ledger

One row per requirement that reached this product from the AI Mindset apps sprints (waves 3 to 10,
`lab-sites/internal-sites/aim-product-system/SPRINT-2026-09-*.md`) and from the rule book
`AIM-APPS-RULES.md`. Status is what the code and the tests show today, not what a changelog promised.
Wave 9 (`SPRINT-2026-09-17-JANITOR.md` § D) asked for this ledger and for the leftovers to be closed.
Wave 10 (`SPRINT-2026-09-17-MENUBAR.md` § A, B, C) added the bar contract, the character in the header and the
global combination; those rows are the `B1` to `B3`, `M6` and `K1` to `K3` entries below.

A review of wave 10 on 2026-09-17 added the `M7` and `K4` rows and closed the dead bar-mode state; build 25
carries them.

Legend: `done` shipped and asserted by a test or a stand run · `open` still to do · `exception` declared
deviation with a reason · `blocked` waits for a decision or an access outside the product.

## Panel, window and shell

| id | requirement | source | status | date |
|----|-------------|--------|--------|------|
| P1 | header contract: live mark 40 pt, product name, version, `settings`, always visible close | wave 3 § B, rules 21, 32 | done · `--ui-self-test` asserts header order and mark size | 2026-09-14 |
| P2 | bottom line in three parts: keys · `esc close` · version and health, 11 pt muted | wave 3 § B, rule 22 | done · `--ui-self-test` footer checks | 2026-09-14 |
| P3 | 16 pt grid for content, gaps and buttons | wave 3 § B, rule 23 | done · `--ui-self-test` grid check | 2026-09-14 |
| P4 | content laid out before the panel shows, only the mark moves on appear | wave 3 § B, rules 24, 28 | done · appear tokens asserted, panel 200 ms | 2026-09-16 |
| P5 | shell frame 420 x 488, the mark does not widen it | wave 3 § B, rule 25 | superseded · wave 10 adds the `menu bar + hotkey` row and the default frame is 420 x 554; `panelWidth`/`panelHeight` in `--design-json`, the page, the README and DESIGN carry the new pair. Rule 25 in the shared rule book still prints 420 x 488 and is the coordinator's line to change | 2026-09-17 |
| P6 | shell built from the shared L2 components, no private copies | wave 7 § B, rule 40 | done · `AIMAppHeader`, `AIMFooterLine`, `AIMPinButton`, `AIMSurface` | 2026-09-16 |
| P7 | one close: escape, ⌘W, `×`, bar item, hotkey, testbed route reach one `close(reason:)` | wave 5, rules 29, 33 | done · `closeReasons` in `--design-json` | 2026-09-16 |
| P8 | transient panel, pin off by default, one `AIMPinButton` with identifier `pin-panel` | wave 5, wave 6 § C, rule 31 | done · migration key `migratedPinToTransient.2.4.0` | 2026-09-16 |
| P9 | hint card from the shared component carries every blocker the panel reports | wave 5 § notifications, rule 30 | done · `AIMHintCard` renders the blocker states, 2.5.0 | 2026-09-17 |
| P10 | version sits in the right edge slot of the header, before `settings` | wave 6, rule 32 | exception · the 388 pt content row holds mark, name and three 28 pt buttons; version reads on the status line under the name and in the bottom line, both slots of rule 22 | 2026-09-16 |

## Mark and character

| id | requirement | source | status | date |
|----|-------------|--------|--------|------|
| M1 | light relay character, two arrows with a gap and a red tip, under 110 voxels | wave 3 § A, rule 5 | done · the dense first version is back by Alex's call of 2026-09-16 | 2026-09-16 |
| M2 | one finite gesture on click (`mirror`), assemble 700 ms, hover lift 2 pt | wave 3 § A, rules 7, 8 | done · `AIMVoxelMotion` from the shared export | 2026-09-14 |
| M3 | menu bar icon and header mark are one drawing from `aim-app-marks.svg` | wave 7 § A, rule 39 | amended by wave 10 § B · the bar, About and the favicons keep the flat drawing through `AIMAppMarkView`; the header carries the voxel character. One source for the flat mark still holds, `AIMAppMarks.sourceSHA256` is checked | 2026-09-17 |
| M4 | the mark rework of wave 6 (`relay-arch`) | wave 6 § C | superseded · wave 9 header returns the product to the two arrows; `relay-arch` stays in the svg as a resolved id | 2026-09-16 |
| M5 | vendored exports byte for byte, verified by sha-256 | wave 3 § A, rule 10 | done · `make design-check`, 18 artifacts; wave 10 re-synced `aim-app-marks.svg` (`401c8793…`) after the prism glyph was simplified upstream | 2026-09-17 |
| M6 | the voxel character stands in the panel header at 40 pt and answers the cursor and a click; the flat mark lives in the bar, About and the favicons | wave 10 § B | done · `header-character` in `--ui-self-test` and in the stand tree, the shot `relay-251-b25-panel.png`; `AXPress` on the character is refused by design, the gesture needs a key window (`docs/QA-2026-09-17-menubar.md`) | 2026-09-17 |
| M7 | one slot name across the family: the header character answers to `header-character`, as it does in MEM PRISM and Calendar Control, so the rule 41 walk and the rule 48 check read three headers with one selector | review of wave 10, rules 41, 48 | done in build 25 · the id sits on the view and on its accessibility element; the version line under the name keeps `product-version` and the other two name that node not at all, so a family-wide id for the version slot belongs in `AIMAppShell.swift` and is the coordinator's line. Relay's header also carries no tagline node, which the other two have | 2026-09-17 |

## Gestures and live layout

| id | requirement | source | status | date |
|----|-------------|--------|--------|------|
| G1 | repair gestures ⇧⇧ and ⌥ switchable, the footer names only the ones that are on | wave 3, wave 4 | done · `gesture-shift`, `gesture-option`, footer keys check | 2026-09-14 |
| G2 | panel at or below 2 % CPU during a layout switch, a cue and a gesture | wave 3 § B | done · panel open and idle on 2.5.0: 0.2 to 0.6 per cent over six samples (`docs/QA-2026-09-17.md`); the repair, cue and gesture paths keep the 2.3.7 measurement, since firing a repair moves the input source of the working machine | 2026-09-17 |
| G3 | the panel reading of the active layout follows a live input source change | wave 9 § D | done · `--live-json --seconds N`, read only; on an idle Mac two switches through the product's own route were read back at 2.36 s and 4.43 s with the layout restored (`docs/QA-2026-09-17.md`); the first build of the watch missed them and was fixed in build 23 | 2026-09-17 |
| G4 | full live keyboard run (`make live-integration-test`) | repo harness | blocked by the sprint boundary · the harness activates a window and emits keys, which takes the focus and the layout of the working machine; it runs when the Mac is free, not during a wave | 2026-09-17 |

## Menu bar and keys

| id | requirement | source | status | date |
|----|-------------|--------|--------|------|
| B1 | one bar contract: four modes `mark` (default), `mark + value`, `value`, `hidden` with a confirmation; `smart` removed; a stored setup migrates once | wave 10 § A | done · `RelayMenuBarMode`, key `menuBarMode`, migration key `migratedMenuBarMode.2.5.1`, asserted in `--ui-self-test` | 2026-09-17 |
| B2 | a click on the item opens the panel, a second click closes it; the position survives a rebuild | wave 10 § A | done · `statusItemAction` since 2.4.1, `autosaveName dev.alex.layout-pilot.status-item.v3` | 2026-09-17 |
| B3 | the settings row `menu bar` shows a live preview of the item in the chosen mode | wave 10 § A | done · `menu-bar-preview` beside `menu-bar-mode`, redrawn on a mode change and on a layout switch, four states in `relay-251-bar-modes.png` | 2026-09-17 |
| K1 | one global combination opens and closes the panel, ⌥⌘L by default, changed in the product settings | wave 10 § C | done · `RelayHotkeyCombo`, Carbon registration, `.hotkey` in `closeReasons` | 2026-09-17 |
| K4 | how deep the combination is editable | review of wave 10, rule 49 | exception · Relay offers a curated list of four combinations plus off (`RelayHotkeyCombo.choices`), while MEM PRISM ships a free recorder, so rule 49 reads at two depths across the family and the design-system demo of block 19 matches the recorder alone. The list stays until the coordinator sets one shape for the four products in rule 49; Relay follows whichever shape lands | 2026-09-17 |
| K2 | a combination that conflicts is shown in a red line and is not stored | wave 10 § C | done · the section heading turns to the accent colour and prints the refusal; Carbon reports an app-held and a system-held combination the same way, which the QA notes as open | 2026-09-17 |
| K3 | the bottom line names the combination | wave 10 § C | done · `hint-keys` reads `⌥⌘L ⇧⇧⌥ repair`, and the self-test measures all three parts so the right one stops truncating | 2026-09-17 |

## Controls, tests and release

| id | requirement | source | status | date |
|----|-------------|--------|--------|------|
| C1 | every control walked on the stand, table control -> press -> what changed | wave 4 § 4, wave 7 § C, rules 38, 41 | done · the full walk of every control is `docs/QA-2026-09-16-c.md`; the setup block of 2.5.0 is walked in `docs/QA-2026-09-17.md` and the wave 10 block in `docs/QA-2026-09-17-menubar.md`, where the two menu buttons are driven through their testbed routes because a non-activating panel cannot hold an NSMenu | 2026-09-17 |
| C2 | windows only through `--testbed`, no synthetic click, no activation, cursor untouched | wave 5 § A | done · every run in this repo goes through `--testbed` and `axdrive` | 2026-09-17 |
| C3 | release through `release-app.mjs relay --install`, zip, SHA, release notes, page version | wave 3 § C, rule 13 | done for 2.5.1 build 25 · zip `f6f43950…73e4dd57` in `sites/apps/language-relay/`, `SHA256SUMS.txt` and the page version updated, nothing committed in `lab-sites` | 2026-09-17 |
| C4 | install through the product installer with a backup, no process killed | wave 2, wave 9 boundaries | done · `./install-runtime.sh update-background` keeps the previous bundle | 2026-09-17 |
| C5 | signing identity that survives a rebuild, so permissions stay granted | wave 3 § C, rule 26 | blocked · the `AIM Mini Apps` identity waits for Alex to trust it; builds stay ad-hoc, commands are in `RELEASE-PIPELINE.md` | 2026-09-14 |
| C6 | product page: version, what's new, zip, SHA, panel screenshot, EN and RU | wave 3 § D, rules 11, 12 | done for 2.5.1 · new stand shot `assets/window.png`, the frame line reads 420 × 554, the feature tiles name the bar modes and the combination in both languages | 2026-09-17 |
