"""Cuts the Dragon Lord boss out of END_USER_DRAGON_LORD_BASIC into the strips
and manifest features/combat/enemy.gd reads for kind "dragon_lord".

The pack is five single-row strips, each with its OWN cell size written into its
filename: idle and walk are 74x74, the attack 90x70, hurt 130x130, death
160x160. enemy.gd slices every animation of a kind with one `cell`, so they have
to be recomposed into a common one.

The dragon himself is 38x50 in all five — the big cells are the effects drawn
around him (wings on hurt, the flame column on death), not a bigger dragon. So
the frames are aligned on HIM, not on their cells: his body centre and his feet,
measured off frame 0 of each strip, which is the plain pose everywhere. Aligning
on cell centres instead would work for idle and walk and throw hurt sideways by
16 px, because his body sits off-centre in that one.

Run from walker-jumpman/:
    python scripts/extract_dragon_lord.py
    <godot> --path godot --headless --import
"""
import json
import os

from PIL import Image, ImageDraw, ImageSequence

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(
    HERE, "..", "..", "Assests", "END_USER_DRAGON_LORD_BASIC",
    "END_USER_DRAGON_LORD_BASIC", "Spritesheets"))
OUT = os.path.normpath(os.path.join(
    HERE, "..", "godot", "features", "combat", "art", "dragon_lord"))

# Texture pixel to world unit. The cast is 0.75 against sheets of about 79 px,
# which draws a bandit 59 tall; the dragon's body is 50, so 2.0 puts him at 100
# — half again the player's 72, which is what makes him read as the boss rather
# than as a large bandit. His effects scale with him: the death burst is 154 px
# of art and lands about 310 on screen, which is the point of it.
RENDER_SCALE = 2.0

# file, cell, loops, per-frame seconds. The key is what enemy.gd plays, so the
# pack's "attack" is "punch" here — that is the name the punch state shows.
SHEETS = {
    "idle":  ("dragon_lord_idle_basic_74x74.png",   (74, 74),   True,  [0.17] * 4),
    "walk":  ("dragon_lord_walk_basic_74x74.png",   (74, 74),   True,  [0.10] * 8),
    # Frames 0-3 are the wind-up with no flame, 4-9 the breath, the rest the
    # recovery. Held longest on 5, which is where the hit lands.
    "punch": ("dragon_lord_attack_arms_90x70.png",  (90, 70),   False,
              [0.09, 0.07, 0.07, 0.07, 0.06, 0.16, 0.07, 0.06, 0.06, 0.06,
               0.06, 0.06, 0.07, 0.07, 0.08, 0.12]),
    "hurt":  ("dragon_lord_hurt_basic_130x130.png", (130, 130), False,
              [0.07, 0.08, 0.10, 0.13, 0.22]),
    # 36 frames, about 2.2 s. enemy.gd lingers for however long this runs.
    "death": ("dragon_lord_death_160x160.png",      (160, 160), False,
              [0.05] * 10 + [0.06] * 14 + [0.08] * 12),
}

# The flame is at full reach from here on; 0-4 are the wind-up, which is the
# telegraph the player reads to step out of it.
HIT_FRAME = 5
# A margin so no frame touches the cell edge and picks up a seam when sampled.
MARGIN = 2

# The two specials ship as PREVIEW gifs, not as spritesheets: each frame is the
# dragon on a stone panel with a ragged border and the word "attack" captioned
# underneath. Three things have to come off before they are sprites.
#
# 1. The chrome. Five exact colours — the transparent padding, three border
#    shades and the panel fill. Keyed by RGB and not by palette index, because
#    these gifs carry a LOCAL PALETTE PER FRAME: index 4 is the panel on frame 0
#    and something else entirely by frame 18, so an index key paints the border
#    in flame colours halfway through.
# 2. The caption. It is drawn in art colours, so the key cannot touch it, but it
#    sits at a fixed rectangle in every frame and nothing else is ever below the
#    panel — verified frame by frame — so it is simply blanked.
# 3. The scale. The dragon is 114x150 in both previews against 38x50 in the
#    sheets: exactly 3x. A BOX filter at exactly 1/3 is the inverse of a 3x
#    nearest upscale, so it recovers the original pixels rather than blurring
#    them.
GIF_CHROME = {(0, 0, 0), (73, 71, 59), (117, 114, 101), (182, 174, 167),
              (199, 197, 188)}
GIF_DOWNSCALE = 3
GIFS = {
    # key: (file, caption box, loops, per-frame seconds)
    "breath": ("special-attack.gif", (294, 399, 428, 431), False, 0.085),
    "slam": ("special-attack-2.gif", (294, 549, 428, 581), False, 0.075),
}
# A slam is a ground attack: its hit box is pegged to the floor rather than to
# the art, which at its widest is mostly wings held overhead. Without this a
# player standing on nothing above him would be hit by a wingtip.
SLAM_MAX_HEIGHT = 34


def frames_of(path, cell):
    sheet = Image.open(path).convert("RGBA")
    cw, ch = cell
    assert sheet.width % cw == 0, "%s is not a whole number of %d cells" % (path, cw)
    return [sheet.crop((i * cw, 0, (i + 1) * cw, ch))
            for i in range(sheet.width // cw)]


def anchor_of(frames, name):
    """Where the dragon stands in this strip's own cell: the centre and the
    sole of frame 0, which is the plain pose in every one of the five."""
    box = frames[0].getbbox()
    assert box, "%s frame 0 is empty" % name
    return (box[0] + box[2]) / 2.0, float(box[3])


def gif_frames(fname, caption):
    """One preview gif, turned into sprites: chrome keyed out by colour, the
    caption blanked, and reduced to the sheets' scale."""
    im = Image.open(os.path.join(SRC, fname))
    out = []
    for raw in ImageSequence.Iterator(im):
        # convert applies THIS frame's own palette, which is the whole reason
        # the key is by colour and not by index.
        f = raw.convert("RGBA")
        f.putdata([(0, 0, 0, 0) if (p[3] == 0 or p[:3] in GIF_CHROME) else p
                   for p in f.get_flattened_data()])
        ImageDraw.Draw(f).rectangle(caption, fill=(0, 0, 0, 0))
        out.append(f.resize((f.width // GIF_DOWNSCALE, f.height // GIF_DOWNSCALE),
                            Image.BOX))
    return out


def effect_box(frame, ax, body_half, floor=None):
    """The bounding box of everything in this frame that is clear of his own
    body — the flame, the dust — which is what a special actually hits with."""
    px = frame.load()
    l = t = None
    r = b = None
    for y in range(frame.height):
        if floor is not None and y < floor:
            continue
        for x in range(frame.width):
            if px[x, y][3] < 24:
                continue
            if x - ax <= body_half:
                continue
            l = x if l is None else min(l, x)
            r = x if r is None else max(r, x)
            t = y if t is None else min(t, y)
            b = y if b is None else max(b, y)
    return None if l is None else (l, t, r, b)


def widest_effect(frames, ax, body_half, floor=None):
    """Which frame throws the effect furthest, and how far. That is the frame
    the blow lands on — measured, so retiming the animation cannot desync it."""
    best_i, best_box, best_reach = 0, None, -1.0
    for i, f in enumerate(frames):
        box = effect_box(f, ax, body_half, floor)
        if box and box[2] - ax > best_reach:
            best_i, best_box, best_reach = i, box, box[2] - ax
    return best_i, best_box


def main():
    loaded = {}
    meta = {}          # key -> (loops, per-frame durations)
    for key, (fname, cell, loop, durations) in SHEETS.items():
        frames = frames_of(os.path.join(SRC, fname), cell)
        assert len(frames) == len(durations), (
            "%s has %d frames but %d durations"
            % (key, len(frames), len(durations)))
        loaded[key] = (frames, anchor_of(frames, key))
        meta[key] = (loop, durations)
    for key, (fname, caption, loop, per) in GIFS.items():
        frames = gif_frames(fname, caption)
        loaded[key] = (frames, anchor_of(frames, key))
        meta[key] = (loop, [per] * len(frames))

    # How far the art reaches from the dragon, over every frame of every strip.
    left = top = 1e9
    right = bottom = -1e9
    for key, (frames, (ax, ay)) in loaded.items():
        for f in frames:
            b = f.getbbox()
            if not b:
                continue
            left = min(left, b[0] - ax)
            right = max(right, b[2] - ax)
            top = min(top, b[1] - ay)
            bottom = max(bottom, b[3] - ay)

    cell_w = int(round(right - left)) + MARGIN * 2
    cell_h = int(round(bottom - top)) + MARGIN * 2
    # Where he ends up inside that cell: enemy.gd puts this point on the floor.
    origin_x = -left + MARGIN
    origin_y = -top + MARGIN

    os.makedirs(OUT, exist_ok=True)
    manifest_anims = {}
    for key, (frames, (ax, ay)) in loaded.items():
        strip = Image.new("RGBA", (cell_w * len(frames), cell_h), (0, 0, 0, 0))
        for i, f in enumerate(frames):
            dx = int(round(origin_x - ax))
            dy = int(round(origin_y - ay))
            strip.alpha_composite(f, (i * cell_w + dx, dy))
        strip.save(os.path.join(OUT, key + ".png"))
        manifest_anims[key] = {
            "file": key + ".png",
            "frames": len(frames),
            "loop": meta[key][0],
            "durations": meta[key][1],
        }
        print("%-6s %2d frames -> %s" % (key, len(frames), key + ".png"))

    # Every attack's hit box is measured off its own art rather than written
    # here: the pixels that are clear of his body on the frame that throws them
    # furthest, turned into world units about his origin. Retiming an animation
    # therefore cannot desync the blow from the picture of it.
    idle_box = loaded["idle"][0][0].getbbox()
    body_half = (idle_box[2] - idle_box[0]) / 2.0

    def measure(key, frame_index=None, floor=None):
        frames, (ax, ay) = loaded[key]
        if frame_index is None:
            frame_index, box = widest_effect(frames, ax, body_half, floor)
        else:
            box = effect_box(frames[frame_index], ax, body_half, floor)
        assert box, "no effect found on %s frame %s" % (key, frame_index)
        l, t, r, b = box
        return frame_index, [round((l - ax) * RENDER_SCALE, 1),
                             round((t - ay) * RENDER_SCALE, 1),
                             round((r - l) * RENDER_SCALE, 1),
                             round((b - t) * RENDER_SCALE, 1)]

    _unused, punch_rect = measure("punch", HIT_FRAME)
    punch_reach = punch_rect[0] + punch_rect[2]
    breath_frame, breath_rect = measure("breath")
    # Pegged to the floor: at its widest the slam is mostly wings held overhead,
    # and a box drawn round those would hit a player standing above him.
    slam_anchor = loaded["slam"][1][1]
    slam_frame, slam_rect = measure("slam", floor=int(slam_anchor) - SLAM_MAX_HEIGHT)

    # A move is an animation plus where and when it lands. `range` is the gap it
    # is chosen at, so the two specials do not compete: the breath covers the
    # ground he cannot walk, the slam answers someone already on top of him.
    moves = {
        # No damage of its own: the plain swing is what the PROFILE says it is,
        # so tuning him in enemy.gd does not mean re-running the extractor. Only
        # the specials carry their own number, because they are their own move.
        "punch": {"anim": "punch", "hit_frame": HIT_FRAME,
                  "hit_rect": punch_rect},
        # `range` is the gap he CHOOSES the move at, which is not the same as
        # how far it hits. The slam's shockwave carries 228 but he only throws
        # it at someone already on top of him, so backing off does not make you
        # safe from one already started. The two bands do not overlap, or the
        # pick would come down to dictionary order instead of distance.
        "slam": {"anim": "slam", "hit_frame": slam_frame,
                 "hit_rect": slam_rect, "damage": 44,
                 "range": [0.0, round(punch_reach + 40.0, 1)]},
        "breath": {"anim": "breath", "hit_frame": breath_frame,
                   "hit_rect": breath_rect, "damage": 30,
                   "range": [round(punch_reach + 60.0, 1),
                             round(breath_rect[0] + breath_rect[2], 1)]},
    }

    manifest = {
        "_generated_by": "scripts/extract_dragon_lord.py",
        "_source": "END_USER_DRAGON_LORD_BASIC (Dragon Lord boss pack)",
        "animations": manifest_anims,
        "cell": [cell_w, cell_h],
        "origin": [round(origin_x, 1), round(origin_y, 1)],
        # The flame comes out of his right, so the art faces right.
        "faces": 1,
        # The plain swing, also read by any kind that does not know about moves.
        "hit_frame": HIT_FRAME,
        "hit_rect": punch_rect,
        "hit_damage": 38,
        "moves": moves,
        "render_scale": RENDER_SCALE,
    }
    with open(os.path.join(OUT, "dragon_lord.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=1, sort_keys=True)
        fh.write('\n')

    print()
    print("cell        %dx%d" % (cell_w, cell_h))
    print("origin      (%.1f, %.1f)  -> drawn %.0f x %.0f world units"
          % (origin_x, origin_y, 38 * RENDER_SCALE, 50 * RENDER_SCALE))
    for name in ("punch", "breath", "slam"):
        m = moves[name]
        print("%-7s frame %-2d rect %-30s reach %-5.0f %s"
              % (name, m["hit_frame"], m["hit_rect"],
                 m["hit_rect"][0] + m["hit_rect"][2],
                 "range %s" % m["range"] if "range" in m else ""))
    print("manifest -> %s" % os.path.join(OUT, "dragon_lord.json"))


if __name__ == "__main__":
    main()
