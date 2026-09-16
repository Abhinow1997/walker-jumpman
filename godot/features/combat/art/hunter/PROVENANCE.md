# Hunter — provenance

Generated files. Do not edit by hand; rerun `scripts/extract_hunter.py`
and let Godot reimport.

| | |
|---|---|
| Character | **Hunter**, Little Fighter 2 (Marti Wong & Starsky Wong, 1999) |
| Source | `Assests/PC _ Computer - Little Fighter 2 - Enemies - Hunter.png`, a ripped sheet |
| Licence | **None.** Ripped commercial game art. |

## Rights

Same standing as the Bandit, Mark and the player: fan-ripped Little Fighter 2
content, fine for coursework, **blocks release**. The one CC0 pack still in the
project is the Magic Cliffs environment; every character is unlicensed. See
[`../mark/PROVENANCE.md`](../mark/PROVENANCE.md),
[`../bandit/PROVENANCE.md`](../bandit/PROVENANCE.md) and
[`../../../player/art/anti_davis/PROVENANCE.md`](../../../player/art/anti_davis/PROVENANCE.md).

## The sheet is four sheets

Packed exactly like the Bandit's and Mark's rips: **four** LF2 sprite files tiled
into one 1600x1120 image, cells 79x79 on an 80 px pitch, 20 columns by 14 rows,
two palettes side by side.

| | columns 0–9 | columns 10–19 |
|---|---|---|
| **rows 0–6** | default palette, LF2 pics 0–69 | alt palette, pics 0–69 |
| **rows 7–13** | default palette, pics 70–139 | alt palette, pics 70–139 |

`pic()` splits an LF2 index into sheet and offset the same way, and asserts the
sheet's dimensions first. `PALETTE = 1` gives the alternate colours.

## An archer cut as a brawler

Hunter is the LF2 **archer**, and he plays as one: pics 10–15 are him drawing the
bow, cut here as his `shoot` animation, and he looses an arrow on the release
frame. The **arrow itself is not on this rip** — LF2 keeps the arrow in a separate
object file — so the flying shaft is drawn by `features/combat/arrow.gd` rather
than cut from a sheet. His melee jab (50/52/53) stays on as the close-range answer
for when the player closes the gap on him.

## Frames

Chosen by eye off a rendered contact sheet. idle and walk are the template's; the
shoot run is the bow-draw, and the punch is the melee jab further down the sheet.

| Animation | LF2 pics | Notes |
|---|---|---|
| `idle` | 0, 1, 2, 3 | archer stance, bow in hand |
| `walk` | 4, 5, 6, 7 | the chase |
| `shoot` | 10, 13, 14, 15 | reach, full draw, aim, loose — the arrow leaves on 15 |
| `punch` | 50, 52, 53 | fist forward, full extension, retract |
| `hurt` | 30, 36, 33, 34 | two recoils, knocked off his feet, flat |

`hurt` keeps the shape `enemy.gd` expects — first two frames are the stagger, the
whole run plays out on death — so his manifest drops into the same script.

## Geometry

LF2 draws every frame against a fixed origin — mid-body, feet on the floor — so
the cell needs no repacking and no resampling: written at **79x79, origin
(39, 79)**, the rip's own pixels. He is 0.75 size in the *world*, like the rest of
the cast, published as `render_scale` for the sprite node to apply.

The punch's reach is measured off the extended fist on the hit frame. Hunter
reaches **24 px native, 18 scaled** — the shortest of the three, a jab rather
than a lunge. The re-check matters most for him: his bow, drawn on nearby frames,
reaches far past his fist, and a hit box measured off the wrong frame's bounding
box would swing at the air in front of the bow. The extractor stops if the arm
has moved.
