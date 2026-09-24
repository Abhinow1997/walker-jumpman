"""Checks that check_levels.py actually rejects what it claims to reject.

A validator that has quietly stopped catching anything still prints "valid" and
is worse than not having one, because the levels now carry its endorsement.
Each case below is a level that must fail, and one that must pass.

    python scripts/test_check_levels.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_levels as cl


TUNE = cl.tuning()

# A minimal level that passes, which every case below then breaks in one way.
# Floor 0..450 and 600..1000: one comfortable 150 px pit, so the fixture
# itself passes cleanly and the tight-gap case below is the only one that warns.
GOOD = {
    "title": "Fixture",
    "width": 1000,
    "fall_y": 900,
    "spawn": [100, 640],
    "solids": [[0, 640, 450, 128], [600, 640, 400, 128]],
    "hazards": [],
    "crates": [],
    "bottles": [],
    "enemies": [],
    "finish": [950, 528, 48, 112],
}


def broken(**changes):
    level = dict(GOOD)
    level.update(changes)
    return level


CASES = [
    ("a gap wider than the jump",
     broken(solids=[[0, 640, 100, 128], [500, 640, 500, 128]]), "reaches"),
    ("a landing higher than the jump rises",
     broken(solids=[[0, 640, 100, 128], [200, 400, 800, 128]]), "rises"),
    ("a spawn hanging in the air",
     broken(spawn=[100, 500]), "not on top of any solid"),
    ("a spawn over the pit",
     broken(spawn=[500, 640]), "over a pit"),
    ("a fall line above the floor",
     broken(fall_y=600), "fall_y"),
    ("a finish that does not meet the floor",
     broken(finish=[950, 400, 48, 112]), "finish bottom edge"),
    ("a finish behind the spawn",
     broken(spawn=[900, 640], finish=[100, 528, 48, 112]), "not to the right"),
    ("a crate floating off the ground",
     broken(crates=[[200, 500]]), "not standing on a solid"),
    ("a bottle written in health points",
     broken(bottles=[[200, 640, 50]]), "health points"),
    ("a hazard on the spawn",
     broken(hazards=[[80, 620, 48, 32]]), "covers the spawn"),
    ("a missing required key",
     {k: v for k, v in GOOD.items() if k != "finish"}, "missing required key"),
]


def main():
    failures = 0

    errors, _, notes = cl.check(GOOD, TUNE)
    if errors:
        print("FAIL  the good fixture should pass: %s" % errors)
        failures += 1
    else:
        print("ok    the good fixture passes (%s)" % "; ".join(notes))

    for name, level, expected in CASES:
        errors, _, _ = cl.check(level, TUNE)
        hit = [e for e in errors if expected in e]
        if hit:
            print("ok    rejects %s" % name)
        else:
            print("FAIL  did NOT reject %s - wanted %r, got %s"
                  % (name, expected, errors or "no errors at all"))
            failures += 1

    # The tight-gap warning has to warn without failing, or a deliberately
    # demanding jump becomes impossible to author.
    tight = broken(solids=[[0, 640, 200, 128], [400, 640, 600, 128]])   # 200 of 213
    errors, warnings, _ = cl.check(tight, TUNE)
    if not errors and any("playtest" in w for w in warnings):
        print("ok    warns without failing on a tight gap")
    else:
        print("FAIL  tight gap: errors=%s warnings=%s" % (errors, warnings))
        failures += 1

    print("")
    print("VALIDATOR TESTS: %d cases / %d failures" % (len(CASES) + 2, failures))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
