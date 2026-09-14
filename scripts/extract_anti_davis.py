#!/usr/bin/env python3
"""Turn the Anti-Davis Little Fighter 2 character pack into Godot sprite strips.

The pack ships as LF2 mod data: three 800x560 BMP sheets of 79x79 cells on a
10-wide, 7-tall grid with a 1 px gutter, plus an encrypted .dat that says which
cell each animation frame uses, where that frame's origin sits inside it, how
long it is held, and — for attacks — where it hits.

Four things have to happen before Godot can use any of it:

  * Transparency. The BMPs are 24-bit with a pure black key colour, so black is
    punched out to alpha. The character's own outline is (21, 21, 21), not
    black, so it survives.
  * Origin. LF2 gives every frame its own (centerx, centery); Godot's
    AtlasTexture regions are uniform. Each frame is therefore shifted until its
    origin lands at ORIGIN inside a fixed OUT cell. Skip this and the sprite
    jitters a few pixels every time the animation changes frame.
  * Timing. LF2 holds each frame for `wait + 1` ticks of a ~30 Hz clock. A
    single frames-per-second number cannot express that, and the attacks depend
    on it: the shoulder charge holds its commit frame four times as long as its
    wind-up. Per-frame durations are written out instead.
  * Hitboxes. LF2's `itr` blocks are the authored hit geometry. Transcribing
    them means a punch connects where the drawing shows it connecting, rather
    than where a hand-guessed rectangle happens to sit.
  * Weapon points. LF2 never draws a held object into a character frame; it
    draws the character, then stamps the object at that frame's `wpoint`. The
    drink animation is empty-handed for exactly that reason, so the wpoints are
    carried across too and the game puts the bottle where the pack says the
    hand is.

Everything except the PNGs themselves lands in moves.json, which the game reads
at load. That file and the strips are generated together and must stay
together; nothing about them should be edited by hand.

Usage (needs Pillow):

    python scripts/extract_anti_davis.py

Then let Godot reimport, e.g. `godot --path godot --headless --import`.
"""
import json
import os
import re
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PACK = os.path.normpath(os.path.join(
    HERE, "..", "..", "Assests", "Anti-Davis", "Anti-Davis"))
SYS_DIR = os.path.join(PACK, "sprite", "sys")
DAT = os.path.join(PACK, "data", "anti_davis.dat")
BALL_DAT = os.path.join(PACK, "data", "anti_davis_ball.dat")
OUT_DIR = os.path.normpath(os.path.join(
    HERE, "..", "godot", "features", "player", "art", "anti_davis"))

# --- LF2 pack layout --------------------------------------------------------

# Davis is drawn 73 px tall in the pack, and the CC0 street enemies are 50 px.
# Side by side at native size he towers over them, so everything he and the
# props are made of is resampled by this factor on the way out: 73 -> 55, a head
# taller than an enemy, which is the relationship a protagonist wants.
#
# Only the cast scales. The level geometry and the movement tuning are left
# alone deliberately, so the jump arc and every gap stay exactly as tuned and
# the level simply reads as roomier around a smaller cast — which is the space
# walking enemies need anyway.
#
# LANCZOS because LF2's art is painted and already anti-aliased (145 colours in
# one idle frame), so it resamples like a small photograph. Crisp indie pixel
# art would not survive this and must never be put through it.
SCALE = 0.75

CELL_W = CELL_H = 79
GUTTER = 1
COLS = 10
SHEETS = [("anti_davis_0.bmp", 0, 69),
          ("anti_davis_1.bmp", 70, 139),
          ("anti_davis_2.bmp", 140, 209)]
BALL_SHEET = ("anti_davis_ball.bmp", 81, 46, 4)  # file, cell w, cell h, columns
KEY_COLOUR = (0, 0, 0)
# LF2 .dat files are the plaintext with this key added byte-wise, after a 123
# byte junk header. The key is 37 characters; longer variants quoted online
# decrypt the first line and then produce garbage.
DAT_KEY = b"odBearBecauseHeIsVeryGoodSiuHungIsAGo"
DAT_HEADER = 123
# LF2 runs its frame clock at roughly 30 Hz and holds a frame for wait + 1 ticks.
LF2_TICK = 1.0 / 30.0

# --- What the platformer needs ---------------------------------------------

# LF2 frame ids, not pic ids: the frame is what carries the origin, the hold and
# the hit geometry. Locomotion is looped at a chosen rate because LF2's walk and
# run cadence is tuned to its own movement speed, not this game's; the attacks
# keep LF2's authored per-frame timing, because that is their whole character.
LOCOMOTION = {
    "idle":  {"ids": [0, 1, 2, 3],      "fps": 6.0,  "loop": True},
    "walk":  {"ids": [5, 6, 7, 8],      "fps": 8.0,  "loop": True},
    "run":   {"ids": [9, 10, 11],       "fps": 12.0, "loop": True},
    "skid":  {"ids": [218],             "fps": 10.0, "loop": False},
    "rise":  {"ids": [213],             "fps": 10.0, "loop": False},
    "fall":  {"ids": [214],             "fps": 10.0, "loop": False},
    # LF2 frames 220-221: struck, doubled over. The pack also has a longer
    # dizzy loop (226-229) and two stagger-backward pairs (222-225); this is the
    # one that reads as a single blow landing rather than as a daze.
    "hurt":  {"ids": [220, 221],        "fps": 9.0,  "loop": False},
    "death": {"ids": [180, 181, 182, 183, 184], "fps": 9.0, "loop": False},
}

# RATE sharpens every attack uniformly. LF2's timings are built for a fighting
# game where both players are standing still; in a platformer where the player
# is usually mid-stride they feel sluggish. 1.0 is the pack's own speed.
RATE = 1.25

# Moves that are not attacks: same frame machinery, no hit boxes. Kept in their
# own table because what they mean is different, not how they are built.
ACTIONS = {
    "drink": [55, 56, 57, 58],  # weapon_drink; the bottle rides on the wpoint
}

ATTACKS = {
    "punch_a": [60, 61, 62, 63],               # jab
    "punch_b": [65, 66, 67, 68],               # cross, chains off the jab
    "kick":    [80, 81, 82, 83, 84],           # flying kick, airborne only
    "charge":  [85, 86, 87, 88, 89, 97, 98],   # shoulder barge at full speed
    "blast":   [240, 241, 242, 243, 244, 245, 246],  # throws the projectile
}

# Union of every frame's content around its origin is 90x94 once the attacks are
# included — they reach much further forward than any locomotion pose — so a
# 96x96 cell with the origin at (44, 82) holds all of them. Deriving these
# automatically would change the cell silently whenever a move is added, and
# player_sprite.gd's PIVOT has to be recomputed by hand when it does.
OUT = (96, 96)
ORIGIN = (44, 82)

BALL_OUT = (84, 48)
BALL_ORIGIN = (52, 24)
BALL_ANIM = {
    "fly": {"ids": [8, 9], "loop": True},      # the streaking, settled form
    "hit": {"ids": [10, 11, 12, 13], "loop": False},  # impact burst
}

# LF2 draws the final lying frame sunk below its origin, because there the body
# is still travelling. Here the player dies in place, so the corpse is lifted to
# rest on the ground line instead of sinking into the floor.
ADJUST = {184: (0, -13)}

_sheets = {}


def decrypt_dat(path):
    raw = open(path, "rb").read()[DAT_HEADER:]
    return bytes((raw[i] - DAT_KEY[i % len(DAT_KEY)]) & 0xFF
                 for i in range(len(raw))).decode("latin-1")


def _int(block, key, default=None):
    found = re.search(key + r":\s*(-?\d+)", block)
    if found:
        return int(found.group(1))
    if default is None:
        raise KeyError("%s missing from frame block" % key)
    return default


def frames_table(path=None):
    """frame id -> pic, origin, hold in seconds, and any hit boxes it opens."""
    text = decrypt_dat(path or DAT)
    table = {}
    for fid, name, block in re.findall(
            r"<frame>\s+(\d+)\s+(\S+)(.*?)<frame_end>", text, re.S):
        cx, cy = _int(block, "centerx"), _int(block, "centery")
        hits = []
        for itr in re.findall(r"itr:(.*?)itr_end:", block, re.S):
            damage = _int(itr, "injury", 0)
            # injury 0 marks LF2's grab and wind-up volumes, which do no damage.
            if damage <= 0:
                continue
            hits.append({"rect": [_int(itr, "x") - cx, _int(itr, "y") - cy,
                                  _int(itr, "w"), _int(itr, "h")],
                         "damage": damage})
        # LF2 allows one wpoint per frame: where a held object is stamped,
        # in the same space as the hit boxes.
        wpoint = []
        found = re.search(r"wpoint:(.*?)wpoint_end:", block, re.S)
        if found:
            wpoint = [_int(found.group(1), "x") - cx, _int(found.group(1), "y") - cy]
        table[int(fid)] = {
            "name": name, "pic": _int(block, "pic"), "cx": cx, "cy": cy,
            "hold": (_int(block, "wait") + 1) * LF2_TICK, "hits": hits,
            "wpoint": wpoint,
        }
    return table


def sheet_for(pic):
    """Return (keyed-out sheet, index of `pic` within it)."""
    for name, lo, hi in SHEETS:
        if lo <= pic <= hi:
            return _load(name), pic - lo
    raise KeyError("no sheet holds pic %d" % pic)


def _load(name):
    if name not in _sheets:
        image = Image.open(os.path.join(SYS_DIR, name)).convert("RGBA")
        px = image.load()
        for y in range(image.height):
            for x in range(image.width):
                if px[x, y][:3] == KEY_COLOUR:
                    px[x, y] = (0, 0, 0, 0)
        _sheets[name] = image
    return _sheets[name]


def cell(pic):
    image, idx = sheet_for(pic)
    x = (idx % COLS) * (CELL_W + GUTTER)
    y = (idx // COLS) * (CELL_H + GUTTER)
    return image.crop((x, y, x + CELL_W, y + CELL_H))


def ball_cell(pic):
    name, w, h, cols = BALL_SHEET
    image = _load(name)
    x = (pic % cols) * (w + GUTTER)
    y = (pic // cols) * (h + GUTTER)
    return image.crop((x, y, x + w, y + h))


def sc(value):
    """Scale one number, a point, or a rect from the pack's pixels to the
    game's. Everything the manifest publishes goes through here, so the hit
    boxes and weapon points cannot drift out of step with the art."""
    if isinstance(value, dict):
        return {k: sc(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [sc(v) for v in value]
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return value
    return round(value * SCALE, 3)


def sc_hits(hits):
    """A hit box scales with the art. The damage written on it does NOT — that
    is a game number, and quietly multiplying it by 0.75 turned the two-jab
    combo into a three-jab one without anything saying so."""
    return [{"damage": h["damage"], "rect": sc(h["rect"])} for h in hits]


def scaled_cell(out_size):
    return (round(out_size[0] * SCALE), round(out_size[1] * SCALE))


def write_strip(path, tiles, out_size):
    strip = Image.new("RGBA", (out_size[0] * len(tiles), out_size[1]), (0, 0, 0, 0))
    for i, (src, dx, dy) in enumerate(tiles):
        strip.paste(src, (i * out_size[0] + dx, dy), src)
    # Resized as one strip rather than per cell: resampling each frame alone
    # rounds its edges independently and the character jitters between frames.
    cw, ch = scaled_cell(out_size)
    strip = strip.resize((cw * len(tiles), ch), Image.LANCZOS)
    strip.save(path)


def check_fits(label, tiles, out_size):
    """A frame silently cropped by the cell is the kind of bug you find in a
    screenshot three days later. Fail loudly instead."""
    for i, (src, dx, dy) in enumerate(tiles):
        box = src.getbbox()
        if box is None:
            continue
        if (box[0] + dx < 0 or box[1] + dy < 0
                or box[2] + dx > out_size[0] or box[3] + dy > out_size[1]):
            sys.exit("%s frame %d does not fit the %dx%d cell: content at %s"
                     % (label, i, out_size[0], out_size[1],
                        (box[0] + dx, box[1] + dy, box[2] + dx, box[3] + dy)))


def main():
    if not os.path.isdir(SYS_DIR):
        sys.exit("Anti-Davis pack not found at %s" % PACK)
    os.makedirs(OUT_DIR, exist_ok=True)
    table = frames_table()
    manifest = {
        "_generated_by": "scripts/extract_anti_davis.py",
        "cell": list(scaled_cell(OUT)), "origin": sc(list(ORIGIN)),
        "ball_cell": list(scaled_cell(BALL_OUT)), "ball_origin": sc(list(BALL_ORIGIN)),
        "animations": {}, "ball": {},
    }

    def tiles_for(ids):
        out = []
        for fid in ids:
            frame = table[fid]
            adj = ADJUST.get(fid, (0, 0))
            out.append((cell(frame["pic"]),
                        ORIGIN[0] - frame["cx"] + adj[0],
                        ORIGIN[1] - frame["cy"] + adj[1]))
        return out

    for key, spec in LOCOMOTION.items():
        tiles = tiles_for(spec["ids"])
        check_fits(key, tiles, OUT)
        write_strip(os.path.join(OUT_DIR, key + ".png"), tiles, OUT)
        hold = 1.0 / spec["fps"]
        manifest["animations"][key] = {
            "file": key + ".png", "loop": spec["loop"],
            "durations": [round(hold, 5)] * len(spec["ids"]),
            "hits": [[] for _ in spec["ids"]],
            "wpoints": [[] for _ in spec["ids"]],
        }
        print("%-8s %d frame(s)" % (key, len(spec["ids"])))

    # Actions keep LF2's own pacing: RATE exists to sharpen combat, and a drink
    # is not combat.
    for key, ids in ACTIONS.items():
        tiles = tiles_for(ids)
        check_fits(key, tiles, OUT)
        write_strip(os.path.join(OUT_DIR, key + ".png"), tiles, OUT)
        manifest["animations"][key] = {
            "file": key + ".png", "loop": False,
            "durations": [round(table[f]["hold"], 5) for f in ids],
            "hits": [[] for _ in ids],
            "wpoints": [sc(table[f]["wpoint"]) for f in ids],
        }
        print("%-8s %d frame(s), %d with a weapon point"
              % (key, len(ids), sum(1 for f in ids if table[f]["wpoint"])))

    for key, ids in ATTACKS.items():
        tiles = tiles_for(ids)
        check_fits(key, tiles, OUT)
        write_strip(os.path.join(OUT_DIR, key + ".png"), tiles, OUT)
        manifest["animations"][key] = {
            "file": key + ".png", "loop": False,
            "durations": [round(table[f]["hold"] / RATE, 5) for f in ids],
            "hits": [sc_hits(table[f]["hits"]) for f in ids],
            "wpoints": [sc(table[f]["wpoint"]) for f in ids],
        }
        hitting = sum(1 for f in ids if table[f]["hits"])
        print("%-8s %d frame(s), %d with a hitbox" % (key, len(ids), hitting))

    ball_table = frames_table(BALL_DAT)
    for key, spec in BALL_ANIM.items():
        tiles = []
        for fid in spec["ids"]:
            frame = ball_table[fid]
            tiles.append((ball_cell(frame["pic"]),
                          BALL_ORIGIN[0] - frame["cx"],
                          BALL_ORIGIN[1] - frame["cy"]))
        check_fits("ball " + key, tiles, BALL_OUT)
        write_strip(os.path.join(OUT_DIR, "ball_" + key + ".png"), tiles, BALL_OUT)
        manifest["ball"][key] = {
            "file": "ball_" + key + ".png", "loop": spec["loop"],
            "durations": [round(ball_table[f]["hold"], 5) for f in spec["ids"]],
        }
        print("ball_%-3s %d frame(s)" % (key, len(spec["ids"])))
    # Every flying frame carries the same box; frame 0's is the canonical one.
    # The rect scales with the art; the damage is a game number and must not.
    manifest["ball"]["hit_rect"] = sc(ball_table[0]["hits"][0]["rect"])
    manifest["ball"]["damage"] = ball_table[0]["hits"][0]["damage"]

    path = os.path.join(OUT_DIR, "moves.json")
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=1, sort_keys=True)
    print("manifest -> %s" % path)


if __name__ == "__main__":
    main()
