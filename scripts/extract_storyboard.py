"""Takes the storyboard art and audio in Assests/Storyboard into the game.

Two kinds of picture come through here, and both are written at 960 x 540 — the
viewport, which is also what title_bg.png is authored at. Drawn 1:1 there, a
panel is not resampled at all; the window's 4/3 magnification then treats it
exactly as it treats the title backdrop, so the storyboard and the screen it
cuts to are the same picture quality. Anything else would show, because these
are full-frame images with fine cloud and grass detail.

PANELS is the cold open: the isles themselves with the sea coming in, then he is
asleep on the ledge, the screech wakes him, he runs for the gap. They play over
the merged voice-over before NEW JOURNEY hands off to the first level.

Panel 0 is the establishing shot and the only one he is not in, which is why it
is the one the opening fades up onto: there is no character to read yet, so the
picture can arrive out of black without anything being missed while it does.

The opening sources are 2730 x 1536, which is 16:9 to within half a pixel of
height, so the fit is a plain resize with no crop and no letterbox.

CARDS is a panel that interrupts a LEVEL instead of replacing it — the standoff
before the dragon and the shot of it leaving. THESE ARE CROPPED, and that is the
one judgement call in this file. Their sources are 2048 x 1536, which is 4:3,
and they are drawn full-screen at 16:9, so a quarter of the height has to go.
Which quarter is a per-card number, because the two pictures are composed
differently — the dragon is sitting on the grass in one and airborne in the
other — and a centred crop that suits the first clips the second's wingtips.
The numbers are in CARDS with what each one is protecting.

Neither kind is pixel art despite looking like it: the column-to-column
differences show no grid at any step from 2 to 16, so there is no native
resolution to snap to, LANCZOS is the right reduction, and the game draws them
under a LINEAR filter.

AUDIO is copied rather than referenced, because res:// cannot reach outside the
project. Two of the clips are the voice over the two cards and the game holds
the picture until each one is out, so re-render one longer and the card simply
holds longer — nothing here or in session.gd has a duration written in it.

Run from walker-jumpman/:
    python scripts/extract_storyboard.py
    <godot> --path godot --headless --import
"""
import os
import shutil

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.normpath(os.path.join(
    HERE, "..", "..", "Assests", "Storyboard"))
OUT = os.path.normpath(os.path.join(
    HERE, "..", "godot", "ui", "art", "storyboard"))
AUDIO_OUT = os.path.normpath(os.path.join(HERE, "..", "godot", "audio"))

# The viewport, and title_bg.png's size. Everything is drawn at this.
CANVAS = (960, 540)

# source file -> written name. The order is the order they play; storyboard.gd
# holds the times, not this script.
PANELS = [
    ("panel 0.jpg", "panel_0.png"),
    ("panel 1.jpg", "panel_1.png"),
    ("panel 2.jpg", "panel_2.png"),
    ("panel 3.jpg", "panel_3.png"),
]

# The in-level cards: source file -> written name -> the top row of the 16:9
# band taken out of it. A level names one in its own "cutscene" block by the
# written name without its extension, so adding a card here and an entry to a
# level file is the whole of putting another one in the game.
#
# Both sources are 2048 x 1536, so the band is 1152 tall and there are 384 rows
# to give away. Where they come from is chosen per card and not centred by
# default:
#
#   start, 192 (centred).  The dragon is sitting on the grass in the middle of
#     the frame and the mountains run along behind it, so the picture is
#     balanced already: half off the top loses cloud and the tip of the tall
#     floating tower, half off the bottom loses the character below the chest.
#     Bottom-aligned reads better as a standoff but cuts the mountain peaks,
#     which looks like a mistake rather than a frame.
#
#   end, 0 (top-aligned).  This one is the dragon AIRBORNE with its wings out,
#     and they reach within 150 px of the top edge. Anything off the top clips
#     them; 96 already has the wingtips touching the frame. Taken off the
#     bottom instead, which is grass and the back of the character's head — he
#     is watching it go and does not need to be more than a silhouette.
# The two Dragon Lord panels are the exception: they are drawn ~1.79 (a touch
# WIDER than 16:9) rather than 4:3, so there is no tall band to take. write_card
# trims their WIDTH instead, centred, and the `top` below is unused for them —
# both characters sit dead centre of the frame, so there is nothing to choose.
#
#   climb_start, 0.  A third shape again: 2730 x 1536, the opening panels'
#     size, which is 16:9 to within half a pixel. write_card's band works out
#     at 1536 of a 1536-tall source, so the only legal `top` is 0 and nothing
#     is cropped at all — it takes the plain-resize path that write_panel
#     would, and sits here rather than in PANELS because it interrupts a level
#     instead of playing in the cold open.
#
#   dragon_lord_defeated_1 and _2, 0.  Same 2730 x 1536 as climb_start and for
#     the same reason: nothing is cropped and `top` is unused. They are the two
#     panels after the Roost's fight — the Lord swearing he will be back, and
#     the Warden answering him — and the second is drawn twice, because the
#     thank-you card that follows reuses its picture rather than having one of
#     its own. See the cutscene block in levels/dragons_roost.json.
CARDS = [
    ("dragon-fight-start.jpg", "dragon_fight_start.png", 192),
    ("dragon-fight-end.jpg", "dragon_fight_end.png", 0),
    ("dragon-lord-fight-start.jpg", "dragon_lord_fight_start.png", 0),
    ("dragon-lord-fight-start-2.jpg", "dragon_lord_fight_start_2.png", 0),
    ("climb-storyboard.jpg", "climb_start.png", 0),
    ("dragon-lorad-defeated-1.jpg", "dragon_lord_defeated_1.png", 0),
    ("dragon-lorad-defeated-2.jpg", "dragon_lord_defeated_2.png", 0),
]

# source file -> written name in godot/audio/. Named for what plays them:
# a level's cutscene entry names a clip the same way it names a panel. The
# Dragon Lord source is spelled "dargon" — a typo in the delivered file, fixed
# on the way in.
AUDIO = [
    ("merged_audio_1789861876055.mp3", "storyboard_scene_1.mp3"),
    ("dragon fight start scene.mp3", "dragon_fight_start.mp3"),
    ("dragon-fight-endscene.mp3", "dragon_fight_end.mp3"),
    ("dragon-voice-angry-growl.mp3", "dragon_roar.mp3"),
    ("dargon-lord-fight.mp3", "dragon_lord_fight.mp3"),
    ("climb-background.mp3", "climb_start.mp3"),
    ("final-fight-background.mp3", "dragon_lord_defeated.mp3"),
]

# How far from its target shape a source may be before this stops. A panel
# regenerated at 4:3 when the game draws it 16:9 would silently stretch on
# screen, and the storyboard is the first thing a new player sees.
ASPECT_TOLERANCE = 0.01
WIDE = CANVAS[0] / CANVAS[1]


def open_source(source_name):
    path = os.path.join(SOURCE, source_name)
    if not os.path.exists(path):
        raise SystemExit("missing panel: %s" % path)
    img = Image.open(path).convert("RGB")
    if img.width < CANVAS[0]:
        raise SystemExit(
            "%s is %d wide, narrower than the %d it is drawn at: it would "
            "be upscaled." % (source_name, img.width, CANVAS[0]))
    return img


def write_panel(source_name, out_name):
    """One opening panel: already 16:9, so a plain resize."""
    img = open_source(source_name)
    aspect = img.width / img.height
    if abs(aspect - WIDE) > ASPECT_TOLERANCE:
        raise SystemExit(
            "%s is %dx%d (aspect %.4f); the opening draws full-frame 16:9 "
            "(%.4f). Re-crop it, or move it to CARDS, which crops."
            % (source_name, img.width, img.height, aspect, WIDE))
    img.resize(CANVAS, Image.LANCZOS).save(os.path.join(OUT, out_name))
    print("%-26s %4dx%-4d          -> %dx%d  %s"
          % (source_name, img.width, img.height, CANVAS[0], CANVAS[1], out_name))


def write_card(source_name, out_name, top):
    """One in-level card, cropped to 16:9 then resized.

    A source TALLER than 16:9 (the 4:3 dragon cards) gives a horizontal band
    taken from row `top` — see CARDS for why each sits where it does. A source
    already WIDER than 16:9 (the Dragon Lord panels, ~1.79) is trimmed to width
    instead, centred, and `top` is unused: there is no vertical choice to make.
    Either way the result is exactly 16:9 and resized 1:1 with no stretch.
    """
    img = open_source(source_name)
    aspect = img.width / img.height
    if aspect > WIDE:
        keep = int(round(img.height * WIDE))
        left = (img.width - keep) // 2
        cut = img.crop((left, 0, left + keep, img.height))
        how = "wide %d@%d" % (keep, left)
    else:
        band = int(round(img.width / WIDE))
        if band > img.height:
            raise SystemExit(
                "%s is %dx%d and a 16:9 band of it would be %d tall, which is "
                "taller than the source. It cannot be shown full-screen without "
                "upscaling." % (source_name, img.width, img.height, band))
        if not 0 <= top <= img.height - band:
            raise SystemExit(
                "%s: a band of %d from row %d runs off a %d-tall source. The "
                "crop has to sit inside it — see CARDS."
                % (source_name, band, top, img.height))
        cut = img.crop((0, top, img.width, top + band))
        how = "band %d@%d" % (band, top)
    cut.resize(CANVAS, Image.LANCZOS).save(os.path.join(OUT, out_name))
    print("%-30s %4dx%-4d  %-13s -> %dx%d  %s"
          % (source_name, img.width, img.height, how, CANVAS[0], CANVAS[1], out_name))


def copy_audio(source_name, out_name):
    """One clip into godot/audio/, skipped when it is already the same file.

    Skipped rather than always written because overwriting reimports, and a
    reimport of the opening's voice-over would churn a file the caption times
    in ui/captions.json are measured against.
    """
    path = os.path.join(SOURCE, source_name)
    if not os.path.exists(path):
        raise SystemExit("missing audio: %s" % path)
    target = os.path.join(AUDIO_OUT, out_name)
    if os.path.exists(target) and os.path.getsize(target) == os.path.getsize(path):
        with open(path, "rb") as a, open(target, "rb") as b:
            if a.read() == b.read():
                print("%-36s -> %-26s unchanged" % (source_name, out_name))
                return
    shutil.copyfile(path, target)
    print("%-36s -> %-26s %d KB"
          % (source_name, out_name, os.path.getsize(path) // 1024))


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(AUDIO_OUT, exist_ok=True)
    for source_name, out_name in PANELS:
        write_panel(source_name, out_name)
    for source_name, out_name, top in CARDS:
        write_card(source_name, out_name, top)
    for source_name, out_name in AUDIO:
        copy_audio(source_name, out_name)


if __name__ == "__main__":
    main()
