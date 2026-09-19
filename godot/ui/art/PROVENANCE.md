# HUD art — provenance

Generated files. Do not edit by hand; rerun the script named below and let Godot
reimport.

## The health and mana bars

| | |
|---|---|
| Files | `bar_health_full.png`, `bar_health_empty.png`, `bar_mana_full.png`, `bar_mana_empty.png`, `hud_bars.json` |
| Script | `scripts/extract_hud_bars.py` |
| Source file | `Assests/health system asset.jpg` |
| Origin | **Generated art**, supplied by the author on 2026-09-16. Not a licensed pack and not attributable. |

The source is a 1952 x 2196 style guide rather than a spritesheet: labelled rows
of full-state examples, partial-fill examples and a component breakdown, all on
flat grey. Only the two partial-fill bars are used, because they are the only
pieces on the sheet showing the orb cap, the lightning fill and the dark empty
track together at one scale. The COMPONENT BREAKDOWN frames look like the
obvious source and are not: their interiors are page grey, so an unfilled bar cut
from one would be a hole in the screen.

Which colour becomes which bar is set in the extractor's `BARS` table rather
than tinted in the HUD, so `bar_health_full.png` really does hold the health
bar. **Green is health, blue is mana** — green for life is the convention a
player arrives with, and the blue lightning belongs to the blast it pays for.
The sheet draws the cyan one first, which is the only reason the two boxes in
that table look out of order.

Each bar is reduced to 80 x 13 native pixels, which `hud.gd` draws at x2 in its
640x360 design space — x3 on the 960x540 screen, so one art pixel is exactly a
3 x 3 block. Both bars are forced to that one size even though the sheet draws
them at different scales, because two bars of different lengths stacked in a
corner read as a mistake and seven percent of stone-block width does not.

The track in both variants is rebuilt column by column, so neither inherits the
torn, sparking fill edge the sheet happens to be drawn at. Since the source is a
JPEG, the script cannot check exact pixel values the way the LF2 extractors do;
it checks the geometry by proportion instead — the lit span has to be saturated
colour and the dark span has to be dark, by a wide margin — and stops if the
sheet has been recropped or replaced.

### Rights

This is the same provenance category as the title screen (`title_bg.png` and the
four menu plates, also generated, also from the author): not a licence problem
the way the LF2 sprites in `features/` are, but not attributable the way the CC0
packs are either. **A credits screen needs its own line for generated art and
must not fold it into the CC0 attributions.**

## The old mech health bar

`healthbar_full.png`, `healthbar_empty.png`, `healthbar.json` and
`scripts/extract_healthbar.py` were removed on 2026-09-16 when the bars above
replaced them. That asset — `Assests/mech-healthbar.png` — had **no known
origin at all**: a bare 60 x 30 PNG with no pack, readme or licence beside it,
and the open question of whether it could be shipped. Retiring it closes that
question. The source file is still in `Assests/` and the deleted script is in
git history if the old bar is ever wanted back.
