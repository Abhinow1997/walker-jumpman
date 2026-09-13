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

Frames are rebaked from LF2's 79x79 cells into a uniform **80x96** cell with the
character's origin (feet, mid-body) at **(40, 82)**. `player_sprite.gd` mirrors
those numbers in `CELL` and `PIVOT`; change one and you must change the other.

| Strip | Frames | LF2 frame ids | Used for |
|---|---|---|---|
| `idle.png` | 4 | 0–3 standing | standing still |
| `walk.png` | 4 | 5–8 walking | the acceleration ramp, under 150 px/s |
| `run.png` | 3 | 9–11 running | full-speed travel |
| `skid.png` | 1 | 218 stop_running | turning against momentum |
| `rise.png` | 1 | 213 dash | ascending |
| `fall.png` | 1 | 214 dash | descending |
| `death.png` | 5 | 180–184 falling | death, holds on the last frame |
