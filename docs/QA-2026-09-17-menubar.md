# Language Relay 2.5.1 · QA of the wave 10 block

Wave 10 (`lab-sites/internal-sites/aim-product-system/SPRINT-2026-09-17-MENUBAR.md` § A, B, C) changed three
things in this product: the shape of the menu bar item, the mark in the panel header and the global
combination. Rule 41 asks for the walk of the block that changed; the rest of the control table stays in
`docs/QA-2026-09-16-c.md` and `docs/QA-2026-09-17.md`.

Installed build under test: 2.5.1 build 24, `./install-runtime.sh update-background` (rollback snapshot
`~/Library/Application Support/Language Relay/Rollback/20260917T121326Z`). Stand: `internal-sites/aim-product-system/testbed`,
windows through `--testbed` only, no synthetic click, no activation, the cursor read and never written.

## Stand pass

`TESTBED_SHOTS=/tmp/codex-screenshots/menubar ./check.sh run relay`

| run | window | AX nodes | press `settings` | after hide | frontmost before → after | cursor | verdict |
|---|---|---|---|---|---|---|---|
| 13:13 | 13645 · 1051,362 454×596 | 37 | pressed `AXButton desc="settings"` | gone | Telegram → Telegram | unchanged | PASS |
| 13:14 | 13746 · 1051,363 454×595 | 37 | pressed `AXButton desc="settings"` | gone | Telegram → Telegram | moved by the user | PASS |

## Control walk of the new block

| control | press | what changed |
|---|---|---|
| `menu-bar-mode` | `axdrive press` opens the NSMenu; the AX reply is empty and the menu leaves with the non-activating panel, the known limit of `testbed/README.md` | the four items call `setMenuBarMode`; the same setter is reached by `--testbed mode <name>`, and the readback below is the receipt |
| `--testbed mode mark` | route | `--design-json` `menuBarMode=mark`, item width 26, the preview draws the mark alone |
| `--testbed mode mark-value` | route | `menuBarMode=mark-value`, width 54, the preview draws mark, arrows and the layout cell |
| `--testbed mode value` | route | `menuBarMode=value`, width 26, the preview draws the layout cell alone |
| `--testbed mode hidden` | route | `menuBarMode=hidden`, the status item is not visible, the preview box is empty and the row says `bar · hidden` |
| `menu-bar-preview` | read only | `AXImage desc="menu bar preview · <mode>"`, redrawn on every mode change and on a layout switch |
| `global-hotkey` | press opens the NSMenu, same limit | the five items call `setHotkey`; `--testbed hotkey <id>` reaches the same setter |
| `--testbed hotkey control-option-l` | route | `--design-json` `hotkey=⌃⌥L`, the button caption and the bottom line follow |
| `--testbed hotkey off` | route | `hotkey=off`, the bottom line drops the combination and prints the gestures alone |
| `--testbed hotkey option-command-l` | route | `hotkey=⌥⌘L`, registered again, the default restored |
| `header-character` | `AXPress` is refused with `-25206` | the character answers the cursor and a real click, and Enter or Space where the window is key; a testbed popover is never key, so the gesture is checked in the VM stand or by hand. The vendored `AIMVoxelView` owns this behaviour and is not patched per product |

Screenshots: `/tmp/codex-screenshots/menubar/relay-251-bar-modes.png` (four modes in the row),
`relay-testbed.png` (the live panel on the stand), `relay-251-denied-footer.png` (the bottom line in its
longest state), `relay-251-mode-*.png` (the panel per mode).

## What the self-test now asserts

- the header carries `header-character` as an `AIMVoxelView` 40 pt with the relay model, and `product-mark` is
  absent from the panel;
- the bar row prints a template image whose size is the width of the current mode, `hidden` draws nothing;
- four modes, `mark` by default, the migration moves an installed setup to `mark + value` once and leaves a
  fresh install at `mark`;
- five combinations, ⌥⌘L by default, no letter that belongs to MEM PRISM, Calendar Control or Aside Tweaks,
  `.hotkey` in the close reasons;
- the three parts of the bottom line are measured in every health state, so the status is not truncated.

## Open

- A combination the system itself holds is refused by Carbon the same way an app-held one is, and the row says
  `held by another app` in both cases. Distinguishing the two needs a system shortcut inventory, which no
  public API gives cheaply.
- The keyboard gesture of the character (Enter, Space) is not reachable from the stand, see the walk table.

## Review fixes, build 25 · 2026-09-17

Stand run on the installed 2.5.1 build 25, panel id 14319 through `--testbed show`, frontmost Telegram before
and after, no app took the focus.

| finding | check | result |
|---|---|---|
| dead `hiddenModeArmed` | `grep -n hiddenModeArmed native/LayoutPilot.swift` | no hit; `make test` and `--ui-self-test` pass |
| the gate still stands | press `\|menu-bar-mode` → `tree` on the menu window | `AXMenuItem "hidden · no item in the bar, hotkey opens the panel"` carries no action of its own, only a submenu with `hide the item · confirm` (`setModeHidden`) and `keep the item in the bar` (`setModeMark`) |
| the setter still works without the flag | press the menu item `value`, then `mark + value` | the row reads `bar · value · ▾` and the preview `menu bar preview · value`, then back to `mark + value`; `defaults read dev.alex.layout-pilot menuBarMode` follows each press (`value`, `mark-value`) |
| one slot name for the family | `tree --window 14319` | `AXImage desc="language relay character" id="header-character"` in the header group, the same id MEM PRISM and Calendar Control expose; `product-mark` absent |
| the version slot | `tree --window 14319` | `AXStaticText id="product-version" value="2.5.1 · build 25"`; MEM PRISM and Calendar Control name that node not at all, so one selector for the version line waits for the shell |

Screenshots: `/tmp/codex-screenshots/menubar/relay-251-b25-panel.png` (the panel),
`relay-251-b25-barmodes-menu.png` (the four modes with the `hidden` submenu open),
`relay-251-b25-header.png` (the header), tree dump `relay-251-b25-tree.txt`.
