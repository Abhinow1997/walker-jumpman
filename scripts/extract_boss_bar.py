#!/usr/bin/env python3
"""Cut the boss health plate out of the boss-system asset sheet.

Source: "Assests/boss-system assests.jpg" — a 2048 x 2048 generated sheet laid
out as a style guide rather than a spritesheet, exactly like the HUD one:
labelled full-state and partial-state examples on flat grey, with a component
breakdown underneath.

Only the PARTIAL STATE row is taken, for the same reason scripts/
extract_hud_bars.py takes its partial rows: it is the one place on the sheet
that shows, at one scale and in proportion, all three things a bar needs — the
winged-heart cap, the lit fill and the dark empty track behind it. The
"Breakdown for Asset Extraction" frame below looks like the obvious source and
is not: its interior is page grey, so an unfilled bar cut from it would be a
hole in the screen. The FULL row is no good either — a floating rock is drawn
over its right-hand end.

The plate carries two bars, and both are used. The green one is the dragon's
health. The magma one under it is the same health LAGGING behind — it drains to
catch up over about half a second, so a blow shows as a band of red between the
two and you can see what you just took off. Drawing one of them permanently
dark was the alternative and it would read as broken art.

Three files come out:

    boss_plate.png        the whole frame with both tracks dark
    boss_fill_health.png  a strip of lit green, the size of its track
    boss_fill_magma.png   a strip of lit magma, the size of its track

ui/hud.gd draws the plate, then each strip clipped to its own fraction, the
same way the player's two bars already work.

The strips are CUT OUT of a fully lit plate after the reduction rather than
reduced on their own, so all three land on the same pixel grid and butt up
exactly. Shipping two whole lit plates instead is the obvious thing and it
does not work: each one carries the other track dark, so drawing the green one
over the magma one erased every part of the magma bar except the sliver
between the two fill levels.

Both lit variants have their track rebuilt column by column, so neither
inherits the ragged edge the sheet draws at its own 70% and 40% fill levels,
and the plate's tracks are rewritten from the median dark column.

The sheet is a JPEG, so nothing here can trust an exact pixel value the way the
LF2 extractors do. The measured geometry is checked against the source by
proportion instead — each track has to be lit where it should be lit and dark
where it should be dark, by a wide margin — and the run stops if the sheet has
been recropped or regenerated.

Usage (needs Pillow and numpy):

    python scripts/extract_boss_bar.py

Then let Godot reimport, e.g. `godot --path godot --headless --import`.
"""
import json
import os
import sys

from PIL import Image

try:
    import numpy as np
except ImportError:  # pragma: no cover - a missing dependency, not a code path
    sys.exit("extract_boss_bar needs numpy: python -m pip install numpy")

# The page key, the blob/halo walk and the box reduction are the same problem
# this sheet's sibling already solved, and solving it twice would mean fixing
# it twice.
from extract_hud_bars import (EDGE_FLOOR, EDGE_SPAN, HALO, PAGE_MARGIN, SOLID,
                              blob, grow, reduce_to_native, saturation)

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.normpath(os.path.join(
    HERE, "..", "..", "Assests", "boss-system assests.jpg"))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "godot", "ui", "art"))

# The partial-state plate, in sheet coordinates: the winged heart, the stone
# frame and both tracks. Measured, and checked below.
BOX = (85, 616, 1925, 945)

# Native size, and the same arithmetic the HUD bars are sized by: hud.gd draws
# at BAR_SCALE 0.5 in a 640x360 design space, the 960x540 viewport scales that
# by 1.5 and a 1280x720 window by 4/3, so 0.5 x 1.5 x 4/3 = 1 and a texture
# pixel is a screen pixel. 736 x 132 therefore draws 368 x 66 in design space —
# a little over half the screen wide, which is what a boss plate wants to be.
NATIVE = (736, 132)

# The row title, "Partially Full State (~70%)", sits above the plate and its
# descenders reach into the top of this crop. It is drawn in flat near-black on
# page grey, which is also what the frame's outlines are, so it cannot be keyed
# out by colour — but it is at a fixed place and there is nothing of the plate
# behind it, so it is blanked. Same treatment extract_dragon_lord.py gives the
# caption on its preview gifs, and for the same reason.
#
# In crop coordinates. The heart's crown is at x 28..415 and is deliberately
# outside this, and the frame's own top edge is at y 68.
TITLE = (470, 0, 1830, 60)

# Each track, in crop coordinates. `band` is the rows the fill occupies between
# the frame's inner outlines, `track` the span it runs along, and `lit`/`dark`
# are clean stretches to rebuild from and to check against.
#
# The magma track starts further left than the green one because the heart
# overlaps the green bar's left end and not the magma bar's. That is the art,
# not a measuring error.
TRACKS = {
    "health": {
        "band": (106, 182),
        "track": (475, 1778),
        "lit": (615, 1215),
        "dark": (1465, 1765),
        "hue": "green",
    },
    "magma": {
        "band": (220, 267),
        "track": (345, 1728),
        "lit": (415, 865),
        "dark": (1115, 1715),
        "hue": "red",
    },
}


def hue_lit(rgb, hue):
    """Is this pixel the track's own lit colour, rather than stone or page?

    By hue rather than by brightness: the stone frame is bright, and the dark
    end of a magma track is redder than it is light.
    """
    red, green, blue = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    if hue == "green":
        return (green - np.maximum(red, blue)) > 25
    return ((red - np.maximum(green, blue)) > 25) & (rgb.max(axis=-1) > 105)


def check(crop, spec, name):
    """Confirm the measured geometry still describes the sheet.

    A wrong `band` or `track` would rebuild the frame instead of the fill,
    which on a JPEG is not something an exact-pixel assertion can catch. What
    is checkable is the thing that makes a bar a bar: inside the band, the lit
    stretch has to be the track's own colour and the dark stretch has to be
    dark.
    """
    y0, y1 = spec["band"]
    band = crop[y0:y1 + 1]
    lit = band[:, spec["lit"][0]:spec["lit"][1] + 1]
    dark = band[:, spec["dark"][0]:spec["dark"][1] + 1]
    lit_share = float(hue_lit(lit, spec["hue"]).mean())
    dark_share = float((dark.max(axis=-1) < 115).mean())
    if lit_share < 0.55:
        sys.exit("%s: only %.0f%% of the 'lit' span is %s fill — the sheet "
                 "changed, remeasure TRACKS[%r]"
                 % (name, lit_share * 100, spec["hue"], name))
    if dark_share < 0.75:
        sys.exit("%s: only %.0f%% of the 'dark' span is dark track — the sheet "
                 "changed, remeasure TRACKS[%r]" % (name, dark_share * 100, name))
    return lit_share, dark_share


def rewrite(crop, spec, lit):
    """Rewrite one track across its whole span, lit or empty, in place."""
    y0, y1 = spec["band"]
    x0, x1 = spec["track"]
    if lit:
        source = crop[y0:y1 + 1, spec["lit"][0]:spec["lit"][1] + 1]
        span = source.shape[1]
        for i in range(x1 - x0 + 1):
            # Ping-pong rather than wrap: the fill's texture runs on into its
            # own reflection, where a wrap would put a hard vertical seam every
            # `span` pixels.
            step = i % (2 * span)
            take = step if step < span else 2 * span - step - 1
            crop[y0:y1 + 1, x0 + i] = source[:, take]
    else:
        source = crop[y0:y1 + 1, spec["dark"][0]:spec["dark"][1] + 1]
        # Median along the bar: an empty track is uniform left to right, so the
        # only thing varying across it is JPEG noise.
        column = np.median(source, axis=1)
        for i in range(x1 - x0 + 1):
            crop[y0:y1 + 1, x0 + i] = column


def plate(crop, lit_track):
    """A copy of the plate with every track emptied, then one of them lit."""
    out = crop.copy()
    for name, spec in TRACKS.items():
        rewrite(out, spec, lit=(name == lit_track))
    return out


def main():
    if not os.path.isfile(SOURCE):
        sys.exit("boss asset sheet not found at %s" % SOURCE)
    os.makedirs(OUT_DIR, exist_ok=True)
    sheet = np.asarray(Image.open(SOURCE).convert("RGB")).astype(float)
    page = np.median(np.concatenate([
        sheet[:PAGE_MARGIN, :].reshape(-1, 3),
        sheet[-PAGE_MARGIN:, :].reshape(-1, 3)]), axis=0)

    x0, y0, x1, y1 = BOX
    crop = sheet[y0:y1, x0:x1].copy()
    # The row title, off. Done before the alpha is built, so the blanked area
    # keys out as page rather than becoming a transparent bite in the plate.
    tx0, ty0, tx1, ty1 = TITLE
    crop[ty0:ty1, tx0:tx1] = page

    for name, spec in TRACKS.items():
        lit_share, dark_share = check(crop, spec, name)
        print("%-7s lit %.0f%%  dark %.0f%%" % (name, lit_share * 100, dark_share * 100))

    distance = np.abs(crop - page).max(axis=2)
    alpha = np.clip((distance - EDGE_FLOOR) / EDGE_SPAN, 0.0, 1.0)
    alpha *= grow(blob(distance > SOLID), HALO)

    scale_x = float(NATIVE[0]) / float(x1 - x0)
    manifest = {
        "_generated_by": "scripts/extract_boss_bar.py",
        "_source": os.path.basename(SOURCE),
        "size": list(NATIVE),
        "plate": "boss_plate.png",
        "bars": {},
    }
    scale_y = float(NATIVE[1]) / float(y1 - y0)
    reduce_to_native(plate(crop, None), alpha, NATIVE).save(
        os.path.join(OUT_DIR, "boss_plate.png"))
    for name, spec in TRACKS.items():
        filename = "boss_fill_%s.png" % name
        lit = reduce_to_native(plate(crop, name), alpha, NATIVE)
        # The track, in native pixels. Rounded outward so a full bar reaches
        # the ends of its track rather than stopping a pixel short of them.
        rect = (int(spec["track"][0] * scale_x),
                int(spec["band"][0] * scale_y),
                int(round((spec["track"][1] + 1) * scale_x)),
                int(round((spec["band"][1] + 1) * scale_y)))
        lit.crop(rect).save(os.path.join(OUT_DIR, filename))
        manifest["bars"][name] = {
            "file": filename,
            "at": [rect[0], rect[1]],
            "size": [rect[2] - rect[0], rect[3] - rect[1]],
        }
        print("%-7s -> %-21s %dx%d at (%d, %d)" % (
            name, filename, rect[2] - rect[0], rect[3] - rect[1],
            rect[0], rect[1]))

    path = os.path.join(OUT_DIR, "boss_bar.json")
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=1, sort_keys=True)
        handle.write("\n")
    print("plate    %dx%d  -> boss_plate.png" % NATIVE)
    print("manifest -> %s" % path)


if __name__ == "__main__":
    main()
