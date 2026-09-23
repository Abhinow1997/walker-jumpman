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

Frames are rebaked from LF2's 79x79 cells into a uniform cell with the
character's origin (feet, mid-body) at a fixed point inside it. The sheets are
written at the pack's own resolution — a **96x96** cell with the origin at
**(44, 82)** — and are **not resampled**.

Two separate numbers do the work the one `SCALE` used to:

| | value | what it means |
|---|---|---|
| `SCALE` | 0.75 | how big he is in the **world**: hit boxes, weapon points, reach |
| `TEXTURE_SCALE` | 1.0 | how big his **sheet** is; 1.0 is the pack's own pixels |
| `render_scale` | 0.75 | published in the manifest; texture pixel to world unit |

`SCALE` exists because Davis is drawn 73 px tall in the pack and the CC0 street
enemies are 50 px; at native size he towered over them. At 0.75 he stands a head
taller, which is the relationship a protagonist wants.

`TEXTURE_SCALE` is 1.0 because the screen magnifies. The game runs a 960x540
viewport in a 1280x720 window — a 4/3 canvas magnification — and 0.75 x 4/3 is
exactly 1, so a pack pixel lands on one screen pixel. Shrinking the sheet as
well threw a quarter of the detail away and then had `TEXTURE_FILTER_NEAREST`
blow the remainder back up, which is where the blocky edges came from. **Change
the viewport and `SCALE` has to change with it, or that stops being exact.**

LANCZOS is still the filter if anything here is ever resampled again, because
LF2's art is painted and already anti-aliased — 145 colours in one idle frame —
so it takes a resize like a small photograph. **Crisp indie pixel art must never
be put through that.**

Only the cast and the props scale. The level geometry and movement tuning are
deliberately untouched, so the jump arc and every gap stay exactly as tuned and
the level simply reads as roomier around a smaller cast. Hit boxes and weapon
points scale with the art; the damage written on a hit box does not. The cell is wider than the
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
| `hurt.png` | 2 | 220–221 injured | struck: doubled over, 0.25 s of hitstun |
| `death.png` | 5 | 180–184 falling | death and the ordinary knockdown, holds on the last frame |
| `burn.png` | 4 | 203–206 fire | struck by a dragon’s breath: 203–204 tumbling inside the flame, 205–206 burning where he landed |
| `drink.png` | 4 | 55–58 weapon_drink | drinking the milk bottle |
| `punch_a.png` | 4 | 60–63 punch | jab, standing attack |
| `punch_b.png` | 4 | 65–68 punch | cross, chains off the jab |
| `kick.png` | 5 | 80–84 jump_attack | airborne attack |
| `charge.png` | 7 | 85–89, 97, 98 run_attack | shoulder barge at full speed |
| `blast.png` | 7 | 240–246 blast | throws the projectile |
| `ball_fly.png` | 2 | ball 8–9 | projectile in flight |
| `ball_hit.png` | 4 | ball 10–13 | projectile impact |


The pack also draws a longer dizzy loop (226-229) and two stagger-backward pairs
(222-225). 220-221 was chosen because it reads as one blow landing rather than
as a daze, which is what a 0.25 s reaction needs.
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
