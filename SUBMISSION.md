# Submission — Assignment 1: Extend Walker Jumpman

| Field | Value |
|---|---|
| **Assignment** | Assignment 1 — Extend Walker Jumpman |
| **Student** | Abhinow1997 |
| **Project name** | The Fractured Isles |
| **GitHub repository/folder URL** | https://github.com/Abhinow1997/walker-jumpman |
| **Submitted commit SHA** | `d8f4213c9c1b4ddd21b7375d33cbed59ff062aaf` |
| **Game-source revision shown in the film** | `80fad64eb95810eba8f8068d21277c29cbf6ddc5` |
| **Godot version and operating system** | Godot 4.7.2 stable (official, build `ed1daf0bf`), GL Compatibility renderer · Windows 11 Enterprise 10.0.26100 |
| **Final film URL and filename** | [Gameplay recording on Northeastern SharePoint](https://northeastern-my.sharepoint.com/:v:/g/personal/gangurde_a_northeastern_edu/IQDO9wMrkFdCTZviPp21xJroAfd-io9MefBzNcI4GRw95o4?e=jQvlwQ) · `Screen Recording 2026-09-24 203056.mp4` (577,994,095 bytes) |
| **Final film SHA-256** | `f56bd17bbe9299d29545c815741c62b72b1c1e8cb3bda8353a0b642a674fbdf1` |

### On the two revisions above

They differ, and the difference is only documentation. `80fad64` is the last commit to
touch `godot/`, and the film was recorded after it. Every commit between `80fad64` and
the submitted `d8f4213` changes `README.md`, `.gitignore` and one screenshot and nothing
else, so the game source in the film is byte-identical to the game source being
submitted. Verifiable with:

```bash
git diff --name-only 80fad64 d8f4213 -- godot/
```

That command prints nothing. This file was added in the commit after `d8f4213` and
changes nothing but itself.

## Summary of my changes

The starter was a one-screen walk-and-jump demo. It is now **The Fractured Isles**, a
Little Fighter 2–style hack-and-slash crossed with a platformer, played start to finish.

**Combat, which the original had none of.** Melee with a punch that chains into a cross,
a kick in the air, and a shoulder charge at a run. An energy blast that costs mana and
can be thrown in mid-air. Crates, rocks and bottles that can be lifted, thrown, or drunk
for health.

**Five enemy kinds and two boss fights.** One script
([`features/combat/enemy.gd`](godot/features/combat/enemy.gd)) drives all of them off a
`PROFILES` table rather than a shared chase: a `bandit` charger who commits a fast dash
from mid-range, a `mark` bruiser with super-armour on his own swing so you cannot trade
jabs and win, and a `hunter` archer who kites backwards and looses arrows across the gap.
The `dragon` and the `dragon_lord` are the bosses, each with its own health plate. The
dragon fights in two phases, cruising and swooping in the air before landing to fight on
its feet. The Dragon's Roost fights both bosses at once — where the plate's two bars stop
being one number at two speeds and become one boss each.

**Four levels, authored as data.** `First Steps`, `The Fractured Isles`, `The Climb` and
`The Dragon's Roost` are JSON in `godot/levels/`, loaded by a single session scene. The
Climb is one screen wide and seven tall; the Roost is a single arena. Two purpose-built
HTML authoring tools in `tools/` replaced hand-writing the layouts.

**A story that runs through the game.** A four-panel opening storyboard with recorded
narration and captions timed against the audio in `godot/ui/captions.json`, plus story
cards bracketing the dragon fight, opening The Climb, introducing the Dragon Lord, and
an end card.

**Music and HUD.** Per-level tracks with separate boss music, health and mana bars, level
captions, a death screen and a level menu.

**A recorded test suite.** 4 assertion suites, 24 diagnostics and 27 capture scripts in
`godot/tests/`, writing timestamped JSON evidence — see [TEST-REPORT.md](TEST-REPORT.md).
Design and process records are in [GAME-BRIEF.md](GAME-BRIEF.md),
[CHANGE-BREIF.md](CHANGE-BREIF.md), [GDD.md](GDD.md) and [FRICTIONAL.md](FRICTIONAL.md).

## Known limitations

Recorded honestly rather than left for discovery.

**Bugs**

- **The title screen prints the wrong key.** The hint reads "SPACE: Confirm", but
  `confirm` is bound to Enter alone and [title.gd](godot/ui/title.gd) tests only
  `confirm`. Space does nothing on the first screen of the game. Use Enter.
- **`capture_storyboard.gd` does not complete.** The storyboard node is freed mid-run
  (`Lambda capture at index 0 was freed`, then `panel 2: dissolve not photographed`), so
  it produces 2 of roughly 10 shots. The README's gameplay screenshot was removed because
  it could not be regenerated.
- **`capture_title.gd` trips an assertion** at line 44: `PRACTICE duplicates NEW JOURNEY
  at first_steps`. The PNGs are written before it fires, so the capture is still usable.
- **A caption typo ships in the game.** `the_climb.json` reads "Its running away! I need
  to follow it and only way off these floating isles is up." — missing an apostrophe and
  a "the".

**Testing**

- One check in the combat suite is intermittent; see §3 of
  [TEST-REPORT.md](TEST-REPORT.md). The latest recorded run is 482 checks, 482 passing.
- No movement or keyboard suite output is retained at this build; both need re-running.
- No human playtesting. Every balance decision was made by one player, its author.

**Distribution and access**

- **No packaged build.** Source only, run from Godot as described in the README. No Web
  export.
- `evidence/` is excluded by `.gitignore`, so captures and timestamped reports are not in
  the repository. They regenerate from `godot/tests/capture_*.gd`. The one exception is
  the README's title screenshot, which is tracked deliberately.
- **The film link requires a Northeastern sign-in** and will not play for an anonymous
  visitor.
- **Not releasable.** The character and enemy art is Little Fighter 2 fan content used
  without a distribution licence. See [SOURCES.md](SOURCES.md) for full credits.
