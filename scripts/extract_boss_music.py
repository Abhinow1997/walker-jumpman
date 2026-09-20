"""Takes the boss-fight music into godot/audio/.

    python scripts/extract_boss_music.py
    <godot> --path godot --headless --import

Source: "Assests/xDeviruchi - Decisive Battle.wav", added by the author on
2026-09-20. It plays for as long as the dragon is fighting on The Fractured
Isles - see `boss_music` in that level file and current_track() in
game/session.gd - and the level's own Magic Cliffs loop comes back when the
body is gone.

A COPY, not a conversion, and that is not the preferred state. The source is
120 s of 44.1 kHz stereo 16-bit PCM, which is 21 MB; the Magic Cliffs loop
beside it is 96 s of Ogg Vorbis in 2.3 MB. There is no Vorbis encoder on this
machine - no ffmpeg, no oggenc, no soundfile - so the wav is copied as it is
rather than degraded to something a stdlib `wave` writer can produce. One
command fixes it when an encoder is to hand:

    ffmpeg -i "Assests/xDeviruchi - Decisive Battle.wav" -q:a 5 \\
        godot/audio/decisive_battle.ogg

and nothing else has to change: game/music.gd looks for the .ogg first and
falls back to the .wav, and this script deletes the wav once the ogg is there.

The header is checked rather than trusted. A replaced file at a different rate
or channel count still plays, so nothing would fail - it would just quietly
sound wrong under the mix, which is the sort of thing that is noticed a week
later.

LICENCE. xDeviruchi publishes chiptune packs for game use and this track is
from one of them, but the file arrived here on its own with no readme, no
licence and no pack around it. Several of those packs are free with attribution
and at least one is CC0; which this is has NOT been established. It goes in the
credits alongside the other unresolved items - see godot/audio/PROVENANCE.md.
"""
import os
import shutil
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.normpath(os.path.join(
    HERE, "..", "..", "Assests", "xDeviruchi - Decisive Battle.wav"))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "godot", "audio"))
OUT = "decisive_battle"

# What the source is, and what a replacement has to be. Rate and channels
# because the mix is set against them; the length bound because a boss track
# that turned out to be a four-second sting would loop audibly under a fight
# that runs minutes.
RATE = 44100
CHANNELS = 2
WIDTH = 2
MIN_SECONDS = 30.0


def main():
    if not os.path.isfile(SOURCE):
        raise SystemExit("boss music not found at %s" % SOURCE)
    with wave.open(SOURCE) as clip:
        rate = clip.getframerate()
        channels = clip.getnchannels()
        width = clip.getsampwidth()
        seconds = clip.getnframes() / float(rate)
    if (rate, channels, width) != (RATE, CHANNELS, WIDTH):
        raise SystemExit(
            "%s is %d Hz, %d channel(s), %d-bit; the game is mixed against "
            "%d Hz stereo 16-bit. Re-render it, or change the constants here "
            "on purpose." % (os.path.basename(SOURCE), rate, channels,
                             width * 8, RATE, WIDTH * 8))
    if seconds < MIN_SECONDS:
        raise SystemExit(
            "%s is only %.1f s. A boss loop shorter than %.0f s repeats "
            "audibly under a fight." % (os.path.basename(SOURCE), seconds,
                                        MIN_SECONDS))

    os.makedirs(OUT_DIR, exist_ok=True)
    ogg = os.path.join(OUT_DIR, OUT + ".ogg")
    wav = os.path.join(OUT_DIR, OUT + ".wav")
    if os.path.isfile(ogg):
        # Somebody ran the ffmpeg line in the header. The wav is then dead
        # weight - music.gd would never look at it again.
        if os.path.isfile(wav):
            os.remove(wav)
            print("removed the wav: %s.ogg is there and music.gd prefers it" % OUT)
        print("%-30s %.1f s already encoded -> %s.ogg"
              % (os.path.basename(SOURCE), seconds, OUT))
        return
    shutil.copyfile(SOURCE, wav)
    print("%-30s %.1f s  %d Hz stereo -> %s.wav  (%.1f MB)"
          % (os.path.basename(SOURCE), seconds, rate, OUT,
             os.path.getsize(wav) / 1048576.0))
    print("     ogg it when an encoder is to hand - see the header of this file")


if __name__ == "__main__":
    main()
