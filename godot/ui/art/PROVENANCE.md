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

## The opening storyboard

| | |
|---|---|
| Files | `storyboard/panel_0.png` … `storyboard/panel_3.png` |
| Script | `scripts/extract_storyboard.py` |
| Source files | `Assests/Storyboard/panel 0.jpg` … `panel 3.jpg` |
| Origin | **Generated art**, supplied by the author on 2026-09-19. Not a licensed pack and not attributable. |

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

**Where the bed came from is not recorded.** If it is not the author's own or a
CC0 track it is a third thing to clear before release, alongside the two below.

### Rights

The same provenance category as `title_bg.png` and the menu plates: generated,
from the author — not a licence problem the way the LF2 sprites in `features/`
are, and not attributable the way the CC0 packs are either. **A credits screen
needs its own line for generated art and must not fold it into the CC0
attributions.**

One thing these panels add to that. The character drawn in panels 1 to 3 is the
protagonist, whose sprite sheet is an unlicensed LF2 fan mod — see
`features/player/art/anti_davis/PROVENANCE.md`. A generated picture of him is
still a picture of him, so redrawing the cast for release means regenerating
those three with it, not just the sheets. Panel 0 has no character in it and is
the one frame of the opening that survives that change untouched.

## The old mech health bar

`healthbar_full.png`, `healthbar_empty.png`, `healthbar.json` and
`scripts/extract_healthbar.py` were removed on 2026-09-16 when the bars above
replaced them. That asset — `Assests/mech-healthbar.png` — had **no known
origin at all**: a bare 60 x 30 PNG with no pack, readme or licence beside it,
and the open question of whether it could be shipped. Retiring it closes that
question. The source file is still in `Assests/` and the deleted script is in
git history if the old bar is ever wanted back.

## The overlay panels

`panel_menu.png`, `panel_popup.png` — cut from
`Assests/Storyboard/game_panels.jpg` by `scripts/extract_panels.py`, which also
measures where the writing goes inside each one and publishes it in
`panels.json` as fractions of the art. Re-crop a panel and its text moves with
it; nothing in hud.gd repeats those numbers.

The source is one page of UI elements on a dark slate grid. The page is removed
by flood filling from the border rather than by a plain colour key: parts of the
stone frames land within 8 of the page's own colour, so a colour key eats holes
in them. Only background actually connected to the outside goes, and the tight
tolerance leaves jpeg speckle behind, which a minimum-island pass then clears
(311 specks on the big panel).

The kit's buttons are deliberately **not** used. Every plate has its word baked
in — START, QUIT, OPTIONS — and the confirm button under these panels says four
different things depending on what is on screen. hud.gd draws that button and
borrows only the kit's green.

Also on the page and unused: the inventory grid, the quest and item slots, the
mini-map frame, the ITEMS panel (the same frame as the pop-up with a dark face)
and the round wooden icons. There is nothing in the game that shows any of them
yet.
