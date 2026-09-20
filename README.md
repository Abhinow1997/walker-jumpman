# walker-jumpman — First Steps

**Playable source prototype · September 10, 2026 · Godot 4.7.2 / GDScript**

Standalone game repository: [nikbearbrown/walker-jumpman](https://github.com/nikbearbrown/walker-jumpman). This checkout contains only this game's source, design package, and test evidence—not the Walker toolkit, Brutalist, or video renders.

Clone with `git clone https://github.com/nikbearbrown/walker-jumpman.git`, then import `walker-jumpman/godot/project.godot` in the regular Godot editor. No .NET runtime or external assets are required. On macOS, the launcher below also works when Godot is installed in Applications; on other platforms, use the editor or `godot --path godot` from the cloned folder.

Double-click [walker-jumpman.command](walker-jumpman.command) to play. The game opens on the title screen: **NEW JOURNEY** plays the opening and then starts the course in First Steps, carries on into The Fractured Isles and ends at The Dragon's Roost, **PRACTICE** drops straight into First Steps, and **LOAD GAME** opens the in-game level list — every level that ships, course or not (**W/S or up/down** to choose, **Enter** to start). In play, **A/D or left/right** to move, **Space** to jump, **J** to attack or throw, **K** to blast, **E** to lift or drink, **R** to retry, **Escape/P** to pause and **M** for the menu. Reach the flag. Retries are unlimited, and finishing a level goes straight to the next one.

The title screen, the opening's title card and all three course levels share the Magic Cliffs loop — the pack ships one track — so starting a new journey carries the music straight on rather than restarting it. First Steps names the same track, so PRACTICE carries it on too; the greybox fixture and Proving Ground are silent. Music lives in [music.gd](godot/game/music.gd), the one node in the project that outlives a scene.

The stage is cut into sections and you do not walk past a fight. While enemies are still standing in your section the camera stops dead, an invisible wall stands on the line, and you can see you have run out of screen rather than out of floor; put them down and both let go — the wall at once, the camera over about half a second, panning forward rather than cutting, with a chevron at the edge to say so. That pan is the only smoothing on the camera's horizontal: a fight backed into a gate ends with you pressed against the wall, which is the furthest the framing ever has to travel, and it used to travel it in one frame while you were still mid-swing. Walking back is never blocked. The Fractured Isles is four sections, the last being the Archway platform, which is the dragon's fight — it has no gate, so the flag ends it, and that means the boss can be run past.

Two bars sit in the top corner. Health is the green one and **you start on all of it**: punks take it, the white milk bottles give it back, and spikes and pits ignore it entirely — those are still instant deaths. A milk bottle found before anything has hit you says ALREADY FULL rather than being wasted, which is why every bottle on the course sits just after a fight. Mana is the blue one, and the blast is the only thing that spends it: five a shot out of a hundred, so twelve shots from a spawn and twenty on a full bar. It also trickles back on its own, a shot's worth every ten seconds, and the brown bottles top it up faster. Punching and kicking stay free, so an empty mana bar costs you the ranged option for a few seconds and nothing else.

**The blast goes up with you.** It used to need the floor; now it can be thrown in mid-air, and the muzzle is measured from your feet, so a jumped shot leaves 105 above them against 34 standing. That cuts both ways and is meant to: a flat shot reaches a bandit and sails under a dragon, a jumped one clears the bandit's head entirely, and the only thing that puts an energy strike into something cruising 156 up is a jump taken from one of the floating stones its arena is built around. Height is a decision now rather than a constant. Throwing one in the air does not brake the jump it came out of — planting your feet is something you can only do when you have feet on something.

Neither bar snaps. Both slide to their new level over about a third of a second, while the number beside them changes at once — so a hit or a blast is something you watch land, and the slow refill is visible as movement rather than a figure that is quietly different next time you look.

![The actual First Steps game, captured during a scripted jump](evidence/screens/03-jump.png)

This simple level has two steps, two gaps, one spike hazard, and a finish. It is the control/retry slice, not the full three-zone/cherry design below. See [build results and limitations](BUILD-REPORT.md). To edit, import [godot/project.godot](godot/project.godot) into Godot.

The first Walker example is a compact 2D platformer built around readable jumps, optional cherries and quick retries. Every new game project uses the `walker-` prefix. The original `jumping-man-godot` recovery collection remains separate and unchanged; it is not included or required here. Historical design references to sibling recovery files refer to the author's local source collection, not files shipped in this repository.

## The opening

NEW JOURNEY plays a cold open before the level: four storyboard panels against
a recorded monologue, then the game's title card, then the level faded up out of
black. **Space, Enter or Escape** skips it at any point and lands in exactly the
same place.

| | |
|---|---|
| 0:00 | the isles, faded up out of black over a second |
| 0:18 | the ledge, where he is asleep — dissolves in over 1.2s |
| 0:30 | the screech |
| 0:45 | the run |
| 0:56 | the title card, and the game's music starts |
| 1:00 | the level, faded up out of black |

The panels are cut off the recording's own playback position rather than a
timer, so a frame hitch shows the right panel late instead of the wrong panel on
time. The cut times live in [storyboard.gd](godot/ui/storyboard.gd) and nowhere
else, and everything that reads them — the capture, the diagnostic — derives its
boundaries from that table rather than repeating the numbers.

One cue dissolves and the rest cut. The isles and the ledge are two held shots
of a quiet morning, so the eye is carried between them; the screech and the run
are the opposite — a noise that wakes him and a decision to move — and a
dissolve would soften the exact thing those cuts are for. It is a per-cue
`fade` in the same table, so any other change can be softened by adding one
number, and the cut still begins on its mark either way: a dissolve fades in
FROM the cue rather than onto it.

The opening fades up rather than cutting in because NEW JOURNEY is leaving a lit
menu. Panel 0 is the establishing shot and the only one he is not in, which is
what makes it the one to arrive out of black: there is no character to read yet,
so nothing is missed while it does.

The music is the transition. The menu loop is hushed on the way in, because the
recording carries its own bed and two would collide; it is cued again on the
title card, and First Steps names that same track — so the cue in `_build_world`
finds it already playing and does nothing. The loop runs unbroken from the logo
into play, which is why there is no cross-fade here and no silence to cover.

Every line he speaks is captioned along the bottom, one at a time, on a dark
scrim — the panels are busy enough that outlined text alone loses its thin
strokes against the clouds. The delivery tags in the recording script
(`[whispers]`, `[curious]`, `[excited]` and the rest) are **not** shown: they
are instructions to the voice, not words, and a subtitle that prints them is
captioning the score rather than the film. One bracket stays, `[EXPLOSION]`,
which is the same convention the other way round — a sound with no words in it
still has to be captioned.

The caption times were measured rather than estimated.
[diag_speech.gd](godot/tests/diag_speech.gd) plays the voice-only stem through
a capture bus, sums its energy into 20 ms windows and prints every run of sound;
fifteen runs came back against fourteen spoken lines and one explosion, so the
pairing is one to one and in order. Re-render the recording and that script is
how the eighteen cues get their new numbers. It needs the stem, not the merged
mix — the mix has a bed under the voice and contains no silence to find.

`godot --path godot --script tests/capture_storyboard.gd` takes the whole thing
the way a player does and writes eight frames into `evidence/screens/`; it
asserts the cut times as arithmetic, then crosses 0:30 for real off the playing
stream, and checks the music node is the same one still playing after the
handoff rather than a restarted copy. `tests/diag_audio.gd` is the headless
check that the cues still fall inside the recording — re-render that mp3 shorter
and the 0:45 panel would simply never appear.

## Read in this order

1. [Game brief](GAME-BRIEF.md) — the short player-facing idea and proposed scope.
2. [Detailed GDD](GDD.md) — sixteen design sections, source evidence, requirements and twenty-two acceptance cases.
3. [Level design](LEVEL-DESIGN.md) — the three-zone course and its untested geometry.
4. [Production plan](PRODUCTION-PLAN.md) — twenty-two dependency-ordered tasks across six phases, plus four deferred tasks.
5. [Playtest plan](PLAYTEST-PLAN.md) — mechanical tests, formative human sessions, evidence and revision rules.
6. [Asset plan](ASSET-PLAN.md) — original greybox requirements and the provenance boundary.
7. [Design status](DESIGN-STATUS.json) — machine-readable revision, decisions, pending approvals and honest runtime state.

![Candidate walker-jumpman course map; not a gameplay screenshot](design/level-overview.png)

[Design consistency review](DESIGN-REVIEW.md) · [Editable SVG map](design/level-overview.svg)

[Level coordinate data](design/level-01.json) drives this candidate blockout. Counts and geometry can be checked without Godot. Jump reachability, zero-cherry/all-cherry routing, camera behavior and enjoyment have not been tested.

## Adding a level

Levels are data. One JSON file each in [godot/levels/](godot/levels), and
[index.json](godot/levels/index.json) keeps two lists. `order` is **the course**:
what NEW JOURNEY walks through, each level loading the next when you reach its
flag, and the only file that knows how long the game is. `also_listed` is
everything else the in-game level list offers. **LOAD GAME shows both**, the
course first — so every level that ships can be picked, and only the course
chains. Nothing has to appear twice: the list is `order` followed by whatever is
in `also_listed` that is not already in it.

The course opens on First Steps, carries on into The Fractured Isles and ends at
The Dragon's Roost. Learning the game is the first stretch of it rather than a
detour beside it, and the last is one arena and one flying boss.

Five levels ship, all validated by `scripts/check_levels.py`:

* **First Steps** is the practice course and the first level of the journey.
  Same cliffs, sea and cast as The Fractured Isles, cut into five short stretches
  that each ask for one thing you have not done yet — see below.
* **The Fractured Isles** is the course proper, and it ends on the Archway platform with the dragon — two floating islands were added there to fight it from.
* **The Dragon's Roost** is the final boss fight and nothing else: a hop in, a
  flat arena with two floating stones to take height from, and the dragon again,
  this time with nothing else in the level and a gate that will not open until it
  is beaten. It ends the course, so finishing it replays it.
* **Proving Ground** is the greybox prototyping slice: somewhere to try a
  mechanic without dressing a level around it. Listed, so you can pick it; not on
  the course, so it chains to nothing.
* **Greybox** is the test fixture and nothing else. It is in neither list and is
  flagged `"listed": false` as well, so it can never be offered as something to
  play. Every suite boots it, because
  a fixture has to be cheap to simulate and still there next week. It holds the
  geometry First Steps had until First Steps became content — which is exactly
  why it had to move out: half of `test_game` and `test_combat` were asserting
  against a level someone was editing for how it plays.

### The practice course

First Steps teaches the game by the shape of the level rather than by a wall of
text. It names a key in exactly one place, for the one lesson shape cannot carry.
What it does everywhere else is make each stretch
impossible to leave until the thing it teaches has been done, and put the safe
version of that thing before the one that costs anything:

| | asks for | how it insists |
|---|---|---|
| **01 The Shallows** | moving, and a jump | A gap with a rock sitting a jump below it. Miss and you land, climb out, and try again — the one gap in the game that cannot kill you |
| **02 Bandits** | committing to a jump, then fists | The same jump over a real pit, then a gate that will not open while the bandit behind it is standing. A milk bottle after, which is when the drink prompt first means anything. The one stretch that names a key — see below |
| **03 The Rocks** | picking something up and throwing it | A hunter shooting across the stretch and two rocks at your feet. Blast him and he reads it coming and guards; throw a rock and he cannot — he gets no warning of that one |
| **04 The Stair** | height, and hitting from the air | Three ledges with a bandit on the top one, met from below. A long run at the bottom of it, which is where the shoulder charge turns up on its own |
| **05 The Anvil** | footwork | Mark, who eats anything you trade with him. The flag is past his gate, so this is not a stretch you can run |

Only the first two rules are strictly enforceable — a gate is the only hard stop
the game has, and rocks and bottles are never solid, so no lesson can be built on
one being in the way. The rest are situations with one good answer rather than
one possible answer, which is most of what a level can do without talking.

**Bandits is the exception, and it talks.** A fight is the one thing the shape of
a level cannot mime: you can stand in front of a bandit indefinitely without ever
discovering that J is a fist. So that stretch carries two coaching lines — the
strike, then the blast — and each retires itself for good the moment the thing it
names has been done once. They are level data, not a rule in the HUD: `coach` is
`[x_from, x_to, text, action]`, so a level decides where a line belongs and what
counts as having learnt it, and no other level uses one.

To add one, write `godot/levels/<id>.json`; put `<id>` in the index's `order` to
make it part of the course, or leave it out to keep it off. Nothing else changes
— the menu, the title, the progress bar, the background signs and the chain to
the next level all read from the file.

| key | shape | meaning |
|---|---|---|
| `title` | string | the menu row, and the results panel's "Next:" line |
| `tagline`, `brief` | string | the results panel, and the menu blurb |
| `width` | number | right wall; the camera stops half a viewport short of it |
| `fall_y` | number | below this is a death, so it must be under every floor |
| `spawn` | `[x, y]` | his feet, which must be the top surface of a solid |
| `solids` | `[[x, y, w, h]]` | platforms and floor; `y` is the **top** edge |
| `hazards` | `[[x, y, w, h]]` | spikes. Instant death, unchanged by health |
| `finish` | `[x, y, w, h]` | the flag; `y + h` has to meet a solid's top |
| `crates` | `[[x, y]]` | optional. Breakable, throwable, never an obstacle. Drawn as the glowing rock; the key is the slot, not the art |
| `bottles` | `[[x, y, bars]]` | optional. White milk bottles; `bars` is **health-bar segments, 1–5**, not points |
| `brews` | `[[x, y, bars]]` | optional. Brown bottles, same units against the **mana** bar |
| `enemies` | `[[x, y]]`, `[[x, y, kind]]` or `[[x, y, kind, "perch"]]` | optional. One entry each. `kind` is `"bandit"` (the default), `"mark"`, `"hunter"`, `"dragon_lord"` or `"dragon"`; each is a folder under `features/combat/art/` cut by `scripts/extract_<kind>.py`. `"perch"` marks one that does **not** hold its section's gate. A `"dragon"` is a flyer and needs flat ground under its perch — every altitude it holds is measured from the height it took off at |
| `gates` | `[x, ...]` | optional. Section end walls, left to right. Three gates make four sections |
| `signs` | `[[x, y, heading]]` or `[[x, y, heading, subtitle]]` | background text, in world coordinates |
| `hills` | `[x, ...]` | optional, greybox only. Omit and six are spaced evenly across the width |
| `theme` | string | optional. Names an art set in `features/world/art/`. Omit for the greybox look |
| `music` | string | optional. Names a track in `godot/audio/` without its extension. Omit and the level is silent |
| `decor` | `[[x, y, piece]]` | optional, themed only. Art with its bottom edge at `y`. Never collision |
| `horizon` | number | optional, themed only. The waterline the parallax layers sit on |

### Themes

A level with no `theme` is drawn procedurally by `session.gd`, the original
greybox: flat rectangles, drawn hills, a flag. Proving Ground and the test
fixture are these.

A level with one is drawn by [scenery.gd](godot/features/world/scenery.gd) from
the same data. **Terrain is not authored** — the cliffs, grass and caps are
generated from the level's own `solids`, the identical rectangles the player
collides with and the validator measures, so the art cannot end up somewhere you
cannot stand or be missing somewhere you can. Only set dressing is placed by
hand, because a tree is a decision rather than a consequence of the geometry.

A solid may name the art it wears as an optional fifth value:

| `solids` entry | drawn as |
|---|---|
| `[x, y, w, h]` | a grassed cliff: grass strip over a filled body, rock caps on the ends |
| `[x, y, w, h, "island_large"]` | that piece, centred, its standing surface on the rectangle's top edge |
| `[x, y, w, h, "bridge"]` | planking, with an anchor post at each end |

`magic_cliffs` is the only theme so far — Ansimuz's **CC0** pack, and the only
licensed art in the project. Its tiles are 16 px, which is **12 world units** at
the game's 0.75 render scale, so those levels are authored on a 12-unit grid.
See [its provenance](godot/features/world/art/magic_cliffs/PROVENANCE.md).

Then check it before playing it:

```
python scripts/check_levels.py
```

That reads the jump envelope out of `features/player/tuning.gd` — currently
**213 px of flat travel and 107 px of rise** — and fails on a gap no jump can
clear, a spawn or prop hanging in the air, a fall line above the floor, a finish
that does not meet the ground, or a bottle written in health points instead of
bars. It warns, without failing, on a gap above 80% of the envelope. A movement
change invalidates every gap in every level, and this is what says so.
`python scripts/test_check_levels.py` checks the validator still rejects what it
claims to. `tests/capture_levels.gd` renders the menu and every level.

Then look at the route you just changed:

```
python scripts/map_level.py
```

That writes `evidence/maps/<id>.png`: the whole course as a strip map, on the
tile grid, with every mandatory gap measured against the jump envelope and the
real jump arc drawn off each ledge. The validator says whether a gap is
clearable; the map shows by how much, which is the question you have while
moving a platform.

### Editing the layout

[tools/level-editor.html](tools/level-editor.html) is a drag-and-drop editor for
the same files. Serve the repo and open it, so it can load the levels itself:

```
python -m http.server 8777
```

then <http://127.0.0.1:8777/tools/level-editor.html>. Opened straight off disk it
works too, but you have to click **Open level** and pick the file.

Drag platforms to move them, drag the right-hand handle to resize, click to
place bandits, crates and bottles, `Delete` to remove, `Ctrl+Z` to undo.
Everything snaps to the 12-unit tile grid, and a prop dropped over a platform
snaps to its surface so it can never be left hanging.

The point of it is the feedback: the jump arc off every ledge is drawn live, and
the **Route** panel scores each gap as a share of the envelope the moment you let
go — so a platform dragged out of reach goes red while you are still holding it,
rather than at the next validator run. **Download JSON** writes the file back
with every field it does not understand preserved.

The **Ground shape** panel tunes the rock itself with sliders: how far the cliff
faces lean in, how tall each break is, how far the edge wanders, how strong the
cave texture is, the width below which a platform stays square, and a nudge for
each rock column. The canvas draws the real leaning, broken wedge while you drag,
the two columns as coloured bands so a nudge is visible, and the collision
rectangle dashed over the lot so you can see they are not the same thing.

### Drawing an edge by hand

Select a plain ground block and the **Outline** panel offers *Draw this edge by
hand*. It seeds a set of handles from the shape the block already has, then you
drag the dots to draw each face however you like. A block with a drawn outline
ignores lean, break and jitter entirely: the handles ARE the shape.

Outlines are stored under `ground.profiles`, keyed by the block's own left x, and
read straight back by the renderer. *Back to automatic* deletes one; a level with
none carries no block at all.

The columns are aligned by their ART, not by their rectangle. Both carry four to
eleven pixels of transparent margin on their outer side, so lining them up by the
sprite box left a sliver of flat fill down every face; the extractor records that
margin as `bleed` and the renderer backs each column out by it. The nudges are on
top of that, for aligning by eye.

Those values are saved into the level as a `ground` block and read straight back
by [scenery.gd](godot/features/world/scenery.gd), so the numbers cannot drift
between the tool and the game. A level left at the defaults carries no block at
all.

It is a convenience, not an authority. `scripts/check_levels.py` is the gate, and
the editor's jump constants are a copy of `tuning.gd` — change the movement and
you must change `TUNE` at the top of the HTML, or it will bless gaps the game
cannot clear. The ground defaults are a copy too, but only the defaults: anything
you actually tune lives in the level file.

## Enemies

Five enemies share one script
([`features/combat/enemy.gd`](godot/features/combat/enemy.gd)) but fight to
different personalities, keyed by kind in its `PROFILES` table. Place any of them
with `[x, y, "kind"]` in a level's `enemies` array.

| kind | style | plays as |
|---|---|---|
| `bandit` | charger | rushes you: from mid-range he commits a fast dash, so standing still in front of him is punished. An even match otherwise — one bar of health, one bar of damage. Even the charge stays slower than your run, so leaving is always an answer. |
| `mark` | bruiser | the tank: far more health, a heavier blow, and **super-armour on his own swing** — catch him mid-punch and he eats it and follows through, so you cannot trade jabs and win. Slow, though; the answer is footwork, not standing your ground. |
| `hunter` | archer | keeps his distance and **looses arrows** across the gap, kiting backwards to hold the range. Draws the bow, fires a straight-flying arrow, and is forced to his fists only if you close on him. Fragile. |
| `dragon_lord` | bruiser | a mark turned up: twice the health, a longer reach measured off his own flame, and two specials picked by distance. No guard — he **burns** a thrown blast out of the air instead, see below. **Currently placed in no level**: he was the Archway boss until the dragon took that fight. Art, profile and tests are all still here, so putting him back is one entry in an `enemies` array. |
| `dragon` | flyer | the final boss, and the only thing in the game that fights in two phases. It sits on its perch until you walk in, **roars**, and takes off; in the air it cruises out of reach, **swoops**, and breathes fire along the deck. Then it **lands** and fights you on its feet — walking in, clawing, and breathing standing fire — before going back up. No guard: its answer to a blast is to **climb over it**. See below. |

Every kind stands where the level put it until the fight starts — walk inside its
`aggro` range, or hit it from outside — and **after that it follows you**, however
far you back off. Aggro decides when a fight begins, not whether it continues: an
enemy that lets you take three steps back and then turns round and stands there
reads as broken rather than as an escape, and the section gates will not let you
leave the fight anyway. A retry puts everyone back on their mark and forgets it.

**They jump.** Once a fight is on, the terrain is their problem rather than your
free win: a gap is leapt, a ledge is climbed, and a player who jumps clean over
their heads is followed up and swung at on the way. The swing is the same swing —
the hit box rides the sprite, so it is high when they are. Three rules keep it
from being oppressive:

* **They only jump when jumping is the answer.** Level floor is walked. The
  triggers are a gap or a step in the way, or you being above them.
* **A jump they cannot make is not attempted.** Each kind carries a `leap` speed,
  which with a fixed 0.75 s of air time sets how wide a gap it can cross: on the
  Fractured Isles a bandit takes the 24, 60, 72, 96 and 120 px gaps and stops at
  the lip of the 132s and the 168; Mark, heavier, gets the short ones and nothing
  else. Nothing walks into a pit any more — falling in used to open that
  section's own gate for free. `tests/diag_gaps.gd` prints the whole table for a
  level, which is how you find out whether a chasm you just authored is one the
  fight can follow you across.
* **Their jump is smaller than yours.** 101 px against your 107, so there is
  nowhere you can climb to that they can follow but you cannot leave — and the
  hunters perched on the Isles' high shelves, 144 px up, stay out of the fight,
  which is what the gate design rests on.

A leap is committed: there is no steering once they are off the ground, so it can
be sidestepped like the bandit's charge. Hit one in mid-air and the stagger takes
its momentum with it — it drops out of the leap rather than finishing it. And
landing leaves them flat-footed for a moment, so being somewhere else when they
come down is the answer to one that follows you up.

The hunter jumps for terrain only, never at you. An archer who leaps has given up
the one thing he is for; his answer to a player on a ledge is to back off and
shoot.

**They block.** Three blasts used to kill a bandit, and throwing them from across
the room was no worse than throwing them from arm's length — so the answer to
every fight was the same key, held down. Now anyone with time to *see* one coming
gets his arms up, and the whole design is in what "time" means:

* Each kind has a **reaction**, in seconds of warning. Against the blast's
  560 px/s that is a distance: 168 px for a bandit, 280 for Mark, 146 for the
  hunter. Thrown from inside it there is no guard at all.
* Seeing one go past — hit or miss — leaves him **braced** for two seconds, and
  a braced enemy reads the next one from **45% of that range**. That is the
  anti-spam rule: mash K and a bandit blocks from 76 px, which is nearly his own
  reach.
* A block is not immunity. A fifth of the blow gets through, it costs him the
  ground he was going to walk, and it **spends a pool** worth one to one and a
  half times his health. The blow that empties the pool is the one that is *not*
  blocked: full damage, full stagger, and the broken-guard frame. The pool
  refills over six seconds, and until it can soak a whole blast again every
  shot simply breaks it afresh — so spending a guard is the opening, and
  finishing him through it is the payoff.

So there are two clean ways to land one, and both are the opposite of mashing:
**get inside his reaction**, or **throw one and wait** — space them past the
two-second brace and anything inside 168 px lands on a bandit untouched. Mashed
from across the room, the same kill costs five blasts and 25 mana instead of
three and 15.

**The Dragon Lord burns them instead.** He cannot block — his pack ships idle,
walk, attack, hurt and death and no defend frame — so his answer is the one a
boss should have anyway: told a blast is coming, he throws his attack early
enough that the fire is out when it arrives, and anything that flies into the
fire is destroyed rather than resolved. A boss who blocks is a wall; a boss who
answers a thrown fireball with a bigger one is a fight.

The range he can do it from is his own animation rather than a number — the flame
is 0.36 s into the swing, which is about 200 px of the blast's flight — and a
swing takes 1.2 s, so he meets roughly every other one. Mashing K at him from
across the arena went from ten blasts and 50 mana to about nineteen and 95, which
is more than a full bar. Inside 200 px he has no time to wind up and every one
lands. It also works the other way round: a blast lobbed into a swing he was
already making burns just the same, so it is worth watching what he is doing
before you press the key.

`tests/diag_guard.gd` prints the blast-by-blast ledger for every kind, guards and
fire alike, if you want to re-check any of these trades.

**The dragon climbs over them.** It has no defend frame either — six frames of
wing-flap and not one of them is a block — but it already lives on the one axis
a blast does not use. The thing flies dead flat, so told one is coming it goes
over the top, and the cost is the pass it was in the middle of. That is a trade
rather than a switch: spamming K at it buys you safety and does no damage at
all, and it reads the next one from closer every time, exactly as a guard does.
Get inside its reaction — 168 px cold, 76 braced — and the blast lands, but only
while it is down at the bottom of a swoop, because cruising it is above the line
the blast flies along in the first place.

### The flyer

The dragon is a fifth style, and the only enemy that is really two: it fights
in the air and it fights on its feet, and the pack draws both. Fourteen
animations, thirteen of them decoded out of watermarked preview gifs — see
`features/combat/art/dragon/PROVENANCE.md`, which explains how and proves it.

**In the air** it uses none of what the others rely on — no gravity, no floor
probe, no walk, no charge, no kiting — so its whole approach is one function
(`_advance_flyer`) and `_integrate` skips the floor for it. **On the ground**
it is an ordinary bruiser and runs the same `_advance_chase` every other enemy
does, which is the point of the split: the ground half is not new movement.

`anim_for()` is what joins them. A flyer has two of nearly everything — two
idles, two walks, two hurts, two ways of breathing fire — and while it is up,
any animation with an `_air` variant plays that one instead. `basic_move()` is
the same idea for the attacks, which cannot be one animation with a suffix
because they land on different frames with different boxes: **swoop** in the
air, **claw** on the ground.

It **starts perched**, standing on a solid the level put it on like anything
else. That is what lets `check_levels.py` measure it, and it makes the take-off
— the one moment in the whole pack drawn facing the camera — a beat of the
fight rather than something that happened before you arrived.

It does not stay up. Nine seconds in the air, then a committed landing, seven
on its feet, then a committed take-off, round and round. In the air it has
three heights, and the arena is built around them:

* **Cruise, 156 above the deck.** You apex at 107 and your highest hit box is 36
  above your feet, so from the floor you reach 143 — you cannot touch it. The
  two floating stones are 96 up, and a jump from one reaches 239. Taking the
  height is the answer; the stones are at opposite ends because a dragon that
  circles would make a single perch a corner to be trapped in.
* **The pass.** It noses down first and opens the throttle second, so the run in
  is a dive rather than one long diagonal, and it will not begin one from inside
  340 — it needs that much to finish descending before it strikes. It bottoms
  out at 23 above your feet, which is low enough for both your standing punch
  (36) and the blast (43) to reach, and it throws the strike a wind-up early so
  the blow lands where you will be rather than a body length behind you.
* **The climb**, above, when it reads a blast.

and one more attack that is not a pass at all: it drops to your level at range
and **hoses fire along the deck**. The counter to that one is to get *inside*
the band, which is the same counter the Dragon Lord's breath has.

On its feet it walks in at 150 — outrunnable, like everything else in the cast
— **claws** at 86 and breathes the standing version of the same fire from 125
to 180. That phase is the fight's breathing space and its danger both: it is
the only time the dragon is reliably in reach, and the only time it can corner
you against a wall.

Beaten, it goes **down** first: dropped out of the air if that is where it was,
and folding forward on the deck in the collapse the pack draws. Then it gets
up, turns away from whoever put it there, and flies out of the level over about
two and a half seconds. The gate it was holding opens the moment it is beaten,
not when the body is cleared, so the way on is already open while you are still
watching it go.

The personality lives entirely in `PROFILES` — health, speed, damage, cooldown,
knockback, leap, guard, reaction, and how it closes (walk, charge, shoot and
kite, or fly). A kind with no row falls back to a plain walker. Art, reach and hit geometry still come from each
kind's manifest, so you can retune a bruiser without recutting a sprite. The
hunter's arrow is its own object ([`features/combat/arrow.gd`](godot/features/combat/arrow.gd)) —
the LF2 rip has his bow-draw frames but no arrow, so the shaft is drawn, not cut.

`godot --path godot --script tests/capture_enemies.gd` renders each kind in the
game — including the hunter's arrow in flight — to `evidence/<kind>/`.
`tests/capture_dragon.gd` does the same for the final boss, but as a fight
rather than a set of poses: perch, take-off, cruise, pass, strike, climb and
fly-away, into `evidence/dragon/`. `tests/diag_dragon.gd` prints the numbers
behind it.

## Proposed defaults ready for review

Godot 4 with typed GDScript, Compatibility rendering, one three-zone level, twenty optional cherries, one fixed-height jump with small forgiveness windows, hazards, quick retries, keyboard controls and a locally tested Web export. No paid services. No moving-platform dependency in the MVP.

The tested engine is Godot 4.7.2.stable.official.ed1daf0bf. Zelda's reusable prompt and command/workflow specification belong to the separate Walker toolkit and are not dependencies of this game.

## Current boundary

The full design is still a draft. Bear subsequently authorized **“Build a simple level for walker-jumpman.”** The first slice is implemented and machine-tested; full-design approvals, human playtesting, cherries/settings, and the Web export remain pending. This is a source-code release, not a hosted game or downloadable executable. The build report and test receipts preserve the earlier local-build history.

Next: play this small control/retry loop before expanding the course. The human owns intent, scope, play-feel judgments, and release decisions; AI implements and checks authorized work. The original `/Users/bear/walker-jumpman` stays untouched.
