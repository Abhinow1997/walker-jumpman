"""Resizes the three opening-storyboard panels in Assests/Storyboard into
ui/art/storyboard at the exact size storyboard.gd draws them.

The panels are the cold open: the isles themselves with the sea coming in, then
he is asleep on the ledge, the screech wakes him, he runs for the gap. They play
over the merged voice-over before NEW JOURNEY hands off to the first level.

Panel 0 is the establishing shot and the only one he is not in, which is why it
is the one the opening fades up onto: there is no character to read yet, so the
picture can arrive out of black without anything being missed while it does.

SIZE. Each is written at 960 x 540 — the viewport, which is also what
title_bg.png is authored at. Drawn 1:1 there, the panel is not resampled at all
under the project's nearest-neighbour filter; the window's 4/3 magnification
then treats it exactly as it treats the title backdrop, so the storyboard and
the screen it cuts to are the same picture quality. Anything else here would
show, because these are full-frame images with fine cloud and grass detail.

The sources are 2730 x 1536, which is 16:9 to within half a pixel of height, so
the fit is a plain resize with no crop and no letterbox.

Run from walker-jumpman/:
    python scripts/extract_storyboard.py
    <godot> --path godot --headless --import
"""
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.normpath(os.path.join(
    HERE, "..", "..", "Assests", "Storyboard"))
OUT = os.path.normpath(os.path.join(
    HERE, "..", "godot", "ui", "art", "storyboard"))

# The viewport, and title_bg.png's size. See SIZE above.
CANVAS = (960, 540)

# source file -> written name. The order is the order they play; storyboard.gd
# holds the times, not this script.
PANELS = [
    ("panel 0.jpg", "panel_0.png"),
    ("panel 1.jpg", "panel_1.png"),
    ("panel 2.jpg", "panel_2.png"),
    ("panel 3.jpg", "panel_3.png"),
]

# How far from 16:9 a source may be before this stops. A panel regenerated at
# 4:3 or 1:1 would silently letterbox or stretch on screen, and the storyboard
# is the first thing a new player sees.
ASPECT = CANVAS[0] / CANVAS[1]
ASPECT_TOLERANCE = 0.01


def main():
    os.makedirs(OUT, exist_ok=True)
    for source_name, out_name in PANELS:
        path = os.path.join(SOURCE, source_name)
        if not os.path.exists(path):
            raise SystemExit("missing panel: %s" % path)
        img = Image.open(path).convert("RGB")
        aspect = img.width / img.height
        if abs(aspect - ASPECT) > ASPECT_TOLERANCE:
            raise SystemExit(
                "%s is %dx%d (aspect %.4f); the storyboard draws full-frame "
                "16:9 (%.4f). Re-crop the panel or change CANVAS."
                % (source_name, img.width, img.height, aspect, ASPECT))
        if img.width < CANVAS[0]:
            raise SystemExit(
                "%s is %d wide, narrower than the %d it is drawn at: it would "
                "be upscaled." % (source_name, img.width, CANVAS[0]))
        final = img.resize(CANVAS, Image.LANCZOS)
        final.save(os.path.join(OUT, out_name))
        print("%-12s %4dx%-4d -> %dx%d  %s"
              % (source_name, img.width, img.height, CANVAS[0], CANVAS[1],
                 out_name))


if __name__ == "__main__":
    main()
