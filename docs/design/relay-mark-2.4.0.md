# Relay mark 2.4.0 · three variants, one choice

Rule 4 of `AIM-APPS-RULES.md`: a shipped mark is refined, a new idea gets a new symbol id. The 2.3.x
relay glyph was a new idea away from its own drawing, so `aim-app-marks.svg` gains `relay-arch` and the
old `relay` id stays in the file as an alias with the same paths, so every shipped `href="#relay"` keeps
resolving while the wave runs.

Contact list: `relay-mark-contacts.svg` (48 / 24 / 18 px next to the four sibling marks), render
`/tmp/codex-screenshots/apps-unify/relay-mark-contacts.png`.

## Why the old glyph was replaced

- `M13 19h22l-5-5M35 29H13l5 5`: each arrow carries one barb, so at 18 px the pair reads as a lightning
  bolt, and at 24 px the barbs disappear into the shafts.
- the 22 px horizontal at y19 repeats the aside row rule and the calendar header line, so three of five
  marks share the same dominant stroke.
- "two arrows facing each other" names a direction, never the thing the product does.

## The three variants

| id | idea | strokes | verdict |
|---|---|---|---|
| A · arch (`relay-arch`) | the run leaves one alphabet, crosses the bridge and lands in the other | arch + landing chevron | chosen |
| B · caps | two key caps, one key, two alphabets | two caps + divider | dropped: at 18 px the caps fill in and read as two windows, and the outline square already belongs to prism and aside |
| C · ring | a closed exchange ring with two barbs | two arcs + two barbs | dropped: at 18 px the barbs merge into the ring and the figure reads as a generic refresh |

## Why A

- the silhouette is the only curve among the five marks, so the row of products stays readable at 18 px;
- it is asymmetric, so the `mirror` gesture of the live character says something: the red landing foot
  changes side, which is the product working both ways (U.S. → Russian and back);
- it repeats nothing from aside, calendar, prism or family: no long horizontal, no outline square, no chevron;
- 2 paths, 4 stroke segments, the same 2 px weight, the signal stays at x32 y5.

## What changed with it

- `voxel-models.json` → `relay`: 80 voxels (was 36), a stepped arch two sheets deep, mid apex, light body,
  ink feet, one red voxel on the landing foot; gesture `mirror` on `x` (was `z`, where two identical bars
  swapped and nothing moved on screen);
- menu bar: `RelayMarkGlyph.mark(size: 18)` draws the arch as a template image, so the bar carries the mark
  glyph instead of the mono voxel block (rule 26);
- the header keeps the live voxel character at 40 pt, About and the page keep the same figure.
