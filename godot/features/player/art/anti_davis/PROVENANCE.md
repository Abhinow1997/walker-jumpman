# Anti-Davis — provenance

Generated files. Do not edit by hand; rerun `scripts/extract_anti_davis.py`
and let Godot reimport.

| | |
|---|---|
| Character | Anti-Davis, 10.04.2003, by **A01** |
| Distributed by | Little Fighter Empire (lf-empire.de) |
| Source in this repo | `Assests/Anti-Davis/Anti-Davis/` (BMP sheets + encrypted `.dat`) |
| Derived from | Davis, a *Little Fighter 2* character by Marti Wong and Starsky Wong |

## Rights

This is a fan-made mod for *Little Fighter 2*, a freeware game. It was published
for use inside LF2, and it is a derivative of that game's original art. No
licence accompanies the pack — the readme covers installation only.

That is fine for coursework and for anything that stays inside the class. It is
**not** a clearance to ship, sell, or publish the game with this character in
it. Before release the protagonist has to be replaced with art that has a
written licence, or commissioned.

`GDD.md` §11 already flags provenance as a top risk. This is that risk, live.

## Cell geometry

Frames are rebaked from LF2's 79x79 cells into a uniform **96x96** cell with the
character's origin (feet, mid-body) at **(44, 82)**. The cell is wider than the
body needs because the attacks reach much further forward than any locomotion
pose. Both numbers live in `moves.json` and the game reads them from there;
`extract_anti_davis.py` fails loudly rather than cropping if a frame outgrows
the cell.

| Strip | Frames | LF2 frame ids | Used for |
|---|---|---|---|
| `idle.png` | 4 | 0–3 standing | standing still |
| `walk.png` | 4 | 5–8 walking | the acceleration ramp, under 150 px/s |
| `run.png` | 3 | 9–11 running | full-speed travel |
| `skid.png` | 1 | 218 stop_running | turning against momentum |
| `rise.png` | 1 | 213 dash | ascending |
| `fall.png` | 1 | 214 dash | descending |
| `death.png` | 5 | 180–184 falling | death, holds on the last frame |
| `drink.png` | 4 | 55–58 weapon_drink | drinking the milk bottle |
| `punch_a.png` | 4 | 60–63 punch | jab, standing attack |
| `punch_b.png` | 4 | 65–68 punch | cross, chains off the jab |
| `kick.png` | 5 | 80–84 jump_attack | airborne attack |
| `charge.png` | 7 | 85–89, 97, 98 run_attack | shoulder barge at full speed |
| `blast.png` | 7 | 240–246 blast | throws the projectile |
| `ball_fly.png` | 2 | ball 8–9 | projectile in flight |
| `ball_hit.png` | 4 | ball 10–13 | projectile impact |

## moves.json

Generated alongside the strips and read at load by `moveset.gd`. Holds the cell
geometry, per-frame durations, and the hit rectangles.

Durations are LF2's own: it holds a frame for `wait + 1` ticks of a ~30 Hz
clock, and the attacks depend on that unevenness — the shoulder charge sits on
its commit frame twice as long as anything around it. A single frames-per-second
number cannot express that, so each frame carries its own length. `RATE` in the
extractor sharpens all attacks uniformly; it is 1.25, because LF2's timings are
built for two players standing still rather than a platformer mid-stride.

Hit rectangles are transcribed from LF2's `itr` blocks, relative to the origin,
in the art's facing-right space. That is why a punch connects where the drawing
shows it connecting. `itr` volumes with `injury: 0` are LF2's grab and wind-up
boxes and are dropped.

Weapon points come from LF2's `wpoint` blocks. LF2 never draws a held object
into a character frame — it draws the body, then stamps the object at that
point — which is why the drink frames are empty-handed in the sheet and the
bottle is composited back on at run time. Only `drink` has them today.

**Never hand-edit this file.** Rerun the extractor.
