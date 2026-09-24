#!/usr/bin/env python3
"""Cut the glowing rock out of the rock sheet, and replace the crate with it.

Source: "Assests/rock.jpg" — a 3942 x 1056 generated sheet on a dark navy page,
in two rows:

    row 1   six frames of the same intact boulder, identical but for the glow in
            its cracks, which brightens and dims: an idle pulse, not damage
            states. All six are taken, and prop.gd loops them.
    row 2   five frames of it shattering, then a block of small debris pieces.

Three strips come out of it, into features/combat/art/:

    rock.png          the six idle frames, bottom-centre origin
    rock_break.png    the five shatter frames, centred, one shared cell
    rock_debris.png   the stone and crystal pieces from the debris block

The debris block is mostly wooden splinters — the sheet looks like a generic
breakables kit — so the pieces are picked by hue: anything browner than it is
blue is left behind. What is taken is stone, crystal and dust.

Two details of the sheet make a naive crop wrong, and both are handled below:

  * It has its own editor grid drawn on it, and those lines are BRIGHTER than
    the rock's own dark outline, so no threshold can separate them. The lines
    that span the whole sheet are found by geometry and painted over from either
    side. Striking them out of the mask instead cut every rock in half along the
    row that crossed it.
  * Each boulder is drawn standing in a tuft of grass, with sparkle motes
    floating around it. Neither belongs to a prop that gets picked up and
    thrown: a boulder sailing through the air with turf attached is wrong, and a
    single-pixel mote touching the rock is enough to drag the crop box out to
    it. The grass is keyed out by hue and the motes by an opening.

Usage (needs Pillow and numpy):

    python scripts/extract_rock.py

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
    sys.exit("extract_rock needs numpy: python -m pip install numpy")

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.normpath(os.path.join(HERE, "..", "..", "Assests", "rock.jpg"))
OUT_DIR = os.path.normpath(os.path.join(
    HERE, "..", "godot", "features", "combat", "art"))
MANIFEST = os.path.join(OUT_DIR, "items.json")

# Sizes in texture pixels. items.json's render_scale (0.75) takes a texture
# pixel to a world unit, so 36 x 48 here is 27 x 36 in the world — the height
# the crate was drawn at, since the rock is standing in for it and the levels,
# the reach of a punch and the carry pose all assume that size.
REST_SIZE = (36, 48)
# The shatter spreads well beyond the boulder's own outline, so its cell is
# wider and shorter: the pieces fly sideways, not up.
BREAK_SIZE = (56, 48)
DEBRIS_SIZE = (14, 14)

# Measured off the sheet. Boxes are generous; each one is tightened to its own
# content, so a few pixels of slack costs nothing.
RESTS = [(112, 40, 430, 500), (834, 40, 1151, 500), (1533, 40, 1852, 500),
         (2158, 40, 2475, 500), (2831, 40, 3137, 500), (3513, 40, 3833, 500)]
BREAKS = [(90, 570, 450, 1020), (535, 570, 940, 1020), (1030, 570, 1450, 1020),
          (1490, 570, 1990, 1020), (2030, 570, 2535, 1020)]
DEBRIS_BOX = (2560, 560, 3941, 1055)

# How far from the page colour a pixel has to be to be artwork. The page's own
# JPEG noise reaches 5, the sheet's hairline marks about 11, and the rock's dark
# outline 18 — so this keeps the outline and drops the marks.
ART = 14.0
# Lines this close to spanning the sheet are its grid, not its art.
SPAN = 0.9
GRID_ART = 26.0
# Below this many source pixels a blob is a mote or a speck, not a piece.
REST_MIN_PX = 3000
BREAK_MIN_PX = 500
DEBRIS_MIN_PX = 400
# How far the opening reaches. Three pixels parts a hairline from the body
# without eating anything the sheet actually draws.
OPEN = 3


def spans(indices):
    out = []
    for i in indices:
        if out and i == out[-1][1] + 1:
            out[-1][1] = i
        else:
            out.append([i, i])
    return out


def erode(mask, r):
    out = mask.copy()
    for _ in range(r):
        p = np.pad(out, 1, constant_values=False)
        out = (p[1:-1, 1:-1] & p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:])
    return out


def dilate(mask, r):
    out = mask.copy()
    for _ in range(r):
        p = np.pad(out, 1, constant_values=False)
        out = (p[1:-1, 1:-1] | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:])
    return out


def blobs(mask, min_px):
    """Every 8-connected run of `mask` at least `min_px` across, as masks."""
    height, width = mask.shape
    seen = np.zeros_like(mask)
    out = []
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
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        ny, nx = y + dy, x + dx
                        if (0 <= ny < height and 0 <= nx < width
                                and mask[ny, nx] and not seen[ny, nx]):
                            seen[ny, nx] = True
                            queue.append((ny, nx))
            if len(cells) >= min_px:
                piece = np.zeros_like(mask)
                for y, x in cells:
                    piece[y, x] = True
                out.append(piece)
    return out


def load():
    """The sheet with its grid painted out, plus the page colour and the mask."""
    if not os.path.isfile(SOURCE):
        sys.exit("rock sheet not found at %s" % SOURCE)
    sheet = np.asarray(Image.open(SOURCE).convert("RGB")).astype(float)
    height, width, _ = sheet.shape
    page = np.median(np.concatenate([
        sheet[0:18, 0:18].reshape(-1, 3), sheet[0:18, -18:].reshape(-1, 3),
        sheet[-18:, 0:18].reshape(-1, 3)]), axis=0)

    rough = np.abs(sheet - page).max(axis=2) > GRID_ART
    for y0, y1 in spans(np.nonzero(rough.sum(axis=1) > width * SPAN)[0].tolist()):
        above, below = sheet[max(0, y0 - 1)], sheet[min(height - 1, y1 + 1)]
        for y in range(y0, y1 + 1):
            t = (y - y0 + 1.0) / (y1 - y0 + 2.0)
            sheet[y] = above * (1.0 - t) + below * t
    for x0, x1 in spans(np.nonzero(rough.sum(axis=0) > height * SPAN)[0].tolist()):
        left, right = sheet[:, max(0, x0 - 1)], sheet[:, min(width - 1, x1 + 1)]
        for x in range(x0, x1 + 1):
            t = (x - x0 + 1.0) / (x1 - x0 + 2.0)
            sheet[:, x] = left * (1.0 - t) + right * t

    art = np.abs(sheet - page).max(axis=2) > ART
    # Grass at a boulder's base: green well clear of blue, over a blue channel
    # far darker than any stone or glow on the sheet.
    grass = ((sheet[:, :, 1] - sheet[:, :, 2]) > 35.0) & (sheet[:, :, 2] < 90.0)
    return sheet, art & ~grass


def keep(art, box, min_px):
    """The artwork inside `box`, opened so hairlines and motes fall away."""
    x0, y0, x1, y1 = box
    full = art[y0:y1, x0:x1]
    pieces = blobs(erode(full, OPEN), max(1, min_px // 8))
    if not pieces:
        sys.exit("nothing survived the opening in box %s — remeasure it" % (box,))
    body = np.zeros_like(full)
    for piece in pieces:
        body |= piece
    body = dilate(body, OPEN) & full
    return [p for p in blobs(body, min_px)]


def reduce_to(sheet, mask, box, size, margin=0):
    """One cell: the masked artwork, box-filtered down to `size`.

    Colour is averaged weighted by coverage and divided back out, or every
    outline pixel picks up a share of the page it was sitting on. Alpha is
    snapped at the end — a pixel-art prop wants a hard silhouette.
    """
    x0, y0, _, _ = box
    ys, xs = np.nonzero(mask)
    ty0, ty1 = ys.min(), ys.max() + 1
    tx0, tx1 = xs.min(), xs.max() + 1
    alpha = mask[ty0:ty1, tx0:tx1].astype(float)
    rgb = sheet[y0 + ty0:y0 + ty1, x0 + tx0:x0 + tx1]
    if margin:
        alpha = np.pad(alpha, margin)
        rgb = np.pad(rgb, ((margin, margin), (margin, margin), (0, 0)))
    small_a = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8))
                         .resize(size, Image.BOX)).astype(float) / 255.0
    small = np.zeros(size[::-1] + (3,))
    for channel in range(3):
        plane = Image.fromarray((rgb[:, :, channel] * alpha).astype(np.uint8))
        small[:, :, channel] = np.asarray(plane.resize(size, Image.BOX)).astype(float)
    covered = small_a[..., None] > 0.01
    small = np.where(covered, small / np.maximum(small_a[..., None], 1e-6), 0.0)
    out = np.zeros(size[::-1] + (4,), dtype=np.uint8)
    out[:, :, :3] = np.clip(small, 0, 255).astype(np.uint8)
    out[:, :, 3] = np.where(small_a >= 0.5, 255, 0)
    return Image.fromarray(out, "RGBA")


def strip(frames, size):
    out = Image.new("RGBA", (size[0] * len(frames), size[1]), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        out.paste(frame, (i * size[0], 0), frame)
    return out


def main():
    sheet, art = load()
    os.makedirs(OUT_DIR, exist_ok=True)
    items = {}

    # --- the idle boulder ---------------------------------------------------
    rests = []
    for box in RESTS:
        pieces = keep(art, box, REST_MIN_PX)
        if len(pieces) != 1:
            sys.exit("box %s holds %d bodies, expected one boulder"
                     % (box, len(pieces)))
        rests.append(reduce_to(sheet, pieces[0], box, REST_SIZE))
    strip(rests, REST_SIZE).save(os.path.join(OUT_DIR, "rock.png"))
    items["rock"] = {"file": "rock.png", "cell": list(REST_SIZE),
                     "frames": len(rests),
                     # Bottom centre: it stands on the floor line.
                     "origin": [REST_SIZE[0] // 2, REST_SIZE[1] - 1]}
    print("rock         %d frame(s), cell %s" % (len(rests), REST_SIZE))

    # --- the shatter --------------------------------------------------------
    # Every piece in the cell, not just the biggest: by the last frame the rock
    # is a dozen separate chunks, and the chunks are the animation.
    breaks = []
    for box in BREAKS:
        pieces = keep(art, box, BREAK_MIN_PX)
        if not pieces:
            sys.exit("box %s holds no shatter pieces — remeasure it" % (box,))
        whole = np.zeros_like(pieces[0])
        for piece in pieces:
            whole |= piece
        breaks.append(reduce_to(sheet, whole, box, BREAK_SIZE, margin=8))
    strip(breaks, BREAK_SIZE).save(os.path.join(OUT_DIR, "rock_break.png"))
    items["rock_break"] = {"file": "rock_break.png", "cell": list(BREAK_SIZE),
                           "frames": len(breaks),
                           # Centred: the break happens around the rock's middle
                           # and throws pieces both ways.
                           "origin": [BREAK_SIZE[0] // 2, BREAK_SIZE[1] // 2]}
    print("rock_break   %d frame(s), cell %s" % (len(breaks), BREAK_SIZE))

    # --- the debris ---------------------------------------------------------
    # The block is mostly wooden splinters. Stone and crystal are whatever is
    # not browner than it is blue.
    stones = []
    for piece in keep(art, DEBRIS_BOX, DEBRIS_MIN_PX):
        ys, xs = np.nonzero(piece)
        colour = sheet[DEBRIS_BOX[1] + ys, DEBRIS_BOX[0] + xs].mean(axis=0)
        if colour[0] > colour[2] + 15.0:
            continue        # wood
        stones.append((xs.min(), piece))
    stones.sort(key=lambda s: s[0])
    shards = [reduce_to(sheet, p, DEBRIS_BOX, DEBRIS_SIZE, margin=4)
              for _, p in stones]
    if not shards:
        sys.exit("no stone debris found — the hue test or the box is wrong")
    strip(shards, DEBRIS_SIZE).save(os.path.join(OUT_DIR, "rock_debris.png"))
    items["rock_debris"] = {"file": "rock_debris.png", "cell": list(DEBRIS_SIZE),
                            "frames": len(shards),
                            "origin": [DEBRIS_SIZE[0] // 2, DEBRIS_SIZE[1] // 2]}
    print("rock_debris  %d piece(s), cell %s" % (len(shards), DEBRIS_SIZE))

    # --- merged into the shared manifest ------------------------------------
    # items.json is one file with several owners: the LF2 extractor writes the
    # crate and the bottles, this writes the rock. Each merges its own keys and
    # leaves the rest alone, so running either does not undo the other.
    manifest = {}
    if os.path.isfile(MANIFEST):
        manifest = json.load(open(MANIFEST, encoding="utf-8"))
    by = manifest.get("_generated_by", [])
    if isinstance(by, str):
        by = [by]
    mine = "scripts/extract_rock.py"
    if mine not in by:
        by.append(mine)
    manifest["_generated_by"] = sorted(by)
    for name, spec in items.items():
        spec["source"] = os.path.basename(SOURCE)
        manifest.setdefault("items", {})[name] = spec
    with open(MANIFEST, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=1, sort_keys=True)
    print("manifest -> %s" % MANIFEST)


if __name__ == "__main__":
    main()
