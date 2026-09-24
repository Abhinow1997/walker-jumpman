"""Validates every level file in godot/levels/ against the movement tuning.

The GDD asks for exactly this under "Content validation": valid start and
finish, no mandatory gap beyond the reviewed jump envelope, no spawn/hazard
overlap, no unreachable mandatory platform. Authoring a level by hand is fast;
finding out three levels later that one gap was two pixels too wide is not.

The jump envelope is READ OUT OF features/player/tuning.gd on every run, never
copied here. A movement change silently invalidates every gap in every level,
and this is the thing that says so. Same reasoning as the art extractors
re-measuring their sheets: a number kept in two places is a number that drifts.

    python scripts/check_levels.py                        every indexed level
    python scripts/check_levels.py path/to/candidate.json  one file, anywhere

The second form is the one to use before replacing a level. A layout exported
from tools/level-editor.html is not in the index yet, and the whole point is
to find out whether it is worth putting there.

Exits 1 on any error. Warnings do not fail the run; they are the gaps that are
theoretically clearable but tight enough to want a human on the controls.
"""

import json
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LEVELS = os.path.normpath(os.path.join(HERE, "..", "godot", "levels"))
STORYBOARD = os.path.normpath(os.path.join(
    HERE, "..", "godot", "ui", "art", "storyboard"))
AUDIO = os.path.normpath(os.path.join(HERE, "..", "godot", "audio"))

# What a story card may wait on, besides a line on the ground.
CUES = ("boss_down",)
# What a music key may name. Ogg is what a track wants to be; wav is tolerated
# because the boss track arrived as one and there was no encoder to hand.
TRACKS = (".ogg", ".wav")
TUNING = os.path.normpath(os.path.join(
    HERE, "..", "godot", "features", "player", "tuning.gd"))

# A gap this close to the theoretical maximum is clearable on paper and
# miserable in practice: it needs a perfect takeoff from the last pixel of the
# ledge. Warn rather than fail, because "tight on purpose" is a real design
# choice and this script does not get to overrule it.
TIGHT = 0.80

# Reaching full speed takes v^2/2a, which is about 20 px at the current tuning.
# A jump taken with less run-up than that is taken slower than the envelope
# below assumes, so the numbers stop applying.
RUN_UP = 20.0

# Decor that stands on something, as opposed to hanging in the sky. These are
# the pieces worth checking: move a platform and any plant that was sitting on
# it is left floating, which nothing else in the pipeline would ever notice
# because decor carries no collision. Hanging cliffs and drifting rocks are
# deliberately airborne and are not checked.
GROUND_DECOR = ("tree", "bush", "tuft", "pillar_bush", "grass_short", "archway")
DECOR_SLACK = 6.0


def tuning():
    """Speed, jump velocity and gravity, read from the resource that owns them."""
    if not os.path.isfile(TUNING):
        sys.exit("tuning.gd not found at %s" % TUNING)
    text = open(TUNING, encoding="utf-8").read()
    out = {}
    for key in ("speed", "jump_velocity", "gravity"):
        found = re.search(r"var\s+%s\s*:\s*float\s*=\s*(-?[\d.]+)" % key, text)
        if not found:
            sys.exit("could not read `%s` out of tuning.gd - the declaration "
                     "moved, and every gap in every level depends on it" % key)
        out[key] = abs(float(found.group(1)))
    return out


def envelope(tune, rise):
    """How far a full-speed jump travels horizontally while landing `rise` px
    above the takeoff. A negative rise is a drop, which travels further.

    Up is positive here: h(t) = u*t - g*t^2/2. The useful root is the LAST time
    the arc is at that height, on the way down.
    """
    u, g, v = tune["jump_velocity"], tune["gravity"], tune["speed"]
    apex = u * u / (2.0 * g)
    under = u * u - 2.0 * g * rise
    if under < 0.0:
        return 0.0, apex          # cannot get that high at all
    return v * (u + math.sqrt(under)) / g, apex


def spans(solids):
    """Each solid as (x0, x1, top_y)."""
    return [(float(s[0]), float(s[0]) + float(s[2]), float(s[1])) for s in solids]


def pits(solids, width):
    """The x ranges with no solid under them at all, where falling is fatal and
    a jump is therefore mandatory. A ledge stacked over the floor is not a pit."""
    merged = []
    for a, b in sorted((s[0], s[1]) for s in spans(solids)):
        if merged and a <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], b)
        else:
            merged.append([a, b])
    out, x = [], 0.0
    for a, b in merged:
        if a > x:
            out.append((x, a))
        x = max(x, b)
    if x < width:
        out.append((x, width))
    return out


def standing_on(solids, x, y, slack=0.5):
    """Is (x, y) the top surface of some solid? The spawn, the finish and every
    prop have to rest on one, or they hang in the air or start inside it."""
    for x0, x1, top in spans(solids):
        if abs(top - y) <= slack and x0 - slack <= x <= x1 + slack:
            return True
    return False


def edge_at(solids, x, side):
    """Top y of the solid whose right (or left) edge is at x. The floor wins
    over a ledge: you take off from whatever you are running along."""
    best = None
    for x0, x1, top in spans(solids):
        at = x1 if side == "right" else x0
        if abs(at - x) <= 0.5 and (best is None or top > best):
            best = top
    return best


def ledges(solids):
    """Solids merged into the surfaces you can actually stand and walk on.

    Two rectangles that share a top edge and touch are one ledge, not two. A
    climb builds its rest shelves that way - three 36 px rocks laid abreast make
    one 108 px surface - and without this the walk below sees the far halves of
    every shelf as ledges with no way onto them, because it only ever steps
    UPWARD and they are level with the piece beside them.
    """
    out = []
    for x0, x1, top in sorted(spans(solids), key=lambda s: (s[2], s[0])):
        if out and abs(out[-1][2] - top) <= 0.5 and x0 <= out[-1][1] + 0.5:
            out[-1] = (out[-1][0], max(out[-1][1], x1), top)
        else:
            out.append((x0, x1, top))
    return out


def hop(tune, a, b):
    """Can he get from platform `a` up to platform `b` in one jump? Each is an
    (x0, x1, top). Returns (ok, rise, gap, reach)."""
    rise = a[2] - b[2]                       # positive: b is the higher one
    gap = 0.0 if a[0] < b[1] and b[0] < a[1] else (
        b[0] - a[1] if b[0] >= a[1] else a[0] - b[1])
    reach, _apex = envelope(tune, rise)
    return (reach > 0.0 and gap <= reach), rise, gap, reach


# His collision box, from features/player/player.gd. The origin is at his feet.
BODY = (15.0, 42.0)


def blocked(tune, solids, a, b, rise):
    """Does anything hang in the way of the jump from ledge `a` to ledge `b`?

    Walks his body along the arc and looks for a solid whose UNDERSIDE it would
    strike. The reachability walk on its own only asks whether the far ledge is
    inside the envelope, which says nothing about what is between them - and in
    a column one screen wide, a good deal can be. The Climb's summit is a
    216 x 132 cliff and two of the last ledges ran underneath it: every hop was
    inside the envelope, every ledge reachable on paper, and in the engine he
    cracked his head on the bottom of the summit and dropped into the sea.

    Only the underside counts. Landing on something is what the jump is for, and
    brushing past the side of a ledge is what the gap measurement already
    covers.
    """
    u, g, v = tune["jump_velocity"], tune["gravity"], tune["speed"]
    right = b[0] >= a[1]
    from_x = a[1] if right else a[0]
    step = v / 60.0 * (1.0 if right else -1.0)
    lo, hi = min(a[0], b[0]) - 40.0, max(a[1], b[1]) + 40.0
    rects = []
    for entry in solids:
        x0, y0 = float(entry[0]), float(entry[1])
        x1, y1 = x0 + float(entry[2]), y0 + float(entry[3])
        if x1 <= lo or x0 >= hi:
            continue
        # The two ledges of the hop itself are not obstacles.
        if abs(y0 - a[2]) < 0.5 and x0 >= a[0] - 0.5 and x1 <= a[1] + 0.5:
            continue
        if abs(y0 - b[2]) < 0.5 and x0 >= b[0] - 0.5 and x1 <= b[1] + 0.5:
            continue
        rects.append((x0, x1, y0, y1))
    for i in range(int(2.0 * u / g * 60.0) + 2):
        t = i / 60.0
        h = u * t - g * t * t / 2.0
        feet = a[2] - h
        if h < 0.0 and feet > a[2] + 4.0:
            break                       # already below the ledge he left
        x = from_x + step * i
        head = feet - BODY[1]
        for x0, x1, y0, y1 in rects:
            if x + BODY[0] / 2.0 <= x0 or x - BODY[0] / 2.0 >= x1:
                continue
            if head < y1 and feet > y0 and feet > y1 - 2.0:
                return (x, feet, y0)    # his head is under its underside
        if h >= rise and i > 2 and b[0] - 4.0 <= x <= b[1] + 4.0:
            return None                 # down on the far ledge, nothing hit
    return None


def climb(level, tune, errors, warnings, notes):
    """A tower rather than a course, so the question is not whether any gap is
    too wide to run at - it is whether every ledge can be reached from one
    below it. Walks the chain outward from the spawn and reports anything it
    cannot get to.

    The horizontal analysis the rest of this file does is meaningless here: in
    a column one screen wide there is a solid over almost every x at SOME
    height, so pits() either finds nothing or finds the space between two
    stacked ledges and measures a running jump across it. That is how a climb
    used to fail validation with a pit that landed 988 px above its takeoff.
    """
    plats = sorted(ledges(level["solids"]), key=lambda s: (-s[2], s[0]))
    sx, sy = float(level["spawn"][0]), float(level["spawn"][1])
    start = [p for p in plats if abs(p[2] - sy) <= 0.5 and p[0] <= sx <= p[1]]
    if not start:
        return                              # already reported as a bad spawn
    seen, edge, worst = set(start), list(start), 0.0
    while edge:
        here = edge.pop()
        for there in plats:
            if there in seen or there[2] >= here[2]:
                continue                    # only ever upward; a drop is death
            ok, rise, gap, reach = hop(tune, here, there)
            if not ok:
                continue
            if gap <= 0.0:
                warnings.append("the ledge at y %g sits directly over the one "
                                "at y %g with no step aside: he would jump "
                                "into its underside" % (there[2], here[2]))
                continue
            hit = blocked(tune, level["solids"], here, there, rise)
            if hit is not None:
                errors.append("the hop from y %g to y %g passes under the "
                              "solid whose top is at y %g: his head meets it "
                              "around (%.0f, %.0f)"
                              % (here[2], there[2], hit[2], hit[0], hit[1]))
                continue
            worst = max(worst, 100.0 * gap / reach)
            if gap > reach * TIGHT:
                warnings.append("the hop from y %g to y %g is %g px across "
                                "with a %g px rise - %.0f%% of the %.1f a "
                                "full-speed jump reaches"
                                % (here[2], there[2], gap, rise,
                                   100.0 * gap / reach, reach))
            seen.add(there)
            edge.append(there)
    stranded = [p for p in plats if p not in seen]
    for p in stranded:
        errors.append("nothing can reach the ledge at (%g..%g, %g): no ledge "
                      "below it is inside one jump" % (p[0], p[1], p[2]))
    fx, fy, fw, fh = (float(v) for v in level["finish"])
    on = [p for p in plats if abs(p[2] - (fy + fh)) <= 0.5
          and p[0] <= fx + fw / 2.0 <= p[1]]
    if on and on[0] not in seen:
        errors.append("the finish stands on a ledge the climb cannot reach")
    notes.append("climb: %d ledges, %g px of rise, every one reachable, "
                 "worst hop %.0f%% of the envelope"
                 % (len(plats), plats[0][2] - plats[-1][2], worst))

    # A source that starts inside a ledge drops a stone that breaks on the
    # frame it is born, which is silent in play and looks like a lane that
    # simply does not work.
    for i, source in enumerate(level.get("rockfall", [])):
        rx, ry = float(source[0]), float(source[1])
        if not 0.0 <= rx <= float(level["width"]):
            errors.append("rockfall source %d is at x %g, outside the level"
                          % (i + 1, rx))
        for x0, x1, top in plats:
            if x0 <= rx <= x1 and top <= ry <= top + 40.0:
                errors.append("rockfall source %d at (%g, %g) is inside the "
                              "ledge at y %g" % (i + 1, rx, ry, top))
        if float(source[2]) <= 0.0:
            errors.append("rockfall source %d drops a stone every %g seconds"
                          % (i + 1, float(source[2])))


def check(level, tune):
    errors, warnings, notes = [], [], []

    for key in ("title", "width", "fall_y", "spawn", "solids", "hazards", "finish"):
        if key not in level:
            errors.append("missing required key `%s`" % key)
    if errors:
        return errors, warnings, notes

    width = float(level["width"])
    solids = level["solids"]
    fall_y = float(level["fall_y"])
    sx, sy = float(level["spawn"][0]), float(level["spawn"][1])

    if not solids:
        return ["no solids: there is nothing to stand on"], warnings, notes

    # --- the start and the end ---------------------------------------------
    if not standing_on(solids, sx, sy):
        errors.append("spawn (%g, %g) is not on top of any solid" % (sx, sy))
    fx, fy, fw, fh = (float(v) for v in level["finish"])
    if not standing_on(solids, fx + fw / 2.0, fy + fh):
        errors.append("finish bottom edge is at y %g, which is not the top of "
                      "any solid" % (fy + fh))
    if not 0.0 <= fx <= width:
        errors.append("finish x %g is outside the level (0..%g)" % (fx, width))
    climbing = bool(level.get("climb", False))
    if climbing:
        # A tower ends above where it starts, not to the right of it.
        if fy + fh >= sy:
            errors.append("the finish stands at y %g and the spawn at %g: a "
                          "climb has to end ABOVE where it began"
                          % (fy + fh, sy))
    elif fx <= sx:
        errors.append("finish (x %g) is not to the right of spawn (x %g)" % (fx, sx))

    # --- the fall line ------------------------------------------------------
    lowest = max(top for _, _, top in spans(solids))
    if fall_y <= lowest:
        errors.append("fall_y %g is above the lowest floor (%g): standing on "
                      "the ground would be fatal" % (fall_y, lowest))

    # --- mandatory jumps ----------------------------------------------------
    # A climb is analysed the other way up; see climb() for why the horizontal
    # reading of a one-screen-wide tower is nonsense.
    if climbing:
        climb(level, tune, errors, warnings, notes)
    right_edges = sorted(s[1] for s in spans(solids))
    for a, b in ([] if climbing else pits(solids, width)):
        gap = b - a
        if a <= sx <= b:
            errors.append("spawn x %g is over a pit (%g..%g)" % (sx, a, b))
        take, land = edge_at(solids, a, "right"), edge_at(solids, b, "left")
        if take is None or land is None:
            # A pit running off either end of the level is a wall, not a jump.
            if a > 0.0 and b < width:
                errors.append("pit %g..%g has no ledge on one side" % (a, b))
            continue
        rise = take - land                       # positive: landing is higher
        reach, apex = envelope(tune, rise)
        if reach <= 0.0:
            errors.append("pit %g..%g lands %g px higher than takeoff, and the "
                          "jump only rises %.1f px" % (a, b, rise, apex))
        elif gap > reach:
            errors.append("pit %g..%g is %g px wide with a %g px rise; a "
                          "full-speed jump reaches %.1f px" % (a, b, gap, rise, reach))
        elif gap > reach * TIGHT:
            warnings.append("pit %g..%g is %g px of a possible %.1f (%.0f%%) - "
                            "clearable, but wants a playtest"
                            % (a, b, gap, reach, 100.0 * gap / reach))
        else:
            notes.append("pit %g..%g: %g px of %.1f (%.0f%%), rise %g"
                         % (a, b, gap, reach, 100.0 * gap / reach, rise))
        before = [e for e in right_edges if e < a]
        run = a - max(before) if before else a - sx
        if run < RUN_UP:
            warnings.append("pit at %g has %.0f px of run-up, under the %.0f it "
                            "takes to reach full speed" % (a, run, RUN_UP))

    # --- hazards ------------------------------------------------------------
    for h in level["hazards"]:
        hx, hy, hw, hh = (float(v) for v in h)
        if hx <= sx <= hx + hw and hy <= sy <= hy + hh:
            errors.append("hazard %s covers the spawn point" % (h,))
        if hx < 0.0 or hx + hw > width:
            errors.append("hazard %s runs outside the level" % (h,))

    # --- everything that has to rest on the floor ---------------------------
    for key in ("crates", "bottles", "brews", "enemies"):
        for entry in level.get(key, []):
            ex, ey = float(entry[0]), float(entry[1])
            if not standing_on(solids, ex, ey):
                errors.append("%s at (%g, %g) is not standing on a solid"
                              % (key[:-1], ex, ey))
            if not 0.0 <= ex <= width:
                errors.append("%s at x %g is outside the level" % (key[:-1], ex))

    # Decor is art and never collision, so nothing else here would notice a
    # plant left hanging over a pit after the ground under it moved.
    for entry in level.get("decor", []):
        if len(entry) < 3 or str(entry[2]) not in GROUND_DECOR:
            continue
        dx, dy = float(entry[0]), float(entry[1])
        tops = [top for x0, x1, top in spans(solids) if x0 - 60.0 <= dx <= x1 + 60.0]
        if not tops:
            warnings.append("%s at x %g has no ground under it at all" % (entry[2], dx))
            continue
        nearest = min(tops, key=lambda t: abs(t - dy))
        if abs(nearest - dy) > DECOR_SLACK:
            warnings.append("%s at (%g, %g) is %+g from the surface it should "
                            "stand on (%g)" % (entry[2], dx, dy, nearest - dy, nearest))

    # The trap the level format already carries a warning about: this value used
    # to be health POINTS and is now bar segments, so an old 50 means fifty bars.
    # Brown bottles are written in the same units against the mana bar.
    for key in ("bottles", "brews"):
        for entry in level.get(key, []):
            if len(entry) > 2 and not 1 <= int(entry[2]) <= 5:
                errors.append("%s at x %g is worth %s bars, and the bar has five "
                              "segments - this was probably written as health points"
                              % (key[:-1], float(entry[0]), entry[2]))

    # --- sections -----------------------------------------------------------
    # `gates` cuts the level into sections the player may not leave until the
    # enemies in one are down. The failure that matters is a gate that can never
    # open, which strands the player for good, so the enemies that hold each one
    # are counted here rather than discovered in play.
    gates = [float(g) for g in level.get("gates", [])]
    guards = [e for e in level.get("enemies", [])
              if not (len(e) > 3 and str(e[3]) == "perch")]
    perches = len(level.get("enemies", [])) - len(guards)
    for i, gate in enumerate(gates):
        if i and gate <= gates[i - 1]:
            errors.append("gate %g is not past the one before it (%g); gates "
                          "run left to right" % (gate, gates[i - 1]))
        if not 0.0 < gate < width:
            errors.append("gate %g is outside the level" % gate)
        low = 0.0 if not i else gates[i - 1]
        holding = [e for e in guards if low <= float(e[0]) < gate]
        if not holding:
            errors.append("the section %g..%g has a gate and nothing to hold it "
                          "- it would open the moment the level loads" % (low, gate))
        else:
            notes.append("section %g..%g: %d enemy(s) hold the gate at %g"
                         % (low, gate, len(holding), gate))
    if gates:
        tail = [e for e in guards if float(e[0]) >= gates[-1]]
        notes.append("section %g..%g: no gate, %d enemy(s), %d perch(es) in the "
                     "level hold nothing"
                     % (gates[-1], width, len(tail), perches))

    # --- story cards --------------------------------------------------------
    # A level may name panels and what brings each one up. Every way of getting
    # this wrong is silent in play: art or a clip that was never extracted
    # leaves a warning in the console and nothing on screen, and a line drawn
    # over a pit is a line the player is never standing on when he crosses it,
    # so that card simply never comes up. None of it shows as a crash, which is
    # why it is checked here.
    for i, cut in enumerate(level.get("cutscene", [])):
        where = "cutscene card %d" % (i + 1)
        panel = str(cut.get("panel", ""))
        if not panel:
            errors.append("%s names no `panel`" % where)
        elif not os.path.isfile(os.path.join(STORYBOARD, panel + ".png")):
            errors.append("%s names the panel %r and there is no %s.png in "
                          "ui/art/storyboard - run scripts/"
                          "extract_storyboard.py" % (where, panel, panel))
        for key in ("audio", "out_audio"):
            clip = str(cut.get(key, ""))
            if clip and not os.path.isfile(os.path.join(AUDIO, clip + ".mp3")):
                errors.append("%s names `%s` %r and there is no %s.mp3 in "
                              "godot/audio - run scripts/extract_storyboard.py"
                              % (where, key, clip, clip))
        after = str(cut.get("after", ""))
        if after and after not in CUES:
            errors.append("%s waits on %r; the cues of that kind are %s"
                          % (where, after, ", ".join(repr(c) for c in CUES)))
        elif after:
            if not level.get("enemies"):
                errors.append("%s waits on the boss and the level has no "
                              "enemies" % where)
            else:
                notes.append("%s: %s plays on `%s`" % (where, panel, after))
        elif "at" not in cut:
            errors.append("%s has neither an `at` line nor an `after` cue, so "
                          "nothing would ever bring it up" % where)
        else:
            at = float(cut.get("at", -1.0))
            if not sx < at < width:
                errors.append("%s is at x %g, which is not between the spawn "
                              "(%g) and the end of the level (%g)"
                              % (where, at, sx, width))
            elif not any(x0 <= at <= x1 for x0, x1, _top in spans(level["solids"])):
                errors.append("%s is at x %g, where there is no floor - it "
                              "only fires when he crosses it on his feet, so "
                              "over a pit it would never fire at all"
                              % (where, at))
            elif at >= fx:
                errors.append("%s is at x %g, past the finish at %g"
                              % (where, at, fx))
            else:
                notes.append("%s: %s plays at x %g" % (where, panel, at))

    # --- the tracks ---------------------------------------------------------
    # `music` is the level's own loop and `boss_music` takes over while a boss
    # is fighting. A name with no file behind it is a warning in the console
    # and silence in play, which is the kind of thing nobody notices until a
    # marker asks why the boss fight has no music.
    for key in ("music", "boss_music"):
        name = str(level.get(key, ""))
        if not name:
            continue
        if not any(os.path.isfile(os.path.join(AUDIO, name + ext))
                   for ext in TRACKS):
            errors.append("`%s` names %r and there is no %s%s in godot/audio"
                          % (key, name, name, "/".join(TRACKS)))
        else:
            notes.append("%s: %s" % (key, name))
    if level.get("boss_music") and not level.get("enemies"):
        errors.append("`boss_music` is named and the level has no enemies, so "
                      "nothing could ever start it")

    return errors, warnings, notes


def report(name, level, tune):
    """Prints one level's findings and returns True if it failed."""
    errors, warnings, notes = check(level, tune)
    print("%-16s %s" % (name, level.get("title", "?")))
    for note in notes:
        print("    ok    %s" % note)
    for warning in warnings:
        print("    WARN  %s" % warning)
    for error in errors:
        print("    FAIL  %s" % error)
    print("")
    return bool(errors)


def main():
    tune = tuning()
    flat, apex = envelope(tune, 0.0)
    print("envelope, from tuning.gd: speed %g, jump %g, gravity %g"
          % (tune["speed"], tune["jump_velocity"], tune["gravity"]))
    print("  %.1f px of flat travel, %.1f px of rise\n" % (flat, apex))

    loose = [a for a in sys.argv[1:] if a.endswith(".json")]
    if loose:
        failed = 0
        for path in loose:
            if not os.path.isfile(path):
                sys.exit("no file at %s" % path)
            failed += report(os.path.basename(path),
                             json.load(open(path, encoding="utf-8")), tune)
        if failed:
            sys.exit("%d candidate(s) failed - do not install this yet" % failed)
        print("candidate is valid; safe to copy into godot/levels/")
        return

    index_path = os.path.join(LEVELS, "index.json")
    if not os.path.isfile(index_path):
        sys.exit("no index at %s" % index_path)
    order = json.load(open(index_path, encoding="utf-8")).get("order", [])
    if not order:
        sys.exit("index.json lists no levels")

    on_disk = set(f[:-5] for f in os.listdir(LEVELS)
                  if f.endswith(".json") and f != "index.json")
    absent = [i for i in order if i not in on_disk]
    if absent:
        sys.exit("index.json lists levels with no file: %s" % ", ".join(absent))
    # Every level file is validated, not just the course. A level off the order
    # is still shipped and still playable — First Steps is what the title
    # screen's PRACTICE row boots — so it still has to hold together, and a
    # course of one would otherwise leave two levels unchecked.
    off_course = sorted(on_disk - set(order))
    checked = list(order) + off_course
    if off_course:
        print("off the course, reachable another way: %s" % ", ".join(off_course))
        print()

    failed = 0
    for name in checked:
        failed += report(name, json.load(
            open(os.path.join(LEVELS, name + ".json"), encoding="utf-8")), tune)

    if failed:
        sys.exit("%d level(s) failed validation" % failed)
    print("%d level(s) valid (%d on the course)" % (len(checked), len(order)))


if __name__ == "__main__":
    main()
