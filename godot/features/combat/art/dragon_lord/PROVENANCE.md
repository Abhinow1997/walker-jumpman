# Dragon Lord (boss)

Cut from `Assests/END_USER_DRAGON_LORD_BASIC.zip` by
`scripts/extract_dragon_lord.py`. Do not hand-edit anything in this folder —
re-run the extractor and `--import`.

## What the pack ships

Eight files, all images, dated 2024-10 to 2025-05: five single-row spritesheets
and two portraits. The cell size is written into each filename, and each sheet
has its own:

| sheet | cell | frames | used as |
|---|---|---|---|
| `dragon_lord_idle_basic_74x74`   | 74x74   | 4  | `idle` |
| `dragon_lord_walk_basic_74x74`   | 74x74   | 8  | `walk` |
| `dragon_lord_attack_arms_90x70`  | 90x70   | 16 | `punch` |
| `dragon_lord_hurt_basic_130x130` | 130x130 | 5  | `hurt` |
| `dragon_lord_death_160x160`      | 160x160 | 36 | `death` |

The dragon is 38x50 in all five. The larger cells hold the effects drawn around
him — the wing flare on hurt, the flame column on death — not a bigger dragon,
which is why they can all be recomposed into one cell without rescaling any of
them. He is aligned on his own body and feet rather than on his cell: he sits
16 px off centre in the hurt sheet and would slide sideways every time he was
struck if the cells were simply stacked.

## The two specials

`special-attack.gif` (15 frames) and `special-attack-2.gif` (23 frames) are
PREVIEW animations, not spritesheets: each frame is the dragon on a stone panel
with a ragged border and the word "attack" captioned underneath. Three things
come off before they are sprites, all handled by the extractor:

- **The chrome** — five exact colours: the transparent padding, three border
  shades and the panel fill. Keyed by RGB, *not* by palette index, because these
  gifs carry a **local palette per frame**: index 4 is the panel on frame 0 and
  something else by frame 18, so an index key paints the border in flame colours
  half way through.
- **The caption** — drawn in art colours, so the key cannot touch it. It sits at
  a fixed rectangle in every frame and nothing else is ever below the panel
  (checked frame by frame), so it is blanked.
- **The scale** — the dragon is 114x150 in both previews against 38x50 in the
  sheets, exactly 3x. A BOX filter at exactly 1/3 is the inverse of a 3x nearest
  upscale, so it recovers the original pixels instead of blurring them.

They become `breath` and `slam`, and the manifest's `moves` block gives each one
the frame it lands on and the box it lands with, both measured off the art. The
slam's box is pegged to the floor rather than drawn round the widest frame,
which is mostly wings held overhead.

## Not used

- `dragon_lord_portrait_512x512.png`, `dragon_lord_portrait_64x64.png` — there
  is nothing in the game that shows a portrait. A boss health bar or a pre-fight
  card would be the place for one.

## Licence

**Unknown.** The archive contains eight image files and no licence, readme or
attribution text of any kind — see the listing above. "END_USER" in the name
suggests one was meant to travel with it. This is fine for coursework on the
same footing as the LF2 rips, but it is not cleared for release and it is not
attributable the way the CC0 packs are. Whoever assembles the credits has to
chase the original source for this one.
