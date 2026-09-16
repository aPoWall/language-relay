# Language Relay · requirements ledger

One row per requirement that reached this product from the AI Mindset apps sprints (waves 3 to 9,
`lab-sites/internal-sites/aim-product-system/SPRINT-2026-09-*.md`) and from the rule book
`AIM-APPS-RULES.md`. Status is what the code and the tests show today, not what a changelog promised.
Wave 9 (`SPRINT-2026-09-17-JANITOR.md` § D) asked for this ledger and for the leftovers to be closed.

Legend: `done` shipped and asserted by a test or a stand run · `open` still to do · `exception` declared
deviation with a reason · `blocked` waits for a decision or an access outside the product.

## Panel, window and shell

| id | requirement | source | status | date |
|----|-------------|--------|--------|------|
| P1 | header contract: live mark 40 pt, product name, version, `settings`, always visible close | wave 3 § B, rules 21, 32 | done · `--ui-self-test` asserts header order and mark size | 2026-09-14 |
| P2 | bottom line in three parts: keys · `esc close` · version and health, 11 pt muted | wave 3 § B, rule 22 | done · `--ui-self-test` footer checks | 2026-09-14 |
| P3 | 16 pt grid for content, gaps and buttons | wave 3 § B, rule 23 | done · `--ui-self-test` grid check | 2026-09-14 |
| P4 | content laid out before the panel shows, only the mark moves on appear | wave 3 § B, rules 24, 28 | done · appear tokens asserted, panel 200 ms | 2026-09-16 |
| P5 | shell frame 420 x 488, the mark does not widen it | wave 3 § B, rule 25 | done · `panelWidth`/`panelHeight` in `--design-json` | 2026-09-14 |
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
| M3 | menu bar icon and header mark are one drawing from `aim-app-marks.svg` | wave 7 § A, rule 39 | done · `AIMAppMarkView`, `RelayMarkGlyph` deleted | 2026-09-16 |
| M4 | the mark rework of wave 6 (`relay-arch`) | wave 6 § C | superseded · wave 9 header returns the product to the two arrows; `relay-arch` stays in the svg as a resolved id | 2026-09-16 |
| M5 | vendored exports byte for byte, verified by sha-256 | wave 3 § A, rule 10 | done · `make design-check`, 18 artifacts | 2026-09-17 |

## Gestures and live layout

| id | requirement | source | status | date |
|----|-------------|--------|--------|------|
| G1 | repair gestures ⇧⇧ and ⌥ switchable, the footer names only the ones that are on | wave 3, wave 4 | done · `gesture-shift`, `gesture-option`, footer keys check | 2026-09-14 |
| G2 | panel at or below 2 % CPU during a layout switch, a cue and a gesture | wave 3 § B | done · measured 2.3.7, re-measured for 2.5.0 in `docs/QA-2026-09-17.md` | 2026-09-17 |
| G3 | the panel reading of the active layout follows a live input source change | wave 9 § D | done · `--live-json --seconds N`, read only, samples the system source and the panel reading and reports every switch it sees | 2026-09-17 |
| G4 | full live keyboard run (`make live-integration-test`) | repo harness | blocked by the sprint boundary · the harness activates a window and emits keys, which takes the focus and the layout of the working machine; it runs when the Mac is free, not during a wave | 2026-09-17 |

## Controls, tests and release

| id | requirement | source | status | date |
|----|-------------|--------|--------|------|
| C1 | every control walked on the stand, table control -> press -> what changed | wave 4 § 4, wave 7 § C, rules 38, 41 | done · `docs/QA-2026-09-16-c.md`, refreshed for 2.5.0 | 2026-09-17 |
| C2 | windows only through `--testbed`, no synthetic click, no activation, cursor untouched | wave 5 § A | done · every run in this repo goes through `--testbed` and `axdrive` | 2026-09-17 |
| C3 | release through `release-app.mjs relay --install`, zip, SHA, release notes, page version | wave 3 § C, rule 13 | done for 2.5.0 | 2026-09-17 |
| C4 | install through the product installer with a backup, no process killed | wave 2, wave 9 boundaries | done · `./install-runtime.sh update-background` keeps the previous bundle | 2026-09-17 |
| C5 | signing identity that survives a rebuild, so permissions stay granted | wave 3 § C, rule 26 | blocked · the `AIM Mini Apps` identity waits for Alex to trust it; builds stay ad-hoc, commands are in `RELEASE-PIPELINE.md` | 2026-09-14 |
| C6 | product page: version, what's new, zip, SHA, panel screenshot, EN and RU | wave 3 § D, rules 11, 12 | done for 2.5.0 | 2026-09-17 |
