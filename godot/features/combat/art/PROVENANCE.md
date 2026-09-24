# Combat art — provenance

Two sources, two sets of rights. Everything here is generated; do not edit any of
it by hand — rerun the script that owns it and let Godot reimport.

| Files | Script | Source | Rights |
|---|---|---|---|
| `crate*`, `bottle*`, `brew*` | `scripts/extract_lf2_items.py` | the LF2 items rip | ripped, **not** cleared to ship |
| `rock*` | `scripts/extract_rock.py` | `Assests/rock.jpg` | generated, not attributable |

`items.json` is shared between the two scripts, each owning its own keys: both
read the file back and merge rather than overwrite, so running either does not
delete the other's entries. Every item carries a `source` naming the sheet it
came from.

## The rock

| | |
|---|---|
| Files | `rock.png`, `rock_break.png`, `rock_debris.png` |
| Source file | `Assests/rock.jpg` |
| Origin | **Generated art**, supplied by the author on 2026-09-17. Not a licensed pack and not attributable. |

Same provenance category as the title screen and the HUD bars: not a licence
problem the way the LF2 art below is, but not attributable the way the CC0 packs
are either. A credits screen needs its own line for generated art.

The sheet is a 3942 x 1056 page on dark navy, in two rows: six frames of one
intact boulder, then five of it shattering followed by a block of debris. The
six are the same rock with the light in its cracks brightening and dimming — an
idle pulse, not damage states — so all six are taken and `prop.gd` loops them at
six a second. This is the only prop in the game whose resting art animates.

Three things about the sheet make a naive crop wrong:

* It has its own editor grid drawn on it, and **those lines are brighter than the
  rock's own dark outline** (distance 40 from the page against the outline's 18),
  so no threshold separates them. The lines that span the whole sheet are found
  by geometry and painted over from either side. Striking them out of the mask
  instead cut every rock in half along the row that crossed it, and half a rock
  is what the blob pass then called the rock.
* Each boulder stands in a **tuft of grass**, with sparkle motes floating around
  it. A prop that gets picked up and thrown must carry neither — a boulder
  sailing through the air with turf attached is wrong, and a one-pixel mote
  touching the rock is enough to drag the crop box out to it. The grass is keyed
  out by hue; the motes by an opening.
* The debris block is **mostly wooden splinters** — the sheet looks like a
  generic breakables kit. The pieces are picked by hue: anything browner than it
  is blue is left behind, which takes 8 of the 21 and leaves the planks.

The rock replaced LF2's wooden crate as the breakable prop. The old `crate*`
art is still cut and still in the manifest, unused by any script in the game:
one line in `crate.gd` switches back.

## LF2 items

Generated files. Do not edit by hand; rerun `scripts/extract_lf2_items.py`
and let Godot reimport.

| | |
|---|---|
| Source file | `Assests/PC _ Computer - Little Fighter 2 - Miscellaneous - Items.png` |
| Origin | A sprite rip of *Little Fighter 2*'s item art (Marti Wong, Starsky Wong) |

## Rights

Same standing as the character in `features/player/art/anti_davis`: this is
ripped art from a freeware game, with no licence attached. Fine for coursework.
**Not** cleared to ship, sell, or publish. See that folder's `PROVENANCE.md`.

## What is taken, and what is not

The sheet holds a dozen LF2 weapons and effects — bats, knives, stones,
baseballs, ice shards. Only the crate and the two bottles are cut out:

| File | Frames | Source cell(s) | Used for |
|---|---|---|---|
| `crate.png` | 1 | crate block, frame 5 | the breakable crate at rest |
| `crate_spin.png` | 6 | crate block, frames 5,1,4,0,2,3 | the crate tumbling after a hit |
| `crate_debris.png` | 16 | debris block, rows 4-5 cols 0-7 | the planks it shatters into |
| `bottle.png` | 1 | bottle block, row 0 col 0 | the milk bottle, health pickup |
| `bottle_drink.png` | 1 | bottle block, index 31 | the same bottle in his hand, tipped to drink |
| `bottle_spin.png` | 8 | bottle block, indices 0,2,…,14 | the bottle tumbling after a hit |
| `bottle_debris.png` | 8 | debris block, rows 7-8 cols 0-3 | the glass it smashes into |
| `brew.png` | 1 | brown-bottle block, row 0 col 0 | the brown bottle, mana pickup |
| `brew_drink.png` | 1 | brown-bottle block, index 31 | the same bottle in his hand, tipped to drink |
| `brew_spin.png` | 8 | brown-bottle block, indices 0,2,…,14 | the brown bottle tumbling after a hit |
| `brew_debris.png` | 8 | debris block, row 1 cols 0-7 | the amber glass it smashes into |

Crate frame 5 is the only one standing square on its base, so it is the crate at
rest. The other five are the angles LF2 drew for a box in the air; all six
together, ordered 5, 1, 4, 0, 2, 3, step round as one continuous roll and are
the tumble a struck crate does. Those six are every angle the original has —
there is no finer rotation to be had.

Both breaks come from LF2's broken-weapon debris block near the foot of the
sheet: ten materials, two rows each. Rows 4 and 5 are the wooden planks in the
crate's own palette; rows 7 and 8 are the milk bottle's glass — the body with
its gold cap still on, then the small shards with bits of the red label. Each row is four rotations of a large fragment then
four of a small one, so rows 4-5 give four fragment sizes with four drawn angles
apiece. They are laid out in the strip as `type * 4 + rotation`, and a piece
spins by stepping through its four angles — the way LF2 does it — rather than by
rotating one sprite. Nothing about the break is invented art.

`crate_debris` and `crate_spin` are originned to their middle for the same
reason the held bottle is: they are airborne and turning, not standing on
anything. `crate.png` alone keeps a bottom-centre origin, because at rest the
crate does stand on the floor.

Each bottle block holds forty rotations. Every other one of the first sixteen —
0, 2, 4 and so on — is an even eight-step turn through a full circle, which is
what a knocked bottle needs; taking them consecutively would cover less than
half a turn in the same number of frames.

The brown bottle — LF2's beer, four blocks below the milk — is laid out
identically: same pitch, same forty rotations in the same order. So it is picked
with the milk bottle's own cell numbers against a different block origin, and the
two sets of frames stay in step. Its debris is the one thing that is not its
own: the sheet has no smashed brown bottle, so the amber sliver row stands in.
The milk bottle's own glass would have been wrong — that is white plastic with a
red label on it, which reads as the other bottle entirely.

`bottle_drink` is index 31 because that is the number LF2's own drink frames
name in `weaponact`. It is the only item originned to its middle rather than to
the ground under it: a held object is stamped onto a weapon point by its centre,
not stood on a floor.

Adding another item is a new entry in the extractor's `PICKS`, not new code.

## Geometry

No two blocks share a grid, so each was measured off the sheet rather than
assumed: the crate block is on a 59 px pitch with 58 px cells, both bottle
blocks on a 49 px pitch with 48 px cells, and the debris block on a 28 x 29 px pitch
with 27 x 28 px cells. The backdrop inside every block is pure
black and is keyed out; no item's own art uses pure black, so nothing is lost.

Every item is re-originned to **bottom centre**, the point that should touch the
ground. That is why placing one is just a world position with no per-item
offset. `items.json` carries the cell size and origin; `items.gd` reads it.

The milk bottle is drawn only 13 x 23 px and the brown one 14 x 32, so their
pickup areas are deliberately far larger than the art — `bottle.gd`'s `body`,
game feel rather than a change to the asset. Each also used to sit in a pulsing
halo, for the same reason: at this size they are easy to walk past. That was
removed on 2026-09-18 — a soft round gradient under crisp pixel art reads as a
smudge rather than a glow — so the bottles are now harder to spot than they
were. If they turn out to be too easy to miss, the answer is a drawn sparkle in
the sheet's own palette, not another gradient.
