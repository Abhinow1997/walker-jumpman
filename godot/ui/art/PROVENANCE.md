# HUD art — provenance

Generated files. Do not edit by hand; rerun the script named below and let Godot
reimport.

## The health and mana bars

| | |
|---|---|
| Files | `bar_health_full.png`, `bar_health_empty.png`, `bar_mana_full.png`, `bar_mana_empty.png`, `hud_bars.json` |
| Script | `scripts/extract_hud_bars.py` |
| Source file | `Assests/health system asset.jpg` |
| Origin | **Generated art**, supplied by the author on 2026-09-16. Not a licensed pack and not attributable. |

The source is a 1952 x 2196 style guide rather than a spritesheet: labelled rows
of full-state examples, partial-fill examples and a component breakdown, all on
flat grey. Only the two partial-fill bars are used, because they are the only
pieces on the sheet showing the orb cap, the lightning fill and the dark empty
track together at one scale. The COMPONENT BREAKDOWN frames look like the
obvious source and are not: their interiors are page grey, so an unfilled bar cut
from one would be a hole in the screen.

Which colour becomes which bar is set in the extractor's `BARS` table rather
than tinted in the HUD, so `bar_health_full.png` really does hold the health
bar. **Green is health, blue is mana** — green for life is the convention a
player arrives with, and the blue lightning belongs to the blast it pays for.
The sheet draws the cyan one first, which is the only reason the two boxes in
that table look out of order.

Each bar is reduced to 80 x 13 native pixels, which `hud.gd` draws at x2 in its
640x360 design space — x3 on the 960x540 screen, so one art pixel is exactly a
3 x 3 block. Both bars are forced to that one size even though the sheet draws
them at different scales, because two bars of different lengths stacked in a
corner read as a mistake and seven percent of stone-block width does not.

The track in both variants is rebuilt column by column, so neither inherits the
torn, sparking fill edge the sheet happens to be drawn at. Since the source is a
JPEG, the script cannot check exact pixel values the way the LF2 extractors do;
it checks the geometry by proportion instead — the lit span has to be saturated
colour and the dark span has to be dark, by a wide margin — and stops if the
sheet has been recropped or replaced.

### Rights

This is the same provenance category as the title screen (`title_bg.png` and the
four menu plates, also generated, also from the author): not a licence problem
the way the LF2 sprites in `features/` are, but not attributable the way the CC0
packs are either. **A credits screen needs its own line for generated art and
must not fold it into the CC0 attributions.**

## The boss health plate

| | |
|---|---|
| Files | `boss_plate.png`, `boss_fill_health.png`, `boss_fill_magma.png`, `boss_bar.json` |
| Script | `scripts/extract_boss_bar.py` |
| Source file | `Assests/boss-system assests.jpg` |
| Origin | **Generated art**, supplied by the author on 2026-09-20. Not a licensed pack and not attributable. |

The plate that appears across the bottom of the screen while a boss is fighting
you — currently the dragon, on The Fractured Isles and The Dragon's Roost.

The source is a 2048 x 2048 style guide laid out exactly like the HUD one:
labelled full-state and partial-state examples on flat grey, with a component
breakdown underneath. Only the **partial-state** row is used, and for the same
reason: it is the one place on the sheet showing the winged-heart cap, the lit
fill and the dark empty track together at one scale. The breakdown frame below
has a page-grey interior, so an unfilled bar cut from it would be a hole in the
screen; the full-state row has a floating rock drawn over its right-hand end.

**Both of the plate's bars are used, and they show the same number.** Green is
the boss's health now; the magma bar under it is that health a moment ago,
draining to catch up over about half a second. The band of red that opens
between them after a blow is the damage you just did, which is the one thing a
single bar cannot show and the reason the art is drawn with two. Leaving the
second track permanently dark was the alternative and it would read as broken
art rather than as a design decision.

Two things in the script are worth knowing before changing it:

- The row title sits above the plate and its descenders reach into the crop.
  It is flat near-black on grey, which is also what the frame's own outlines
  are, so it cannot be keyed out by colour — it is **blanked** at a fixed
  rectangle instead, the same treatment `extract_dragon_lord.py` gives the
  captions on its preview gifs.
- The two fills are cut out of a fully lit plate **after** the reduction, so
  all three files land on the same pixel grid. Shipping two whole lit plates is
  the obvious thing and it does not work: each one carries the other track
  dark, so drawing the green one over the magma one erased everything of the
  magma bar except the sliver between the two fill levels.

The plate is reduced to 736 x 132 native pixels, which `hud.gd` draws at x0.5
in its 640x360 design space; x1.5 for the viewport and x4/3 for a 1280x720
window bring that back to 1, so a texture pixel is a screen pixel. As with the
player's bars the source is a JPEG, so the script checks its geometry by
proportion rather than by exact value and stops if the sheet has been recropped
or regenerated.

### Rights

Same category as the player's bars and the title screen: generated, from the
author, **not** attributable the way the CC0 packs are. It belongs on the
credits screen's generated-art line, not among the CC0 attributions.

## The opening storyboard

| | |
|---|---|
| Files | `storyboard/panel_0.png` … `panel_3.png`, `storyboard/dragon_fight_start.png`, `storyboard/dragon_fight_end.png`, and four clips in `audio/` |
| Script | `scripts/extract_storyboard.py` |
| Source files | `Assests/Storyboard/panel 0.jpg` … `panel 3.jpg`, `dragon-fight-start.jpg`, `dragon-fight-end.jpg`, and four mp3s beside them |
| Origin | **Generated art and audio**, supplied by the author on 2026-09-19 and 2026-09-20. Not a licensed pack and not attributable. |

Four 2730 x 1536 frames taken to the 960 x 540 viewport and nothing else: no
crop, no key, no recolour, because unlike every other sheet in this folder they
are already finished full-frame pictures rather than a page of pieces. They are
the cold open — the isles with the sea coming in, then asleep on the ledge,
woken by the screech, running for the gap. `ui/storyboard.gd` owns the times
they cut at; the script only ever changes their size.

Panel 0 arrived after the other three and pushed the ledge from 0:00 to 0:18.
Nothing needed renumbering, because the panel order is the order of the list in
the extractor and the cut times are the order of the table in `storyboard.gd`:
add a source file to one and a cue to the other and the opening grows a shot.

### The cards around the dragon fight

`dragon_fight_start.png` and `dragon_fight_end.png` are the fifth and sixth
pictures in the folder and neither is part of the opening. They play inside The
Fractured Isles: the standoff as the player steps onto the Archway deck, and
the dragon in the air with its wings out once it is beaten and gone. They come
through the same script, which has two tables — `PANELS` for the opening and
`CARDS` for these — because they are a different shape and are treated
differently.

**They are cropped, and that is the one judgement call in the extractor.** The
sources are 2048 x 1536, which is 4:3, and the game draws them full-screen at
16:9, so a quarter of the height has to go. Which quarter is a per-card number
in `CARDS` with what it is protecting written beside it:

- **the standoff, centred.** The dragon is sitting on the grass in the middle
  of the frame with the mountains behind it, so the picture is already
  balanced. Half off the top costs cloud and the tip of the tall floating
  tower; half off the bottom costs the character below the chest.
  Bottom-aligned reads better as a standoff and cuts the mountain peaks, which
  looks like a mistake rather than a frame.
- **the departure, top-aligned.** This one is the dragon AIRBORNE and its
  wings reach within 150 px of the top edge, so anything off the top clips
  them. It comes off the bottom instead, which is grass and the back of the
  character's head — he is watching it go and does not need to be more than a
  silhouette.

An earlier version of the first card was square, 2048 x 2048, and was shown
whole in the middle of the screen with bars either side, because no 16:9 band
of *that* composition kept both the floating islands and the character. The
author replaced it with a 4:3 recomposition and asked for it full-screen, which
is what the crop numbers above are for.

Neither kind of panel is pixel art, despite both looking like it. The
column-to-column differences show no grid at any step from 2 to 16, so there is
no native resolution to snap to: LANCZOS is the right reduction and the game
draws them under a LINEAR filter, exactly as it draws the HUD bars.

### The cards' audio

Three clips beside the panels, copied into `godot/audio/` by the same script
because `res://` cannot reach outside the project:

| | | |
|---|---|---|
| `dragon fight start scene.mp3` | `dragon_fight_start.mp3` | 10.5 s, over the standoff |
| `dragon-fight-endscene.mp3` | `dragon_fight_end.mp3` | 9.5 s, over the departure |
| `dragon-voice-angry-growl.mp3` | `dragon_roar.mp3` | 8.6 s, the standoff's exit |

**The clip decides how long its card holds** — `session.gd` reads the stream's
length, so re-rendering one longer lengthens the card and no duration is
written down anywhere. The roar is the standoff's `out_audio`: it starts as the
picture begins to dissolve and carries into the first seconds of the fight,
which is the one place in the folder a dragon's growl belongs. Move it by
changing one key in `levels/fractured_isles.json`.

The standoff also carries a printed line — "Wow! A drake! What's it doing
here??" — which is the author's, and lives in the level file rather than here
because it is words rather than an asset. It is drawn in `game/session.gd` with
the column, baseline, size and scrim `ui/storyboard.gd` gives the opening's
captions, so the two read as one piece of typography.

The copy is skipped when the bytes already match, so a run cannot churn
`storyboard_scene_1.mp3` — the opening's caption times in `ui/captions.json`
are measured against that exact file.

Another card is a source file in `CARDS`, a clip in `AUDIO` and an entry in a
level's `"cutscene"` list. `scripts/check_levels.py` fails a level that names
art or a clip it cannot find, and one whose cue could never fire.

### The voice-over

`audio/storyboard_scene_1.mp3` is a copy of
`Assests/Storyboard/merged_audio_1789861876055.mp3`: the monologue in
`Assests/Storyboard/opening-monologue-elevenlabs.md`, rendered to speech by the
author and mixed down with a background bed. 56.568 s, and the panel times are
written against it. Both stems are still beside it in that folder —
`Scene-1.mp3` is the voice alone, `scene-1-background.mp3` the bed.

It is copied into the project rather than referenced because `res://` cannot
reach outside it, and it is the merged file rather than the two stems because
the mix is the thing the cuts were timed to. Re-render it and run
`tests/diag_audio.gd`, which fails if the new length no longer reaches the
0:45 cut.

The voice stem earns its keep even though the game never loads it. The caption
cues in `ui/storyboard.gd` are measured off it by `tests/diag_speech.gd` — see
that file's header for the two-line procedure — because the merged mix has a
continuous bed under the voice and no silence in it to find. Copy the stem to
`godot/audio/_stem_probe.mp3` to re-measure, and **delete it afterwards**:
`godot/audio/*.mp3` is tracked on purpose and one left behind would ship.

**Where the bed came from is not recorded.** If it is not the author's own or a
CC0 track it is a third thing to clear before release, alongside the two below.

### Rights

The same provenance category as `title_bg.png` and the menu plates: generated,
from the author — not a licence problem the way the LF2 sprites in `features/`
are, and not attributable the way the CC0 packs are either. **A credits screen
needs its own line for generated art and must not fold it into the CC0
attributions.**

One thing these panels add to that. The character drawn in panels 1 to 3 **and
in both dragon cards** is the protagonist, whose sprite sheet is an unlicensed
LF2 fan mod — see `features/player/art/anti_davis/PROVENANCE.md`. A generated
picture of him is still a picture of him, so redrawing the cast for release
means regenerating those five with it, not just the sheets. Panel 0 has no
character in it and is the one frame of the storyboard that survives that
change untouched.

The four clips are the author's own renders and sit in the same generated
category as the pictures. Unlike the opening's voice-over, none of them has an
unaccounted-for background bed: **where the opening's bed came from is still
not recorded** and is still a thing to clear before release.

## The old mech health bar

`healthbar_full.png`, `healthbar_empty.png`, `healthbar.json` and
`scripts/extract_healthbar.py` were removed on 2026-09-16 when the bars above
replaced them. That asset — `Assests/mech-healthbar.png` — had **no known
origin at all**: a bare 60 x 30 PNG with no pack, readme or licence beside it,
and the open question of whether it could be shipped. Retiring it closes that
question. The source file is still in `Assests/` and the deleted script is in
git history if the old bar is ever wanted back.

## The overlay panels

`panel_menu.png`, `panel_popup.png`, `btn_go.png`, `btn_plain.png`,
`btn_stop.png` — cut from `Assests/Storyboard/game_panels.jpg` by
`scripts/extract_panels.py`, which also measures where the writing goes inside
each panel and publishes it in `panels.json` as fractions of the art. Re-crop
a panel and its text moves with it; nothing in hud.gd repeats those numbers.

The source is one page of UI elements on a dark slate grid. The page is removed
by flood filling from the border rather than by a plain colour key: parts of the
stone frames land within 8 of the page's own colour, so a colour key eats holes
in them. Only background actually connected to the outside goes, and the tight
tolerance leaves jpeg speckle behind, which a minimum-island pass then clears
(311 specks on the big panel).

### The buttons, with their words lifted off

The kit's buttons used to be skipped. Every plate has a word baked into it —
START, QUIT, OPTIONS — and the confirm button under these panels says four
different things depending on what is on screen ("ENTER / RESUME", "ENTER /
NEXT LEVEL"), so hud.gd drew a flat rectangle in the kit's green instead. That
was the wrong trade: the painted bevel, the rounded frame and the shaded face
are most of what makes this read as a game, and the word is the easy part to
replace.

So the word is **erased and the plate kept**. It is found rather than measured
— the letters are near-white against a face that is not, so the light pixels
well inside the frame are the word, and their box grown by the letters'
outline is what gets painted over. Each row of that box is refilled from the
same row just OUTSIDE it, which keeps the top-to-bottom shading; a flat fill
flattens the bevel, and sampling a fixed distance in from the edge lands on
the frame and fills the plate with its own outline. Both were tried.

Three of the five are taken: `btn_go` is the green START, which is what the
confirm button is; `btn_plain` is the grey, which is every secondary press;
`btn_stop` is the red QUIT and is not used yet — it is here because a
give-up button is one line away and the alternative is coming back to the
sheet for it. Green is never used twice on one screen: two green plates side
by side read as two equal choices, which is the opposite of a primary and a
toggle.

Each is written at the kit's own 236 x 83 so nothing is resampled, with a
**cap** in the manifest — the width of the rounded end. hud.gd draws one in
three slices, the two caps at their drawn width and everything between them
stretched, so a 118-wide plate fills a 170-wide button without pulling its
corners out of round.

The label is drawn on top, and its SIZE is worked out per row rather than
fixed: `label_size` takes every label that will share a row and returns the
largest point size at which the longest of them clears the two rounded ends.
The pause screen is why — it went from two plates at 170 to four at 140 and
"ENTER / RESUME" ran off both ends of its own. One size for the whole row,
not one per button: four plates with the long label a point smaller than the
short ones reads as a mistake.

### The caret

Both cards are drawn as filled-in text fields, with a black caret sitting
where the first letter would go. The game writes its own text over the top, so
on screen it read as a stray mark at the start of every brief. `lift_cursor`
takes it off the same way the words come off the buttons: inside the card, in
the corner it is always in, anything much darker than the card is it. 125
pixels on the menu panel; the pop-up has none.

Also on the page and unused: the inventory grid, the quest and item slots, the
mini-map frame, the ITEMS panel (the same frame as the pop-up with a dark face),
the round wooden icons, and the blue COIN plate. There is nothing in the game
that shows any of them yet.

**There is no font in any pack here**, and there is none in the project. Every
string the game draws — the menu, the briefs, the button labels, the HUD
numbers, the storyboard captions — is Godot's `ThemeDB.fallback_font`, which is
a plain sans and not the blocky pixel face the kit letters its own plates with.
Nothing in `Assests/` ships a `.ttf`, `.otf` or `.fnt`; the LF2 rips, the Magic
Cliffs pack, TinyQuesters and the UI kit were all checked. Matching the kit's
lettering needs a font added to the project, and until one is there the most
that can be done is what the labels do now: an outline under the ink, so the
type at least sits on the art instead of floating over it.
