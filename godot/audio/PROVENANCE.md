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
seamless — see `game/music.gd`. **Settled licence**, as is the boss track
below; the storyboard clips are the ones still outstanding.

## decisive_battle.wav

| | |
|---|---|
| Script | `scripts/extract_boss_music.py` |
| Source | `xDeviruchi - Decisive Battle.wav`, track 9 of *xDeviruchi — 8-Bit Fantasy & Adventure Music (2021)* |
| Origin | **CC BY-SA 4.0** — Marllon Silva (xDeviruchi). Commercial use permitted. Attribution requested, not required. |

The loop that takes over while the dragon is fighting — `boss_music` on both
The Fractured Isles and The Dragon's Roost, cued by `current_track()` in
`game/session.gd`. 120 s, 44.1 kHz stereo. One battle theme for the game: the
Dragon Lord is the last boss on the same coast and he fights to the same track
the dragon does.

**It went missing from the repository once and is now tracked.** `.gitignore`
ignored `*.wav` and granted no exception for `godot/audio/` the way it does one
line earlier for `*.mp3`, so only the `.import` beside it was ever committed.
Every clone therefore reached **both** boss fights with no battle track at all
— and not even the coast loop, because `ResourceLoader.exists()` is satisfied
by the `.import` alone, so `cue()` got past its guard, `load()` returned null
and that null was assigned: the fights ran in silence. `tests/diag_battle_music.gd`
printed `stream=<none> playing=false` across the whole fight. The test suite
missed it because `the-fight-brings-its-own-track-in` compared the track NAME
and nothing else, and the name was set on a player with no stream.

Three things changed as a result, and all three matter more than the file
coming back: `!godot/audio/*.wav` now excepts it, `cue()` leaves the current
track playing when a load fails instead of assigning null, and it clears the
name so the test compares something real.

**The loop turns at 116.033 s, not at the end of the file.** The pack is built
Intro / Loop / End and ships the points in *READ THIS FIRST.pdf*, Tables 1 and
2; Decisive Battle is "Loop, End", beginning 0, final 116.033. The last four
seconds of the 120.18 s file are a closing tag meant to finish the piece, not
to run back into the top of it. `LOOP_END` in `game/music.gd` holds the number.

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
ffmpeg -i "xDeviruchi - Decisive Battle.wav" -q:a 5 \
    godot/audio/decisive_battle.ogg
```

and nothing else changes: `music.gd` looks for the `.ogg` first, and the
extractor deletes the wav once the ogg is beside it. Godot's importer already
compresses the wav to 4.1 MB of QOA for the build, so what ships is not as bad
as what is checked in. Doing this also lets `!godot/audio/*.wav` come back out
of `.gitignore` — the exception exists only because the wav is currently the
only copy there is.

### Rights

**Settled.** This was an open release-blocker for as long as the file had
arrived on its own — no readme, no licence, no pack around it — and "probably
fine" is not a licence. The pack it came from has since been produced intact,
and its manual (*READ THIS FIRST.pdf*, §2 Licensing and copyright) says so
directly: every file in *8-Bit Fantasy & Adventure Music (2021)* is released
under **Attribution-ShareAlike 4.0 International**, usable in commercial and
non-commercial projects alike. The one prohibition is redistributing the music
*as music* — hosting the files for download, or reselling them as an OST —
which is not what shipping a game that plays them is.

Credits are explicitly **not mandatory**; the author asks for one line and
would like it. Take him up on it:

> music by Marllon Silva (a.k.a) xDeviruchi

Struck off the release checklist. The LF2 sprites and the dragon pack are
still on it.

## The storyboard clips

`storyboard_scene_1.mp3`, `dragon_fight_start.mp3`, `dragon_fight_end.mp3`,
`dragon_lord_fight.mp3` and `dragon_roar.mp3` are all copied in by `scripts/extract_storyboard.py` from
`Assests/Storyboard/`. They are the author's own renders — generated, the same
provenance category as the title screen and the HUD plates, and not
attributable the way the CC0 packs are. See `godot/ui/art/PROVENANCE.md`, which
covers them alongside the pictures they play under.

One thing carries over from there: **where the opening voice-over's background
bed came from is not recorded**, and that is a third thing to clear before
release.
