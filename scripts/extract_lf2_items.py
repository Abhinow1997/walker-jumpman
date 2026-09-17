#!/usr/bin/env python3
"""Cut the crate and the two bottles out of the Little Fighter 2 items sheet.

Source: "PC _ Computer - Little Fighter 2 - Miscellaneous - Items.png" in
Assests/ — a rip of LF2's item sprites, laid out as labelled blocks on a teal
page with coloured grid lines and a pure black backdrop inside each block.

Only the crate, its shatter debris and the two bottles are taken: the white milk
bottle, which is health, and the brown one below it, which is mana. The sheet
holds a dozen other weapons and effects that this game has no use for yet;
adding one is a new entry in PICKS, not a new script.

Geometry was measured off the sheet rather than assumed, because no two blocks
share a grid: the crate block is on a 59 px pitch with 58 px cells, both bottle
blocks on a 49 px pitch with 48 px cells, and the debris block on a 28 x 29 px
pitch with 27 x 28 px cells.

The two bottle blocks are laid out identically — same pitch, same rotation order
— so the brown one is picked with the white one's cell numbers against a
different block origin, and the two sets of frames stay in step.

Each sprite is re-originned to the point that should sit on the ground — bottom
centre — so a crate and a bottle both stand on the floor line with no per-item
offsets in the game code.

Usage (needs Pillow):

    python scripts/extract_lf2_items.py

Then let Godot reimport, e.g. `godot --path godot --headless --import`.
"""
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SHEET = os.path.normpath(os.path.join(
    HERE, "..", "..", "Assests",
    "PC _ Computer - Little Fighter 2 - Miscellaneous - Items.png"))
OUT_DIR = os.path.normpath(os.path.join(
    HERE, "..", "godot", "features", "combat", "art"))

KEY_COLOUR = (0, 0, 0)

# The props are sized with the character, or a crate drawn for a 73 px Davis
# stands chest-high to a 55 px one. Same factors and same reasoning as
# scripts/extract_anti_davis.py — see the notes on SCALE and TEXTURE_SCALE
# there. SCALE is world size; TEXTURE_SCALE is sheet resolution, and leaving it
# at 1.0 is what keeps a prop drawn pixel for pixel as it was painted.
SCALE = 0.75
TEXTURE_SCALE = 1.0
RENDER_SCALE = SCALE / TEXTURE_SCALE

# Block origins and pitches, measured from the sheet. "cell" and "pitch" may be
# a single number for square blocks, or (w, h) where the two differ.
CRATE = {"x": 5, "y": 476, "cell": 58, "pitch": 59}
BOTTLE = {"x": 5, "y": 946, "cell": 48, "pitch": 49, "cols": 10}
# The brown bottle, four blocks further down the page. Same grid as the milk
# bottle and the same forty rotations in the same order.
BREW = {"x": 5, "y": 1434, "cell": 48, "pitch": 49, "cols": 10}
# LF2's broken-weapon debris: ten materials, two rows each. Rows 4 and 5 are the
# wooden planks a crate shatters into; rows 7 and 8 are the milk bottle's glass.
DEBRIS = {"x": 5, "y": 1970, "cell": (27, 28), "pitch": (28, 29), "cols": 10}

# Which cells to take.
#   crate frame 5 is the only one resting square on its base, so it is the crate
#   at rest; all six together are the tumble it does once something hits it.
#   bottle (0, 0) is the straight-on full bottle. The angled variant lower in the
#   block reads worse standing on a floor.
PICKS = {
    "crate": {"block": CRATE, "cells": [5]},
    # The crate tumbling through the air after a hit. The block's six frames are
    # the only angles LF2 drew for a box; 5 is square-on and the rest step round
    # from it, so this order reads as one continuous roll rather than a shuffle.
    "crate_spin": {"block": CRATE, "cells": [5, 1, 4, 0, 2, 3]},
    "bottle": {"block": BOTTLE, "cells": [(0, 0)]},
    # Tipped toward the mouth, for the hand during the drink animation. LF2's
    # drink frames name weaponact 31, and index 31 of this block is that tilt.
    "bottle_drink": {"block": BOTTLE, "cells": [(1, 3)]},
    # The bottle tumbling after a hit. The block holds forty rotations; every
    # other one of the first sixteen is an even eight-step turn through a full
    # circle, which is what a knocked bottle needs.
    "bottle_spin": {"block": BOTTLE, "cells": [(i % 10, i // 10) for i in range(0, 16, 2)]},
    # The brown bottle, cell for cell the same picks against the other block.
    "brew": {"block": BREW, "cells": [(0, 0)]},
    "brew_drink": {"block": BREW, "cells": [(1, 3)]},
    "brew_spin": {"block": BREW, "cells": [(i % 10, i // 10) for i in range(0, 16, 2)]},
    # Brown glass. The sheet has no smashed brown bottle, so this is the amber
    # sliver row instead of the milk bottle's own debris — that one is white
    # plastic with a red label on it, which reads as the wrong bottle entirely.
    # Four large slivers and four small, matching the milk bottle's two sizes.
    "brew_debris": {"block": DEBRIS,
                    "cells": [(c, 1) for c in range(4)]       # large slivers
                           + [(c, 1) for c in range(4, 8)]},  # small slivers
    # The crate's shatter. Four fragment sizes, four rotations each, in strip
    # order: type * 4 + rotation. LF2 spins a piece by swapping between its four
    # drawn angles rather than rotating one sprite, and so does the game.
    # The bottle's smashed glass: row 7 is the body with its gold cap still on,
    # row 8 the small shards with bits of the red label. Two fragment sizes,
    # four rotations each, same strip order as the crate's.
    "bottle_debris": {"block": DEBRIS,
                      "cells": [(c, 7) for c in range(4)]      # body and cap
                             + [(c, 8) for c in range(4)]},    # small shards
    "crate_debris": {"block": DEBRIS,
                     "cells": [(c, 4) for c in range(4)]      # big splintered burst
                            + [(c, 4) for c in range(4, 8)]   # medium plank
                            + [(c, 5) for c in range(4)]      # plank bundle
                            + [(c, 5) for c in range(4, 8)]}, # small splinter
}

# The crate frames must share one cell so the tumble does not jump between
# frames, and they already fill it, so the sheet's own 58x58 is kept and the
# origin put on its bottom edge. The bottle is a lone frame, so it is cropped to
# its own content with a pixel of margin.
TIGHT = {"bottle", "bottle_drink", "brew", "brew_drink"}

# Items whose origin is their middle rather than the ground under them, because
# they are held rather than stood on. LF2 stamps a held object by its own
# centre onto the frame's weapon point, so that is what has to line up.
CENTRED = {"bottle_drink", "crate_debris", "crate_spin", "bottle_debris",
           "bottle_spin", "brew_drink", "brew_debris", "brew_spin"}


def load_sheet():
    if not os.path.isfile(SHEET):
        sys.exit("items sheet not found at %s" % SHEET)
    image = Image.open(SHEET).convert("RGBA")
    px = image.load()
    for y in range(image.height):
        for x in range(image.width):
            if px[x, y][:3] == KEY_COLOUR:
                px[x, y] = (0, 0, 0, 0)
    return image


def _pair(value):
    return value if isinstance(value, tuple) else (value, value)


def cell_of(sheet, block, index):
    pitch = _pair(block["pitch"])
    col, row = index if isinstance(index, tuple) else (index, 0)
    x = block["x"] + col * pitch[0]
    y = block["y"] + row * pitch[1]
    size = _pair(block["cell"])
    return sheet.crop((x, y, x + size[0], y + size[1]))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    sheet = load_sheet()
    # Every cell and origin below addresses the texture, in its own pixels;
    # render_scale takes a texture pixel to a world unit. Nothing else in this
    # manifest is a measurement — the props' world sizes live in crate.gd and
    # bottle.gd, which are hand-tuned against the drawn art.
    # items.json has more than one owner: this writes the crate and the bottles,
    # scripts/extract_rock.py writes the rock. So the file is read back and only
    # this script's own keys are replaced — writing it fresh deleted the rock and
    # left the game with a prop whose art had no manifest entry.
    manifest = {}
    if os.path.isfile(os.path.join(OUT_DIR, "items.json")):
        manifest = json.load(open(os.path.join(OUT_DIR, "items.json"), encoding="utf-8"))
    by = manifest.get("_generated_by", [])
    if isinstance(by, str):
        by = [by]
    mine = "scripts/extract_lf2_items.py"
    if mine not in by:
        by.append(mine)
    manifest["_generated_by"] = sorted(by)
    manifest["_source"] = os.path.basename(SHEET)
    manifest["render_scale"] = round(RENDER_SCALE, 6)
    manifest.setdefault("items", {})

    for name, spec in PICKS.items():
        tiles = [cell_of(sheet, spec["block"], i) for i in spec["cells"]]
        for tile in tiles:
            if tile.getbbox() is None:
                sys.exit("%s picked an empty cell; check the measured grid" % name)

        if name in TIGHT:
            box = tiles[0].getbbox()
            content = tiles[0].crop(box)
            cell = (content.width + 2, content.height + 2)
            strip = Image.new("RGBA", cell, (0, 0, 0, 0))
            strip.paste(content, (1, 1), content)
            if name in CENTRED:
                origin = [cell[0] // 2, cell[1] // 2]
            else:
                # Bottom centre of the art, so it stands on the floor line.
                origin = [cell[0] // 2, cell[1] - 1]
        else:
            cell = _pair(spec["block"]["cell"])
            strip = Image.new("RGBA", (cell[0] * len(tiles), cell[1]), (0, 0, 0, 0))
            for i, tile in enumerate(tiles):
                strip.paste(tile, (i * cell[0], 0), tile)
            if name in CENTRED:
                origin = [cell[0] // 2, cell[1] // 2]
            else:
                origin = [cell[0] // 2, cell[1]]

        # Scaled last, as one strip. Resampling each frame on its own rounds its
        # edges independently and a spinning prop jitters between angles. At
        # TEXTURE_SCALE 1.0 there is nothing to resize and the sheet's own pixels
        # go straight out.
        scaled = (max(1, round(cell[0] * TEXTURE_SCALE)),
                  max(1, round(cell[1] * TEXTURE_SCALE)))
        origin = [round(origin[0] * TEXTURE_SCALE, 3),
                  round(origin[1] * TEXTURE_SCALE, 3)]
        if scaled != cell:
            strip = strip.resize((scaled[0] * len(tiles), scaled[1]), Image.LANCZOS)
        cell = scaled

        path = os.path.join(OUT_DIR, name + ".png")
        strip.save(path)
        manifest["items"][name] = {"file": name + ".png", "cell": list(cell),
                                   "origin": origin, "frames": len(tiles)}
        print("%-12s %d frame(s), cell %s, origin %s" % (name, len(tiles), cell, origin))

    path = os.path.join(OUT_DIR, "items.json")
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=1, sort_keys=True)
    print("manifest -> %s" % path)


if __name__ == "__main__":
    main()
