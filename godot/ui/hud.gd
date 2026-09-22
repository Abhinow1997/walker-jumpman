extends Control

const Music = preload("res://game/music.gd")

var game: Node2D
## What each prompt slot is currently showing and when it started showing it,
## for the fade. Two slots — the action cue and the lesson above it — so the
## two fade independently.
##
## Keyed on WHAT the prompt is rather than on what it says, or the drink cue
## would restart its fade every tenth of a second and never finish: the
## countdown is part of its text.
var cue_seen := {}
## When he first spent mana, and whether that lesson is over. Held here rather
## than on the player because it is a fact about what has been SHOWN, not about
## what he has done — blasts_thrown is the fact, and it is lifetime, so a retry
## does not put this back.
var blast_at: float = -1.0
var blast_done: bool = false
## Whether an action cue was drawn this frame. The lesson above it reads this
## to know which shelf to sit on — stacked when there is a plate under it,
## down at the action cue's own height when there is not, so a lesson on its
## own does not float a body's length over his head. Not the same question as
## the key it returns: ALREADY FULL is a plate with no key on it.
var action_cue_up: bool = false

## Dark ink on light paper, as before. The play HUD has no paper behind it any
## more, so it carries its own: every string on it is drawn with a pale outline
## and the same dark face on top.
##
## The halo goes under the ink rather than the other way round because the levels
## are mostly light — First Steps is cream to the horizon — and pale text on pale
## art disappears. The halo only has to survive the dark patches: the Magic
## Cliffs sky, the slate ground, a cliff face.
const INK := Color("25354a")
const HALO := Color(0.96, 0.95, 0.91, 0.92)
## Outline width in HUD pixels. Four reads as a one-pixel ring at 12 px and does
## not close up the counters of the fallback font.
const HALO_WIDTH := 4
## Behind the two meters that have to read as a length rather than as text.
const TROUGH := Color(0.11, 0.16, 0.21, 0.55)
## The level's coaching lines — see _coach_prompt. Warmer than INK so a line that
## is teaching you something does not read as the same thing as a line telling
## you what is under your feet, and dark enough to sit inside the same halo.
const COACH := Color("8a4a2c")

## --- the prompts over the level ---------------------------------------------
##
## A prompt is a small plate with the key on a cap and the verb beside it,
## standing OVER the thing it is about: the rock you can lift, or him.
##
## It used to be a bare line of outlined text centred on the screen — so the
## words "E / LIFT" appeared in the middle of a pit on the far side of the
## frame from the rock they were about, at the same size and in the same face
## as the death banner and the menu hint. It read as a debug overlay, and it
## never said WHICH thing it meant.
##
## Pale plate, dark keycap, dark ink: the same way round as the rest of this
## HUD, which is written as dark ink on light paper because the levels are
## mostly bright. The cap is inverted out of it because that is what a key
## looks like.
const CUE_TEXT := 11
const CUE_H := 19.0
const CUE_PAD := 6.0
const CUE_GAP := 5.0
const CUE_CAP_MIN := 15.0
## How far above the anchor the plate's foot sits, in HUD pixels. A thing you
## can pick up is small and low, so its prompt sits close over it; his own sit
## clear of his head, and a lesson sits above those again because the two can
## be up at once — the bandit stretch has a rock standing in it.
## Both of the action cues clear the top of his SPRITE, which stands about 22
## of these above the point either of them is measured from. At 20 and 26 the
## plate sat on his head.
const CUE_OVER_PROP := 34.0
const CUE_OVER_HIM := 34.0
const CUE_OVER_LESSON := 62.0
## Kept inside the frame whatever the camera is doing, and below the two bars.
const CUE_EDGE := 6.0
const CUE_CEILING := 62.0
## Faded in rather than popped. A prompt appears because you walked into range,
## which is a gentler event than the hard cut it used to make.
const CUE_FADE := 0.18
const CUE_PLATE := Color(0.96, 0.95, 0.91, 0.95)
const CUE_RIM := Color(0.15, 0.20, 0.28, 0.50)
const CUE_CAP_FACE := Color(0.13, 0.18, 0.26, 0.95)
const CUE_CAP_INK := Color(0.97, 0.96, 0.93)
## ALREADY FULL is the one cue that is not an invitation, so it is greyed and
## carries no key: there is nothing to press.
const CUE_DIM := Color("6d7885")

## --- and the two that point at a bar ----------------------------------------
##
## The bars are the one part of this HUD that is never explained. You can play
## the whole of First Steps without learning that the green one is what the
## milk bottle is filling or that the blue one is what the blast spends, and
## the numbers beside them say how much of something without saying of what.
##
## So: drink, and the bar that bottle pours into is named while it climbs.
## Blast for the first time, and the one it came out of is named while it dips.
## Both are First Steps' only, like every other prompt here, and both point
## sideways — the bars live in the top corner and there is nothing above them
## to hang a plate from.
const BAR_WORD := {"health": "HEALTH", "mana": "MANA"}
## Clear of the number beside the bar, which is measured rather than guessed:
## it is three digits at full health and two after one hit.
const BAR_CUE_GAP := 12.0
## How long the first blast holds the mana bar's name up. A blast is over in a
## moment and the dip in the bar is eased over about a third of a second, so
## the cue has to outlast both by enough to be read.
const BLAST_HOLD := 2.4

## Health and mana come from the same sheet, cut into a full and an empty version
## each by scripts/extract_hud_bars.py. The empty one is drawn, then the full one
## clipped to the player's fraction, so the lightning sweeps across a frame that
## never moves.
const BARS := "res://ui/art/hud_bars.json"
const BAR_ART := "res://ui/art/"
## Drawn at HALF its size in the 640x360 design space. Half looks backwards for a
## HUD element, but the art is now extracted at the size it ends up on screen
## rather than at a fourteenth of it: 0.5 here, x1.5 for the viewport and x4/3
## for a 1280x720 window come back to 1, so a texture pixel is a screen pixel.
## It was 2.0 against 80x13 art, which magnified every source pixel into a 4x4
## block. The bar's size on screen is unchanged — only its resolution went up.
const BAR_SCALE := 0.5
## Where the two bars sit, and the gap between them.
const BAR_AT := Vector2(20, 8)
const BAR_STEP := 30.0
## How fast a bar's fill chases the real value, as an exponential rate. The bars
## do not snap: a blast takes five points off a hundred and the trickle puts
## them back a fifth of a point at a time, and both should be something you
## watch happen rather than a number that has already changed by the time you
## look. Nine is about a third of a second to close most of a gap — quick enough
## that a hit still reads as a hit, slow enough to see the level move.
const BAR_EASE := 9.0
## Below this the chase is over and the bar is set exactly, so it lands on the
## real value instead of creeping at it forever.
const BAR_SETTLED := 0.0005

## --- the boss plate ---------------------------------------------------------
##
## One enemy in a level may be a boss, and while it is fighting you its health
## gets its own plate across the bottom of the screen — the winged heart, the
## stone frame and two tracks, cut from the asset sheet by
## scripts/extract_boss_bar.py.
##
## On a level that fights ONE boss the plate carries two bars and both are the
## SAME number. The green one is its health now; the magma one under it is
## that health a moment ago, draining to catch up. The band of red between
## them is what you just took off, which is the one thing a single bar cannot
## show you and the reason the art is drawn with two.
##
## The Dragon's Roost fights TWO, and there the two bars are one boss each —
## green the Dragon Lord, magma the flying dragon — and each keeps its own for
## the whole fight, so beating one empties its bar and leaves the other where
## it was. See boss_track in game/session.gd.
const BOSS_BARS := "res://ui/art/boss_bar.json"
## Drawn at the same half scale as the player's, and for the same reason: the
## art is extracted at the size it lands on screen.
const BOSS_SCALE := 0.5
## Centred across the bottom, clear of the progress line at 351. Deliberately
## the opposite corner from the player's own bars — his are a glance, this is
## the thing you are watching.
const BOSS_Y := 278.0
## How fast each of the two chases the real value. The green is the player's
## own BAR_EASE, so a hit reads the same whoever takes it; the magma is slow
## enough that the gap between them is legible for about half a second.
const BOSS_EASE := 9.0
const BOSS_LAG_EASE := 2.6

## Replaced by whatever hud_bars.json reports; this is only what the fallback
## rectangles are sized against if the art is missing. Keep it at NATIVE.
var bar_size := Vector2(320, 52)
## name -> {empty: Texture2D, clip: AtlasTexture, fill: Vector2}. `clip` is an
## AtlasTexture whose region is narrowed each frame, rather than
## draw_texture_rect_region, which renders the art as flat white here.
var bars := {}
## What each bar is currently showing, chasing what the player actually has.
## Negative until the first frame, which is how a bar knows to start at the real
## value rather than sliding up from empty the moment a level loads.
var shown := {"health": -1.0, "mana": -1.0}

## The boss plate, loaded the same way the player's bars are, and empty when
## the art has not been imported yet.
var boss_size := Vector2(736, 132)
var boss_plate: Texture2D = null
## name -> {clip: AtlasTexture, fill: Vector2}
var boss_bars := {}
## What the two tracks are showing. Negative until the first frame of a fight,
## which is how they know to start full rather than sliding up from empty.
var boss_shown := {"health": -1.0, "magma": -1.0}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	## Linear, because the bar art is a reduction of a painted sheet rather than
	## pixel art, and because the HUD only lands texel-perfect at 1280x720 — at
	## any other window size BAR_SCALE x 1.5 x magnification is not an integer and
	## nearest sampling would break the frame's straight edges up unevenly.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_load_bars()
	_load_boss_bar()
	_load_panels()

func _process(delta: float) -> void:
	## Eases both bars toward the player. Separate from _draw because the draw
	## has no delta, and separate from the session's step because a bar that is
	## still settling has to keep redrawing after the value behind it stopped
	## moving.
	if not is_instance_valid(game) or not is_instance_valid(game.player):
		return
	var moved := false
	for name in shown:
		var target: float = clampf(_reading(name), 0.0, 1.0)
		var was: float = shown[name]
		if was < 0.0:
			shown[name] = target
		else:
			shown[name] = was + (target - was) * (1.0 - exp(-BAR_EASE * delta))
			if absf(target - float(shown[name])) < BAR_SETTLED:
				shown[name] = target
		if absf(float(shown[name]) - was) > 0.00001:
			moved = true
	# And the boss plate, on its own two rates. Reset between fights, so the
	# next boss does not inherit the last one's empty bar.
	#
	# Two tracks, and what they mean depends on how many bosses the FIGHT has.
	# With ONE they are the same number at two speeds — green now, magma a beat
	# behind, and the band between them is the damage just dealt. With TWO — The
	# Dragon's Roost — they are two DIFFERENT bosses: green is the Dragon Lord on
	# the main track, magma the dragon on the red, each tracking its own live
	# health for as long as the fight lasts. Beat one and its bar empties and
	# stays empty; the other goes on draining where it was, because the session
	# hands out the tracks once and does not take them back until both are gone.
	# See boss_track/boss_main/boss_second in game/session.gd.
	var main: Node2D = game.boss_main() if is_instance_valid(game) else null
	if main == null:
		if boss_shown["health"] >= 0.0:
			boss_shown["health"] = -1.0
			boss_shown["magma"] = -1.0
			moved = true
	else:
		var second: Node2D = game.boss_second()
		var main_frac: float = clampf(float(main.health)
				/ maxf(float(main.max_health), 1.0), 0.0, 1.0)
		# The magma track carries the second boss when there are two, eased as fast
		# as the green so it reads as its own live bar; with one boss it lags the
		# main health on the slow rate, which is the damage band.
		var magma_frac: float = main_frac
		var magma_rate: float = BOSS_LAG_EASE
		if second != null:
			magma_frac = clampf(float(second.health)
					/ maxf(float(second.max_health), 1.0), 0.0, 1.0)
			magma_rate = BOSS_EASE
		for name in boss_shown:
			var target: float = main_frac if name == "health" else magma_frac
			var rate: float = BOSS_EASE if name == "health" else magma_rate
			var was: float = boss_shown[name]
			if was < 0.0:
				boss_shown[name] = target
			else:
				boss_shown[name] = was + (target - was) * (1.0 - exp(-rate * delta))
				if absf(target - float(boss_shown[name])) < BAR_SETTLED:
					boss_shown[name] = target
			if absf(float(boss_shown[name]) - was) > 0.00001:
				moved = true
	if moved:
		queue_redraw()

func _reading(name: String) -> float:
	return game.player.mana_fraction() if name == "mana" else game.player.health_fraction()

func _load_bars() -> void:
	var text := FileAccess.get_file_as_string(BARS)
	if text.is_empty():
		push_warning("hud: %s is missing. Run scripts/extract_hud_bars.py." % BARS)
		return
	var data: Dictionary = JSON.parse_string(text)
	bar_size = Vector2(float(data.size[0]), float(data.size[1]))
	for name in data.bars:
		var spec: Dictionary = data.bars[name]
		var empty_path: String = BAR_ART + str(spec.files.empty)
		var full_path: String = BAR_ART + str(spec.files.full)
		if not ResourceLoader.exists(empty_path) or not ResourceLoader.exists(full_path):
			# The art is generated, so a fresh checkout that has not been
			# imported yet falls back to plain rectangles rather than nothing.
			push_warning("hud: %s bar art not imported yet; falling back to a plain bar" % name)
			bars.clear()
			return
		var clip := AtlasTexture.new()
		clip.atlas = load(full_path)
		bars[name] = {
			"empty": load(empty_path),
			"clip": clip,
			"fill": Vector2(float(spec.fill_x0), float(spec.fill_x1)),
		}

func _load_boss_bar() -> void:
	var text := FileAccess.get_file_as_string(BOSS_BARS)
	if text.is_empty():
		push_warning("hud: %s is missing. Run scripts/extract_boss_bar.py." % BOSS_BARS)
		return
	var data: Dictionary = JSON.parse_string(text)
	boss_size = Vector2(float(data.size[0]), float(data.size[1]))
	var plate_path: String = BAR_ART + str(data.plate)
	if not ResourceLoader.exists(plate_path):
		# Generated art, so a fresh checkout that has not been imported yet
		# falls back to no plate rather than to a crash.
		push_warning("hud: boss plate not imported yet; the boss fights without one")
		return
	boss_plate = load(plate_path)
	for name in data.bars:
		var spec: Dictionary = data.bars[name]
		var lit_path: String = BAR_ART + str(spec.file)
		if not ResourceLoader.exists(lit_path):
			boss_bars.clear()
			boss_plate = null
			return
		var clip := AtlasTexture.new()
		clip.atlas = load(lit_path)
		boss_bars[name] = {
			"clip": clip,
			"at": Vector2(float(spec.at[0]), float(spec.at[1])),
			"size": Vector2(float(spec.size[0]), float(spec.size[1])),
		}

func boss() -> Node2D:
	## The boss whose fight is happening right now, or null. The session owns
	## the rule now, because which track is playing follows the same one and a
	## plate that could disagree with the soundtrack about whether a fight is
	## on would be worse than either being wrong alone. See game/session.gd.
	return game.boss() if is_instance_valid(game) else null

func text_at(text: String, position: Vector2, size_px: int = 14, color: Color = INK) -> void:
	draw_string(ThemeDB.fallback_font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

func over_level(text: String, position: Vector2, size_px: int = 12, color: Color = INK) -> void:
	## A string on the play HUD, which has no panel behind it. The pale ring is
	## the panel now, drawn per glyph so it follows the text instead of boxing it.
	draw_string_outline(ThemeDB.fallback_font, position, text, HORIZONTAL_ALIGNMENT_LEFT,
		-1, size_px, HALO_WIDTH, HALO)
	text_at(text, position, size_px, color)

func centered(text: String, y: float, font_size: int, color: Color = INK) -> void:
	var width := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	text_at(text, Vector2((640-width)/2, y), font_size, color)

func wrapped(text: String, box: Rect2, y: float, font_size: int,
			 lines: int = 2, color: Color = INK) -> void:
	## Centred and broken to the width of the card it is written on. The level
	## briefs are whole sentences and the card is about 214 wide; draw_string does
	## not wrap, so they simply ran off both edges of the panel and over the frame.
	draw_multiline_string(ThemeDB.fallback_font, Vector2(box.position.x, y), text,
		HORIZONTAL_ALIGNMENT_CENTER, box.size.x, font_size, lines, color)

func _centred_over_level(text: String, y: float, font_size: int, color: Color = INK) -> void:
	var width := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	over_level(text, Vector2((640-width)/2, y), font_size, color)

## --- the panel the menu, the pause screen and the results share -------------
##
## The menu grew a row per level, so the panel is sized from its contents rather
## than being the one fixed rectangle it used to be. The session hit-tests
## clicks against button_rect() and row_at() rather than repeating the numbers.

## Cut from the UI kit by scripts/extract_panels.py, which also measures where
## the writing goes inside each one and publishes it as fractions of the art —
## so re-cropping a panel moves its text with it and nothing here is re-typed.
##
## The menu wears the big runed frame, the one with the game's name on its
## headstone: it is the front screen. Pause and results wear the small stone
## pop-up, because an in-game message should not be a full-screen monument.
const PANELS := "res://ui/art/panels.json"
const PANEL_ART := "res://ui/art/"
## The art is written at the size it is drawn in PHYSICAL pixels, so 0.5 here,
## x1.5 for the HUD layer and x4/3 for a 1280x720 window come back to 1 — the
## same arrangement as the health bars.
const PANEL_SCALE := 0.5
## Both panels hang from one bottom line with the button under it, so the
## overlay sits in the same place whichever of the two is showing.
const PANEL_BOTTOM := 282.0
const BUTTON_AT := Rect2(235, 290, 170, 40)
## --- the pause row ----------------------------------------------------------
##
## PAUSED is the one screen with more than one thing to do, and it used to say
## so in prose: two of its four actions were a line of text inside the card
## reading "R: restart attempt    M: main menu", which is a keyboard-only
## instruction sitting next to two buttons you can click. Now all four are
## plates in one row — resume, restart, main menu, music — so the screen shows
## what it offers instead of describing half of it.
##
## Four at 140 with 10 between them is 590 of the 640, which is as wide as the
## row can be and still look placed rather than jammed against the edges. The
## longest label, "ENTER / RESUME", is about 100 at 14 px, so every one of them
## has room without abbreviating the key away.
const PAUSE_SLOT := Vector2(140.0, 40.0)
const PAUSE_GAP := 10.0
const PAUSE_ROW_Y := 290.0
const PAUSE_SLOTS := 4
## The kit's own plates, with their baked words lifted off — see
## extract_panels.py. `btn_go` is its green START, which is what the confirm
## button is; `btn_plain` is its grey, which is everything else you can press.
const BUTTON_GO := "btn_go"
const BUTTON_PLAIN := "btn_plain"
## The face and lip the drawn rectangle used before the plates existed, kept
## for a checkout that has not imported the art yet. Sampled off the kit's
## green so the fallback is at least the right colour.
const BUTTON_FACE := Color("498c69")
const BUTTON_LIP := Color("6fb98a")
## The toggle while the music is off, so the state reads without the label.
const BUTTON_OFF := Color("57606b")
const BUTTON_OFF_LIP := Color("7d8894")
## The label on a plate: the kit writes its own in near-white with a dark
## outline, and this is that, drawn rather than baked.
const BUTTON_INK := Color(0.97, 0.96, 0.93)
const BUTTON_EDGE := Color(0.09, 0.11, 0.15, 0.85)
## The label's size, how small it may be shrunk to fit its plate, and how much
## of the plate the two rounded ends and their bevels take.
const BUTTON_TEXT := 14
const BUTTON_TEXT_MIN := 10
const BUTTON_MARGIN := 30.0

## Only the fallback shape, for a checkout that has not imported the art yet.
const PANEL_W := 340.0
const PANEL_MID := 182.5
const ROW_H := 22.0

## name -> {tex, size, interior, text_box}. Empty if the art is missing, which
## puts every panel back on the plain rectangle it used to be.
var panels := {}
## name -> {tex, size, cap}. The kit's button plates; `cap` is the rounded end,
## which _button_plate may not stretch. Empty falls back to the drawn
## rectangle, the same way the panels do.
var buttons := {}

func _load_panels() -> void:
	var text := FileAccess.get_file_as_string(PANELS)
	if text.is_empty():
		push_warning("hud: %s is missing. Run scripts/extract_panels.py." % PANELS)
		return
	var data: Dictionary = JSON.parse_string(text)
	for name in data.get("panels", {}):
		var spec: Dictionary = data["panels"][name]
		var path: String = PANEL_ART + str(spec.file)
		if not ResourceLoader.exists(path):
			push_warning("hud: panel art not imported yet; falling back to plain panels")
			panels.clear()
			return
		panels[name] = {
			"tex": load(path),
			"size": Vector2(float(spec.size[0]), float(spec.size[1])) * PANEL_SCALE,
			"interior": spec.interior,
			"text_box": spec.text_box,
		}
	for name in data.get("buttons", {}):
		var spec: Dictionary = data["buttons"][name]
		var path: String = PANEL_ART + str(spec.file)
		if not ResourceLoader.exists(path):
			buttons.clear()
			return
		buttons[name] = {
			"tex": load(path),
			"size": Vector2(float(spec.size[0]), float(spec.size[1])),
			"cap": float(spec.cap),
		}

func _panel_name() -> String:
	return "panel_menu" if game.state == game.State.MENU else "panel_popup"

func panel_rect() -> Rect2:
	var spec: Dictionary = panels.get(_panel_name(), {})
	if spec.is_empty():
		var h: float = 140.0 + game.listing().size() * ROW_H 			if game.state == game.State.MENU else 159.0
		return Rect2((640.0 - PANEL_W) / 2.0, PANEL_MID - h / 2.0, PANEL_W, h)
	var size: Vector2 = spec.size
	return Rect2((640.0 - size.x) / 2.0, PANEL_BOTTOM - size.y, size.x, size.y)

## One of the panel's measured regions, in HUD coordinates. `interior` is
## everything inside the frame; `text_box` the pale card within it, which on the
## big panel is a smaller area than the parchment around it.
func _face(key: String) -> Rect2:
	var r := panel_rect()
	var spec: Dictionary = panels.get(_panel_name(), {})
	if spec.is_empty():
		return r.grow(-16.0)
	var f: Array = spec[key]
	return Rect2(r.position.x + float(f[0]) * r.size.x,
				 r.position.y + float(f[1]) * r.size.y,
				 (float(f[2]) - float(f[0])) * r.size.x,
				 (float(f[3]) - float(f[1])) * r.size.y)

func pause_slot(i: int) -> Rect2:
	## One place in the pause row, left to right. Empty off the pause screen,
	## which is what stops a click landing on a button that is not drawn — the
	## same guard music_rect() has always had.
	if not is_instance_valid(game) or game.state != game.State.PAUSED:
		return Rect2()
	if i < 0 or i >= PAUSE_SLOTS:
		return Rect2()
	var span := PAUSE_SLOTS * PAUSE_SLOT.x + (PAUSE_SLOTS - 1) * PAUSE_GAP
	var left := (640.0 - span) / 2.0
	return Rect2(left + i * (PAUSE_SLOT.x + PAUSE_GAP), PAUSE_ROW_Y,
			PAUSE_SLOT.x, PAUSE_SLOT.y)

func button_rect() -> Rect2:
	if is_instance_valid(game) and game.state == game.State.PAUSED:
		return pause_slot(0)
	return BUTTON_AT

## Restart the attempt and go back to the main menu. Both are keys that have
## always worked; these are the same two as things you can click. Empty off the
## pause screen.
func restart_rect() -> Rect2:
	return pause_slot(1)

func menu_rect() -> Rect2:
	return pause_slot(2)

## The music toggle. Empty off the pause screen, which is the only place it is
## offered — and which is what stops a click landing on one that is not drawn.
func music_rect() -> Rect2:
	return pause_slot(3)

func music_label() -> String:
	## What pressing it will DO, not what the music is doing now.
	return "N  /  MUSIC ON" if Music.muted else "N  /  MUSIC OFF"

func _row_rect(i: int) -> Rect2:
	## The level list sits on the parchment, between the heading and the card
	## below it. The rows tighten as the list grows rather than the panel growing:
	## the frame is a fixed piece of art now and cannot be stretched to fit.
	var inner := _face("interior")
	var card := _face("text_box")
	var top: float = inner.position.y + 24.0
	var band: float = maxf(card.position.y - 6.0 - top, ROW_H)
	var rows: float = maxf(float(game.listing().size()), 1.0)
	var h: float = minf(ROW_H, band / rows)
	return Rect2(inner.position.x + 8.0, top + i * h, inner.size.x - 16.0, h)

## Which level row the given point is over, or -1. Only meaningful on the menu.
func row_at(at: Vector2) -> int:
	if not is_instance_valid(game) or game.state != game.State.MENU:
		return -1
	for i in game.listing().size():
		if _row_rect(i).has_point(at):
			return i
	return -1

func _bar(name: String, at: Vector2, fraction: float, empty_tint: Color) -> void:
	## One bar of either kind. `fraction` is 0 to 1; `empty_tint` is only for the
	## fallback rectangles, which is the one place the two bars need telling
	## apart without their art.
	fraction = clampf(fraction, 0.0, 1.0)
	var spec: Dictionary = bars.get(name, {})
	if spec.is_empty():
		var box := Rect2(at.x, at.y + 6.0, bar_size.x * BAR_SCALE, 10.0)
		draw_rect(box, TROUGH)
		box.size.x *= fraction
		draw_rect(box, empty_tint)
		return
	draw_texture_rect(spec.empty, Rect2(at, bar_size * BAR_SCALE), false)
	# Rounded to whole source pixels, or the clip edge shimmers between two
	# columns as the bar changes and the pixel art stops looking like pixel art.
	var fill: Vector2 = spec.fill
	var edge := roundf(lerpf(fill.x, fill.y, fraction))
	if edge > 0.0:
		var clip: AtlasTexture = spec.clip
		clip.region = Rect2(0, 0, edge, bar_size.y)
		draw_texture_rect(clip, Rect2(at, Vector2(edge, bar_size.y) * BAR_SCALE), false)

func _meters() -> void:
	## The two bars and their numbers, stacked in the corner.
	##
	## Green is life, blue is the blast: the bars are cut that way round by
	## scripts/extract_hud_bars.py, so the colour lives in the art rather than in
	## a tint here, and the fallback rectangles below match it.
	##
	## Both draw their EASED fill, not the player's raw fraction — see _process.
	## The numbers beside them are the real values, so the figure is right the
	## instant it changes while the bar is still catching up to it.
	var health_at := BAR_AT
	var mana_at := BAR_AT + Vector2(0, BAR_STEP)
	_bar("health", health_at, float(shown["health"]),
		Color("a23e36") if game.player.health_fraction() < 0.34 else Color("2f9e5a"))
	_bar("mana", mana_at, float(shown["mana"]), Color("2f7fb9"))
	# Baselines set against the middle of each bar rather than its top edge, so
	# the number reads as belonging to the bar beside it.
	var number_x := BAR_AT.x + bar_size.x * BAR_SCALE + 10.0
	var middle := bar_size.y * BAR_SCALE / 2.0 + 5.0
	over_level("%d" % game.player.health, Vector2(number_x, health_at.y + middle), 13)
	over_level("%d" % game.player.mana, Vector2(number_x, mana_at.y + middle), 13)

func bar_rect(name: String) -> Rect2:
	## Where a bar is drawn, in HUD coordinates. The same two numbers _meters
	## lays them out from, so a cue pointing at one cannot drift off it.
	var at := BAR_AT + Vector2(0.0, BAR_STEP if name == "mana" else 0.0)
	return Rect2(at, bar_size * BAR_SCALE)

func _boss_plate() -> void:
	## The boss's health, across the bottom of the screen. Nothing at all while
	## no boss is fighting, which is every level but the last two.
	##
	## Magma under green, so the band of red that opens between them after a
	## hit is the damage: they are the same number at two speeds. Where two
	## bosses fight at once they are instead one bar each, and an empty track is
	## a boss already beaten rather than a bar waiting to fill.
	##
	## Each fill is a STRIP the size of its own track, not a whole lit plate,
	## which is what keeps one from painting over the other — see the note in
	## scripts/extract_boss_bar.py, where drawing whole plates erased all of
	## the magma bar except the sliver between the two levels.
	if boss_plate == null or game.boss_main() == null:
		return
	var at := Vector2((640.0 - boss_size.x * BOSS_SCALE) / 2.0, BOSS_Y)
	draw_texture_rect(boss_plate, Rect2(at, boss_size * BOSS_SCALE), false)
	for name in boss_bars:
		var spec: Dictionary = boss_bars[name]
		var size: Vector2 = spec.size
		# Rounded to whole source pixels, or the clip edge shimmers between two
		# columns as the bar drains.
		var edge := roundf(size.x * clampf(float(boss_shown[name]), 0.0, 1.0))
		if edge <= 0.0:
			continue
		var clip: AtlasTexture = spec.clip
		clip.region = Rect2(0, 0, edge, size.y)
		draw_texture_rect(clip,
			Rect2(at + spec.at * BOSS_SCALE, Vector2(edge, size.y) * BOSS_SCALE), false)

## How near the gate he has to be before the chevron appears, and how far in
## from the right edge of the screen it sits.
const GATE_CUE_RANGE := 300.0
const GATE_CUE_X := 596.0

func _gate_cue() -> void:
	## A chevron at the right edge once the section is clear: the way on is open.
	## No word, because nothing on the play HUD is words any more — and an arrow
	## pointing the way out needs none.
	##
	## Nothing is drawn while the gate is shut. The stopped camera is the message
	## there: he can see he has run out of screen.
	if game.gates.is_empty():
		return
	var index: int = game.section_of(game.player.position.x)
	if index >= game.gates.size() or not game.section_clear(index):
		return
	var gate: float = float(game.gates[index])
	if gate - game.player.position.x > GATE_CUE_RANGE:
		return
	# Pulsed off the attempt clock rather than a clock of its own, so it does not
	# keep beating while the game is paused.
	var pulse: float = 0.55 + 0.45 * sin(game.elapsed * 5.0)
	var mid := 40.0
	var tint := Color("2fb98a")
	tint.a = pulse
	for step in 2:
		var x := GATE_CUE_X - 26.0 + float(step) * 13.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, mid - 11.0), Vector2(x + 9.0, mid), Vector2(x, mid + 11.0),
			Vector2(x - 5.0, mid + 11.0), Vector2(x + 4.0, mid),
			Vector2(x - 5.0, mid - 11.0)]), tint)

func teaches() -> bool:
	## Whether this level prompts at all — `hints` in the level file.
	##
	## First Steps is the only one that sets it, and that is the point of it:
	## the course teaches lifting, throwing, drinking, the fist and the blast in
	## its first level, and a game still naming keys three levels later has not
	## taught anything. Off, nothing is cued over anything. The gate chevron
	## stays on every level, because that is the camera answering a question you
	## are asking rather than a lesson you have already had.
	return bool(game.level.get("hints", false))

func _cue_fade(slot: String, showing: String) -> float:
	## How far into its fade the cue in this slot is. Keyed on WHAT it is —
	## "lift", "drink" — and not on the words, because the drink cue counts down
	## and would otherwise restart every tenth of a second and never arrive.
	var mark: Array = cue_seen.get(slot, [])
	if mark.size() != 2 or str(mark[0]) != showing:
		mark = [showing, game.elapsed]
		cue_seen[slot] = mark
	# Clamped both ways: a retry puts game.elapsed back to zero under a cue that
	# is already up, and a negative age has to read as "just appeared" rather
	# than as a number below the floor.
	return clampf((game.elapsed - float(mark[1])) / CUE_FADE, 0.0, 1.0)

func _fade(tint: Color, by: float) -> Color:
	return Color(tint.r, tint.g, tint.b, tint.a * by)

func cue_box(anchor: Vector2, key: String, label: String, over: float) -> Rect2:
	## Where a cue lands, in HUD coordinates: centred over a point in the WORLD
	## and standing `over` above it, then held inside the frame. Public because
	## this is the whole claim — that a prompt is over the thing it is about
	## rather than in the middle of the screen — and a claim should be testable.
	var font := ThemeDB.fallback_font
	var width := CUE_PAD * 2.0 + font.get_string_size(
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, CUE_TEXT).x
	if key != "":
		width += cap_width(key) + CUE_GAP
	var at: Vector2 = game.to_hud(anchor) - Vector2(width / 2.0, over + CUE_H)
	at.x = clampf(at.x, CUE_EDGE, 640.0 - CUE_EDGE - width)
	at.y = clampf(at.y, CUE_CEILING, 360.0 - CUE_EDGE - CUE_H)
	return Rect2(at, Vector2(width, CUE_H))

func cap_width(key: String) -> float:
	return maxf(ThemeDB.fallback_font.get_string_size(
			key, HORIZONTAL_ALIGNMENT_LEFT, -1, CUE_TEXT).x + 9.0, CUE_CAP_MIN)

func _cue(anchor: Vector2, key: String, label: String, tint: Color,
		over: float, fade: float) -> void:
	var box := cue_box(anchor, key, label, over)
	# The tail is drawn first, and points at the ANCHOR rather than at the
	# middle of the plate: a cue shoved sideways by the edge of the screen still
	# has to say which thing it belongs to. Three rows rather than a triangle,
	# so its edge steps like the art behind it.
	var point: float = clampf(game.to_hud(anchor).x, box.position.x + CUE_PAD,
			box.end.x - CUE_PAD)
	for row in 3:
		var half: float = 3.0 - float(row)
		draw_rect(Rect2(point - half, box.end.y + float(row), half * 2.0, 1.0),
				_fade(CUE_PLATE, fade))
	_cue_plate(box, key, label, tint, fade)

func bar_cue_box(bar: Rect2, label: String) -> Rect2:
	## A cue standing beside a bar, past its number. Its own placement and not
	## cue_box: cue_box measures from a point in the world and is floored below
	## the bars, which is exactly where this one may not go.
	var font := ThemeDB.fallback_font
	var number := font.get_string_size("100", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var width := CUE_PAD * 2.0 + font.get_string_size(
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, CUE_TEXT).x
	# 10 is the gap _meters leaves between the bar and its number.
	var left := bar.end.x + 10.0 + number + BAR_CUE_GAP
	return Rect2(left, bar.position.y + (bar.size.y - CUE_H) / 2.0,
			width, CUE_H)

func _bar_cue(bar: Rect2, label: String, tint: Color, fade: float) -> void:
	var box := bar_cue_box(bar, label)
	# Pointing LEFT at the bar, for the same reason the others point down: a
	# plate floating beside two stacked bars has to say which of them it means.
	var middle: float = box.get_center().y
	for column in 3:
		var half: float = 3.0 - float(column)
		draw_rect(Rect2(box.position.x - 1.0 - float(column), middle - half,
				1.0, half * 2.0), _fade(CUE_PLATE, fade))
	_cue_plate(box, "", label, tint, fade)

func _cue_plate(box: Rect2, key: String, label: String, tint: Color,
		fade: float) -> void:
	var font := ThemeDB.fallback_font
	# Chamfered: the body inset a pixel top and bottom, and a full-height band
	# inset a pixel each side. A square corner on a plate this small is the one
	# thing that would put it back to reading as a debug rectangle.
	draw_rect(Rect2(box.position + Vector2(0.0, 1.0),
			box.size - Vector2(0.0, 2.0)), _fade(CUE_PLATE, fade))
	draw_rect(Rect2(box.position + Vector2(1.0, 0.0),
			box.size - Vector2(2.0, 0.0)), _fade(CUE_PLATE, fade))
	draw_rect(box, _fade(CUE_RIM, fade), false, 1.0)
	var x: float = box.position.x + CUE_PAD
	if key != "":
		var cap := Rect2(x, box.position.y + 3.0, cap_width(key), CUE_H - 6.0)
		draw_rect(cap, _fade(CUE_CAP_FACE, fade))
		var cap_at := Vector2(cap.get_center().x - font.get_string_size(
				key, HORIZONTAL_ALIGNMENT_LEFT, -1, CUE_TEXT).x / 2.0,
				cap.position.y + cap.size.y * 0.78)
		draw_string(font, cap_at, key, HORIZONTAL_ALIGNMENT_LEFT, -1, CUE_TEXT,
				_fade(CUE_CAP_INK, fade))
		x += cap.size.x + CUE_GAP
	draw_string(font, Vector2(x, box.position.y + CUE_H * 0.70), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, CUE_TEXT, _fade(tint, fade))

func _drink_prompt() -> String:
	## One key, three different jobs, so the prompt has to say which one is on
	## offer. Nothing is picked up on contact: the point of the tutorial is that
	## lifting and drinking are both actions you take.
	## Nothing while he drinks. The countdown and its meter used to sit here to
	## say that standing still is the mechanic rather than a fault, but the
	## health bar already says it: the drink arrives mouthful by mouthful, so the
	## bar is climbing the whole time he is stood there.
	action_cue_up = false
	if not teaches() or game.player.is_drinking():
		return ""
	var key := ""
	var label := ""
	var what := ""
	var dim := false
	# Over HIM for the two things he does with his hands, over the ROCK for the
	# one that is about a particular rock. The line this replaced was centred on
	# the screen and could not say which of two crates it meant.
	var anchor: Vector2 = game.player.position
	var over := CUE_OVER_HIM
	var held: Node2D = game.bottle_being_carried()
	var near: Node2D = game.carryable_in_reach()
	if held != null:
		# Holding the bottle: the wait is whatever is left in that one, not a
		# flat six seconds, or a part-drunk bottle looks unchanged. Which bar it
		# fills decides whether "already full" is even the question.
		dim = game.player.refill_full(held.refills)
		what = "full" if dim else "drink"
		key = "" if dim else "HOLD E"
		label = "ALREADY FULL" if dim else "DRINK  %0.1fs" % held.drink_seconds(game.player)
	elif game.player.is_carrying():
		what = "throw"
		key = "J"
		label = "THROW"
	elif near != null:
		what = "lift"
		key = "E"
		label = "LIFT"
		anchor = near.global_position
		over = CUE_OVER_PROP
	else:
		return ""
	_cue(anchor, key, label, CUE_DIM if dim else INK, over,
			_cue_fade("action", what))
	action_cue_up = true
	return key

func bar_lesson() -> String:
	## Which bar wants naming this frame: "health", "mana" or nothing.
	##
	## Drinking wins over the first blast if both are live, because the drink
	## is the thing happening in front of him — and if the bottle is a brew
	## they are the same cue anyway.
	##
	## Public and separate from the drawing so a headless test can ask it. It
	## is not a pure question, though: asking it is what starts and ends the
	## first-blast clock, so nothing but the HUD and its tests should.
	if not teaches():
		return ""
	if game.player.is_drinking() and is_instance_valid(game.drinking_bottle):
		var pour := str(game.drinking_bottle.refills)
		return pour if BAR_WORD.has(pour) else ""
	return "mana" if _first_mana() else ""

func _bar_lesson() -> void:
	var which := bar_lesson()
	if which == "":
		return
	_bar_cue(bar_rect(which), str(BAR_WORD[which]), COACH,
			_cue_fade("bar", which))

func _first_mana() -> bool:
	## True for BLAST_HOLD seconds after the first blast he ever throws, and
	## never again. blasts_thrown is lifetime, so a retry does not replay it.
	if blast_done or game.player.blasts_thrown <= 0:
		return false
	if blast_at < 0.0:
		blast_at = game.elapsed
		return true
	# A retry winds game.elapsed back under a cue that is already up. Rather
	# than restart the lesson, take it as given.
	if game.elapsed < blast_at or game.elapsed - blast_at > BLAST_HOLD:
		blast_done = true
		return false
	return true

func _coach_prompt(taken: String = "") -> void:
	## The level naming a key, for the one thing the shape of a level cannot
	## mime. Everything else on the practice course is taught by geometry — a gap
	## you have to jump, a gate that will not open — but you can stand in front of
	## a bandit indefinitely without ever discovering that J is a fist.
	##
	## Level data, not a rule in here: `coach` is [x_from, x_to, text, action],
	## and the level decides where a line belongs and what retires it. The first
	## line in range whose action has not been done yet is the one on screen, so
	## they arrive in the order the level lists them and each disappears for good
	## once its lesson has landed. See coach_note in levels/first_steps.json.
	##
	## The text is "KEY  /  VERB" and is split on the slash, so the key goes on
	## the cap and the verb beside it. A line with no slash is all verb and gets
	## no cap, which is what a lesson that is not about one key should look like.
	if not teaches():
		return
	var at: float = game.player.position.x
	for entry in game.level.get("coach", []):
		if entry.size() < 4 or at < float(entry[0]) or at > float(entry[1]):
			continue
		if _coached(str(entry[3])):
			continue
		var key := ""
		var label := str(entry[2]).strip_edges()
		var cut := label.find("/")
		if cut > 0:
			key = label.substr(0, cut).strip_edges()
			label = label.substr(cut + 1).strip_edges()
		if key != "" and key == taken:
			# The cue under this one is already naming the key. Nothing is
			# retired — the lesson comes back the moment his hands are empty.
			return
		# Above the lift and drink cue when there is one — the stretch the
		# fight lines are written for has a rock standing in it — and on the
		# lower shelf when there is not.
		_cue(game.player.position, key, label, COACH,
				CUE_OVER_LESSON if action_cue_up else CUE_OVER_HIM,
				_cue_fade("lesson", str(entry[3])))
		return

func _coached(action: String) -> bool:
	## Has he done it? Lifetime counts, so a retry never puts a lesson back.
	match action:
		"strike":
			# Any swing that is not a blast: the jab, the kick and the charge are
			# all the same key and all the same lesson.
			return game.player.attacks_thrown - game.player.blasts_thrown > 0
		"blast":
			return game.player.blasts_thrown > 0
		"jump":
			return game.player.jumps > 0
	return true    # an action nothing knows how to check is already learnt

func _draw() -> void:
	if not is_instance_valid(game):
		return
	## The play HUD is the two bars, their numbers and the progress line, and
	## nothing else. The game title, the level name, the control list, the retry
	## count and the timer were all cleared off the screen: they were static text
	## that never changed while you played, sitting over the level art. What is
	## left either moves (the bars, the progress line) or answers a question you
	## are asking right now (the numbers, the prompts below).
	##
	## Not all of it is gone from the game: the level name is a row on the menu,
	## and the retry count and finish time are on the results panel. They are
	## read between attempts now rather than during one.
	_meters()
	## Spawn to flag, read off the level. It was (x-128)/1704 typed in, which is
	## exactly First Steps' spawn and finish and silently wrong for any other level.
	var from: float = float(game.level.spawn[0])
	var to: float = float(game.level.finish[0])
	var progress: float = clampf((game.player.position.x-from)/maxf(to-from, 1.0), 0, 1)
	draw_rect(Rect2(20,351,600,4), TROUGH)
	draw_rect(Rect2(20,351,600*progress,4), Color("2fb98a"))
	_boss_plate()
	if game.state == game.State.PLAYING:
		_gate_cue()
		# The action cue first, and the lesson is told which key it took. With a
		# rock over his head the cue reads "J / THROW", and a second plate above
		# it reading "J / STRIKE" is the same key twice in a stack.
		_coach_prompt(_drink_prompt())
		_bar_lesson()
		return
	if game.state == game.State.DYING:
		# A defeat screen rather than a one-line hint: the banner reads the same
		# every time, the cause line under it says what finished this attempt (see
		# death_reason in session.gd), and the last line is the retry already under
		# way. The banner carries a heavier ring than the play-HUD default so it
		# holds up as a headline over the level.
		draw_string_outline(ThemeDB.fallback_font, Vector2(0, 152), "MISSION FAILED",
			HORIZONTAL_ALIGNMENT_CENTER, 640, 30, 7, Color(0.04, 0.05, 0.08, 0.85))
		draw_string(ThemeDB.fallback_font, Vector2(0, 152), "MISSION FAILED",
			HORIZONTAL_ALIGNMENT_CENTER, 640, 30, Color("d2483c"))
		_centred_over_level(game.death_reason, 182, 15)
		_centred_over_level("Back at the start in a moment.", 206, 12)
		return
	# Edge to edge. It used to stop short of the two cream strips, which hid the
	# seam; with nothing bracketing the screen any more, a dimmed middle and two
	# bright bands read as a rendering fault rather than as a modal panel.
	# Darker than it was: the panels are stone and parchment now rather than a
	# white card, and a 16% wash left them competing with the level behind them.
	draw_rect(Rect2(0,0,640,360), Color(0.06,0.09,0.13,0.45))
	var r := panel_rect()
	var spec: Dictionary = panels.get(_panel_name(), {})
	if spec.is_empty():
		draw_rect(r, Color("fffdf7"))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 4)), Color("ef875f"))
	else:
		draw_texture_rect(spec.tex, r, false)
	if game.state == game.State.MENU:
		_level_select()
	else:
		_message_panel()
	# Drawn rather than taken from the kit, whose plates all have their word baked
	# in — these say several different things. Their colours are the kit's.
	if game.state == game.State.PAUSED:
		# All four of the row at once, at ONE size — see label_size. Grey but
		# the first: one green confirm and three secondaries is the hierarchy,
		# and the kit letters its own OPTIONS plate in that same grey.
		var row := [_button_label(), "R  /  RESTART", "M  /  MAIN MENU",
				music_label()]
		var row_size := label_size(row, PAUSE_SLOT.x)
		_button_plate(button_rect(), BUTTON_GO, str(row[0]), row_size)
		_button_plate(restart_rect(), BUTTON_PLAIN, str(row[1]), row_size)
		_button_plate(menu_rect(), BUTTON_PLAIN, str(row[2]), row_size)
		_button_plate(music_rect(), BUTTON_PLAIN, str(row[3]), row_size)
	else:
		_button_plate(button_rect(), BUTTON_GO, _button_label())
	if game.state == game.State.MENU:
		# Under the button rather than on the card. It used to be the last line
		# inside the card and it collided with the brief above it — the brief
		# is three lines now and the card is not tall enough for both.
		_centred_over_level("W/S or the arrows to choose.",
				button_rect().end.y + 14.0, 11, Color(0.83, 0.86, 0.90, 0.85))

func label_size(labels: Array, width: float) -> int:
	## The largest size at which EVERY one of these labels fits a plate that
	## wide. One size for the whole row rather than one per button: four plates
	## side by side with the long label a point smaller than the short ones
	## reads as a mistake, and a row is only as legible as its worst fit.
	##
	## The margin is the two rounded ends and their bevels: a label measured
	## against the plate's full width runs into them at both ends, which is
	## what "ENTER / RESUME" did when the pause row went from two buttons at
	## 170 to four at 140.
	var font := ThemeDB.fallback_font
	var room := width - BUTTON_MARGIN
	var size := BUTTON_TEXT
	while size > BUTTON_TEXT_MIN:
		var worst := 0.0
		for label in labels:
			worst = maxf(worst, font.get_string_size(
					str(label), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
		if worst <= room:
			break
		size -= 1
	return size

func _button_plate(box: Rect2, name: String, label: String, size: int = 0) -> void:
	## A button, wearing one of the kit's plates. THREE SLICES: the rounded end
	## at each side at its drawn width, and everything between them stretched
	## to fill. A plate scaled whole would pull its corners out of round, and
	## these are 118 wide against buttons that are 160 to 170.
	##
	## Height is not stretched — the plates are 41 in design units and the
	## boxes are 40, which is inside a pixel and not worth a slice.
	var spec: Dictionary = buttons.get(name, {})
	if spec.is_empty():
		# No art imported: the rectangle this used to be.
		_plate(box, label, BUTTON_FACE if name == BUTTON_GO else BUTTON_OFF,
				BUTTON_LIP if name == BUTTON_GO else BUTTON_OFF_LIP)
		return
	var tex: Texture2D = spec.tex
	var src: Vector2 = spec.size
	var cap: float = spec.cap
	var end: float = minf(cap * PANEL_SCALE, box.size.x * 0.45)
	draw_texture_rect_region(tex, Rect2(box.position, Vector2(end, box.size.y)),
			Rect2(0.0, 0.0, cap, src.y))
	draw_texture_rect_region(tex,
			Rect2(box.position + Vector2(end, 0.0),
				  Vector2(box.size.x - end * 2.0, box.size.y)),
			Rect2(cap, 0.0, src.x - cap * 2.0, src.y))
	draw_texture_rect_region(tex,
			Rect2(box.position + Vector2(box.size.x - end, 0.0),
				  Vector2(end, box.size.y)),
			Rect2(src.x - cap, 0.0, cap, src.y))
	# The word, drawn rather than baked — which is the whole reason the plates
	# could be used at all. Outlined like the kit's own lettering, because a
	# flat label on a shaded face loses its thin strokes.
	var font := ThemeDB.fallback_font
	if size <= 0:
		size = label_size([label], box.size.x)
	var at := Vector2(box.get_center().x
			- font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x / 2.0,
			box.position.y + box.size.y * 0.63)
	draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5,
			BUTTON_EDGE)
	draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, BUTTON_INK)

func _plate(box: Rect2, label: String, face: Color, lip: Color) -> void:
	## A button. Its label is centred on the BOX rather than on the screen, which
	## is why this does not go through centered().
	draw_rect(box, face)
	draw_rect(Rect2(box.position, Vector2(box.size.x, 3.0)), lip)
	draw_rect(box, lip, false, 2.0)
	var w := ThemeDB.fallback_font.get_string_size(
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	text_at(label, Vector2(box.get_center().x - w / 2.0,
			box.position.y + box.size.y * 0.66), 14, Color("f4efe2"))

func _button_label() -> String:
	if game.state == game.State.PAUSED:
		return "ENTER  /  RESUME"
	if game.state == game.State.COMPLETE:
		# The last level has nothing after it, so finishing it replays instead.
		return "ENTER  /  NEXT LEVEL" if game.next_level_id() != "" else "ENTER  /  PLAY AGAIN"
	return "ENTER  /  START"

func _level_select() -> void:
	## The menu is the level select, and it lists EVERY level that ships rather
	## than the course: the course is what a new journey walks through, and this
	## is what you are allowed to pick. See listing() in session.gd. Each title
	## comes from the level file itself, so adding a level is one line in the
	## index and nothing here.
	var inner := _face("interior")
	var card := _face("text_box")
	var order: Array = game.listing()
	# On the parchment, above the card. The panel's own headstone already carries
	# the game's name, so this only has to say what the list is for. Shadowed,
	# because the parchment is a painted texture rather than a flat fill and
	# flat ink on it reads as washed out.
	var font := ThemeDB.fallback_font
	var head := "Choose a level."
	var head_w := font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var head_at := Vector2((640.0 - head_w) / 2.0, inner.position.y + 17.0)
	draw_string(font, head_at + Vector2(1.0, 1.0), head, HORIZONTAL_ALIGNMENT_LEFT,
			-1, 18, Color(0.35, 0.20, 0.11, 0.45))
	draw_string(font, head_at, head, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, INK)
	for i in order.size():
		var row := _row_rect(i)
		var picked: bool = i == game.menu_index
		if picked:
			# A burnt-in mark on the parchment with a lit top edge, which is
			# how every raised thing on the kit's own frames is drawn. The old
			# flat block belonged to the white card it used to sit on.
			draw_rect(row, Color(0.24, 0.13, 0.08, 0.52))
			draw_rect(Rect2(row.position, Vector2(row.size.x, 1.0)),
					Color(0.85, 0.66, 0.42, 0.55))
			draw_rect(Rect2(row.position + Vector2(0.0, row.size.y - 1.0),
					Vector2(row.size.x, 1.0)), Color(0.12, 0.06, 0.03, 0.40))
		var baseline := Vector2(row.position.x + 10.0,
				row.position.y + row.size.y - 6.0)
		# The number in the parchment's own brown rather than the body ink, so
		# the eye runs down the titles and not down the digits.
		text_at("%d." % (i + 1), baseline, 14,
				Color("ffeeca") if picked else Color(0.42, 0.26, 0.15, 0.85))
		text_at(game.level_title(order[i]), baseline + Vector2(22.0, 0.0), 14,
				Color("ffeeca") if picked else INK)
	# What the highlighted level is, on the card below the list — which is what
	# that card is drawn for. THREE lines, not two: the briefs are whole
	# sentences and two of them cut First Steps off at "one thing you have not".
	var chosen: String = order[clampi(game.menu_index, 0, order.size() - 1)]
	wrapped(str(game.level_data(chosen).get("brief", "")), card,
			card.position.y + 16.0, 12, 3)

func _message_panel() -> void:
	## The pause screen and the results screen, which share the pop-up.
	##
	## PAUSED says where you are and how the attempt is going, and nothing
	## else. It used to carry "One jump. No double jump. Unlimited retries."
	## along the bottom — a rule sheet, on the screen you open when you already
	## know the rules and want to do something — and a line of prose telling
	## you about two keys that are now buttons under it. Both are gone.
	var title := str(game.level.get("tagline", ""))
	var detail := str(game.level.get("brief", ""))
	var foot := ""
	if game.state == game.State.PAUSED:
		title = "Take a breath."
		detail = game.level_title(game.level_id)
		foot = "%s on the clock   /   %s" % [_clock(game.elapsed), _tries(game.deaths)]
	elif game.state == game.State.COMPLETE:
		title = "Course complete."
		detail = "%s   /   %s" % [_clock(game.last_finish_time), _tries(game.deaths)]
		foot = ("Next: %s" % game.level_title(game.next_level_id())
				if game.next_level_id() != ""
				else "The end of the course. ENTER plays it again.")
	var card := _face("text_box")
	centered(title, card.position.y + 30.0, 22)
	wrapped(detail, card, card.position.y + 54.0, 13)
	wrapped(foot, card, card.end.y - 24.0, 12, 2, Color(0.35, 0.40, 0.47))

func _clock(seconds: float) -> String:
	## Minutes and seconds. A bare "137.4 seconds" is a number to work out
	## rather than a time to read, and an attempt at the Isles is minutes long.
	var whole := int(maxf(seconds, 0.0))
	return "%d:%02d" % [whole / 60, whole % 60]

func _tries(deaths: int) -> String:
	return "no retries" if deaths == 0 else "%d retr%s" % [deaths,
			"y" if deaths == 1 else "ies"]
