#!/usr/bin/env python3
"""Turn the Anti-Davis Little Fighter 2 character pack into Godot sprite strips.

The pack ships as LF2 mod data: three 800x560 BMP sheets of 79x79 cells on a
10-wide, 7-tall grid with a 1 px gutter, plus an encrypted .dat that says which
cell each animation frame uses and where that frame's origin sits inside it.

Two things have to happen before Godot can use them:

  * Transparency. The BMPs are 24-bit with a pure black key colour, so black is
    punched out to alpha. The character's own outline is (21, 21, 21), not
    black, so it survives.
  * Origin. LF2 gives every frame its own (centerx, centery); Godot's
    AtlasTexture regions are uniform. Each frame is therefore shifted until its
    origin lands at ORIGIN inside a fixed OUT cell. Skip this and the sprite
    jitters a few pixels every time the animation changes frame.

Usage (needs Pillow):

    python scripts/extract_anti_davis.py

Then let Godot reimport, e.g. `godot --path godot --headless --import`.
"""
import os
import re
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PACK = os.path.normpath(os.path.join(
    HERE, "..", "..", "Assests", "Anti-Davis", "Anti-Davis"))
SYS_DIR = os.path.join(PACK, "sprite", "sys")
DAT = os.path.join(PACK, "data", "anti_davis.dat")
OUT_DIR = os.path.normpath(os.path.join(
    HERE, "..", "godot", "features", "player", "art", "anti_davis"))

# --- LF2 pack layout --------------------------------------------------------

CELL_W = CELL_H = 79
GUTTER = 1
COLS = 10
SHEETS = [("anti_davis_0.bmp", 0, 69),
          ("anti_davis_1.bmp", 70, 139),
          ("anti_davis_2.bmp", 140, 209)]
KEY_COLOUR = (0, 0, 0)
# LF2 .dat files are the plaintext with this key added byte-wise, after a 123
# byte junk header. The key is 37 characters; longer variants quoted online
# decrypt the first line and then produce garbage.
DAT_KEY = b"odBearBecauseHeIsVeryGoodSiuHungIsAGo"
DAT_HEADER = 123

# --- What the platformer needs ---------------------------------------------

# LF2 frame ids, not pic ids: the frame is what carries the per-frame origin.
ANIM = {
    "idle":  [0, 1, 2, 3],               # standing
    "walk":  [5, 6, 7, 8],               # walking
    "run":   [9, 10, 11],                # running
    "skid":  [218],                      # stop_running
    "rise":  [213],                      # dash, knee up: reads as the way up
    "fall":  [214],                      # dash, legs forward: reads as the way down
    "death": [180, 181, 182, 183, 184],  # knocked back, tumble, flat
}

# Union of every frame's content around its origin is 77x94, so an 80x96 cell
# with the origin at (40, 82) holds all of them with a pixel to spare. These
# must stay in step with CELL and PIVOT in player_sprite.gd.
OUT = (80, 96)
ORIGIN = (40, 82)

# LF2 draws the final lying frame sunk below its origin, because there the body
# is still travelling. Here the player dies in place, so the corpse is lifted to
# rest on the ground line instead of sinking into the floor.
ADJUST = {184: (0, -13)}

_sheets = {}


def decrypt_dat(path):
    raw = open(path, "rb").read()[DAT_HEADER:]
    return bytes((raw[i] - DAT_KEY[i % len(DAT_KEY)]) & 0xFF
                 for i in range(len(raw))).decode("latin-1")


def frames_table():
    text = decrypt_dat(DAT)
    table = {}
    for fid, name, block in re.findall(
            r"<frame>\s+(\d+)\s+(\S+)(.*?)<frame_end>", text, re.S):
        def field(k):
            return int(re.search(k + r":\s*(-?\d+)", block).group(1))
        table[int(fid)] = {"name": name, "pic": field("pic"),
                           "cx": field("centerx"), "cy": field("centery")}
    return table


def sheet_for(pic):
    """Return (keyed-out sheet, index of `pic` within it)."""
    for name, lo, hi in SHEETS:
        if lo <= pic <= hi:
            if name not in _sheets:
                image = Image.open(os.path.join(SYS_DIR, name)).convert("RGBA")
                px = image.load()
                for y in range(image.height):
                    for x in range(image.width):
                        if px[x, y][:3] == KEY_COLOUR:
                            px[x, y] = (0, 0, 0, 0)
                _sheets[name] = image
            return _sheets[name], pic - lo
    raise KeyError("no sheet holds pic %d" % pic)


def cell(pic):
    image, idx = sheet_for(pic)
    x = (idx % COLS) * (CELL_W + GUTTER)
    y = (idx // COLS) * (CELL_H + GUTTER)
    return image.crop((x, y, x + CELL_W, y + CELL_H))


def main():
    if not os.path.isdir(SYS_DIR):
        sys.exit("Anti-Davis pack not found at %s" % PACK)
    os.makedirs(OUT_DIR, exist_ok=True)
    table = frames_table()
    for key, ids in ANIM.items():
        strip = Image.new("RGBA", (OUT[0] * len(ids), OUT[1]), (0, 0, 0, 0))
        for i, fid in enumerate(ids):
            frame = table[fid]
            src = cell(frame["pic"])
            adj = ADJUST.get(fid, (0, 0))
            dx = i * OUT[0] + ORIGIN[0] - frame["cx"] + adj[0]
            dy = ORIGIN[1] - frame["cy"] + adj[1]
            strip.paste(src, (dx, dy), src)
        path = os.path.join(OUT_DIR, key + ".png")
        strip.save(path)
        print("%-6s %d frame(s) -> %s" % (key, len(ids), path))


if __name__ == "__main__":
    main()
