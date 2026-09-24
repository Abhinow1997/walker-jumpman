# Dragon (final boss)

Cut from `Assests/demo_lugia/` by `scripts/extract_dragon.py`. Do not hand-edit
anything in this folder — re-run the extractor and `--import`.

Not to be confused with `../dragon_lord/`, which is a different pack, a
different creature and a different fight. That one is a bipedal boss you trade
blows with on the ground at the end of The Fractured Isles. This one flies, and
lands, and does both.

## What the pack ships

`demo_lugia.zip` is **two files** — `demo_lugia-Sheet.png` and
`demo_lugia.aseprite` — and both hold the *same* six frames: one in-place
wing-flap. The `.aseprite` adds only the seven body-part layers it was drawn on
(`back_wing`, `back_leg`, `torso`, `tail`, `head`, `legs`, `wings`) plus an
`effects` layer that is empty in every frame.

Everything else is in the **eleven `.gif` files** sitting beside the zip —
`7wpd6L.gif`, `nunurj.gif`, `FwZsEO.gif` and so on, named by whatever the
download did. They are the store page's preview animations, and between them
they hold the whole boss:

| file | frames | what it is | used as |
|---|---|---|---|
| `F8eIii.gif` | 22 | the flap twice, then take off, fly, land | ground truth (see below) |
| `75NSHV.gif` | 4 | sitting, breathing | `idle` |
| `oIn+jh.gif` | 8 | walking on all fours | `walk` |
| `FwZsEO.gif` | 9 | rears up and swipes; the white arc is the blow | `claw` |
| `7wpd6L.gif` | 10 | standing, throws a fire plume | `fire` |
| `nunurj.gif` | 10 | the same breath in flight | `fire_air` |
| `5YzQUH.gif` | 8 | rears, roars head-on, launches | `takeoff` |
| `14mpnz.gif` | 6 | comes down wings-first and folds up | `land` |
| `5Wgewc.gif` | 3 | struck on the ground, with a flash frame | `hurt` |
| `mLQFFK.gif` | 3 | struck in the air | `hurt_air` |
| `YG0f_G.gif` | 6 | folds forward until it is flat | `death` |

`F8eIii (1).gif` is a byte-identical second copy of `F8eIii.gif`; the extractor
detects and drops it.

The flap itself is taken from the **sheet** rather than from the gif, because
there it needs no decoding at all: `idle_air`, `walk_air`, `jump` and `swoop`
are all re-cuts of those six authoritative frames.

## Getting the watermark off

Every frame of every gif has the word **"Preview" stamped across it**. This was
first read as making them unusable. It does not: the stamp is exactly
reversible, and `extract_dragon.py` reverses it and then **proves** it did.

The stamp is two semi-transparent overlays — a deeper outline and a pale fill,
both at alpha ≈ 0.209 — composited over the art at a fixed position and then
quantised into each gif's own small palette. Three facts make that invertible:

- **The text never moves.** Its mask is the same 2938 pixels in every frame of
  every gif. And every one of the 43264 pixels in the frame is seen as clean
  background somewhere across the eleven files, so the mask is *read off the
  backgrounds* rather than guessed — `stamp()` asserts that it covered the lot.
- **The sheet is ground truth.** `F8eIii.gif` frames 0–11 are two turns of the
  same six frames the sheet holds, so the blend is **fitted** by least squares
  against known art — `solve()` regresses the gif's channel on the sheet's,
  which gives the slope (1 − α) and the intercept (α × colour).
- **The last of the error is removable.** Un-blending leaves at most 1 per
  channel, and each animation's real palette is visible outside the text box.
  Snapping the un-blended pixel to that palette closes the gap.

`verify()` then re-decodes those twelve known frames and asserts every art
pixel comes back **identical**, silhouette included. It does — 24718 of 24718.
If a future Pillow or a re-download changes the quantisation, this is the check
that fails rather than the sprites quietly growing speckle along the text.

## Measured, not written

Three things in the manifest come off the pixels rather than out of this file:

- **The stance.** Every clip registers the same way — the ground line is y 127
  in the sheet, in the walk, in the idle and in the claw — so one origin is
  right for all fourteen. It has to be measured off the right frame, though: on
  the deep downstroke the wings sweep 30 px *below* the feet, so "the lowest
  pixel" is a wingtip on two frames out of six. The extractor takes the sheet
  frame whose art reaches **highest**, which is the one with the wings furthest
  out of the way, and on that frame alone the bottom of the silhouette is soles.
- **The attack boxes.** `claw`, `fire` and `fire_air` are measured as the
  bounding box of everything on the frame that is clear of the dragon's own
  body, on whichever frame throws it furthest — so retiming an animation cannot
  desync the blow from the picture of it. That finds the white arc on claw
  frame 5 and the plume on fire frame 8.
- **The swoop's box** is the exception, because its "effect" is the dragon
  itself: it hits you with its whole leading half, so the box is everything
  forward of its origin on the strike frame. On the downstroke that includes
  the wing sweeping past below its feet, which is what lets a pass connect with
  somebody standing on the ground while the dragon is still above it.

## Drawn size

The body measures 89 × 52 from nose to tail root and sole to shoulder. At
`render_scale` 1.5 that is 133 long and 78 tall, against a 42-tall player and
the Dragon Lord's 88 — the longest thing in the game by a wide margin, and the
only one wider than it is tall. Alone in the cast it is drawn facing **left**,
so the manifest says `"faces": -1`.

Not 2.0, which is what the other boss is cut at. The camera shows 270 units
above the player's feet and the raised wings reach 69 px above the dragon's own
sole; at 1.5 that is 103, leaving 166 of cruising altitude, and at 2.0 it is
138 and it would fly with its wingtips off the top of the screen.

## Licence

**Unknown.** The archive is two files and no licence, readme or attribution of
any kind, and the eleven gifs alongside it name no author either. `demo_lugia`
is whatever the original project was called; the creature is a green wyvern and
not the Pokémon the filename suggests.

Same footing as the Dragon Lord pack and the LF2 rips: fine for coursework, not
cleared for release, and not attributable the way the CC0 packs are. Note that
the gifs are a **store preview**, which is a weaker claim to use than a
downloaded archive even before the licence question — so whoever assembles the
credits has to chase the original source for this one, and should.
