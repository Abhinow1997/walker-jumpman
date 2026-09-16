"""Cuts the Magic Cliffs environment pack into the pieces the game places.

    python scripts/extract_magic_cliffs.py
    <godot> --path godot --headless --import

THE ONLY LICENSED ART IN THE PROJECT. Magic Cliffs Environment by Ansimuz
(Luis Zuno) is CC0 - public domain, commercial use, no attribution required.
Every other sheet here is ripped commercial art. See the PROVENANCE.md this
writes next to the output.

Same contract as the other four extractors: named pieces out, a JSON manifest
beside them, and the measurements re-checked against the source on every run so
a sheet that has shifted fails loudly instead of producing plausible garbage.

Nothing is resampled. This is crisp 14-colour pixel art and a resize destroys
it - the exact reason the CC0 Punk was dropped earlier. It does not need one:
the cast is drawn at 0.75 world size against a 4/3 canvas magnification, which
nets to 1, so a pack pixel lands on one screen pixel. See the note on SCALE and
TEXTURE_SCALE in scripts/extract_anti_davis.py.
"""

import json
import os
import shutil
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PACK = os.path.normpath(os.path.join(
    HERE, "..", "..", "Assests", "Magic-Cliffs-Gamekit", "Magic-Cliffs-Gamekit",
    "Assets", "Environment", "PNG"))
OUT_DIR = os.path.normpath(os.path.join(
    HERE, "..", "godot", "features", "world", "art", "magic_cliffs"))

SHEET = "tileset.png"
SHEET_SIZE = (928, 320)
TILE = 16

# World size, matching the cast. Not a resample: the sheets go out untouched and
# the sprite node carries this, exactly as the character extractors do.
RENDER_SCALE = 0.75

# The dark body colour of every cliff. Terrain is drawn as this flat colour with
# the grass strip and the edge caps over it, which is how the pack's own preview
# reads: large masses are flat, and the detail lives at their edges.
#
# Read off the INTERIOR OF A CAP, not off fill_stone. fill_stone is a decorative
# stone tile and is several shades lighter; using it made every cliff body read
# as a lighter panel sitting between two darker ends, with a seam down each side.
# grass_strip's underside, ground_left's interior and ground_right's interior all
# agree on this value, and the check below holds the run to it.
FILL = (17, 32, 36)
# Where that colour is sampled from, as (piece, box): the deep interior of the
# left cap, well clear of its rock edge and its grass.
FILL_SOURCE = ("ground_left", (60, 60, 92, 111))

# The stone the archway is set into. Lighter than the earth cliffs, which is
# exactly why taking the cliff colour from fill_stone was wrong.
STONE = (25, 49, 51)

# Pieces drawn against a wall in the sheet, with the colour of the wall behind
# them. Dropped anywhere else that slab reads as a dark box: a plant floating on
# a plinth, or a portal that is a rectangle rather than an arch. The background
# is flood-filled inward from the edges, so a matching pixel enclosed by the art
# itself survives - which is what leaves the archway its ring of rocks.
TRANSPARENT_BACKING = {
    "bush": FILL,
    "tuft": FILL,
    "pillar_bush": FILL,
    "archway": STONE,
}

# Every terrain piece in the sheet is drawn against one horizontal line: the
# grass surface, the y a character actually stands on. It sits at this row of
# the SOURCE SHEET, so a piece cut at sheet y has its surface (GRASS_LINE - y)
# rows down from its own top edge. That is what lets a 111 px cap with tall
# tufts and a 38 px strip with short ones line up without per-piece fudging.
GRASS_LINE = 190
# How far a piece's own grass band may start from that line before the run
# fails. These edges are hand-drawn and a cap's grass rolls over its shoulder a
# row or two later than a flat strip's; a sheet that had actually been re-laid
# out would be wrong by far more than this.
GRASS_SLACK = 2

# The bright yellow-green of the grass band, as a test rather than one value:
# it is a gradient, and only its separation from the dirt below matters here.
def is_grass(rgb):
    return rgb[0] > 110 and rgb[1] > 120 and rgb[2] < 110

# name: (x, y, w, h) in the sheet. Measured off the alpha channel, then named by
# eye; the checks below confirm each rect still holds exactly one whole sprite.
PIECES = {
    # --- ground the player stands on ------------------------------------
    "grass_strip":  (192, 186, 48, 38),   # tiles horizontally along a top edge
    "grass_short":  (304, 186, 32, 22),
    "ground_left":  (36, 177, 92, 111),   # left cap: brown dirt and rock
    "ground_right": (512, 186, 44, 86),   # right cap: grey-green rock
    # The rock column each cap sits on, with the grass and the fade below it cut
    # away so it repeats down a face without a fringe of turf every 80 units.
    # The caps alone are 83 and 64 units tall against a face you can see 270 of,
    # which left two thirds of every cliff edge as flat colour.
    "edge_left":    (36, 211, 48, 77),    # brown earth and boulders
    "edge_right":   (512, 212, 44, 60),   # grey-green rock
    "fill_stone":   (688, 48, 48, 48),    # loose rubble; too busy for a big face
    # The texture the inside of a cliff is made of. Its base colour IS the cliff
    # colour, with darker rock shapes over it, so it tiles across a face without
    # a seam and without disagreeing with the caps at either end. Tiling this
    # instead of filling a flat rectangle is what stops a tall cliff reading as
    # a box: at 1664 units deep, flat colour is most of the screen.
    "body_stone":   (240, 240, 64, 32),
    # --- the floating islands the level is named after --------------------
    "island_large": (41, 24, 98, 76),
    "island_small": (48, 121, 48, 39),
    "island_wide":  (543, 104, 64, 40),
    "rock_float":   (601, 56, 48, 32),
    "rock_chunk":   (537, 56, 32, 32),
    # --- the bridge -------------------------------------------------------
    "bridge_left":  (583, 188, 41, 30),
    "bridge_mid":   (640, 187, 32, 31),
    "bridge_right": (688, 188, 41, 30),
    # --- set dressing -----------------------------------------------------
    "archway":      (752, 192, 96, 112),  # the portal Area 3 is built around
    "tree":         (191, 46, 123, 114),
    "bush":         (256, 180, 32, 44),
    "tuft":         (352, 183, 16, 25),
    "pillar_bush":  (144, 105, 32, 55),
    # Plants that hang DOWN a cliff face rather than standing on top of one.
    # Their backing is the cliff colour, so it is deliberately kept: drape one
    # over the lip and it reads as growth on the rock instead of a cut-out. This
    # is the detail that makes the pack's own cliffs look like cliffs.
    "vine":         (144, 240, 32, 32),
    "vine_rock":    (464, 243, 32, 45),
    "hang_left":    (325, 43, 59, 97),    # cliff hanging from the top of frame
    "hang_thin":    (400, 43, 16, 96),
    "hang_right":   (432, 43, 59, 97),
}

# Pieces whose surface has to agree with GRASS_LINE. The islands are free-
# standing objects rather than part of the ground mass, so they are measured
# but not tied to it.
ON_THE_GROUND_LINE = ("grass_strip", "grass_short", "ground_left", "ground_right")

# Cut from INSIDE a bigger piece rather than standing alone in the sheet, so the
# usual "this rect holds exactly one whole sprite" check does not apply: a slice
# out of a cliff face has a ragged edge by nature. They are checked for being
# substantially solid instead, which is what a rock column has to be to tile.
SUBCROPS = ("edge_left", "edge_right")
SUBCROP_SOLID = 0.80

# The bridge is planking seen slightly from above, with posts and a rope rail
# hanging below it. Every silhouette measure reads the posts, so the deck - the
# row you actually walk on - is declared and then checked, the same way the
# bandit's origin is. All three sections share it or the bridge steps mid-span.
BRIDGE_DECK = 1
DECLARED_SURFACE = {"bridge_left": BRIDGE_DECK, "bridge_mid": BRIDGE_DECK,
                    "bridge_right": BRIDGE_DECK}

# `surface` is only meaningful for something you stand on. For set dressing - a
# tree, a bush, the archway - the renderer anchors to the bottom edge instead,
# and the value recorded for those pieces is not used.
STANDABLE = (ON_THE_GROUND_LINE + tuple(DECLARED_SURFACE)
             + ("island_large", "island_small", "island_wide",
                "rock_float", "rock_chunk"))

# Parallax layers, copied through untouched, ordered BACK TO FRONT with the rate
# each one scrolls at relative to the camera. 0 is nailed to the view and 1 would
# move with the world; the distant green headland is the nearest of the four and
# so the fastest. The sea sits in front of the clouds because in the pack's own
# preview the headland and the water read as one distance, with the sky behind.
BACKGROUND = [
    ("sky.png", 0.0),
    ("clouds.png", 0.15),
    ("sea.png", 0.25),
    ("far-grounds.png", 0.45),
]


def row_coverage(image):
    """Opaque pixels per row."""
    width, height = image.size
    alpha = image.split()[3].load()
    return [sum(1 for x in range(width) if alpha[x, y] > 0) for y in range(height)]


def surface_row(image):
    """The row a character's feet sit on: the top of the piece's solid mass,
    below any grass tufts or leaves poking above it.

    Measured against the piece's OWN widest row rather than its rect width. An
    island or a cap has an irregular silhouette and never reaches full width, so
    a fixed threshold either reads the tufts as solid or never triggers at all.
    """
    rows = row_coverage(image)
    peak = max(rows) if rows else 0
    if peak == 0:
        return 0
    for y, filled in enumerate(rows):
        if filled >= peak * 0.9:
            return y
    return 0


def grass_top(image):
    """First row where the bright grass band is essentially at full width.

    Opacity cannot answer this: the tufts above the surface are dense enough to
    read as solid, so every alpha threshold either catches them or misses the
    ragged edge of a cap. The grass COLOUR does answer it - it appears at the
    surface and falls away into dirt below - so that is what the shared line is
    checked against.
    """
    width, height = image.size
    alpha = image.split()[3].load()
    pixels = image.convert("RGB").load()
    band = []
    for y in range(height):
        band.append(sum(1 for x in range(width)
                        if alpha[x, y] > 0 and is_grass(pixels[x, y])))
    peak = max(band) if band else 0
    if peak == 0:
        return None
    for y, filled in enumerate(band):
        if filled >= peak * 0.9:
            return y
    return None


def strip_backing(image, colour, tolerance=6):
    """Clears the flat background slab behind a plant, working inward from the
    edges so that a FILL-coloured pixel inside the leaves survives."""
    pixels = image.load()
    width, height = image.size
    def matches(p):
        return (p[3] > 0 and abs(p[0] - colour[0]) <= tolerance
                and abs(p[1] - colour[1]) <= tolerance
                and abs(p[2] - colour[2]) <= tolerance)
    stack = [(x, y) for x in range(width) for y in (0, height - 1)]
    stack += [(x, y) for y in range(height) for x in (0, width - 1)]
    seen, cleared = set(), 0
    while stack:
        x, y = stack.pop()
        if (x, y) in seen or not (0 <= x < width and 0 <= y < height):
            continue
        seen.add((x, y))
        if not matches(pixels[x, y]):
            continue
        pixels[x, y] = (0, 0, 0, 0)
        cleared += 1
        stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    return cleared


def main():
    sheet_path = os.path.join(PACK, SHEET)
    if not os.path.isfile(sheet_path):
        sys.exit("Magic Cliffs pack not found at %s" % PACK)
    sheet = Image.open(sheet_path).convert("RGBA")
    if sheet.size != SHEET_SIZE:
        sys.exit("tileset.png is %s, expected %s - the pack changed, remeasure"
                 % (sheet.size, SHEET_SIZE))

    name, box = FILL_SOURCE
    px, py, pw, ph = PIECES[name]
    sample = sheet.crop((px, py, px + pw, py + ph)).crop(box).convert("RGB")
    counts = {}
    for colour in sample.getdata():
        counts[colour] = counts.get(colour, 0) + 1
    common = max(counts, key=counts.get)
    if common != FILL:
        sys.exit("the cliff interior in %s is %s, expected %s - the palette moved "
                 "and every terrain body in every level would be a shade off the "
                 "caps drawn at its ends" % (name, common, FILL))

    os.makedirs(OUT_DIR, exist_ok=True)
    manifest = {
        "_generated_by": "scripts/extract_magic_cliffs.py",
        "_source": "Magic Cliffs Environment by Ansimuz (Luis Zuno)",
        "_license": "CC0 - public domain, commercial use, no attribution required",
        "tile": TILE,
        "render_scale": RENDER_SCALE,
        "fill": "#%02x%02x%02x" % FILL,
        "grass_line": GRASS_LINE,
        "pieces": {},
        "background": [],
    }

    for name, (x, y, w, h) in sorted(PIECES.items()):
        piece = sheet.crop((x, y, x + w, y + h))
        box = piece.getbbox()
        if box is None:
            sys.exit("%s is empty at (%d, %d) - the sheet layout moved" % (name, x, y))
        if name in SUBCROPS:
            solid = sum(1 for p in piece.getdata() if p[3] > 0) / float(w * h)
            if solid < SUBCROP_SOLID:
                sys.exit("%s is only %.0f%% solid; a column that sparse will not "
                         "tile down a cliff face without gaps" % (name, 100.0 * solid))
        elif box != (0, 0, w, h):
            sys.exit("%s does not fill its %dx%d rect (content at %s): the rect "
                     "is clipping the sprite or catching a neighbour"
                     % (name, w, h, box))
        if name in ON_THE_GROUND_LINE:
            # The artist drew every ground piece against one line in the sheet,
            # so the offset is derived from where the piece was cut, never from
            # its own silhouette. A 111 px cap with tall tufts and a 22 px strip
            # with short ones then meet without a step at the seam.
            surface = GRASS_LINE - y
            seen = grass_top(piece)
            if seen is None or abs(seen - surface) > GRASS_SLACK:
                sys.exit("%s has its grass band starting at row %s, but it sits "
                         "at sheet y %d so the shared line says %d. The pack has "
                         "been re-laid-out and the ground would step at every seam."
                         % (name, seen, y, surface))
        elif name in DECLARED_SURFACE:
            surface = DECLARED_SURFACE[name]
            rows = row_coverage(piece)
            width = piece.size[0]
            if rows[surface] < width * 0.5:
                sys.exit("%s: the deck row %d is only %d of %d px wide, so the "
                         "declared surface is not on the planking any more"
                         % (name, surface, rows[surface], width))
        else:
            # Grass marks the top of anything grown over; bare rock has none, so
            # it falls back to the top of the piece's own solid mass.
            surface = grass_top(piece)
            if surface is None:
                surface = surface_row(piece)
        cleared = 0
        if name in TRANSPARENT_BACKING:
            cleared = strip_backing(piece, TRANSPARENT_BACKING[name])
            if cleared == 0:
                sys.exit("%s has no flat backing to clear, so it is no longer the "
                         "piece this expected - check the sheet" % name)
        piece.save(os.path.join(OUT_DIR, name + ".png"))
        # Transparent margin on each side. An edge column is drawn so its rock
        # meets the silhouette, and both of these carry 4 to 11 px of nothing on
        # their outer side: aligned by the rect instead, the rock sits that far
        # inside the cliff and leaves a sliver of flat fill along every face.
        edges = piece.getbbox() or (0, 0, w, h)
        manifest["pieces"][name] = {
            "file": name + ".png", "size": [w, h], "surface": surface,
            "standable": name in STANDABLE,
            "bleed": [edges[0], w - edges[2]],
        }
        print("%-14s %3dx%-3d surface %2d%s"
              % (name, w, h, surface,
                 "  backing cleared: %d px" % cleared if cleared else ""))

    for layer, factor in BACKGROUND:
        source = os.path.join(PACK, layer)
        if not os.path.isfile(source):
            sys.exit("background layer %s missing from the pack" % layer)
        out_name = layer.replace("-", "_")
        shutil.copyfile(source, os.path.join(OUT_DIR, out_name))
        size = Image.open(source).size
        manifest["background"].append(
            {"file": out_name, "size": list(size), "factor": factor})
        print("%-14s %3dx%-3d background, scroll %.2f"
              % (out_name[:-4], size[0], size[1], factor))

    path = os.path.join(OUT_DIR, "magic_cliffs.json")
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=1, sort_keys=True)
    print("\n%d pieces + %d background layers" % (len(PIECES), len(BACKGROUND)))
    print("manifest -> %s" % path)


if __name__ == "__main__":
    main()
