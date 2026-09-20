"""Cuts the dragon out of Assests/demo_lugia into the strips and manifest
features/combat/enemy.gd reads for kind "dragon" — the flying boss.

WHAT THE PACK SHIPS, AND WHY IT TAKES A DECODER TO GET AT IT

`demo_lugia.zip` is two files — `demo_lugia-Sheet.png` and `demo_lugia.aseprite`
— and both hold the SAME six frames: one in-place wing-flap. On its own that is
a boss with one animation.

The eleven `.gif` files sitting beside the zip are the store page's preview
animations, and they hold everything else: a ground idle, a ground walk, a claw,
a fire breath standing and another in flight, a roaring take-off, a landing, two
hurts and a collapse. Every frame of every one of them has the word "Preview"
stamped across it, which is why they look unusable.

They are not. The stamp is TWO SEMI-TRANSPARENT OVERLAYS — a pale fill and a
deeper outline, both at alpha ~0.209 — composited over the art at a FIXED
position, and then quantised into each gif's own small palette. Three facts make
that exactly reversible:

  * The text never moves. Its mask is the same 2938 pixels in every frame of
    every gif, and every pixel of the 208x208 frame is seen as clean background
    in at least one frame somewhere, so the mask can be read off the backgrounds
    rather than guessed.
  * The sheet is ground truth. `F8eIii.gif` frames 0-11 are two turns of the
    same six frames the sheet holds, so the blend can be FITTED against known
    art rather than eyeballed — see solve() below, which least-squares it.
  * The quantisation error is at most 1 per channel, and every animation's real
    palette is visible outside the text box. Snapping the un-blended pixel to
    that palette removes the last of it.

The result is checked, not hoped for: verify() re-decodes those twelve known
frames and asserts EVERY art pixel comes back identical. It does.

None of this is a licence to use the gifs; see PROVENANCE.md, which says what is
known about where this pack came from (nothing).

Run from walker-jumpman/:
    python scripts/extract_dragon.py
    <godot> --path godot --headless --import
"""
import json
import os

import numpy as np
from PIL import Image, ImageSequence

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, "..", "..", "Assests", "demo_lugia"))
OUT = os.path.normpath(os.path.join(
    HERE, "..", "godot", "features", "combat", "art", "dragon"))

SHEET = "demo_lugia-Sheet.png"
# The gif that doubles as the ground truth: its first twelve frames are the
# sheet's six, twice.
TRUTH = "F8eIii.gif"
TRUTH_FRAMES = 12

# The source grid. The gifs are a clean 4x nearest upscale of the same cell.
CELL = 208
GIF_UPSCALE = 4
COLS, ROWS = 3, 2

# Texture pixel to world unit. The dragon's body measures 89 x 52 from nose to
# tail root and sole to shoulder, so 1.5 draws him 133 long and 78 tall against
# a 42-tall player and the Dragon Lord's 88 — the longest thing in the game by
# a wide margin, and the only one wider than it is tall.
#
# NOT 2.0, which is what the other boss is cut at. Two numbers set the ceiling
# and he does not fit under both at 2.0: the camera shows 270 units above the
# player's feet, and his raised wings reach 69 px above his own sole. At 1.5
# that is 103, leaving 166 of cruising altitude; at 2.0 it is 138 and he flies
# with his wingtips off the top of the screen.
RENDER_SCALE = 1.5

# Which gif is which, and which of its frames to take. The filenames are the
# download's own and say nothing, so this table is the only place the pack's
# contents are written down — keep it and PROVENANCE.md in step.
#
# `sheet` means the six frames of the zip's own spritesheet rather than a gif:
# the flap cycle is authoritative there and needs no decoding at all.
#
# An "_air" suffix is a phase variant. enemy.gd's flyer plays the air one while
# it is up and the plain one while it is down — see anim_for() there — so a
# dragon has two idles, two walks, two hurts and two ways of breathing fire.
CLIPS = {
    # --- in the air ---------------------------------------------------------
    # The flap, from the sheet. Same six frames at two speeds: holding station
    # and driving forward.
    "idle_air": ("sheet", [0, 1, 2, 3, 4, 5], True, [0.11] * 6),
    "walk_air": ("sheet", [0, 1, 2, 3, 4, 5], True, [0.07] * 6),
    # The climb/glide pair enemy.gd shows whenever a body is off the ground:
    # index 0 rising (wings driven down, which is what lifts him), 1 falling.
    "jump": ("sheet", [0, 2], False, [0.12, 0.12]),
    # The swoop's strike. Wings up and held — the telegraph the player reads —
    # then a cut straight to the deepest downstroke with no mid-frame between
    # them, which is what a hard wing-beat looks like: slow up, fast down.
    "swoop": ("sheet", [3, 4, 0, 0, 1, 2], False,
              [0.11, 0.15, 0.06, 0.15, 0.09, 0.12]),
    # Fire, in flight: a wind-up, then a plume thrown a long way forward.
    "fire_air": ("nunurj.gif", list(range(10)), False, [0.09] * 10),
    "hurt_air": ("mLQFFK.gif", [0, 1, 2], False, [0.07, 0.10, 0.16]),

    # --- on the ground ------------------------------------------------------
    "idle": ("75NSHV.gif", [0, 1, 2, 3], True, [0.16] * 4),
    "walk": ("oIn+jh.gif", list(range(8)), True, [0.09] * 8),
    # Rears up and swipes. The white arc on frame 5 is the blow.
    "claw": ("FwZsEO.gif", list(range(9)), False,
             [0.08, 0.08, 0.09, 0.10, 0.07, 0.13, 0.08, 0.08, 0.12]),
    "fire": ("7wpd6L.gif", list(range(10)), False, [0.09] * 10),
    "hurt": ("5Wgewc.gif", [0, 1, 2], False, [0.07, 0.10, 0.16]),

    # --- the two that change which of those sets applies --------------------
    # The roar and the launch. Frames 2 to 4 turn to face the player head-on
    # with the wings thrown wide, which is the one moment in the pack drawn
    # straight at the camera, and it is the moment the fight starts.
    "takeoff": ("5YzQUH.gif", list(range(8)), False,
                [0.09, 0.10, 0.13, 0.16, 0.13, 0.08, 0.07, 0.09]),
    # Comes down wings-first, touches, and folds up.
    "land": ("14mpnz.gif", [0, 1, 2, 3, 4, 5], False,
             [0.07, 0.08, 0.10, 0.09, 0.09, 0.12]),

    # Beaten: it goes down on the deck. enemy.gd's flyer then picks it up and
    # flies it out of the level — see _depart there — so this is the collapse
    # and not the whole of the death.
    "death": ("YG0f_G.gif", [0, 1, 2, 3, 4, 5], False,
              [0.09, 0.09, 0.10, 0.12, 0.16, 0.30]),
}

# Which frame of each attack the blow lands on, as an index into its own list.
# Measured where the art makes it obvious and written here where it does not:
# the claw's white arc and the two fire plumes are found by the widest-effect
# search below, so only the swoop — whose "effect" is the dragon itself — is
# pinned by hand.
SWOOP_HIT = 3
# A margin so no frame touches the cell edge and picks up a seam when sampled.
MARGIN = 2


# --- getting the watermark off ----------------------------------------------

def gif_frames(name):
    """One gif, at the source resolution. The upscale is asserted rather than
    assumed: every 4x4 block must be one colour, or this is not a clean
    nearest-neighbour blow-up and nothing below holds."""
    im = Image.open(os.path.join(SRC, name))
    out = []
    for raw in ImageSequence.Iterator(im):
        big = np.array(raw.convert("RGB"))
        h, w = CELL * GIF_UPSCALE, CELL * GIF_UPSCALE
        assert big.shape[:2] == (h, w), "%s is %s, not %dx%d" % (
            name, big.shape[:2], h, w)
        blocks = big.reshape(CELL, GIF_UPSCALE, CELL, GIF_UPSCALE, 3)
        small = blocks[:, 0, :, 0, :]
        assert np.array_equal(blocks, np.repeat(np.repeat(
            small[:, None, :, None, :], GIF_UPSCALE, 1), GIF_UPSCALE, 3)), (
            "%s is not a clean %dx nearest upscale" % (name, GIF_UPSCALE))
        out.append(small)
    return out


def sheet_cells():
    img = np.array(Image.open(os.path.join(SRC, SHEET)).convert("RGBA"))
    assert img.shape[:2] == (CELL * ROWS, CELL * COLS), (
        "%s is %s, not the %dx%d grid of %d px cells this reads"
        % (SHEET, img.shape[:2], COLS, ROWS, CELL))
    return [img[(i // COLS) * CELL:(i // COLS + 1) * CELL,
                (i % COLS) * CELL:(i % COLS + 1) * CELL] for i in range(6)]


def stamp(gifs, cells):
    """Where the watermark is and what it is made of.

    The mask comes off the BACKGROUNDS, not off the art. Wherever the sheet is
    transparent, whatever the gif shows there is either the flat background or
    the background with the stamp over it — which names the stamp's colours in
    two frames flat. Every one of the 43264 pixels is clean background in some
    frame of some gif, so sweeping all of them classifies the lot.
    """
    truth = gifs[TRUTH][:TRUTH_FRAMES]
    bg = tuple(int(v) for v in truth[0][0, 0])
    over = set()
    for i, frame in enumerate(truth):
        empty = cells[i % 6][:, :, 3] <= 8
        for c in np.unique(frame[empty].reshape(-1, 3), axis=0):
            t = tuple(int(v) for v in c)
            if t != bg:
                over.add(t)
    assert len(over) == 2, (
        "expected two stamp layers over the background, found %d: %s"
        % (len(over), sorted(over)))
    # Deeper first, so layer 1 is always the outline and 2 the fill.
    layers = sorted(over, key=lambda c: sum(c))
    mask = np.zeros((CELL, CELL), dtype=np.uint8)
    seen = np.zeros((CELL, CELL), dtype=bool)
    for frames in gifs.values():
        for frame in frames:
            for n, colour in enumerate(layers, start=1):
                hit = np.all(frame == colour, axis=2)
                mask[hit] = n
                seen |= hit
            seen |= np.all(frame == bg, axis=2)
    assert seen.all(), (
        "%d pixels are never seen as clean background, so the stamp mask "
        "cannot be read off them" % (~seen).sum())
    return np.array(bg), mask, layers


def solve(gifs, cells, mask):
    """The blend, least-squared against known art.

    For one overlay, result = (1 - a) * art + a * colour, so regressing the
    gif's channel on the sheet's gives the slope (1 - a) and the intercept
    (a * colour). The twelve ground-truth frames give thousands of pairs per
    layer, which is why this is fitted rather than written down.
    """
    truth = gifs[TRUTH][:TRUTH_FRAMES]
    out = {}
    for layer in (1, 2):
        art, got = [], []
        for i, frame in enumerate(truth):
            cell = cells[i % 6]
            sel = (cell[:, :, 3] > 8) & (mask == layer)
            art.append(cell[:, :, :3][sel].astype(float))
            got.append(frame[sel].astype(float))
        art, got = np.concatenate(art), np.concatenate(got)
        slopes, intercepts = [], []
        for k in range(3):
            m, b = np.polyfit(art[:, k], got[:, k], 1)
            slopes.append(m)
            intercepts.append(b)
        alpha = 1.0 - float(np.mean(slopes))
        out[layer] = (alpha, np.array([b / alpha for b in intercepts]))
    return out


def decoder(bg, mask, blend):
    """Returns a function that takes one gif's frames and gives back RGBA with
    the stamp removed and the background keyed out."""
    def decode(frames):
        # The animation's real palette: the colours it uses OUTSIDE the text
        # box, which were never touched. The stamp cannot invent a colour, so
        # anything the un-blend produces has to land on one of these — which is
        # what removes the last of the gif's own quantisation.
        clean = mask == 0
        palette = set()
        for f in frames:
            for c in np.unique(f[clean].reshape(-1, 3), axis=0):
                palette.add(tuple(int(v) for v in c))
        palette.discard(tuple(bg))
        candidates = np.vstack([np.array(sorted(palette), dtype=float),
                                bg[None, :].astype(float)])
        out = []
        for f in frames:
            v = f.astype(float).copy()
            for layer in (1, 2):
                alpha, colour = blend[layer]
                sel = mask == layer
                v[sel] = (v[sel] - alpha * colour) / (1.0 - alpha)
            sel = mask > 0
            under = v[sel]
            near = np.argmin(((under[:, None, :] - candidates[None, :, :]) ** 2
                              ).sum(axis=2), axis=1)
            v[sel] = candidates[near]
            rgb = np.clip(np.round(v), 0, 255).astype(np.uint8)
            alpha_ch = np.where(np.all(rgb == bg, axis=2), 0, 255).astype(np.uint8)
            out.append(np.dstack([rgb, alpha_ch]))
        return out
    return decode


def verify(decode, gifs, cells):
    """Re-decode the twelve frames whose answer is known and insist on every
    pixel. A decoder that is 99% right would leave speckle along the text."""
    got = decode(gifs[TRUTH])[:TRUTH_FRAMES]
    total = exact = 0
    for i, frame in enumerate(got):
        cell = cells[i % 6]
        art = cell[:, :, 3] > 8
        total += int(art.sum())
        exact += int((frame[:, :, :3][art] == cell[:, :, :3][art]).all(axis=1).sum())
        assert (frame[:, :, 3] > 8).sum() == art.sum(), (
            "frame %d recovers a different silhouette than the sheet's" % i)
    assert exact == total, (
        "only %d of %d art pixels came back exactly (%.2f%%)"
        % (exact, total, 100.0 * exact / total))
    return total


# --- measuring what each attack hits with ------------------------------------

def effect_box(frame, ax, body_half):
    """The bounding box of everything on this frame that is clear of the
    dragon's own body — the fire, the claw's arc — which is what an attack
    actually reaches with. Forward is -x: he is drawn facing left."""
    alpha = frame[:, :, 3] > 24
    xs = np.arange(frame.shape[1])[None, :]
    alpha = alpha & (xs < ax - body_half)
    ys, cols = np.nonzero(alpha)
    if not len(ys):
        return None
    return int(cols.min()), int(ys.min()), int(cols.max()), int(ys.max())


def widest_effect(frames, ax, body_half):
    """Which frame throws the effect furthest, and how far. Measured, so
    retiming an animation cannot desync the blow from the picture of it."""
    best = (0, None, -1.0)
    for i, f in enumerate(frames):
        box = effect_box(f, ax, body_half)
        if box and ax - box[0] > best[2]:
            best = (i, box, ax - box[0])
    return best[0], best[1]


def main():
    cells = sheet_cells()
    names = sorted(f for f in os.listdir(SRC) if f.lower().endswith(".gif"))
    # The ground-truth gif first, then the rest: the download carries it twice
    # under two names — `F8eIii.gif` and `F8eIii (1).gif` — and the duplicate
    # sorts FIRST, so taking them in name order would drop the one every check
    # below is keyed to.
    names = [TRUTH] + [n for n in names if n != TRUTH]
    gifs = {}
    for name in names:
        frames = gif_frames(name)
        if any(len(v) == len(frames) and np.array_equal(v[0], frames[0])
               for v in gifs.values()):
            continue      # a duplicate of one already taken
        gifs[name] = frames

    bg, mask, layers = stamp(gifs, cells)
    blend = solve(gifs, cells, mask)
    decode = decoder(bg, mask, blend)
    checked = verify(decode, gifs, cells)
    print("stamp       %d px, layers %s" % (int((mask > 0).sum()), layers))
    for layer in (1, 2):
        alpha, colour = blend[layer]
        print("            layer %d  alpha %.4f  colour (%.0f, %.0f, %.0f)"
              % (layer, alpha, colour[0], colour[1], colour[2]))
    print("decoder     verified on %d art pixels of known answer: all exact"
          % checked)
    print()

    # Every clip, decoded once per gif rather than once per clip.
    clean = {name: decode(frames) for name, frames in gifs.items()}
    sheet_rgba = [c for c in cells]

    loaded = {}
    for key, (src, picks, loop, holds) in CLIPS.items():
        pool = sheet_rgba if src == "sheet" else clean[src]
        assert len(picks) == len(holds), (
            "%s has %d frames but %d durations" % (key, len(picks), len(holds)))
        loaded[key] = [pool[i] for i in picks]

    # Where he stands, measured off one frame and reused for all of them.
    #
    # Every clip in the pack registers the same way — the ground line is y 127
    # in the sheet, in the walk, in the idle and in the claw — so one origin is
    # right for the lot. It has to be measured off the right frame, though: on
    # the deep downstroke his wings sweep 30 px BELOW his feet, so "the lowest
    # pixel" is a wingtip on two frames out of six. The sheet frame whose art
    # reaches HIGHEST is the one with the wings furthest out of the way, and on
    # that one the bottom of the silhouette is his soles and nothing else.
    tops = [int(np.nonzero((c[:, :, 3] > 8).any(axis=1))[0].min()) for c in cells]
    up = int(np.argmin(tops))
    solid = cells[up][:, :, 3] > 8
    rows = np.nonzero(solid.any(axis=1))[0]
    sole = int(rows.max()) + 1
    feet = np.nonzero(solid[sole - 4:sole].any(axis=0))[0]
    ax = (int(feet.min()) + int(feet.max())) / 2.0

    left = top = 1e9
    right = bottom = -1e9
    for frames in loaded.values():
        for f in frames:
            ys, xs = np.nonzero(f[:, :, 3] > 8)
            left = min(left, float(xs.min()) - ax)
            right = max(right, float(xs.max() + 1) - ax)
            top = min(top, float(ys.min()) - sole)
            bottom = max(bottom, float(ys.max() + 1) - sole)

    cell_w = int(round(right - left)) + MARGIN * 2
    cell_h = int(round(bottom - top)) + MARGIN * 2
    origin_x, origin_y = float(-left + MARGIN), float(-top + MARGIN)
    dx, dy = int(round(origin_x - ax)), int(round(origin_y - sole))

    os.makedirs(OUT, exist_ok=True)
    manifest_anims = {}
    for key, (src, picks, loop, holds) in CLIPS.items():
        frames = loaded[key]
        strip = Image.new("RGBA", (cell_w * len(frames), cell_h), (0, 0, 0, 0))
        for i, f in enumerate(frames):
            strip.alpha_composite(Image.fromarray(f, "RGBA"), (i * cell_w + dx, dy))
        strip.save(os.path.join(OUT, key + ".png"))
        manifest_anims[key] = {"file": key + ".png", "frames": len(frames),
                               "loop": loop, "durations": holds}
        print("%-9s %2d frames  %-16s -> %s.png" % (key, len(frames), src, key))

    # --- the four attacks, and what each reaches with ------------------------
    idle = loaded["idle"][0]
    ys, xs = np.nonzero(idle[:, :, 3] > 8)
    body_half = (xs.max() - xs.min()) / 2.0

    def world(box):
        ## A pixel box in the cell, as a world-unit rect about his origin,
        ## written facing FORWARD and positive the way enemy.gd mirrors it. He
        ## faces left, so forward is -x here and the two ends swap.
        l, t, r, b = (int(v) for v in box)
        return [round(float(ax - (r + 1)) * RENDER_SCALE, 1),
                round(float(t - sole) * RENDER_SCALE, 1),
                round(float(r + 1 - l) * RENDER_SCALE, 1),
                round(float(b + 1 - t) * RENDER_SCALE, 1)]

    moves = {}
    for key, damage in (("claw", 30), ("fire", 38), ("fire_air", 34)):
        i, box = widest_effect(loaded[key], ax, body_half)
        assert box, "no effect found anywhere in %s" % key
        moves[key] = {"anim": key, "hit_frame": int(i), "hit_rect": world(box),
                      "damage": damage}

    # The swoop's "effect" is the dragon himself: he hits you with his whole
    # leading half, so the box is everything on the strike frame forward of his
    # own origin. On the downstroke that includes the wing sweeping past below
    # his feet, which is what lets the pass connect with somebody standing on
    # the ground while the dragon is still above it.
    strike = loaded["swoop"][SWOOP_HIT]
    fys, fxs = np.nonzero((strike[:, :, 3] > 8) & (np.arange(CELL)[None, :] <= ax))
    moves["swoop"] = {"anim": "swoop", "hit_frame": SWOOP_HIT,
                      "hit_rect": world((fxs.min(), fys.min(), fxs.max(), fys.max())),
                      "damage": 34}

    # Which phase each belongs to, and the gap it is chosen at. The bands do
    # not overlap within a phase, or the pick would come down to dictionary
    # order instead of distance.
    claw_reach = moves["claw"]["hit_rect"][0] + moves["claw"]["hit_rect"][2]
    swoop_reach = moves["swoop"]["hit_rect"][0] + moves["swoop"]["hit_rect"][2]
    moves["claw"]["phase"] = "ground"
    moves["claw"]["basic"] = True
    moves["swoop"]["phase"] = "air"
    moves["swoop"]["basic"] = True
    moves["fire"]["phase"] = "ground"
    moves["fire"]["range"] = [round(claw_reach + 40.0, 1),
                              round(moves["fire"]["hit_rect"][0]
                                    + moves["fire"]["hit_rect"][2], 1)]
    moves["fire_air"]["phase"] = "air"
    moves["fire_air"]["range"] = [round(swoop_reach + 40.0, 1),
                                  round(moves["fire_air"]["hit_rect"][0]
                                        + moves["fire_air"]["hit_rect"][2], 1)]

    manifest = {
        "_generated_by": "scripts/extract_dragon.py",
        "_source": "Assests/demo_lugia (sheet + 10 preview gifs, stamp removed)",
        "animations": manifest_anims,
        "cell": [cell_w, cell_h],
        "origin": [round(origin_x, 1), round(origin_y, 1)],
        # He is drawn facing left, alone in the cast.
        "faces": -1,
        # The plain swing for anything that does not know about phases. The
        # flyer picks between claw and swoop itself — see basic_move() in
        # features/combat/enemy.gd.
        "hit_frame": SWOOP_HIT,
        "hit_rect": moves["swoop"]["hit_rect"],
        "hit_damage": 34,
        "moves": moves,
        "render_scale": RENDER_SCALE,
    }
    with open(os.path.join(OUT, "dragon.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=1, sort_keys=True)
        fh.write('\n')

    print()
    print("stance      off sheet frame %d, the one with the wings highest" % up)
    print("cell        %dx%d, origin (%.1f, %.1f)" % (cell_w, cell_h, origin_x, origin_y))
    print("drawn       %.0f long, %.0f to the raised wingtip"
          % ((right - left) * RENDER_SCALE, -top * RENDER_SCALE))
    for name in ("claw", "swoop", "fire", "fire_air"):
        m = moves[name]
        print("%-9s frame %-2d reach %-5.0f %-7s %s"
              % (name, m["hit_frame"], m["hit_rect"][0] + m["hit_rect"][2],
                 m["phase"], "band %s" % m["range"] if "range" in m else "basic"))
    print("manifest -> %s" % os.path.join(OUT, "dragon.json"))


if __name__ == "__main__":
    main()
