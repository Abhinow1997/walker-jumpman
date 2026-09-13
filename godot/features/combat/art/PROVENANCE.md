# LF2 items — provenance

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

The sheet holds a dozen LF2 weapons and effects — bats, knives, stones, beer,
baseballs, ice shards. Only two are cut out:

| File | Frames | Source cell(s) | Used for |
|---|---|---|---|
| `crate.png` | 1 | crate block, frame 5 | the breakable crate at rest |
| `crate_spin.png` | 6 | crate block, frames 5,1,4,0,2,3 | the crate tumbling after a hit |
| `crate_debris.png` | 16 | debris block, rows 4-5 cols 0-7 | the planks it shatters into |
| `bottle.png` | 1 | bottle block, row 0 col 0 | the milk bottle, health pickup |
| `bottle_drink.png` | 1 | bottle block, index 31 | the same bottle in his hand, tipped to drink |
| `bottle_spin.png` | 8 | bottle block, indices 0,2,…,14 | the bottle tumbling after a hit |
| `bottle_debris.png` | 8 | debris block, rows 7-8 cols 0-3 | the glass it smashes into |

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

The bottle block holds forty rotations. Every other one of the first sixteen —
0, 2, 4 and so on — is an even eight-step turn through a full circle, which is
what a knocked bottle needs; taking them consecutively would cover less than
half a turn in the same number of frames.

`bottle_drink` is index 31 because that is the number LF2's own drink frames
name in `weaponact`. It is the only item originned to its middle rather than to
the ground under it: a held object is stamped onto a weapon point by its centre,
not stood on a floor.

Adding another item is a new entry in the extractor's `PICKS`, not new code.

## Geometry

No two blocks share a grid, so each was measured off the sheet rather than
assumed: the crate block is on a 59 px pitch with 58 px cells, the bottle block
on a 49 px pitch with 48 px cells, and the debris block on a 28 x 29 px pitch
with 27 x 28 px cells. The backdrop inside every block is pure
black and is keyed out; no item's own art uses pure black, so nothing is lost.

Every item is re-originned to **bottom centre**, the point that should touch the
ground. That is why placing one is just a world position with no per-item
offset. `items.json` carries the cell size and origin; `items.gd` reads it.

The bottle is drawn only 13 x 23 px. Its pickup area is deliberately far larger
than the art, and a halo is drawn behind it, because otherwise it is neither
findable nor plausibly standable-on at this scale. Both are in `bottle.gd` —
game feel, not changes to the asset.
