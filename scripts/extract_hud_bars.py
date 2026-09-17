#!/usr/bin/env python3
"""Cut the health and mana bars out of the HUD asset sheet.

Source: "Assests/health system asset.jpg" — a 1952 x 2196 generated sheet laid
out as a style guide rather than a spritesheet: labelled rows of full-state
examples, partial-fill examples and a component breakdown, all on flat grey.

Only the two PARTIAL FILL bars are taken. They are the only pieces on the sheet
that show, in one image at one scale, all three parts a HUD bar needs: the orb
cap, the lightning fill and the dark empty track behind it. The COMPONENT
BREAKDOWN frames further down look like the obvious source, but their interiors
are page grey rather than track, so an unfilled bar cut from them would be a
hole in the screen.

Like scripts/extract_healthbar.py, this writes the two extremes rather than the
one state the sheet is drawn in:

    bar_health_full.png    lightning across the whole track
    bar_health_empty.png   dark track across the whole track
    bar_mana_full.png      as above, green
    bar_mana_empty.png

hud.gd draws the empty one, then the full one clipped to the player's health or
mana, so the fill sweeps across a fixed frame.

Both variants have their track rebuilt column by column, so neither inherits the
torn, sparking edge the sheet draws at its own fill level: `full` tiles the lit
columns across the whole track (ping-ponged, so the lightning continues instead
of visibly repeating), and `empty` writes the median dark column everywhere.

The sheet is a JPEG, so nothing here can trust an exact pixel value the way the
LF2 extractors do. The measured geometry below is checked against the source by
proportion instead — the track has to be dark where it should be dark and lit
where it should be lit, by a wide margin — and the run stops if the sheet has
been recropped or replaced.

Usage (needs Pillow and numpy):

    python scripts/extract_hud_bars.py

Then let Godot reimport, e.g. `godot --path godot --headless --import`.
"""
import json
import os
import sys
from collections import deque

from PIL import Image

try:
    import numpy as np
except ImportError:  # pragma: no cover - a missing dependency, not a code path
    sys.exit("extract_hud_bars needs numpy: python -m pip install numpy")

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.normpath(os.path.join(
    HERE, "..", "..", "Assests", "health system asset.jpg"))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "godot", "ui", "art"))

# Native size both bars are reduced to: the size the bar actually occupies on
# screen, so one texture pixel is one screen pixel and there is nothing to
# magnify. Worked back from the HUD: it draws the art at BAR_SCALE 0.5 in a
# 640x360 design space, the 960x540 viewport scales that by 1.5, and a 1280x720
# window scales it by 4/3 again. 320 x 0.5 x 1.5 x 4/3 = 320. Change BAR_SCALE
# or HUD_SCALE in hud.gd and this has to be worked back through again.
#
# This was 80 x 13, a fourteen-fold reduction of a 1097 px source that the HUD
# then blew back up 4x — so every source pixel landed as a 4 x 4 block and the
# bars read as far coarser than anything around them. The sheet has the
# resolution; there was no reason to throw it away and magnify the result.
NATIVE = (320, 52)

# Measured off the sheet. `box` is the bar's crop, `band` the rows the fill
# occupies inside it, `track` the straight span of the track between the orb cap
# and the right frame, and `lit` a stretch of clean lightning to tile from.
#
# The two bars are drawn at different scales on the sheet (the cyan one is 1097
# px wide, the green one 969), so each is reduced by its own factor to the one
# NATIVE size. Stacking two bars of different lengths in a corner would read as
# a mistake, and seven percent of stone-block width does not.
BARS = {
    "health": {
        "box": (105, 744, 1202, 938),
        "band": (60, 134),
        "track": (195, 1070),
        "lit": (205, 680),
        "dark": (780, 1050),
    },
    "mana": {
        "box": (191, 959, 1160, 1110),
        "band": (50, 100),
        "track": (154, 944),
        "lit": (165, 340),
        "dark": (400, 930),
    },
}

# Where the page shows through. Sampled from the sheet's own top and bottom
# margins rather than assumed, since a regenerated sheet may sit on a different
# grey.
PAGE_MARGIN = 40
# How far from the page colour a pixel has to be to count as artwork at all,
# and the softer ramp that turns the glow around a bar into partial alpha.
SOLID = 55.0
EDGE_FLOOR = 12.0
EDGE_SPAN = 26.0
# The glow is included out to this many pixels around the bar, so the halo
# survives the reduction; sparkles further out than this are dropped.
HALO = 5


def blob(mask):
    """The largest 4-connected component of `mask`, as a mask.

    The bar is one connected piece of artwork and the loose sparkles around it
    are not, which is the whole reason to bother: keying on colour alone would
    leave a scatter of grey-fringed dots around a bar that is supposed to be a
    clean rectangle.
    """
    height, width = mask.shape
    seen = np.zeros_like(mask)
    best = []
    for start_y in range(height):
        for start_x in range(width):
            if not mask[start_y, start_x] or seen[start_y, start_x]:
                continue
            queue = deque([(start_y, start_x)])
            seen[start_y, start_x] = True
            cells = []
            while queue:
                y, x = queue.popleft()
                cells.append((y, x))
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = y + dy, x + dx
                    if (0 <= ny < height and 0 <= nx < width
                            and mask[ny, nx] and not seen[ny, nx]):
                        seen[ny, nx] = True
                        queue.append((ny, nx))
            if len(cells) > len(best):
                best = cells
    out = np.zeros_like(mask)
    for y, x in best:
        out[y, x] = True
    return out


def grow(mask, radius):
    out = mask.copy()
    for _ in range(radius):
        padded = np.pad(out, 1, constant_values=False)
        out = (padded[1:-1, 1:-1] | padded[:-2, 1:-1] | padded[2:, 1:-1]
               | padded[1:-1, :-2] | padded[1:-1, 2:])
    return out


def saturation(rgb):
    return rgb.max(axis=-1) - rgb.min(axis=-1)


def check(spec, crop, name):
    """Confirm the measured geometry still describes the sheet.

    A wrong `band` or `track` would rebuild the frame instead of the fill, which
    on a JPEG is not something an exact-pixel assertion can catch. What is
    checkable is the thing that makes the bar a bar: inside the band, the lit
    stretch has to be saturated colour and the dark stretch has to be dark.
    """
    y0, y1 = spec["band"]
    band = crop[y0:y1 + 1]
    lit = band[:, spec["lit"][0]:spec["lit"][1] + 1]
    dark = band[:, spec["dark"][0]:spec["dark"][1] + 1]
    lit_share = float(((saturation(lit) > 45) & (lit.max(axis=-1) > 105)).mean())
    dark_share = float((dark.max(axis=-1) < 115).mean())
    if lit_share < 0.75:
        sys.exit("%s: only %.0f%% of the 'lit' span is lit colour — the sheet "
                 "changed, remeasure BARS[%r]" % (name, lit_share * 100, name))
    if dark_share < 0.75:
        sys.exit("%s: only %.0f%% of the 'dark' span is dark track — the sheet "
                 "changed, remeasure BARS[%r]" % (name, dark_share * 100, name))
    return lit_share, dark_share


def rebuild(crop, spec, lit):
    """A copy of the crop with its whole track rewritten, lit or empty."""
    out = crop.copy()
    y0, y1 = spec["band"]
    x0, x1 = spec["track"]
    if lit:
        source = crop[y0:y1 + 1, spec["lit"][0]:spec["lit"][1] + 1]
        span = source.shape[1]
        for i in range(x1 - x0 + 1):
            # Ping-pong rather than wrap: the lightning runs on into its own
            # reflection, where a wrap would put a hard vertical seam every
            # `span` pixels.
            step = i % (2 * span)
            take = step if step < span else 2 * span - step - 1
            out[y0:y1 + 1, x0 + i] = source[:, take]
    else:
        source = crop[y0:y1 + 1, spec["dark"][0]:spec["dark"][1] + 1]
        # Median along the bar: the empty track is uniform left to right, so the
        # only thing varying across it is JPEG noise.
        column = np.median(source, axis=1)
        for i in range(x1 - x0 + 1):
            out[y0:y1 + 1, x0 + i] = column
    return out


def reduce_to_native(crop, alpha, size):
    """Box-filter down to `size`, with the page grey kept out of the edges.

    Colour is averaged weighted by coverage and then divided back out, or every
    outline pixel picks up a share of whatever the artwork was sitting on. Alpha
    is snapped to fully on or off at the end: a pixel-art HUD wants a hard
    silhouette, and a half-transparent fringe at this size is just fog.
    """
    small_a = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8))
                         .resize(size, Image.BOX)).astype(float) / 255.0
    rgb = np.zeros(size[::-1] + (3,))
    for channel in range(3):
        plane = Image.fromarray((crop[:, :, channel] * alpha).astype(np.uint8))
        rgb[:, :, channel] = np.asarray(plane.resize(size, Image.BOX)).astype(float)
    covered = small_a[..., None] > 0.01
    rgb = np.where(covered, rgb / np.maximum(small_a[..., None], 1e-6), 0.0)
    out = np.zeros(size[::-1] + (4,), dtype=np.uint8)
    out[:, :, :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    out[:, :, 3] = np.where(small_a >= 0.5, 255, 0)
    return Image.fromarray(out, "RGBA")


def main():
    if not os.path.isfile(SOURCE):
        sys.exit("HUD asset sheet not found at %s" % SOURCE)
    os.makedirs(OUT_DIR, exist_ok=True)
    sheet = np.asarray(Image.open(SOURCE).convert("RGB")).astype(float)
    page = np.median(np.concatenate([
        sheet[:PAGE_MARGIN, :].reshape(-1, 3),
        sheet[-PAGE_MARGIN:, :].reshape(-1, 3)]), axis=0)

    manifest = {
        "_generated_by": "scripts/extract_hud_bars.py",
        "_source": os.path.basename(SOURCE),
        "size": list(NATIVE),
        "bars": {},
    }
    for name, spec in BARS.items():
        x0, y0, x1, y1 = spec["box"]
        crop = sheet[y0:y1, x0:x1]
        lit_share, dark_share = check(spec, crop, name)

        distance = np.abs(crop - page).max(axis=2)
        alpha = np.clip((distance - EDGE_FLOOR) / EDGE_SPAN, 0.0, 1.0)
        alpha *= grow(blob(distance > SOLID), HALO)

        files = {}
        for variant, lit in (("full", True), ("empty", False)):
            image = reduce_to_native(rebuild(crop, spec, lit), alpha, NATIVE)
            filename = "bar_%s_%s.png" % (name, variant)
            image.save(os.path.join(OUT_DIR, filename))
            files[variant] = filename

        # The clip span, in native pixels. Rounded outward so the fill reaches
        # the ends of the track rather than stopping a pixel short of them.
        scale_x = float(NATIVE[0]) / float(x1 - x0)
        manifest["bars"][name] = {
            "files": files,
            "fill_x0": int(spec["track"][0] * scale_x),
            "fill_x1": int(round((spec["track"][1] + 1) * scale_x)),
        }
        print("%-7s lit %.0f%%  dark %.0f%%  fill x %d..%d" % (
            name, lit_share * 100, dark_share * 100,
            manifest["bars"][name]["fill_x0"], manifest["bars"][name]["fill_x1"]))

    path = os.path.join(OUT_DIR, "hud_bars.json")
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=1, sort_keys=True)
    print("manifest -> %s" % path)


if __name__ == "__main__":
    main()
