#!/usr/bin/env python3
"""Cut the LF2 Hunter out of the ripped sheet into the game's enemy format.

Source: Assests/PC _ Computer - Little Fighter 2 - Enemies - Hunter.png

Hunter's rip is packed exactly like the Bandit's and Mark's — FOUR LF2 sprite
files tiled into one 1600x1120 image, 79x79 cells on an 80 px pitch, 20 columns
by 14 rows, two palette variants side by side. So pic() is the same mapping and
the sheet's dimensions are asserted before anything is cut.

    columns  0-9   default palette   columns 10-19  alt palette
    rows     0-6   LF2 pics 0-69     rows      7-13 LF2 pics 70-139

Hunter is the LF2 archer, and here he plays as one. Pics 10-15 are him drawing
the bow — reach, nock, draw, aim, loose — and that is his `shoot` animation; the
arrow leaves on the release frame (15). The arrow object is NOT on this rip (LF2
keeps it in a separate file), so the flying arrow itself is drawn by
features/combat/arrow.gd rather than cut from a sheet. His melee jab (50/52/53)
stays as the close-range answer when something closes the distance on him.

What was READ OFF THIS sheet, never assumed: the walk and idle line up with the
template, the shoot run is the bow-draw (10/13/14/15), the punch is his melee jab
(50/52/53) and the hurt run is 30/36/33/34. The punch arm is re-measured here
every run, so a different rip cannot silently point the hit box at empty air — at
the bow, say, which reaches much further.

Emits the SAME manifest shape as scripts/extract_bandit.py and extract_mark.py,
so features/combat/enemy.gd loads him by pointing `kind` at this folder.

Scaled by 0.75 like the rest of the cast — see
features/player/art/anti_davis/PROVENANCE.md for why that factor exists. This is
LF2 art, painted and anti-aliased, so it resamples well; the CC0 pixel-art packs
must never be put through the same path.

Usage (needs Pillow):

    python scripts/extract_hunter.py

Then let Godot reimport, e.g. `godot --path godot --headless --import`.
"""
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SHEET = os.path.normpath(os.path.join(
    HERE, "..", "..", "Assests",
    "PC _ Computer - Little Fighter 2 - Enemies - Hunter.png"))
OUT_DIR = os.path.normpath(os.path.join(
    HERE, "..", "godot", "features", "combat", "art", "hunter"))

CELL = 79
PITCH = 80
COLS_PER_SHEET = 10
ROWS_PER_SHEET = 7
PALETTE = 0          # 0 = default (red bandana), 1 = alternate palette

## LF2 draws every frame against a fixed origin: mid-body, feet on the floor.
## There is no .dat with this rip, so the convention is used directly and every
## frame is checked against it below.
ORIGIN = (39, CELL)

## World size, and only world size. See the long note on SCALE and TEXTURE_SCALE
## in scripts/extract_anti_davis.py — both extractors must agree on these or the
## enemy and the player stop being to the same scale.
SCALE = 0.75
## The sheet is written at the rip's own resolution and never resampled: 0.75 of
## world size against the viewport's 4/3 magnification is exactly 1:1 on screen.
TEXTURE_SCALE = 1.0
RENDER_SCALE = SCALE / TEXTURE_SCALE

## LF2 pic indices, read off a contact sheet of this rip. idle and walk are the
## template's; the punch is his melee jab (the bow-draw at 10-15 is skipped), and
## the hurt run keeps the shape enemy.gd expects — it reads the first two frames
## as the recoil and runs the whole thing out on death: two standing recoils
## (30, 36), knocked off his feet (33), then flat (34).
ANIMS = {
    "idle":  {"pics": [0, 1, 2, 3],      "loop": True,
              "hold": [0.140, 0.140, 0.140, 0.140]},
    "walk":  {"pics": [4, 5, 6, 7],      "loop": True,
              "hold": [0.110, 0.110, 0.110, 0.110]},
    # The bow: reach, full draw, aim, loose. The arrow leaves on the last frame.
    "shoot": {"pics": [10, 13, 14, 15],  "loop": False,
              "hold": [0.140, 0.160, 0.100, 0.100]},
    # Melee jab: fist forward, full extension, retract. The close-range answer.
    "punch": {"pics": [50, 52, 53],      "loop": False,
              "hold": [0.100, 0.200, 0.120]},
    "hurt":  {"pics": [30, 36, 33, 34],  "loop": False,
              "hold": [0.100, 0.100, 0.140, 0.500]},
    # The jump: rising, then falling. These are the only two pics on the whole
    # sheet whose feet leave the floor line, which is what the check in main()
    # asserts - a grounded pose cannot be substituted for one of them by
    # accident. 63 has the legs swept back under him, 64 the knees up in front,
    # the same pair the player's own rise and fall are drawn from.
    "jump":  {"pics": [63, 64],          "loop": False,
              "hold": [0.300, 0.300]},
}

## Index into punch's pics, not an LF2 pic: the frame with the fist out (pic 52).
HIT_FRAME = 1
## The extended fist on that frame, in native LF2 pixels relative to ORIGIN, with
## the usual allowance so the box reaches the player's body. Measured: the fist
## reaches x 55..63, y -45..-34; the box covers it and drops toward the chest.
HIT_RECT = [10, -46, 14, 18]
## One bar of the player's five, same weight as the Bandit and Mark.
HIT_DAMAGE = 20

## Where the arm really is on the hit frame: (max_x, min_y, max_y) relative to
## ORIGIN. Re-checked every run so a different rip cannot silently leave the hit
## box pointing at empty air. Hunter reaches shortest of the three — a jab, not a
## lunge, and nowhere near the bow's reach, which is the trap this guards against.
ARM_EXPECTED = (24, -44, -36)
## A jump frame has to be drawn in the air. Every grounded pose on these rips
## plants its feet 1 px above the floor line; the airborne ones sit 8 to 13 px
## clear, so this tells them apart with room to spare and a re-rip that shifts
## the grid fails loudly instead of leaving him sliding along the ground.
AIRBORNE_CLEAR = 5



def load_sheet():
    if not os.path.isfile(SHEET):
        sys.exit("hunter sheet not found at %s" % SHEET)
    image = Image.open(SHEET).convert("RGBA")
    px = image.load()
    for y in range(image.height):
        for x in range(image.width):
            if px[x, y][:3] == (0, 0, 0):
                px[x, y] = (0, 0, 0, 0)
    return image


def pic(sheet, index):
    """LF2 pic index -> its 79x79 cell in the tiled rip."""
    which, offset = divmod(index, COLS_PER_SHEET * ROWS_PER_SHEET)
    row = which * ROWS_PER_SHEET + offset // COLS_PER_SHEET
    col = PALETTE * COLS_PER_SHEET + offset % COLS_PER_SHEET
    return sheet.crop((col * PITCH, row * PITCH,
                       col * PITCH + CELL, row * PITCH + CELL))


def arm_extent(frame):
    """The punching arm: the rows that reach out past the torso. On pic 52 the
    legs stop short of the torso edge, so they are not mistaken for the fist."""
    px = frame.load()
    torso_edge = 60
    xs, ys = [], []
    for y in range(CELL):
        row = [x for x in range(CELL) if px[x, y][3] > 0]
        if row and max(row) > torso_edge:
            xs.append(max(row))
            ys.append(y)
    if not xs:
        return None
    return (max(xs) - ORIGIN[0], min(ys) - ORIGIN[1], max(ys) - ORIGIN[1])


def sc(value):
    if isinstance(value, (list, tuple)):
        return [sc(v) for v in value]
    return round(value * SCALE, 3)


def tex(value):
    """Pack pixels to texture pixels. Only the cell and the origin, which
    address the sheet rather than the world."""
    if isinstance(value, (list, tuple)):
        return [tex(v) for v in value]
    return round(value * TEXTURE_SCALE, 3)


def main():
    sheet = load_sheet()
    if sheet.size != (PITCH * COLS_PER_SHEET * 2, PITCH * ROWS_PER_SHEET * 2):
        sys.exit("sheet is %s, expected %s — the rip changed, remeasure the grid"
                 % (sheet.size, (PITCH * COLS_PER_SHEET * 2, PITCH * ROWS_PER_SHEET * 2)))
    os.makedirs(OUT_DIR, exist_ok=True)

    out_cell = (round(CELL * TEXTURE_SCALE), round(CELL * TEXTURE_SCALE))
    manifest = {
        "_generated_by": "scripts/extract_hunter.py",
        "_source": "Little Fighter 2 Hunter (ripped sheet, unlicensed fan content)",
        # cell and origin address the texture; render_scale takes a texture
        # pixel to a world unit. The hit box and reach below are already world.
        "render_scale": round(RENDER_SCALE, 6),
        "cell": list(out_cell), "origin": tex(list(ORIGIN)), "faces": 1,
        "hit_frame": HIT_FRAME, "hit_rect": sc(HIT_RECT), "hit_damage": HIT_DAMAGE,
        "animations": {},
    }

    for name, spec in ANIMS.items():
        tiles = [pic(sheet, n) for n in spec["pics"]]
        for n, tile in zip(spec["pics"], tiles):
            if tile.getbbox() is None:
                sys.exit("%s: pic %d is empty — wrong grid or wrong pic index"
                         % (name, n))
        strip = Image.new("RGBA", (CELL * len(tiles), CELL), (0, 0, 0, 0))
        for i, tile in enumerate(tiles):
            strip.paste(tile, (i * CELL, 0), tile)
        # Resized as one strip, not per cell: resampling each frame alone rounds
        # its edges independently and the character jitters between frames. At
        # TEXTURE_SCALE 1.0 there is nothing to resize.
        if out_cell != (CELL, CELL):
            strip = strip.resize((out_cell[0] * len(tiles), out_cell[1]), Image.LANCZOS)
        strip.save(os.path.join(OUT_DIR, "%s.png" % name))
        manifest["animations"][name] = {
            "file": "%s.png" % name, "frames": len(tiles),
            "loop": spec["loop"], "durations": spec["hold"],
        }
        print("%-6s %d frame(s) from pics %s" % (name, len(tiles), spec["pics"]))

    for n in ANIMS["jump"]["pics"]:
        box = pic(sheet, n).getbbox()
        if box is None:
            sys.exit("jump: pic %d is empty" % n)
        clear = ORIGIN[1] - (box[3] - 1)
        if clear < AIRBORNE_CLEAR:
            sys.exit("jump: pic %d has its feet %d px off the floor line, needs %d "
                     "- that is a standing pose, not an airborne one"
                     % (n, clear, AIRBORNE_CLEAR))
        print("jump   pic %d clears the floor line by %d px" % (n, clear))

    arm = arm_extent(pic(sheet, ANIMS["punch"]["pics"][HIT_FRAME]))
    if arm is None:
        sys.exit("no extended arm on the hit frame; check HIT_FRAME")
    if any(abs(a - b) > 2 for a, b in zip(arm, ARM_EXPECTED)):
        sys.exit("punch arm is at %s, expected about %s — remeasure HIT_RECT"
                 % (arm, ARM_EXPECTED))
    print("punch reaches %d px native (%.1f scaled), hit box %s for %d damage"
          % (arm[0], arm[0] * SCALE, sc(HIT_RECT), HIT_DAMAGE))

    path = os.path.join(OUT_DIR, "hunter.json")
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=1, sort_keys=True)
    print("manifest -> %s" % path)


if __name__ == "__main__":
    main()
