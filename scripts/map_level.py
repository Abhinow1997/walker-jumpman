"""Renders a level to an annotated strip map you can design against.

    python scripts/map_level.py                  every level in the index
    python scripts/map_level.py fractured_isles  just that one

Writes evidence/maps/<id>.png.

check_levels.py answers "is this clearable". This answers "what does the route
look like", which is the question you actually have while moving a platform. It
draws the whole course with

  * a tile grid, because levels are authored on one (1 tile = 12 world units)
  * every mandatory gap measured, with its share of the jump envelope
  * the REAL jump arc off each takeoff ledge, integrated from tuning.gd, so a
    gap you cannot make is visibly short rather than a number to be trusted
  * where the spawn, flag, bandits, crates and bottles sit

The arc is the point. A percentage says a gap is 58% of the envelope; the arc
shows whether the landing is under it, and by how much.
"""

import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_levels as cl

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "evidence", "maps"))

SCALE = 0.9            # world units to map pixels
TILE = 12.0            # one 16 px Magic Cliffs tile at 0.75 render scale
MARGIN_TOP = 52
MARGIN_BOTTOM = 96
MARGIN_LEFT = 30
SKY_ABOVE = 170.0      # world units of headroom above the highest ledge
DEPTH_BELOW = 150.0    # how far below the lowest ledge ground is drawn

# A course is ten times wider than it is interesting, so one row would be a
# ribbon nobody can read. It is cut into strips instead, each overlapping its
# neighbour so that no jump lands exactly on a seam.
ROW_SPAN = 1200.0
ROW_OVERLAP = 120.0
ROW_GAP = 30

INK = (37, 53, 74)
MUTED = (150, 158, 170)
GRID = (228, 232, 238)
GRID_MAJOR = (196, 204, 214)
SOLID = (37, 53, 74)
ISLAND = (86, 120, 108)
BRIDGE = (150, 116, 66)
GOOD = (40, 124, 104)
TIGHT = (214, 138, 46)
BAD = (176, 52, 44)
ARC = (56, 132, 200)
SPAWN = (40, 124, 104)
ENEMY = (176, 52, 44)
CRATE = (150, 116, 66)
BOTTLE = (86, 140, 196)


def font(size):
    for name in ("segoeui.ttf", "arial.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def rows_for(width):
    out, x = [], 0.0
    while x < width:
        out.append((max(0.0, x - ROW_OVERLAP * 0.5),
                    min(width, x + ROW_SPAN + ROW_OVERLAP * 0.5)))
        x += ROW_SPAN
    return out


def draw_level(level, name, tune):
    width = float(level["width"])
    fall_y = float(level["fall_y"])
    spans = cl.spans(level["solids"])
    top_world = min(t for _, _, t in spans) - SKY_ABOVE
    bottom_world = max(t for _, _, t in spans) + DEPTH_BELOW
    band = int((bottom_world - top_world) * SCALE)

    rows = rows_for(width)
    row_w = int((ROW_SPAN + ROW_OVERLAP) * SCALE)
    img = Image.new("RGB", (MARGIN_LEFT * 2 + row_w,
                            MARGIN_TOP + len(rows) * (band + ROW_GAP + 34)
                            + MARGIN_BOTTOM), (250, 250, 247))
    d = ImageDraw.Draw(img)
    f_small, f_mid, f_big = font(11), font(13), font(19)
    d.text((MARGIN_LEFT, 12), "%s - %s" % (name, level.get("title", "")),
           font=f_big, fill=INK)

    for index, (x0, x1) in enumerate(rows):
        top = MARGIN_TOP + index * (band + ROW_GAP + 34)
        _row(d, level, tune, x0, x1, top, band, top_world, bottom_world,
             width, (f_small, f_mid))

    flat, apex = cl.envelope(tune, 0.0)
    foot = img.height - MARGIN_BOTTOM + 34
    for i, line in enumerate([
        "1 tile = %d world units. Grid every tile, labelled every 10 in world "
        "units and tiles. Jump envelope %.0f px flat, %.0f px rise, read from "
        "tuning.gd." % (TILE, flat, apex),
        "Blue is the arc off each ledge and the tick is where it comes back down. "
        "A gap is green under %d%% of that reach, amber over it, red if no jump "
        "makes it." % int(cl.TIGHT * 100),
        "Rows read left to right, top to bottom, overlapping by %d units so no "
        "jump sits on a seam. Ground is cut off at %d; the real fall line is %d."
        % (int(ROW_OVERLAP), int(bottom_world), int(fall_y)),
    ]):
        d.text((MARGIN_LEFT, foot + i * 18), line, font=f_mid, fill=MUTED)
    return img


def _row(d, level, tune, x0, x1, top, band, top_world, bottom_world, width, fonts):
    f_small, _ = fonts

    def sx(x):
        return MARGIN_LEFT + (x - x0) * SCALE

    def sy(y):
        return top + (min(y, bottom_world) - top_world) * SCALE

    def inside(x):
        return x0 - 40.0 <= x <= x1 + 40.0

    d.rectangle([MARGIN_LEFT, top, sx(x1), top + band],
                fill=(255, 255, 253), outline=(230, 234, 240))

    x = math.floor(x0 / TILE) * TILE
    while x <= x1:
        major = abs(x % (TILE * 10)) < 0.01
        d.line([(sx(x), top), (sx(x), top + band)],
               fill=GRID_MAJOR if major else GRID, width=1)
        if major:
            d.text((sx(x) + 2, top + band + 4), "%d" % x, font=f_small, fill=MUTED)
            d.text((sx(x) + 2, top + band + 17), "%dt" % (x / TILE),
                   font=f_small, fill=GRID_MAJOR)
        x += TILE

    for entry in level["solids"]:
        ex, ey, ew, eh = (float(v) for v in entry[:4])
        if ex > x1 or ex + ew < x0:
            continue
        wears = str(entry[4]) if len(entry) > 4 else ""
        colour = BRIDGE if wears == "bridge" else (ISLAND if wears else SOLID)
        d.rectangle([sx(ex), sy(ey), sx(ex + ew), sy(ey + eh)], fill=colour)
        d.text((sx(ex) + 3, sy(ey) - 13), wears or "%dx%d" % (ew, eh),
               font=f_small, fill=colour)

    for a, b in cl.pits(level["solids"], width):
        if not inside(a) and not inside(b):
            continue
        gap = b - a
        take = cl.edge_at(level["solids"], a, "right")
        land = cl.edge_at(level["solids"], b, "left")
        if take is None or land is None:
            continue
        rise = take - land
        reach, _ = cl.envelope(tune, rise)
        share = gap / reach if reach > 0 else 9.9
        tone = GOOD if share <= cl.TIGHT else (TIGHT if share <= 1.0 else BAD)

        points, t = [], 0.0
        while t < 3.0:
            ax = a + tune["speed"] * t
            ay = take - (tune["jump_velocity"] * t - 0.5 * tune["gravity"] * t * t)
            if ay > bottom_world or ax > x1 + 40.0:
                break
            if ax >= x0:
                points.append((sx(ax), sy(ay)))
            t += 0.010
        if len(points) > 1:
            d.line(points, fill=ARC, width=2)
        if inside(a + reach):
            d.line([(sx(a + reach), sy(land) - 20), (sx(a + reach), sy(land) + 10)],
                   fill=ARC, width=2)
            d.text((sx(a + reach) + 3, sy(land) - 32), "reach %d" % reach,
                   font=f_small, fill=ARC)

        d.line([(sx(a), sy(take)), (sx(b), sy(take))], fill=tone, width=4)
        if inside(a):
            d.text((sx(a) + 3, sy(take) + 7),
                   "%d px   %.0f%%%s" % (gap, 100.0 * share,
                                         ("   rise %+d" % -rise) if rise else ""),
                   font=f_small, fill=tone)

    def pin(px, py, colour, text, dy):
        if not inside(px):
            return
        d.ellipse([sx(px) - 4, sy(py) - 4, sx(px) + 4, sy(py) + 4], fill=colour)
        d.text((sx(px) + 7, sy(py) + dy), text, font=f_small, fill=colour)

    spawn = level["spawn"]
    pin(float(spawn[0]), float(spawn[1]), SPAWN, "SPAWN", -44)
    for e in level.get("enemies", []):
        pin(float(e[0]), float(e[1]), ENEMY, "bandit", -16)
    for c in level.get("crates", []):
        pin(float(c[0]), float(c[1]), CRATE, "crate", -30)
    for bottle in level.get("bottles", []):
        pin(float(bottle[0]), float(bottle[1]), BOTTLE,
            "bottle %db" % (bottle[2] if len(bottle) > 2 else 2), -58)
    for hz in level.get("hazards", []):
        hx, hy, hw, hh = (float(v) for v in hz)
        if not inside(hx):
            continue
        d.rectangle([sx(hx), sy(hy), sx(hx + hw), sy(hy + hh)], fill=BAD)
        d.text((sx(hx), sy(hy) - 13), "spikes", font=f_small, fill=BAD)
    fx, fy, fw, fh = (float(v) for v in level["finish"])
    if inside(fx):
        d.rectangle([sx(fx), sy(fy), sx(fx + fw), sy(fy + fh)], outline=GOOD, width=2)
        d.text((sx(fx) - 8, sy(fy) - 15), "FINISH", font=f_small, fill=GOOD)


def main():
    tune = cl.tuning()
    order = json.load(open(os.path.join(cl.LEVELS, "index.json"),
                           encoding="utf-8")).get("order", [])
    os.makedirs(OUT_DIR, exist_ok=True)
    for name in sys.argv[1:] or order:
        path = os.path.join(cl.LEVELS, name + ".json")
        if not os.path.isfile(path):
            sys.exit("no level called %s" % name)
        level = json.load(open(path, encoding="utf-8"))
        out = os.path.join(OUT_DIR, name + ".png")
        image = draw_level(level, name, tune)
        image.save(out)
        print("%-16s %d wide, %d rows -> %s"
              % (name, level["width"], len(rows_for(float(level["width"]))), out))


if __name__ == "__main__":
    main()
