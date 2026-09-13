# Health bar — provenance

Generated files. Do not edit by hand; rerun `scripts/extract_healthbar.py`
and let Godot reimport.

| | |
|---|---|
| Source file | `Assests/mech-healthbar.png` |
| Origin | **Unknown.** Supplied as a bare 60 x 30 PNG with no pack, readme or licence alongside it. |

## Rights

Unlike the LF2 art in `features/`, nothing is known about where this came from.
It is not from the Little Fighter 2 rips — different palette, different pixel
scale, a heart motif LF2 does not use. It looks like a UI sprite from an asset
pack, which usually means a licence exists somewhere.

**Before release, find out what it is and whether it can be used.** If the pack
is unknown or its terms cannot be met, the bar is the cheapest thing in the
project to redraw: it is 53 x 12 pixels and the code reads its geometry from
`healthbar.json`, so a replacement of the same shape drops straight in.

## What the extractor does

The asset is drawn in one fixed state — three segments lit, two grey — which a
HUD cannot use. Two versions are written instead:

| File | Segments | Under-bar |
|---|---|---|
| `healthbar_empty.png` | all grey | dark |
| `healthbar_full.png` | all lit | amber and orange |

`hud.gd` draws the empty one and then the full one clipped to the player's
health fraction, so the segments and the under-bar fill together and a segment
can sit half-lit at the clip edge. At 25 of 100 health one segment of five is
lit; after the milk, three and a half.

The recolouring cannot be a blanket palette swap: the heart is drawn in the same
two reds as a lit segment and would grey out with them. The segments are
addressed by position instead — at row `15 + n`, segment `i` starts at
`x = 20 + 5i - n`, its two coloured pixels being the next two along. Those
numbers were measured off the asset, and the extractor re-checks every one of
them against the source on each run and stops if any has moved.
