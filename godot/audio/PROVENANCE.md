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

The loop that takes over while the dragon is fighting on The Fractured Isles —
`boss_music` in that level file, cued by `current_track()` in
`game/session.gd`. 120 s, 44.1 kHz stereo.

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

## The storyboard clips

`storyboard_scene_1.mp3`, `dragon_fight_start.mp3`, `dragon_fight_end.mp3` and
`dragon_roar.mp3` are all copied in by `scripts/extract_storyboard.py` from
`Assests/Storyboard/`. They are the author's own renders — generated, the same
provenance category as the title screen and the HUD plates, and not
attributable the way the CC0 packs are. See `godot/ui/art/PROVENANCE.md`, which
covers them alongside the pictures they play under.

One thing carries over from there: **where the opening voice-over's background
bed came from is not recorded**, and that is a third thing to clear before
release.
