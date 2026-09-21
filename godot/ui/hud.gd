extends Control

const Music = preload("res://game/music.gd")

var game: Node2D
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
## The plate carries two bars and both are the SAME number. The green one is
## the boss's health now; the magma one under it is that health a moment ago,
## draining to catch up. The band of red between them is what you just took
## off, which is the one thing a single bar cannot show you and the reason the
## art is drawn with two.
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
	# Two tracks, and what they mean depends on how many bosses are up. With ONE
	# they are the same number at two speeds — green now, magma a beat behind, and
	# the band between them is the damage just dealt. With TWO — The Dragon's
	# Roost — they are two DIFFERENT bosses: green is the Dragon Lord on the main
	# track, magma the dragon on the red, each tracking its own live health. See
	# boss_main/boss_second in game/session.gd.
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

func _boss_plate() -> void:
	## The boss's health, across the bottom of the screen. Nothing at all while
	## no boss is fighting, which is every level but the last two.
	##
	## Magma under green, so the band of red that opens between them after a
	## hit is the damage: they are the same number at two speeds.
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

func _drink_prompt() -> void:
	## One key, three different jobs, so the prompt has to say which one is on
	## offer. Nothing is picked up on contact: the point of the tutorial is that
	## lifting and drinking are both actions you take.
	## Nothing while he drinks. The countdown and its meter used to sit here to
	## say that standing still is the mechanic rather than a fault, but the
	## health bar already says it: the drink arrives mouthful by mouthful, so the
	## bar is climbing the whole time he is stood there.
	if game.player.is_drinking():
		return
	var label := ""
	var dim := false
	var held: Node2D = game.bottle_being_carried()
	if held != null:
		# Holding the bottle: the wait is whatever is left in that one, not a
		# flat six seconds, or a part-drunk bottle looks unchanged. Which bar it
		# fills decides whether "already full" is even the question.
		dim = game.player.refill_full(held.refills)
		label = "ALREADY FULL" if dim else "HOLD E  /  DRINK  %0.1fs" % held.drink_seconds(game.player)
	elif game.player.is_carrying():
		label = "J  /  THROW"
	elif game.carryable_in_reach() != null:
		label = "E  /  LIFT"
	else:
		return
	# Clear of the ground line, so it never sits on top of the level geometry.
	_centred_over_level(label, 275, 13, Color("8d98a2") if dim else INK)

func _coach_prompt() -> void:
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
	var at: float = game.player.position.x
	for entry in game.level.get("coach", []):
		if entry.size() < 4 or at < float(entry[0]) or at > float(entry[1]):
			continue
		if _coached(str(entry[3])):
			continue
		# Above the lift and drink line, which can be on screen at the same time:
		# the stretch this is written for has a rock standing in it.
		_centred_over_level(str(entry[2]), 252, 13, COACH)
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
		_coach_prompt()
		_drink_prompt()
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
