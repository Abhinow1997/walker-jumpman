#!/usr/bin/env python3
"""Turn the mech health bar asset into a full and an empty version.

Source: Assests/mech-healthbar.png — a 60 x 30 sprite with a heart, five
slanted segment slots and an amber under-bar, drawn in one fixed state: three
segments lit, two grey.

A HUD needs the two extremes, not one frozen state. This writes:

    healthbar_empty.png   every segment grey, under-bar dark
    healthbar_full.png    every segment lit, under-bar amber

The HUD draws the empty one, then draws the full one clipped to the player's
health fraction. One clip fills the segments and the under-bar together, and a
segment can sit half-lit at the clip edge.

The recolouring cannot be a blanket palette swap, because the heart is drawn in
the same two reds as a lit segment and would grey out with them. The segments
are parallelograms at a known place instead: at row 15 + n, segment i starts at
x = 20 + 5i - n, and its two coloured pixels are the next two along. That
formula was read off the asset and is checked against it on every run.

Usage (needs Pillow):

    python scripts/extract_healthbar.py

Then let Godot reimport, e.g. `godot --path godot --headless --import`.
"""
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.normpath(os.path.join(
    HERE, "..", "..", "Assests", "mech-healthbar.png"))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "godot", "ui", "art"))

# Content sits in the middle of an otherwise empty 60 x 30 canvas.
CROP = (0, 11, 53, 23)

# Segment geometry, measured off the asset.
SEGMENTS = 5
SEG_TOP = 15          # first row with coloured fill
SEG_ROWS = 4          # rows 15..18
SEG_X = 20            # segment 0's left edge on row SEG_TOP
SEG_PITCH = 5         # distance between segments
LIT_IN_SOURCE = 3     # how many are drawn lit; the rest are grey

# The under-bar, a single row of amber and orange.
BAR_ROW = 21
BAR_X0, BAR_X1 = 14, 39

LIT = [(196, 36, 48, 255), (137, 30, 43, 255)]      # bright, shadow
DIM = [(133, 133, 133, 255), (93, 93, 93, 255)]
AMBER = [(255, 162, 20, 255), (255, 80, 0, 255)]
DARK = (26, 25, 50, 255)

# Where the fill starts and ends, in source x. The under-bar begins before the
# first segment, so the clip runs from its left edge to the last segment's
# right, and health reads across the whole assembly rather than the slots alone.
FILL_X0 = 13
FILL_X1 = 44


def seg_pixels(index):
    """The two coloured pixels of one segment, as (x, y) pairs."""
    out = []
    for n in range(SEG_ROWS):
        x0 = SEG_X + SEG_PITCH * index - n
        y = SEG_TOP + n
        out.append((x0 + 1, y))
        out.append((x0 + 2, y))
    return out


def main():
    if not os.path.isfile(SOURCE):
        sys.exit("health bar asset not found at %s" % SOURCE)
    os.makedirs(OUT_DIR, exist_ok=True)
    source = Image.open(SOURCE).convert("RGBA")
    px = source.load()

    # Verify the measured geometry against the asset before trusting it. A
    # silently wrong formula would recolour the heart or miss a segment, and
    # that is the kind of thing you notice in a screenshot three days later.
    for i in range(SEGMENTS):
        expected = LIT if i < LIT_IN_SOURCE else DIM
        for k, (x, y) in enumerate(seg_pixels(i)):
            if px[x, y] != expected[k % 2]:
                sys.exit("segment %d pixel (%d, %d) is %s, expected %s — the "
                         "asset changed, remeasure SEG_* above"
                         % (i, x, y, px[x, y], expected[k % 2]))

    variants = {}
    for name, lit in (("full", True), ("empty", False)):
        image = source.copy()
        out = image.load()
        target = LIT if lit else DIM
        for i in range(SEGMENTS):
            for k, (x, y) in enumerate(seg_pixels(i)):
                out[x, y] = target[k % 2]
        if not lit:
            for x in range(BAR_X0, BAR_X1 + 1):
                out[x, BAR_ROW] = DARK
        cropped = image.crop(CROP)
        path = os.path.join(OUT_DIR, "healthbar_%s.png" % name)
        cropped.save(path)
        variants[name] = "healthbar_%s.png" % name
        print("%-6s %s  %s" % (name, cropped.size, path))

    manifest = {
        "_generated_by": "scripts/extract_healthbar.py",
        "_source": os.path.basename(SOURCE),
        "size": [CROP[2] - CROP[0], CROP[3] - CROP[1]],
        "fill_x0": FILL_X0 - CROP[0],
        "fill_x1": FILL_X1 - CROP[0],
        "segments": SEGMENTS,
        "files": variants,
    }
    path = os.path.join(OUT_DIR, "healthbar.json")
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=1, sort_keys=True)
    print("manifest -> %s" % path)


if __name__ == "__main__":
    main()
