# Audio — provenance

Every sound file in `godot/audio/`, where it came from and whether it can ship.
The art has one of these per folder; this is the one for the ears.

## magic_cliffs.ogg

| | |
|---|---|
| Script | `scripts/extract_magic_cliffs.py` |
| Source | `Assests/Magic-Cliffs-Gamekit/Assets/magic cliffs music/magic cliffs.ogg` |
| Origin | **CC0** — Magic Cliffs Environment by Ansimuz (Luis Zuno). Public domain, commercial use, no attribution required. |

The 96-second loop the pack ships. The title screen, First Steps, The Fractured
Isles and The Dragon's Roost all name it, which is what makes NEW JOURNEY
seamless — see `game/music.gd`. **The only piece of audio here with a settled
licence.**

## decisive_battle.wav

| | |
|---|---|
| Script | `scripts/extract_boss_music.py` |
| Source | `Assests/xDeviruchi - Decisive Battle.wav`, added by the author 2026-09-20 |
| Origin | **Not established.** See Rights below. |

The loop that takes over while the dragon is fighting — `boss_music` on The
Fractured Isles, cued by `current_track()` in `game/session.gd`. 120 s,
44.1 kHz stereo.

**It is not in this repository, and that is a bug in this table rather than a
choice.** `.gitignore` ignores `*.wav` and grants no exception for
`godot/audio/` the way it does one line earlier for `*.mp3`, so only the
`.import` beside it was ever committed; `Assests/` is outside the clone, so
`extract_boss_music.py` cannot put it back on a fresh machine either. What a
clone gets is `music.gd` warning and leaving the coast loop playing under both
boss fights. The Dragon's Roost has been moved onto `dragon_lord_fight.mp3`
below as a stand-in; The Fractured Isles still names this and is still silent
of a battle track without it. Producing the `.ogg` with the command below
fixes both and needs no `.gitignore` change — `.ogg` is deliberately not
ignored.

**It plays 8 dB above the other tracks**, and that is a mastering difference
rather than a preference. Its file peaks at -2.0 dBFS and averages -14.9; the
Magic Cliffs loop is cut far hotter, so at one shared fader the battle track
came out of the bus 3 dB *under* a loop that is deliberately well back, and
under the fight's own roars and blasts it was reported inaudible. The trim is
`TRIM` in `game/music.gd` and it is keyed by track, because the reason for it
belongs to this recording and not to either level that plays it. Measured with
`tests/diag_music_levels.gd`, which taps the master bus: with the trim the
battle track averages -20.0 dBFS out against the coast loop's -25.0, and its
loudest sample is -6.0, so there is nothing near clipping.

**It is a wav and it should be an ogg.** 20 MB against the 2.3 MB the Magic
Cliffs loop costs for a comparable length. There is no Vorbis encoder on the
machine it was added on — no ffmpeg, no oggenc, no `soundfile` — and degrading
it to something Python's stdlib `wave` can write would be worse than the file
size. One command fixes it:

```
ffmpeg -i "Assests/xDeviruchi - Decisive Battle.wav" -q:a 5 \
    godot/audio/decisive_battle.ogg
```

and nothing else changes: `music.gd` looks for the `.ogg` first, and the
extractor deletes the wav once the ogg is beside it. Godot's importer already
compresses the wav to 4.1 MB of QOA for the build, so what ships is not as bad
as what is checked in.

### Rights

xDeviruchi publishes chiptune packs for game use, and this track is from one of
them. **The file arrived here on its own** — no readme, no licence, no pack
around it. Several of those packs are free with attribution and at least one is
CC0; which this one is has not been established, and "probably fine" is not a
licence. It goes on the credits screen with the other unresolved items and it
is on the release checklist beside the LF2 sprites and the dragon pack.

## dragon_lord_fight.mp3

A storyboard clip — see below — doing a second job. It is the audio under The
Dragon's Roost's two walk-in panels, and since the wav above went missing it is
also that level's `boss_music`. ~22 s, 128 kbps, and `music.gd` loops it
(`AudioStreamMP3.loop`, set by the caller because the `.import` has
`loop=false` for its one-shot use).

**This is a stand-in and it should be replaced.** It is speech with a bed under
it, not a battle theme; it is a fifth the length of the track it replaced; and
the player hears it as dialogue in the cutscene immediately before the fight
loops it. Its `TRIM` entry is `0.0` because nobody has measured it — the `+8`
above belongs to the xDeviruchi master and not to this render. Point
`boss_music` in `godot/levels/dragons_roost.json` back at `decisive_battle`
once that file exists.

## The storyboard clips

`storyboard_scene_1.mp3`, `dragon_fight_start.mp3`, `dragon_fight_end.mp3`,
`dragon_lord_fight.mp3` and
`dragon_roar.mp3` are all copied in by `scripts/extract_storyboard.py` from
`Assests/Storyboard/`. They are the author's own renders — generated, the same
provenance category as the title screen and the HUD plates, and not
attributable the way the CC0 packs are. See `godot/ui/art/PROVENANCE.md`, which
covers them alongside the pictures they play under.

One thing carries over from there: **where the opening voice-over's background
bed came from is not recorded**, and that is a third thing to clear before
release.
