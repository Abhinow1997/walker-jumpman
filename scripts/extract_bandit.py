#!/usr/bin/env python3
"""Cut the LF2 Bandit out of the ripped sheet into the game's enemy format.

Source: Assests/PC _ Computer - Little Fighter 2 - Enemies - Bandit.png

The sheet is not one LF2 sheet but FOUR tiled into one image: the bandit's two
sprite files stacked vertically, in two palette variants side by side. Cells are
79x79 on an 80 px pitch at native resolution, 20 columns by 14 rows.

    columns  0-9   red bandana      columns 10-19  teal bandana
    rows     0-6   LF2 pics 0-69    rows      7-13 LF2 pics 70-139

So an LF2 pic index maps to a cell by splitting it into sheet and offset, which
is what pic() below does. Set PALETTE to 1 for the teal variant — a second enemy
type is that one number.

Deliberately emits the SAME manifest shape as scripts/extract_punk.py, so
features/combat/enemy.gd reads either without caring which pack it came from.

Scaled by 0.75 like the rest of the cast — see
features/player/art/anti_davis/PROVENANCE.md for why that factor exists. This is
LF2 art, painted and anti-aliased, so it resamples well; the CC0 pixel-art packs
must never be put through the same path.

Usage (needs Pillow):

    python scripts/extract_bandit.py

Then let Godot reimport, e.g. `godot --path godot --headless --import`.
"""
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SHEET = os.path.normpath(os.path.join(
    HERE, "..", "..", "Assests",
    "PC _ Computer - Little Fighter 2 - Enemies - Bandit.png"))
OUT_DIR = os.path.normpath(os.path.join(
    HERE, "..", "godot", "features", "combat", "art", "bandit"))

CELL = 79
PITCH = 80
COLS_PER_SHEET = 10
ROWS_PER_SHEET = 7
PALETTE = 0          # 0 = red bandana, 1 = teal

## LF2 draws every frame against a fixed origin: mid-body, feet on the floor.
## There is no .dat with this rip, so the convention is used directly and every
## frame is checked against it below.
ORIGIN = (39, CELL)
SCALE = 0.75

## LF2 pic indices. Read off the sheet rather than taken on faith — render
## scripts and the checks below both exist because the bandit's template is
## close to but not identical to Davis's.
##
## hurt is deliberately shaped like the punk's was, because enemy.gd reads its
## first two frames as the recoil and runs the whole thing out on death: two
## standing recoils, then knocked off his feet, then flat.
ANIMS = {
    "idle":  {"pics": [0, 1, 2, 3],     "loop": True,
              "hold": [0.140, 0.140, 0.140, 0.140]},
    "walk":  {"pics": [4, 5, 6, 7],     "loop": True,
              "hold": [0.110, 0.110, 0.110, 0.110]},
    # Wind-up, full extension, follow-through.
    "punch": {"pics": [10, 13, 11],     "loop": False,
              "hold": [0.100, 0.200, 0.120]},
    "hurt":  {"pics": [36, 37, 31, 34], "loop": False,
              "hold": [0.100, 0.100, 0.140, 0.500]},
}

## Index into punch's pics, not an LF2 pic: the frame with the arm out.
HIT_FRAME = 1
## The extended arm on that frame, in native LF2 pixels relative to ORIGIN, with
## the usual allowance around the glove. Measured: the arm occupies x 24..39,
## y -43..-33, and the glove is the far third of that.
HIT_RECT = [16, -44, 24, 14]
## One bar of the player's five.
HIT_DAMAGE = 20

## Where the arm really is on the hit frame: (max_x, min_y, max_y) relative to
## ORIGIN. Re-checked every run so a different rip cannot silently leave the hit
## box pointing at empty air.
ARM_EXPECTED = (39, -43, -33)


def load_sheet():
    if not os.path.isfile(SHEET):
        sys.exit("bandit sheet not found at %s" % SHEET)
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
    """The punching arm: the rows that reach out past the torso."""
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


def main():
    sheet = load_sheet()
    if sheet.size != (PITCH * COLS_PER_SHEET * 2, PITCH * ROWS_PER_SHEET * 2):
        sys.exit("sheet is %s, expected %s — the rip changed, remeasure the grid"
                 % (sheet.size, (PITCH * COLS_PER_SHEET * 2, PITCH * ROWS_PER_SHEET * 2)))
    os.makedirs(OUT_DIR, exist_ok=True)

    out_cell = (round(CELL * SCALE), round(CELL * SCALE))
    manifest = {
        "_generated_by": "scripts/extract_bandit.py",
        "_source": "Little Fighter 2 Bandit (ripped sheet, unlicensed fan content)",
        "cell": list(out_cell), "origin": sc(list(ORIGIN)), "faces": 1,
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
        # its edges independently and the character jitters between frames.
        strip = strip.resize((out_cell[0] * len(tiles), out_cell[1]), Image.LANCZOS)
        strip.save(os.path.join(OUT_DIR, "%s.png" % name))
        manifest["animations"][name] = {
            "file": "%s.png" % name, "frames": len(tiles),
            "loop": spec["loop"], "durations": spec["hold"],
        }
        print("%-6s %d frame(s) from pics %s" % (name, len(tiles), spec["pics"]))

    arm = arm_extent(pic(sheet, ANIMS["punch"]["pics"][HIT_FRAME]))
    if arm is None:
        sys.exit("no extended arm on the hit frame; check HIT_FRAME")
    if any(abs(a - b) > 2 for a, b in zip(arm, ARM_EXPECTED)):
        sys.exit("punch arm is at %s, expected about %s — remeasure HIT_RECT"
                 % (arm, ARM_EXPECTED))
    print("punch reaches %d px native (%.1f scaled), hit box %s for %d damage"
          % (arm[0], arm[0] * SCALE, sc(HIT_RECT), HIT_DAMAGE))

    path = os.path.join(OUT_DIR, "bandit.json")
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=1, sort_keys=True)
    print("manifest -> %s" % path)


if __name__ == "__main__":
    main()
