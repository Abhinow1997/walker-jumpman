"""Validates every level in godot/levels/index.json against the movement tuning.

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
    if fx <= sx:
        errors.append("finish (x %g) is not to the right of spawn (x %g)" % (fx, sx))

    # --- the fall line ------------------------------------------------------
    lowest = max(top for _, _, top in spans(solids))
    if fall_y <= lowest:
        errors.append("fall_y %g is above the lowest floor (%g): standing on "
                      "the ground would be fatal" % (fall_y, lowest))

    # --- mandatory jumps ----------------------------------------------------
    right_edges = sorted(s[1] for s in spans(solids))
    for a, b in pits(solids, width):
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
    for key in ("crates", "bottles", "enemies"):
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
    for entry in level.get("bottles", []):
        if len(entry) > 2 and not 1 <= int(entry[2]) <= 5:
            errors.append("bottle at x %g is worth %s bars, and the bar has five "
                          "segments - this was probably written as health points"
                          % (float(entry[0]), entry[2]))

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
    stray = sorted(on_disk - set(order))
    if stray:
        print("note: on disk but not in the index, so unreachable in game: %s\n"
              % ", ".join(stray))

    failed = 0
    for name in order:
        failed += report(name, json.load(
            open(os.path.join(LEVELS, name + ".json"), encoding="utf-8")), tune)

    if failed:
        sys.exit("%d level(s) failed validation" % failed)
    print("%d level(s) valid" % len(order))


if __name__ == "__main__":
    main()
