"""Cuts the overlay panels and the buttons out of the UI kit in
Assests/Storyboard/game_panels.jpg into ui/art, with a manifest telling hud.gd
where the text goes inside each one.

The sheet is one page of elements on a dark slate grid. Three are used:

  panel_menu   the big runed frame with THE FRACTURED ISLES on its headstone.
               The level select wears this one — it is the front screen and it
               is the only piece with the game's name on it.
  panel_popup  the small stone frame with a cream face. Pause and results wear
               this: an in-game message should not be a full-screen monument.

THE BUTTONS ARE TAKEN NOW, with their words lifted off. Every one on the sheet
has a word baked into it — START, QUIT, OPTIONS — and the game's confirm button
says four different things depending on what is on screen ("ENTER / RESUME",
"ENTER / NEXT LEVEL"), so for a long time hud.gd drew a flat rectangle in the
kit's colours instead. That was the wrong trade: a painted plate with a bevel,
a rounded frame and a shaded face is most of what makes this UI look like a
game, and the word is the easy part to replace.

So the word is ERASED and the plate kept. It is found rather than measured —
the letters are near-white against a face that is not, so the light pixels
inside the frame are the word, and their box grown by the outline is what gets
painted over. Each row of that box is refilled with the median of the same
row's face OUTSIDE it, which keeps the top-to-bottom shading the plate is
drawn with; a flat fill would flatten the bevel.

They are written with a CAP, the width of the rounded end, so hud.gd can draw
one at any width in three slices — left cap, stretched middle, right cap — and
the corners never distort. Their height is fixed, which is what a button of a
fixed height in a 640x360 design space wants.

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
# The plates at the bottom right of the sheet, and the width each is written
# at in physical pixels. 236 is the size the kit draws them, so nothing is
# resampled: at PANEL_SCALE they come out 118 x 41 in the 640 x 360 design
# space, which is within two pixels of the height the game's buttons already
# were, and one texture pixel is one screen pixel at 1280 x 720 exactly as the
# panels and the health bars are. hud.gd stretches the width.
#
# Three of the five are taken. Green is the confirm button, which is what the
# kit drew it for; grey is everything else that can be pressed; red is nothing
# yet and is here because a quit or a give-up button is one line away and the
# alternative is coming back to the sheet for it. The blue COIN plate and the
# second grey are the same two styles again at another width.
BUTTONS = {
    "btn_go":    {"box": (1710, 1233, 1948, 1316), "width": 236},
    "btn_plain": {"box": (1418, 1364, 1656, 1447), "width": 236},
    "btn_stop":  {"box": (1710, 1364, 1948, 1447), "width": 236},
}
# How much lighter than its own row a pixel has to be to be part of the baked
# word, and how far the erase grows past it to take the letters' dark outline.
WORD_LIGHT = 34
WORD_GROW = 5
# How far outside the erase box the refill is sampled from.
EDGE_SAMPLE = 3
# How far inside its measured box the card's own face starts, and how much of
# that face the caret hunt looks at — it is always in the top-left corner where
# the first letter would go. CARD_DARK is how much darker than the card a pixel
# has to be to be the caret rather than shading.
CARD_INSET = 6
CARD_CORNER = 0.14
CARD_DARK = 42
# How far the erase grows past the caret, to take its anti-aliased edge with
# it. One left a single dark pixel behind at the corner of the card.
CARD_GROW = 2
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


def lift_word(img):
    """Erase the word baked into a button plate, keeping its frame and shading.

    Returns the plate and the CAP — the width of its rounded end, measured as
    the distance from the edge to where the face becomes full height, which is
    how far in hud.gd may not stretch.
    """
    # load(), not convert(): convert returns a COPY even when the mode already
    # matches, so writing through it erases the word in an image nobody keeps.
    if img.mode != "RGBA":
        img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    solid = [[x for x in range(w) if px[x, y][3] > 200] for y in range(h)]

    def luma(p):
        return 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]

    # The word: light pixels well inside the frame. The frame's own top bevel
    # is light too, so the search is kept to the middle band and away from the
    # ends, where nothing is ever written.
    lit = []
    for y in range(int(h * 0.2), int(h * 0.85)):
        row = solid[y]
        if len(row) < w // 2:
            continue
        mid = sorted(luma(px[x, y]) for x in row)[len(row) // 2]
        for x in row:
            if x < w * 0.08 or x > w * 0.92:
                continue
            if luma(px[x, y]) > mid + WORD_LIGHT:
                lit.append((x, y))
    if not lit:
        raise SystemExit("no baked word found in a button plate — remeasure BUTTONS")
    x0 = max(0, min(p[0] for p in lit) - WORD_GROW)
    x1 = min(w - 1, max(p[0] for p in lit) + WORD_GROW)
    y0 = max(0, min(p[1] for p in lit) - WORD_GROW)
    y1 = min(h - 1, max(p[1] for p in lit) + WORD_GROW)

    # Refilled a row at a time from the same row's own face, so the plate keeps
    # the shading it is drawn with.
    #
    # Sampled at two fixed columns just inside the frame rather than from the
    # median of everything outside the word box. The median takes the letters'
    # dark outline with it on the rows where the box only just clears them,
    # and the result was a plate with a faint ghost of its own word along the
    # top and bottom of the erase.
    for y in range(y0, y1 + 1):
        row = solid[y]
        if len(row) < w // 2:
            continue
        # Just OUTSIDE the erase box on either side: the box was already grown
        # past the letters by WORD_GROW, so a few pixels further out is clean
        # face, and it is nowhere near the frame — sampling a fixed distance in
        # from the edge lands on the border instead and fills the plate with
        # its own outline.
        lx = x0 - EDGE_SAMPLE
        rx = x1 + EDGE_SAMPLE
        pair = [px[x, y] for x in (lx, rx)
                if 0 <= x < w and px[x, y][3] > 200]
        if not pair:
            continue
        fill = tuple(sum(p[c] for p in pair) // len(pair) for c in range(3)) + (255,)
        for x in range(x0, x1 + 1):
            if px[x, y][3] > 0:
                px[x, y] = fill

    # The cap: how far in from either end the plate is not yet full height.
    tall = max(len(col) for col in
               [[y for y in range(h) if px[x, y][3] > 200] for x in range(w)])
    cap = 0
    for x in range(w):
        if len([y for y in range(h) if px[x, y][3] > 200]) >= tall:
            cap = x
            break
    return img, max(cap + 1, 2)


def lift_cursor(img, text_box):
    """Erase the text cursor the kit bakes into a card.

    Both cards are drawn as filled-in text fields, with a black caret sitting
    in the top left where the first letter would go. It is part of the picture
    and the game writes its own text over the top of it, so on screen it reads
    as a stray mark at the start of every brief.

    Found rather than measured: inside the card, in the corner the caret is
    always in, anything much darker than the card itself is it.
    """
    w, h = img.size
    px = img.load()
    x0 = int(text_box[0] * w) + CARD_INSET
    y0 = int(text_box[1] * h) + CARD_INSET
    x1 = int(text_box[2] * w) - CARD_INSET
    y1 = int(text_box[3] * h) - CARD_INSET
    face = [px[x, y] for y in range(y0, y1) for x in range(x0, x1)
            if px[x, y][3] > 200]
    if not face:
        return 0
    face.sort(key=lambda p: 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2])
    fill = face[len(face) // 2]
    mid = 0.299 * fill[0] + 0.587 * fill[1] + 0.114 * fill[2]
    hunt_x = int(x0 + (x1 - x0) * CARD_CORNER)
    hunt_y = int(y0 + (y1 - y0) * CARD_CORNER)
    marks = [(x, y) for y in range(y0, hunt_y) for x in range(x0, hunt_x)
             if px[x, y][3] > 200
             and 0.299 * px[x, y][0] + 0.587 * px[x, y][1]
                 + 0.114 * px[x, y][2] < mid - CARD_DARK]
    for x, y in marks:
        for dx in range(-CARD_GROW, CARD_GROW + 1):
            for dy in range(-CARD_GROW, CARD_GROW + 1):
                if x0 <= x + dx < x1 and y0 <= y + dy < y1:
                    px[x + dx, y + dy] = fill
    return len(marks)


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


def cut(sheet, box):
    """One piece off the sheet with the page keyed out and trimmed to itself."""
    crop = sheet.crop(box)
    w, h = crop.size
    px, alpha = cut_page(crop)
    specks = drop_specks(alpha, w, h)
    rgba = Image.new("RGBA", (w, h))
    rgba.putdata([(px[i][0], px[i][1], px[i][2], alpha[i]) for i in range(w * h)])
    return rgba.crop(rgba.getbbox()), specks


def main():
    sheet = Image.open(SOURCE)
    os.makedirs(OUT, exist_ok=True)
    manifest = {"panels": {}, "buttons": {}}
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
        caret = lift_cursor(rgba, text_box)
        out_w = spec["width"]
        out_h = round(rgba.height * out_w / rgba.width)
        final = rgba.resize((out_w, out_h), Image.LANCZOS)
        final.save(os.path.join(OUT, name + ".png"))
        manifest["panels"][name] = {
            "file": name + ".png",
            "size": [out_w, out_h],
            "interior": interior,
            "text_box": text_box,
        }
        print("%-12s %4dx%-4d -> %3dx%-3d  specks %-3d caret %-3d interior %s text_box %s"
              % (name, w, h, out_w, out_h, specks, caret, interior, text_box))

    for name, spec in BUTTONS.items():
        plate, specks = cut(sheet, spec["box"])
        plate, cap = lift_word(plate)
        out_w = spec["width"]
        out_h = round(plate.height * out_w / plate.width)
        scale = float(out_w) / float(plate.width)
        final = plate.resize((out_w, out_h), Image.LANCZOS)
        final.save(os.path.join(OUT, name + ".png"))
        manifest["buttons"][name] = {
            "file": name + ".png",
            "size": [out_w, out_h],
            # The rounded end, in WRITTEN pixels: hud.gd draws the plate in
            # three slices and may stretch only what is between them.
            "cap": max(int(round(cap * scale)), 2),
        }
        print("%-12s %4dx%-4d -> %3dx%-3d  specks %-3d cap %d (word lifted)"
              % (name, plate.width, plate.height, out_w, out_h, specks,
                 manifest["buttons"][name]["cap"]))

    with open(os.path.join(OUT, "panels.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=1, sort_keys=True)
        fh.write(chr(10))
    print("manifest -> %s" % os.path.join(OUT, "panels.json"))


if __name__ == "__main__":
    main()
