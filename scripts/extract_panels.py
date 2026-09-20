"""Cuts the overlay panels and the confirm button out of the UI kit in
Assests/Storyboard/game_panels.jpg into ui/art, with a manifest telling hud.gd
where the text goes inside each one.

The sheet is one page of elements on a dark slate grid. Three are used:

  panel_menu   the big runed frame with THE FRACTURED ISLES on its headstone.
               The level select wears this one — it is the front screen and it
               is the only piece with the game's name on it.
  panel_popup  the small stone frame with a cream face. Pause and results wear
               this: an in-game message should not be a full-screen monument.

The kit's buttons are NOT taken. Every one of them has its word baked into the
plate — START, QUIT, OPTIONS — and the confirm button underneath these panels
says four different things depending on what is on screen ("ENTER / RESUME",
"ENTER / NEXT LEVEL"). A plate reading START under the word RESUME is worse
than no plate, so hud.gd draws that button and only borrows the kit's colours.

KEYING. The background is flat slate with a grid ruled over it, and parts of the
stone frames land within 8 of that same colour — so a plain colour key eats
holes in the frames. It is flood filled from the border instead, with a tight
tolerance: only background that is actually CONNECTED to the outside goes, and
anything enclosed by a frame stays whatever colour it happens to be.

SIZES. Each is written at the size it is drawn in physical pixels — design size
x1.5 for the HUD layer x4/3 for a 1280x720 window — so a texture pixel is a
screen pixel there, exactly as the health bars are. See PANEL_SCALE in hud.gd.

Run from walker-jumpman/:
    python scripts/extract_panels.py
    <godot> --path godot --headless --import
"""
import json
import os
from collections import deque

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.normpath(os.path.join(
    HERE, "..", "..", "Assests", "Storyboard", "game_panels.jpg"))
OUT = os.path.normpath(os.path.join(HERE, "..", "godot", "ui", "art"))

# The page's own colours: the flat field, the ruled grid, and the lighter noise
# along their edges. Tolerances are tight on purpose — see KEYING above.
PAGE = [((69, 76, 84), 7), ((45, 49, 60), 13), ((72, 81, 90), 7)]

# box on the sheet, and the width to write it at in physical pixels.
PIECES = {
    # 636 is as wide as it can be and still clear the button: at this
    # aspect it stands 553 tall, which is 276 in design units against the
    # 282 its bottom hangs from. See PANEL_BOTTOM in hud.gd.
    "panel_menu": {"box": (84, 32, 1368, 1148), "width": 636},
    "panel_popup": {"box": (2148, 752, 2668, 1028), "width": 680},
}
# Opaque specks left behind by jpeg noise in the field. Nothing real is smaller.
MIN_ISLAND = 40


def is_page(p):
    for colour, tol in PAGE:
        if (abs(p[0] - colour[0]) <= tol and abs(p[1] - colour[1]) <= tol
                and abs(p[2] - colour[2]) <= tol):
            return True
    return False


def cut_page(img):
    """Clear the page from around the piece, reaching in from the border only."""
    w, h = img.size
    px = list(img.convert("RGB").get_flattened_data())
    alpha = [255] * (w * h)
    seen = bytearray(w * h)
    q = deque()
    for x in range(w):
        for i in (x, (h - 1) * w + x):
            if not seen[i] and is_page(px[i]):
                seen[i] = 1
                q.append(i)
    for y in range(h):
        for i in (y * w, y * w + w - 1):
            if not seen[i] and is_page(px[i]):
                seen[i] = 1
                q.append(i)
    while q:
        i = q.popleft()
        alpha[i] = 0
        x, y = i % w, i // w
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h:
                j = ny * w + nx
                if not seen[j] and is_page(px[j]):
                    seen[j] = 1
                    q.append(j)
    return px, alpha


def drop_specks(alpha, w, h):
    """Opaque islands too small to be art — jpeg noise the flood fill stepped
    around — cleared so the piece does not carry a halo of dots."""
    seen = bytearray(w * h)
    cleared = 0
    for start in range(w * h):
        if alpha[start] == 0 or seen[start]:
            continue
        q = deque([start])
        seen[start] = 1
        island = [start]
        while q:
            i = q.popleft()
            x, y = i % w, i // w
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < w and 0 <= ny < h:
                    j = ny * w + nx
                    if alpha[j] != 0 and not seen[j]:
                        seen[j] = 1
                        q.append(j)
                        island.append(j)
        if len(island) < MIN_ISLAND:
            for i in island:
                alpha[i] = 0
            cleared += 1
    return cleared


def faces(img):
    """Where the writing goes. `interior` is everything inside the frame, and
    `text_box` the pale panel within it — on the menu panel those differ,
    because its interior is parchment with a smaller card laid on top."""
    w, h = img.size
    px = img.convert("RGB").load()
    floor = int(h * 0.22)      # under the headstone, which is pale too

    def bounds(test):
        cols = [0] * w
        rows = [0] * h
        for y in range(floor, h):
            for x in range(w):
                if test(px[x, y]):
                    cols[x] += 1
                    rows[y] += 1
        xs = [x for x in range(w) if cols[x] > (h - floor) * 0.12]
        ys = [y for y in range(h) if rows[y] > w * 0.20]
        if not xs or not ys:
            return None
        return [round(xs[0] / w, 4), round(ys[0] / h, 4),
                round(xs[-1] / w, 4), round(ys[-1] / h, 4)]

    pale = bounds(lambda p: p[0] > 195 and p[1] > 185 and p[2] > 150
                  and p[0] - p[2] < 70)
    warm = bounds(lambda p: (p[0] > 130 and p[0] - p[2] > 45)
                  or (p[0] > 195 and p[1] > 185 and p[2] > 150))
    return warm or pale, pale or warm


def main():
    sheet = Image.open(SOURCE)
    os.makedirs(OUT, exist_ok=True)
    manifest = {}
    for name, spec in PIECES.items():
        crop = sheet.crop(spec["box"])
        w, h = crop.size
        px, alpha = cut_page(crop)
        specks = drop_specks(alpha, w, h)
        rgba = Image.new("RGBA", (w, h))
        rgba.putdata([(px[i][0], px[i][1], px[i][2], alpha[i])
                      for i in range(w * h)])
        rgba = rgba.crop(rgba.getbbox())

        interior, text_box = faces(rgba)
        out_w = spec["width"]
        out_h = round(rgba.height * out_w / rgba.width)
        final = rgba.resize((out_w, out_h), Image.LANCZOS)
        final.save(os.path.join(OUT, name + ".png"))
        manifest[name] = {
            "file": name + ".png",
            "size": [out_w, out_h],
            "interior": interior,
            "text_box": text_box,
        }
        print("%-12s %4dx%-4d -> %3dx%-3d  specks %-3d interior %s text_box %s"
              % (name, w, h, out_w, out_h, specks, interior, text_box))

    with open(os.path.join(OUT, "panels.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=1, sort_keys=True)
        fh.write(chr(10))
    print("manifest -> %s" % os.path.join(OUT, "panels.json"))


if __name__ == "__main__":
    main()
