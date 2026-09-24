# SOURCES

## Starter

- The base level game was provided by the professor. Seeing that starter is what prompted the idea of integrating it into an LF2-style hack-and-slash crossed with a platformer, which is what this version tries to be.

## Characters and Enemies

- The main game character and the enemies come from Little Fighter 2 — https://www.lf2.net/index_en.html
- LF2 has been one of the most fun and identifiable games for me since I played it with friends in my childhood, so the inspiration is taken from there.
- The main character is an LF2 mod — LF2 has a very active modding community, so I used it: https://www.lf-empire.de/lfe-fileplanet/characters/303-anti-davis
- Sprite reference: https://www.spriters-resource.com/pc_computer/littlefighter2/
- A new world was turned around and created on top of these to make the current version of the game.

## Background and World Generation Assets

Taken from the artists below:

- Boss Dragon Lord — https://binary-80.itch.io/dragonlord
- Dragon — https://shinobugaen.itch.io/pixel-abyss-lugia
- Environment and music — https://ansimuz.itch.io/magic-cliffs-environment

## Collaborators

- None. This was a solo project.

## Tools and AI Contributions

- Image generation, storyboard panels, and game panels are generated via Google Gemini — https://gemini.google.com/
- The dialogue voice-overs were written by me, but the voices themselves are done via ElevenLabs — https://elevenlabs.io/
- The code was written with Claude Code — https://claude.com/claude-code

### What the AI contributed, area by area

- **The game (code).** Claude Code did the implementation: the player and enemy
  scripts, the level loader, the combat and boss systems, the diagnostics under
  `godot/tests/`, the asset extraction scripts in `scripts/`, the two authoring tools
  in `tools/`, and the documentation. It worked to my direction — I decided what the
  game was, what went in, and what the numbers should be; it wrote and refactored the
  code that did it.
- **The script.** The opening monologue and all dialogue are written by me. The AI's
  contribution to the script was organisational, not authorial: caption timing,
  formatting, and keeping the delivery tags out of the on-screen captions.
- **The beat sheet.** The story beats, the level order, and the hero's-journey
  structure that the four levels follow are mine. Claude Code turned that ordering
  into the level index and the storyboard cue table; Gemini drew the panels for the
  beats I specified.
- **The visuals.** Gemini generated the concept art and the storyboard panels. None
  of the in-game character, enemy or environment art is AI-generated — that all comes
  from the LF2 packs and the itch.io artists credited above.
- **The narration.** My script, performed by an ElevenLabs voice.

## Originally Done by Me

- The game level design and storyboarding are originally done by me.
- The dialogue voice-over writing.
- The decision to integrate the professor's base level game as an LF2-style hack-and-slash platformer, and building the new world around the LF2 characters.
- The two authoring tools in `tools/` — a level editor that draws the real jump arc
  over every gap, and an asset painter that lays out levels on top of the actual
  environment art. I specified both and what they had to show me; Claude Code wrote
  them.

## What I Decided, Checked, Changed, or Rejected

A fuller account, with commits and tests, is in [FRICTIONAL.md](FRICTIONAL.md).

**Decided.**

- To abandon my original concept — a pure platformer about a wind-up toy escaping an
  attic — and rebuild it as an LF2 hack-and-slash platformer.
- To take only part of LF2's moveset: melee, **one** energy blast, and health
  restoration, rather than porting the full set of specials.
- That bosses should work like the original Dark Souls games — a wall you have to beat
  to progress, not an optional encounter.
- The four-level course order, and to put The Climb on it as the last mechanical test
  before the final boss.

**Checked.**

- That scaling the world x2 for the taller character changed units and not feel: time
  to apex is identical either side of the change (0.333 s), and the coyote and
  jump-buffer windows are counted in ticks, so they did not scale.
- That every required gap is actually clearable, using the level editor and
  `scripts/check_levels.py` — both reading their numbers from the same tuning file as
  the game.
- Boss health, battle music and the arena seal, with the diagnostics in
  `godot/tests/`.
- The caption timings, re-marked by ear against the recording rather than inferred.
- The difficulty of every fight, by replaying them.

**Changed.**

- The energy blast cost, from 20 points a shot to 5 — at 20 the bar emptied in five
  blasts and the blast became something to hoard rather than use.
- Added a mana cost in the first place, because spamming the blast key trivialised
  the game.
- Enemy behaviour after watching them walk off cliffs, stand still when I did not
  approach, and give up when I backed away: a drop limit, and an aggro latch that
  starts a fight when I enter range *or* hit them from outside it.
- Section gates, after finding I could simply run past every enemy and skip the
  fights, and again after finding I could snipe from a perch and never be dealt with.
- The boss arena seal margin, from 64 to 24, after the first diagnostic run caught me
  walking back out of a sealed fight.

**Rejected.**

- The Wind-Up Knight concept, and the AI-generated concept art behind it: slow to
  produce and impossible to turn into usable sprites — the two animation sheets are
  not even the same character.
- Level layouts authored by prompting, which came back random, inconsistent, and with
  no relationship to the background art. Replaced with the two tools above.
- A caption-timing pass that matched measured sound to script lines in order. It was
  internally consistent and wrong, because one line spans two segments.
- A boss-music test that compared a track *name* rather than a stream, and so passed
  on a build where the music file was missing entirely.
- Two generated Dragon Lord defeat panels, which were never used in the game. They
  are still in the repository root as `dragon-lorad-defeated-1.jpg` and `-2.jpg`,
  listed here so the count of what was generated matches the count of what shipped.
