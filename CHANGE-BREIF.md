# CHANGE-BRIEF — walker-jumpman

Written against the starter "First Steps prototype" before the
LF2 conversion began. Predictions below are the original record. Anything learned
later is added under "Revisions", not edited into the text above it.

## 1. Character concept

**Where this started.** My original concept was a pure platformer with no combat, on
a narrative closer to a toy escaping from a room. As development went on and the
ideas shifted, I took inspiration elsewhere and moved to the version described
below. Noted here so the record shows the change; the fuller account of what shifted
and why is in [FRICTIONAL.md](FRICTIONAL.md).

**Where it landed.** The starter protagonist is a procedural rig: a rectangle body
drawn in code, no art files. I am replacing it with **Anti-Davis**, a Little Fighter
2 character mod (A01, 2003, lf-empire.de), because LF2 is the game I actually want
this to feel like.

Visual features that distinguish it from the starter:

- Hand-sliced sprite sheets instead of drawn primitives — idle, run, jump, fall,
  hurt and death are separate drawn poses, not one shape being squashed.
- A turn that reads as a pivot: the sprite narrows through a floor value and
  stretches slightly as it flips, rather than snapping mirror-image.
- Drawn at 3/4 of pack resolution against a 960x540 canvas so one source texel lands
  on exactly one screen pixel — no blurred or doubled pixels.
- A tall, human-proportioned silhouette, roughly 1.5x the starter's height.
- An LF2 moveset the starter has none of: a two-hit punch chain, an air kick, a
  running shoulder charge, a thrown energy blast, drinking, and picking up and
  throwing light and heavy objects.

The swap is isolated to the visual layer: the sprite is a drop-in replacement for the
procedural rig with the same interface, and the original is kept as a fallback.
Movement code should not need to know which one is mounted.

## 2. The new section of level

The level work is driven by a story first, not by a list of mechanics. I am building
a world for the protagonist to live in, and letting that world justify why the game
plays the way it does.

**The premise.** The Holocene earthquakes broke the world and shattered it into
pieces. The old maps called it Earth; the old maps are underwater now. What is left
floats. He has held one ledge on those floating isles for years — no war, no wound,
just salt off the water and the old stones humming to themselves — until something
explodes out over the sea and wakes up. He knows every sound these isles can make,
and that is not one of them.

**What the premise buys me, and why I wrote it this way:**

- **Crumbling ground is the reason for the platformer.** A world that has physically
  broken apart is the most honest justification I can give for gaps, ledges, drops
  and a sea underneath everything. The player is not jumping because it is a
  platformer; they are jumping because there is nothing left to walk on.
- **A magical world is the reason for his powers.** The old stones hum. That is what
  licenses an energy blast coming out of a man's hands, and it means I do not have
  to explain it a second time.
- **The same world is the reason for the enemies.** Bandits are already part of his
  ordinary life — he names them in the opening as a sound he would have recognised —
  so they are the scavengers of a broken world rather than enemies dropped in to
  fill a level. The dragons are the thing that is *not* ordinary, which is what makes
  the screech a call to adventure instead of a Tuesday.
- **A hero's journey is the reason the levels differ.** The shape of that journey is
  what lets each level be a different kind of test without the course feeling
  arbitrary, and it is what earns the combat rather than bolting it on.

**The course, as that journey:**

| Level | Story beat | What it asks for |
|---|---|---|
| First Steps | the ordinary world — his own coast | movement and the jump, nothing unintroduced |
| The Fractured Isles | leaving the ledge; the road of trials | crumbling ground, then a bridge ambush, then the dragon on the archway |
| The Climb | the ascent, alone | one screen wide, seven screens tall, no floor and no way back |
| The Dragon's Roost | the confrontation | one arena, one flying boss, everything at once |

**Decisions it asks the player to make:**

- **Fight or pass.** Enemies cost health and time; most can be run past. Neither is
  free.
- **Blast height.** The projectile spawns relative to his feet, so a blast thrown at
  the top of a jump flies about 107 px higher than one thrown standing. A flat shot
  passes under a flying dragon; a jumped shot sails over a bandit standing right in
  front of you. Choosing the height is the decision, and I want it to be the
  decision.
- **Spend or save.** Bottles restore health, and drinking commits him to a long
  looping animation. Drinking near-full wastes most of it; drinking in range of an
  enemy gets it interrupted.
- **Commit with no way back.** The Climb's view ratchets upward and never returns, so
  every jump is one you cannot undo. It is deliberately the shortest level on the
  course, so bouncing off it costs minutes rather than an evening.
- **Where to stand.** The Roost is largely about position, not reflex — which is the
  point of putting the purely mechanical Climb immediately before it.

## 3. What must remain unchanged

- **Controls.** move_left (A / Left), move_right (D / Right), jump (Space), pause
  (Esc / P), restart (R), confirm (Enter), menu (M) keep their existing bindings and
  behaviour. New actions may only be *added*, never rebound over these.
- **Movement and jump tuning.** One fixed-height jump. No double jump, no wall jump.
  Coyote and jump-buffer windows stay at 6 physics ticks each. Time to apex stays at
  0.333 s.
- **Collision behaviour.** One axis-aligned rectangle on a CharacterBody2D, feet at
  the node origin, spawn measured from the feet. Animation poses must never resize
  the collider.
- **Retry.** Unlimited, immediate, no lives counter, no penalty screen. R restarts
  the attempt from anywhere.
- **Pause.** Esc / P, from play, and resumable.
- **Completion.** Reaching the visible finish completes the level. The finish stays
  at the end of the route, not before the last collectible.

### Changes I expect to need, and why

- **Tuning values scaled x2** (speed 160 -> 320, jump -320 -> -640, gravity
  960 -> 1920, terminal 480 -> 960). The LF2 character is much taller than the
  starter rectangle, so the world has to grow with him or he cannot fit through his
  own level. Positions, velocities and accelerations all scale by the same factor,
  which leaves timing untouched — apex time is unchanged, and the forgiveness
  windows are counted in ticks, not pixels, so they do not scale at all. This is a
  change of units, not of feel, and I will verify that claim rather than assert it.
- **Collider 18x28 -> 15x42**, for the same reason: it has to match the drawn body.
  Narrower as well as taller, because the LF2 silhouette is slimmer than the
  rectangle it replaces.
- **Viewport 640x360 -> 960x540**, so the taller character and the pixel art land on
  the pixel grid exactly.
- **Hazards keep killing outright.** Combat adds a health bar, and the risk is that
  the bar quietly replaces the instant-death rule. Health is what enemies spend;
  spikes and falls still kill on contact, the same as the starter.

## 4. Predicted failure cases

**F1 — The character outgrows the level geometry.**
Scaling the world x2 while the viewport only grows 1.5x means the player sees
proportionally less of the course than in the starter. Landings that were visible
before takeoff may now be off-screen, and a taller body may not clear gaps or fit
under ledges that a 18x28 box did. This is the failure I think is most likely.
*Check:* a per-level gap and jump diagnostic that walks every required gap and
confirms it is clearable at the tuned values, plus a reachability pass over each
level's solids; then play each level and confirm every main-route landing is on
screen at the moment of takeoff.

**F2 — Committed attack animations break the jump.**
Attacks hold the character in an animation. If a move zeroes the movement axis while
he is airborne, it will brake the jump it was thrown from and drop him short — which
silently violates "jump tuning unchanged" without changing a single tuning value.
*Check:* the planted-movement rule must be restricted to grounded moves only, and
the air kick and air blast tested mid-jump for arc distance against the same jump
with no attack input. Any difference in landing position is the bug.

**F3 — The Climb's one-way camera traps the player.**
A view that only ratchets upward means a missed jump can leave the player alive on a
ledge below the camera with no route up and no death to reset them — a soft lock the
starter's single flat level could not produce.
*Check:* a ratchet diagnostic that drives the climb and asserts the camera never
descends, plus deliberately failing jumps at each height and confirming every
outcome is either a recoverable landing or a clean death and respawn. Never a stuck
player.

**F4 — The boss fight desynchronises from its music and state.**
Boss health, arena sealing, and the fight's music are three systems that have to
agree. If a boss dies while a track is mid-transition, or the arena seals before the
player is inside it, the level can become uncompletable.
*Check:* diagnostics driving the boss to zero health and asserting the track,
the arena seal and the completion state all resolve, including on retry.

**F5 — Retry stops restoring the world cleanly.**
The starter restores a level with a handful of objects. With enemies, thrown
projectiles, carried objects, drunk bottles and boss state, R may leave residue.
*Check:* restart from mid-fight, mid-carry, mid-drink and mid-air, and confirm
health, enemies, items, camera, music and input all return to their starting state.

## Revisions

Appended as they happen. Nothing above this line is edited.

**How to read this.** Each entry says what changed against the prediction it revises,
when, and what evidence exists. Where the record cannot settle a question, it says so
rather than choosing the answer that makes the prediction look better. The narrative
account of all of this is in [FRICTIONAL.md](FRICTIONAL.md).

### Outcome of the five predicted failure cases

- **F1 — occurred.** 13 Sep, commit `2a366f1`. The taller character did break the
  level geometry, and the fix was the x2 rescale, the 15x42 collider and the 960x540
  viewport. See R9 below on what the record can and cannot say about this one.
- **F2 — did not occur as a bug.** The planted-movement rule shipped restricted to
  grounded moves from the start, so the air kick and the air blast never braked the
  jump they were thrown from. Predicted, designed around, never observed.
- **F3 — unproven, not passed.** `diag_ratchet.gd` asserts the camera never descends,
  and no soft lock was observed in play. But I did not run the deliberate
  miss-at-every-height test the prediction called for, so I cannot claim this one is
  cleared — only that nothing went wrong.
- **F4 — occurred, but not in the form predicted.** I expected boss health, the arena
  seal and the music to desynchronise from each other. Two different things happened
  instead: the seal margin never latched (R5), and the boss music file was absent from
  the repository altogether (R8). The systems agreed with each other fine; the
  prediction was aimed at the wrong risk.
- **F5 — unverified.** No retry residue was observed, but I did not systematically
  restart from mid-fight, mid-carry, mid-drink and mid-air as the prediction said I
  would. Treat as untested.

### R1 — Combat was never in the original plan (13 Sep, `f16d2cd`)

The brief above already records that the concept began as a pure platformer about a
wind-up toy escaping an attic, with a tension meter and winding stations instead of
enemies. What it does not say plainly enough: **the entire combat system is a
revision, not a plan.** It exists because the plain platformer was not fun to play in
early testing, and because the AI-generated art for the toy concept could not be
turned into usable sprites. Everything in section 1 and most of section 2 is
downstream of abandoning that first idea.

### R2 — Bosses were added after two levels existed (22 Sep, `b7dff44`, `8a6e3b2`)

Not in the original plan either. After two levels I judged that the narrative and the
game both needed a wall to beat, in the manner of the original Dark Souls games, and
added the dragon and the Dragon Lord. The boss sprites come from different artists'
packs than the environment, so they do not sit in the world perfectly; I altered the
narrative to accommodate them rather than pretend the seam is not there. The Climb was
then inserted before the final boss so that one purely mechanical test stands between
the last ordinary level and the Roost.

### R3 — Level authoring moved from prompting to purpose-built tools (by 17 Sep, `b849e5a`)

The brief assumed levels would simply be authored. They were, badly. Detailed layouts
produced by prompting came back random and inconsistent — gaps unclearable or trivial
with no reason for either, and no relationship at all to the background art, because
whatever was placing rectangles in a JSON file could not see the tileset it would be
drawn with. Replaced with two tools: `tools/level-editor.html`, which draws the real
jump arc over every gap and reports what is unreachable in words, and
`tools/asset-painter.html`, which paints layouts on top of the actual environment
sheets. Neither is a second source of truth; the game reads the same JSON either way.

### R4 — The blast needed a cost, and then the cost was wrong

Not predicted at all. With no cost, spamming the blast key trivialised every
encounter, so I added a mana drain. I then over-corrected: at 20 points a shot the bar
emptied in five blasts and only a bottle refilled it, which turned the blast into
something to hoard rather than use. Settled at 5 a shot against a bar of 100,
regenerating 5 every ten seconds. Running dry disarms him briefly and never kills him.
The flying dragon additionally learned to react to being spammed rather than absorb it.

### R5 — Enemy behaviour needed rules the brief never considered

Four failures found by playing, none of them predicted:

- Enemies walked off cliffs and died without my involvement — fixed with an edge
  probe and a 120 px drop limit, and by making their jump deliberately weaker than
  the player's so there is nowhere he can stand that they cannot follow.
- I could drag them off cliffs deliberately — same drop limit.
- They stood still until approached, and gave up if I backed away — fixed with an
  aggro latch that starts a fight on entering range *or* on being hit from outside it,
  and never releases until retry.
- The boss arena seal margin was 64 px against a story card that wakes the dragon 48
  px past the line, so it never latched; the first run of `diag_arena_seal.gd` watched
  me stroll back out of a live boss fight. Reduced to 24.

### R6 — Amendment to section 3: "completion" is now qualified

Section 3 says completion means reaching the visible finish. That is still true of the
finish itself, but it is no longer the whole rule, and the brief should not be read as
if it were. **I could originally run past every enemy and skip the fighting entirely**,
which made the combat optional and defeated the reason for adding it. Levels now cut
themselves into sections, and a section's wall stays solid while any enemy in it is
alive — so the finish is reachable only after clearing the route to it. Perch hunters
originally did not hold their gate, which left sniping from a shelf as a live exploit
until that was corrected.

This is a real change to a "must remain unchanged" item and is recorded as such rather
than quietly absorbed. The retry, pause and control contracts in section 3 were **not**
changed: bindings were added alongside the originals, never over them.

### R7 — Caption timing: first method rejected (19 Sep, `bf4b41d`)

The opening's captions were first timed by measuring runs of sound in the recording
and matching them to script lines in order. Fifteen measured segments, fifteen script
items, and the result was individually plausible and collectively wrong — line one
spans two segments because it contains an ellipsis, so everything after it was off by
one. Re-marked by ear with `tests/time_captions.gd`; the audio analysis was demoted to
what it can actually prove.

### R8 — The boss music was missing from the repository entirely (24 Sep, `91f8706`)

`decisive_battle.wav` was caught by a `*.wav` line in `.gitignore` with no exception,
so only its `.import` was ever committed and every clone reached **both** dragon fights
in silence. The existing test did not catch it because it compared a track *name*
rather than a stream. This is the failure in the project I am least comfortable with,
because a passing test is what gave me confidence.

### R9 — On the x2 rescale: what the record can and cannot say

Section 3 lists the rescale under "changes I expect to need"; Entry 4 of FRICTIONAL.md
describes it as something that broke on contact with the new sprite. The commit record
cannot separate the two, because `2a366f1` rescaled the tuning **and** added the
Anti-Davis extraction script in the same commit — the sprite and the rescale landed
together. I am flagging the discrepancy rather than editing one document to agree with
the other. What is independently verifiable either way: time to apex is unchanged at
0.333 s, and the coyote and buffer windows are still 6 ticks each.


