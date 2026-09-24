# Mark — provenance

Generated files. Do not edit by hand; rerun `scripts/extract_mark.py`
and let Godot reimport.

| | |
|---|---|
| Character | **Mark**, Little Fighter 2 (Marti Wong & Starsky Wong, 1999) |
| Source | `Assests/PC _ Computer - Little Fighter 2 - Enemies - Mark.png`, a ripped sheet |
| Licence | **None.** Ripped commercial game art. |

## Rights

Same standing as the Bandit and the player: fan-ripped Little Fighter 2 content,
fine for coursework, **blocks release**. The one CC0 pack still in the project is
the Magic Cliffs environment; every character is unlicensed. See
[`../bandit/PROVENANCE.md`](../bandit/PROVENANCE.md) and
[`../../../player/art/anti_davis/PROVENANCE.md`](../../../player/art/anti_davis/PROVENANCE.md).

## The sheet is four sheets

Packed exactly like the Bandit's rip: **four** LF2 sprite files tiled into one
1600x1120 image, cells 79x79 on an 80 px pitch, 20 columns by 14 rows, two
palettes side by side.

| | columns 0–9 | columns 10–19 |
|---|---|---|
| **rows 0–6** | default palette, LF2 pics 0–69 | alt palette, pics 0–69 |
| **rows 7–13** | default palette, pics 70–139 | alt palette, pics 70–139 |

`pic()` splits an LF2 index into sheet and offset the same way, and asserts the
sheet's dimensions first — a differently packed rip would otherwise read garbage
cells and look like an animation bug. `PALETTE = 1` gives the alternate colours.

## Frames

Chosen by eye off a rendered contact sheet, not copied from the Bandit: the walk
and idle line up, but Mark's punch and hurt runs do not.

| Animation | LF2 pics | Notes |
|---|---|---|
| `idle` | 0, 1, 2, 3 | fighting stance |
| `walk` | 4, 5, 6, 7 | the chase |
| `punch` | 10, 11, 12 | wind-up, full extension, follow-through |
| `hurt` | 30, 36, 33, 34 | two recoils, knocked off his feet, flat |
| `jump` | 63, 64 | rising, legs swept back; falling, knees up |
| `guard` | 60, 61 | arms in; then the frame it gives way on |

The Bandit's punch is `10, 13, 11`; Mark's extension is pic 11, so his is
`10, 11, 12`. `hurt` keeps the shape `enemy.gd` expects — it reads the first two
frames as the stagger and runs the whole run out on death — so his manifest drops
into the same script with nothing enemy-specific in it.

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

LF2 draws every frame against a fixed origin — mid-body, feet on the floor — so
the cell needs no repacking and no resampling: written at **79x79, origin
(39, 79)**, the rip's own pixels. He is 0.75 size in the *world*, like the rest of
the cast, published as `render_scale` for the sprite node to apply.

The punch's reach is measured off the extended arm on the hit frame rather than
the frame's bounding box, which includes his legs. Mark reaches **30 px native,
22 scaled** — shorter and higher than the Bandit's 39 — and `enemy.gd` derives
where he commits to a swing from that number, so a closer reach just means he
steps in a little further before he throws. The extractor re-checks the arm
against the source on every run and stops if it has moved.
