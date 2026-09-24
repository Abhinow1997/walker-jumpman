# TEST-REPORT — walker-jumpman

**Scope and honesty statement.** The results in this report are read from the recorded
run output in `evidence/`, written by the test suites themselves. They were **not
re-run while writing this report** — Godot is not on the PATH of the machine this was
assembled on, so nothing here is a fresh execution. Every number below is traceable to
a named file with a timestamp inside it, and where a suite has no retained output this
report says so rather than assuming it passes.

Engine recorded in every run: **Godot 4.7.2-stable (official)**.

---

## 1. What the test suites are

Fifty-five scripts under `godot/tests/`, in three kinds. They are not all tests, and
the distinction matters when reading this report.

| Kind | Count | What it is | Counts as a result? |
|---|---:|---|---|
| `test_*.gd` | 4 | Assertion suites. Each check records PASS/FAIL and the values it observed, then writes a JSON file into `evidence/`. | **Yes** |
| `diag_*.gd` | 23 | Diagnostics. Drive one system and print what happened, for investigating a specific behaviour. No pass/fail file. | No — investigative |
| `capture_*.gd` | 26 | Screenshot captures. Render frames into `evidence/screens/` so a visual change can be reviewed. | No — visual evidence |

There is also `scripts/check_levels.py`, a static reachability and spacing checker that
runs without the engine, with its own unit tests in `scripts/test_check_levels.py`.

The four assertion suites:

- **`test_levels.gd`** — the level pipeline: the catalogue, loading one level over
  another, section gates, story cards, boss arenas, music handoff, and the menu.
- **`test_combat.gd`** — the moveset and its hit geometry: what connects, when, and
  what a swing must not break. Written against real crates in real levels rather than
  synthetic fixtures.
- **`test_game.gd`** — the platformer itself: movement, jumping, hazards, retry,
  completion. Writes `evidence/mechanics-*.json`.
- **`test_keyboard.gd`** — real key events through the input map rather than direct
  state pokes. Writes `evidence/keyboard-*.json`.

---

## 2. Results

| Suite | Latest recorded run | Checks | Pass | Fail | Evidence file |
|---|---|---:|---:|---:|---|
| `test_levels.gd` | 2026-09-24 18:50:15 | 162 | 162 | **0** | `evidence/levels-1790275815.92.json` |
| `test_combat.gd` | 2026-09-24 18:10:43 | 281 | 280 | **1** | `evidence/combat-1790273443.217.json` |
| `test_game.gd` | — | — | — | — | **no retained output at this build** |
| `test_keyboard.gd` | — | — | — | — | **no retained output at this build** |
| `check_levels.py` | — | — | — | — | not recorded; no Python on this machine |

**443 checks recorded, 442 passing, 1 failing.**

Ten combat runs and ten level runs are retained in `evidence/`, spanning
17:24 to 18:50 on 2026-09-24, so the history of the final tuning session is visible,
not just its last frame.

---

## 3. The open failure

**`it-comes-down-and-fights-on-its-feet`** — `test_combat.gd`, Dragon's Roost.

The check asserts that the flying dragon, after landing, throws a grounded attack that
is a *different* move from its air attack:

```
saw_ground and ground_attack != "" and ground_attack != air_attack
```

Observed in the run:

```json
{ "landed_after_s": 0.0333,  "in_the_air": "",  "on-its-feet": "",
  "settled": true,           "saw_air_again": true }
```

**Reading it:** both `in_the_air` and `on-its-feet` came back empty, so the dragon was
never seen in its attack state in *either* phase during the observation window. It
settled into cruise, touched down after two frames, and took off again about a second
later without attacking. The loop then broke on `saw_air_again`.

**What this is not.** The very next check, `and-then-takes-off-again`, passed — so the
air/ground cycle itself is working. The failure is specifically that no ground attack
was observed inside the window, not that the dragon is stuck or inert.

**Most likely cause** (not confirmed): the check's observation window opens only once
`settled` is true, and `landed_after_s` of 0.033 means the dragon reached the deck
almost immediately after settling. The ground phase may simply be shorter than the
window needs, which would make this a timing-sensitive test rather than a gameplay
defect. That is a hypothesis from reading the assertion, not a diagnosis — it has not
been investigated.

**Status: open, uninvestigated.** It is recorded here rather than excluded.

---

## 4. What the passing checks actually cover

Test names in both suites are written as sentences, so the recorded run doubles as a
description of behaviour. A representative selection:

**Course and level pipeline** (`test_levels.gd`)
- `every-shipped-level-loads`, `schema-*` for all five level files
- `first-steps-leads-into-the-isles`, `the-isles-lead-up-the-climb`,
  `and-the-climb-leads-to-the-roost`, `the-roost-is-the-end-of-the-course`
- `load_level-leaves-no-stale-geometry`, `load_level-rebuilds-the-props`
- `a-level-off-the-course-leads-nowhere`, `the-fixture-is-not-on-the-list`

**Section gates — the anti-skip design**
- `the-dragon-cannot-be-run-past`, `an-unfought-section-is-shut`
- `the-camera-stops-at-the-shut-gate`, `the-wall-holds-him-in`
- `perch-enemies-are-flagged-and-hold-gate`
- `clearing-a-section-opens-it`, `a-retry-shuts-the-gate-again`
- `the-flag-cannot-be-reached-past-the-dragon`

**Boss arenas**
- `it-shuts-once-the-fight-is-on-and-he-is-inside`,
  `and-he-cannot-walk-back-out-of-it` — the regression guard for the seal-margin bug
- `the-roost-seals-behind-both-of-its-bosses`, `and-fences-its-flyer-to-the-same-room`
- `beaten-over-the-water-it-still-comes-down-on-a-deck`

**Music**
- `the-fight-brings-its-own-track-in`, `the-battle-track-ends-with-the-fight`
- `every-boss-track-is-one-the-mixer-knows` — the guard against the missing-file bug
- `cueing-the-track-again-does-not-restart-it`, `and-mute-beats-it-outright`

**The Climb**
- `the-view-does-not-travel-sideways`, `the-view-climbs-with-him`,
  `the-fatal-line-climbs-too`, `a-retry-drops-the-view-back`
- `a-stone-can-be-struck-out-of-the-air`

**Moveset and hit geometry** (`test_combat.gd`)
- `one-swing-one-hit`, `punch-misses-behind`, `punch-misses-far`,
  `jab-chains-into-cross`, `kick-ends-on-landing`, `running-attack-is-charge`
- `blast-spawns-projectile`, `blast-reaches-distant-crate`, `blast-expires`
- `charge-knocks-crate-instead-of-erasing-it`

**Enemy behaviour — the Entry 8 fixes, now guarded**
- `he-stays-put-until-the-fight-starts`, `walking-into-his-range-starts-it`,
  `and-then-he-follows-you-out-of-range`, `a-hit-from-out-of-range-starts-it`,
  `a-retry-un-engages-him` — the aggro latch
- `a-gap-he-can-clear-is-leapt`, `a-gap-he-cannot-clear-stops-him-at-the-lip`,
  `a-ledge-is-climbed-not-stared-at` — the cliff-walking fixes
- `a-perch-holds-while-the-deck-lives`, `a-perch-comes-down-when-the-deck-clears`
- `a-guard-can-be-broken-by-spending-it`, `a-blow-from-behind-is-not-guarded`

---

## 5. Gaps — what is not covered, or not evidenced

Listed because a report that only shows green is not a test report.

1. **No retained output for `test_game.gd` or `test_keyboard.gd`.** These are the
   suites covering the starter's own contract — movement, jump, hazards, retry,
   completion, and real key events. Earlier `mechanics-*.json` and `keyboard-*.json`
   files existed at earlier commits but are not present at this build. **The claim in
   CHANGE-BRIEF that controls, retry and pause were preserved is therefore argued from
   the diff, not from a current recorded run.** Re-running these two suites is the
   single highest-value action available.
2. **`check_levels.py` has no recorded output.** Reachability of every required gap is
   asserted in documentation but not evidenced by a retained run.
3. **F3 and F5 from CHANGE-BRIEF remain untested** — the deliberate
   miss-at-every-height test on The Climb, and systematic retry-from-mid-state. Both
   are recorded as unverified in that document's Revisions section.
4. **No performance evidence retained.** `diag_perf.gd` exists; no output is kept.
5. **No human playtest data.** Every balance judgement in this project was made by one
   player, its author. `PLAYTEST-PLAN.md` specifies a protocol that was not run with
   outside participants.
6. **Diagnostics and captures produce no pass/fail.** 49 of the 55 scripts are
   investigative or visual. Coverage should be counted as four suites, not fifty-five.

---

## 6. Caveats on the provenance of these results

These affect how much weight the numbers above can carry.

- **All recorded runs postdate the last commit.** The final commit is `2cad68a` at
  12:57 on 2026-09-24; the runs are at 18:10 and 18:50. They therefore describe a
  **working tree with uncommitted changes**, not any committed state. At the time of
  writing, `godot/game/music.gd`, `godot/levels/the_climb.json` and
  `godot/tests/test_levels.gd` are all modified and uncommitted.
- **The combat run is older than the level run.** Combat last ran at 18:10, levels at
  18:50. Anything changed between those times is unevidenced on the combat side, so
  the single failure may or may not still reproduce.
- **`test_levels.gd` itself was modified at 14:48**, before its 18:50 run — the suite
  and the code under test both moved in the same session.
- **Minor repository hygiene:** `godot/tests/capture_opening.gd.uid` is an orphan — the
  `.gd` file it refers to no longer exists.

---

## 7. How to reproduce

From the repository root, with Godot 4.7.2 on the PATH:

```bash
godot --path godot --script tests/test_levels.gd
godot --path godot --script tests/test_combat.gd
godot --path godot --script tests/test_game.gd
godot --path godot --script tests/test_keyboard.gd
```

Each writes a timestamped JSON file into `evidence/` and prints a failure count. The
static level checker needs Python but no engine:

```bash
python scripts/check_levels.py
```

Screenshot captures follow the same pattern and write into `evidence/screens/`, for
example:

```bash
godot --path godot --script tests/capture_storyboard.gd
```
