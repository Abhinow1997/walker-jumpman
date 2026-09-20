# Bandit — provenance

Generated files. Do not edit by hand; rerun `scripts/extract_bandit.py`
and let Godot reimport.

| | |
|---|---|
| Character | **Bandit**, Little Fighter 2 (Marti Wong & Starsky Wong, 1999) |
| Source | `Assests/PC _ Computer - Little Fighter 2 - Enemies - Bandit.png`, a ripped sheet |
| Licence | **None.** Ripped commercial game art. |

## Rights

Same standing as the player: fan-ripped Little Fighter 2 content, fine for
coursework, **blocks release**. He replaced a CC0 enemy, so as of this change
there is no licensed art left in the project — see
[`../../../player/art/anti_davis/PROVENANCE.md`](../../../player/art/anti_davis/PROVENANCE.md).

The Streets of Fight pack is still in `Assests/` if that ever has to be undone.
It is CC0 and holds a fully animated Brawler Girl and a complete stage.

## The sheet is four sheets

This is not one LF2 sprite file. The rip tiles **four** into one image: the
bandit's two sprite files stacked, in two palettes side by side. Cells are 79x79
on an 80 px pitch at native resolution, 20 columns by 14 rows.

| | columns 0–9 | columns 10–19 |
|---|---|---|
| **rows 0–6** | red bandana, LF2 pics 0–69 | teal bandana, pics 0–69 |
| **rows 7–13** | red bandana, pics 70–139 | teal bandana, pics 70–139 |

So an LF2 pic index maps to a cell by splitting it into sheet and offset. The
extractor's `pic()` does exactly that, and asserts the sheet's dimensions first —
a different rip with a different packing would otherwise read garbage cells and
look like an animation bug.

**`PALETTE = 1` gives the teal bandit.** A second enemy type is that one number.

## Frames

Chosen by eye off a rendered contact sheet, not assumed: the bandit's template
is close to but not identical to Davis's.

| Animation | LF2 pics | Notes |
|---|---|---|
| `idle` | 0, 1, 2, 3 | fighting stance |
| `walk` | 4, 5, 6, 7 | the chase |
| `punch` | 10, 13, 11 | wind-up, full extension, follow-through |
| `hurt` | 36, 37, 31, 34 | two recoils, knocked off his feet, flat |
| `jump` | 63, 64 | rising, legs swept back; falling, knees up |
| `guard` | 60, 61 | arms in; then the frame it gives way on |

`hurt` is deliberately shaped like the enemy it replaced, because `enemy.gd`
reads its first two frames as the stagger and runs the whole thing out on death.
That is why an unrelated pack's manifest drops straight in.

`jump` was added when the enemies learned to leave the ground. 63 and 64 are the
only two pics on the whole sheet whose feet clear the floor line — every standing
pose plants them 1 px above it, these sit 8 to 13 px clear — so the extractor
checks that clearance on every run rather than trusting the indices. A re-rip
that shifts the grid fails loudly instead of leaving him sliding through the air
in a walk cycle.

`guard` is LF2's defend pair, added when the enemies learned to block a thrown
blast. `enemy.gd` shows one or the other by hand rather than playing the run:
frame 0 for as long as the guard holds, frame 1 on the blow that empties it. The
extractor checks these two sit ON the floor line, which is the mirror of the
check `jump` gets and catches the same regrid from the other side.

## Geometry

LF2 draws every frame against a fixed origin — mid-body, feet on the floor —
so the cell needs no repacking and no resampling: the sheet is written at
**79x79, origin (39, 79)**, the rip's own pixels.

He is 0.75 size in the *world*, like the rest of the cast, and the manifest
publishes that as `render_scale` for the sprite node to apply. `SCALE` and
`TEXTURE_SCALE` mean the same things they do for the player — see
`features/player/art/anti_davis/PROVENANCE.md`, which carries the long version.
Both extractors must agree on `SCALE` or the bandit and the player stop being to
the same scale.

The punch's reach is measured off the extended arm on the hit frame rather than
taken from the frame's bounding box, which includes his legs and would put the
hit box well past his fist. Measured at 39 px native, 29 scaled; `enemy.gd`
derives where he commits to a swing from that number rather than hard-coding it.
The extractor re-checks the arm against the source on every run and stops if it
has moved.
