# Language Relay · requirements ledger

One row per requirement that reached this product from the AI Mindset apps sprints (waves 3 to 10,
`lab-sites/internal-sites/aim-product-system/SPRINT-2026-09-*.md`) and from the rule book
`AIM-APPS-RULES.md`. Status is what the code and the tests show today, not what a changelog promised.
Wave 9 (`SPRINT-2026-09-17-JANITOR.md` § D) asked for this ledger and for the leftovers to be closed.
Wave 10 (`SPRINT-2026-09-17-MENUBAR.md` § A, B, C) added the bar contract, the character in the header and the
global combination; those rows are the `B1` to `B3`, `M6` and `K1` to `K3` entries below.

A review of wave 10 on 2026-09-17 added the `M7` and `K4` rows and closed the dead bar-mode state; build 25
carries them.

Wave 11 (`SPRINT-2026-09-17-QUIET.md` § B, E) added the bridge watchdog and the offscreen boundary of rule 50;
those rows are `W1` to `W7` and the reworked `P5`, `G4` and `C2` entries below. Build 26 carries them, and the
receipts are `docs/QA-2026-09-17-quiet.md`.

A review of wave 11 on 2026-09-17 found two defects and build 27 carries their repair: the `busy-timeout`
reading was erased by the gesture the release let through, so the released flags moved into a counter of their
own (`W7`); and the owner's machine still ran 2.5.1 build 25 because the only install route left for a changed
bridge was the interactive one, which rule 52 keeps off that machine (`C3`, `C4`).

Legend: `done` shipped and asserted by a test or a stand run · `open` still to do · `exception` declared
deviation with a reason · `blocked` waits for a decision or an access outside the product.

## Panel, window and shell

| id | requirement | source | status | date |
|----|-------------|--------|--------|------|
| P1 | header contract: live mark 40 pt, product name, version, `settings`, always visible close | wave 3 § B, rules 21, 32 | done · `--ui-self-test` asserts header order and mark size | 2026-09-14 |
| P2 | bottom line in three parts: keys · `esc close` · version and health, 11 pt muted | wave 3 § B, rule 22 | done · `--ui-self-test` footer checks | 2026-09-14 |
| P3 | 16 pt grid for content, gaps and buttons | wave 3 § B, rule 23 | done · `--ui-self-test` grid check | 2026-09-14 |
| P4 | content laid out before the panel shows, only the mark moves on appear | wave 3 § B, rules 24, 28 | done · appear tokens asserted, panel 200 ms | 2026-09-16 |
| P5 | shell frame 420 x 488, the mark does not widen it | wave 3 § B, rule 25 | superseded · the default frame is 420 x 672 in build 26: wave 10 added the `menu bar + hotkey` row, wave 11 the `bridge` row, and 52 pt more close a squeeze that arrived with the setup card, where the rows below it were laid out at 14 to 30 pt against the 36 pt they declare. `--ui-self-test` now measures the row height, so the next wave that runs out of room fails instead of shrinking. `panelWidth`/`panelHeight` in `--design-json`, the page, the README and DESIGN carry the new pair. Rule 25 in the shared rule book still prints 420 x 488 and is the coordinator's line to change | 2026-09-17 |
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
| G4 | full live keyboard run (`make live-integration-test`) | repo harness | blocked by rule 50 · the harness activates a window and emits keys, which takes the focus and the layout of the owner's machine. Wave 11 names its home: the VM stand of `internal-sites/aim-product-system/testbed/vm/`. It is not a boundary waiting to be lifted on this Mac | 2026-09-17 |

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

## Bridge watchdog

| id | requirement | source | status | date |
|----|-------------|--------|--------|------|
| W1 | `layoutPilotBusy` gets a lifetime: a flag older than five seconds is released, the status is written `busy-timeout` and the next gesture works | wave 11 § B | done · `layoutPilotBusyTimeout = 5`, released in `layoutPilotFix`; the fresh, the stale and the twice-released flag are checked in `tests/bridge-watchdog.lua`. The reading that survives the gesture is `W7` | 2026-09-17 |
| W2 | every exit of `layoutPilotFix` and `layoutPilotConvert` passes through a reset, the path without one is covered by a test | wave 11 § B | done · the body of the repair runs under `pcall` (`fix-error`), the write inside the conversion callback under its own (`apply-error`), `layoutPilotRestart` drops the flag with the run token, and the flag has one writer, `layoutPilotSetBusy`. The test raises inside the accessibility read, the exact path that held the flag on 2026-09-17 | 2026-09-17 |
| W3 | `layoutPilotStatus()` returns tap, busy, secureInput, lastStatus, settings | wave 11 § B | done · plus `busySeconds`, `busyStale`, `busyTimeout`, `version` and, from build 27, `timeouts` and `timeoutAgo`; read only, it repairs nothing by itself, and `layoutPilotStatusLine()` is the same reading in one line for the app. `--bridge-json` prints it with no window | 2026-09-17 |
| W4 | the panel shows `bridge · <state>` and a `restart bridge` button | wave 11 § B | done · `bridge-status` and `bridge-restart` in the panel, six readings for six states asserted in `--ui-self-test` (build 27 adds `ready · started-shift · 1 timeout 12s ago`), the row measured at 36 pt; the press is verified at the bridge level by the lua test and was not fired on the owner's machine (rule 50) | 2026-09-17 |
| W5 | at launch the app checks the bridge and restarts it once when the tap is off or the flag is stuck, and writes it into the hint | wave 11 § B | done · `repairBridgeAtLaunch()`; a healthy bridge is only asked to re-read its settings, a repaired one adds `restarted at launch, <reason>` to the `bridge` row. Before build 26 the launch restarted the bridge every time, whatever its state | 2026-09-17 |
| W6 | the bridge protocol version follows the change | wave 11 § B, rule 13 | partial · the repository and `~/.config/language-relay/hammerspoon.lua` carry 2.4.1 and the app expects it; Hammerspoon keeps the 2.3.3 it loaded until the owner reloads it himself, which is his press and not the product's. Until then the row reads `2.3.3 · reload for 2.4.1`, verified by `--bridge-json` after the build 27 install, and the gestures keep working on the loaded bridge. `tests/background.sh` compares the live bridge against the installed file instead of a number frozen in the test | 2026-09-17 |
| W7 | the release of a stale flag stays readable after the gesture it let through | review of wave 11, rule 51 | done in build 27 · `layout_pilot_last_status` is volatile: `layoutPilotFix` wrote `started-<trigger>` four lines after the release wrote `busy-timeout`, so the `bridge` row could never show a timeout. The release now also counts itself in `layout_pilot_busy_timeouts` and dates itself in `layout_pilot_busy_timeout_at`; `layoutPilotStatus()` returns `timeouts` and `timeoutAgo`, `layoutPilotStatusLine()` carries nine fields, and the row prints `ready · started-shift · 1 timeout 12s ago`. `tests/bridge-watchdog.lua` asserts the count survives the releasing gesture, and `--ui-self-test` asserts the row text | 2026-09-17 |

## Controls, tests and release

| id | requirement | source | status | date |
|----|-------------|--------|--------|------|
| C1 | every control walked on the stand, table control -> press -> what changed | wave 4 § 4, wave 7 § C, rules 38, 41 | done · the full walk of every control is `docs/QA-2026-09-16-c.md`; the setup block of 2.5.0 is walked in `docs/QA-2026-09-17.md` and the wave 10 block in `docs/QA-2026-09-17-menubar.md`, where the two menu buttons are driven through their testbed routes because a non-activating panel cannot hold an NSMenu | 2026-09-17 |
| C2 | no window on the owner's machine: offscreen render, accessibility without a show, snapshot of an open window by id | wave 5 § A, wave 11 § C, rule 50 | done · wave 11 used `--self-test`, `--ui-self-test`, `--bridge-json`, `--render-ui` and `make bridge-test` only; `--testbed` was not used and no window was shown. The route stays for debugging on an explicit ask | 2026-09-17 |
| C3 | release through `release-app.mjs relay`, zip, SHA, release notes, page version | wave 3 § C, rule 13 | done for 2.5.2 build 27 · zip `bd1d6379…a88674b6` in `sites/apps/language-relay/`, `SHA256SUMS.txt`, release notes and the page SHA updated, nothing committed in `lab-sites`. The version slot stays 2.5.2, so the catalog card was untouched | 2026-09-17 |
| C4 | install through the product installer with a backup, no process killed | wave 2, wave 9 boundaries | done for build 27 · `./install-runtime.sh update-background`: staged copy, signature check, verified rollback snapshot `20260917T125732Z`, LaunchAgent kickstart. Build 26 never reached the machine because the route refused a changed bridge outright and pushed the apply to the interactive `install`, which reloads the owner's Hammerspoon and opens a settings window, both off the owner's machine under rule 52. The route now copies the new lua, names the reload as the owner's press and leaves Hammerspoon alone; `defaults read` on the installed bundle answers 2.5.2 build 27 | 2026-09-17 |
| C5 | signing identity that survives a rebuild, so permissions stay granted | wave 3 § C, rule 26 | blocked · the `AIM Mini Apps` identity waits for Alex to trust it; builds stay ad-hoc, commands are in `RELEASE-PIPELINE.md` | 2026-09-14 |
| C6 | product page: version, what's new, zip, SHA, panel screenshot, EN and RU | wave 3 § D, rules 11, 12 | done for 2.5.2 build 27 · the download SHA and the release notes on the page follow build 27 · offscreen shot `assets/window.png` 840 × 1344, the frame line reads 420 × 672, the gesture tile names the five second release and the control paragraph names the `bridge` row, both languages | 2026-09-17 |
