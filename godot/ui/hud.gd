extends Control
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

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	## Linear, because the bar art is a reduction of a painted sheet rather than
	## pixel art, and because the HUD only lands texel-perfect at 1280x720 — at
	## any other window size BAR_SCALE x 1.5 x magnification is not an integer and
	## nearest sampling would break the frame's straight edges up unevenly.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_load_bars()
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
## Borrowed off the kit's own START plate. The kit's buttons are not used — see
## the note in extract_panels.py — but its green is.
const BUTTON_FACE := Color("498c69")
const BUTTON_LIP := Color("6fb98a")

## Only the fallback shape, for a checkout that has not imported the art yet.
const PANEL_W := 340.0
const PANEL_MID := 182.5
const ROW_H := 22.0

## name -> {tex, size, interior, text_box}. Empty if the art is missing, which
## puts every panel back on the plain rectangle it used to be.
var panels := {}

func _load_panels() -> void:
	var text := FileAccess.get_file_as_string(PANELS)
	if text.is_empty():
		push_warning("hud: %s is missing. Run scripts/extract_panels.py." % PANELS)
		return
	var data: Dictionary = JSON.parse_string(text)
	for name in data:
		var spec: Dictionary = data[name]
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

func button_rect() -> Rect2:
	return BUTTON_AT

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
	if game.state == game.State.PLAYING:
		_gate_cue()
		_coach_prompt()
		_drink_prompt()
		return
	if game.state == game.State.DYING:
		_centred_over_level(game.death_reason, 155, 21, Color("a23e36"))
		_centred_over_level("Back at the start in a moment.", 180, 13)
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
	# in — this one says four different things. Its colours are the kit's.
	var button := button_rect()
	draw_rect(button, BUTTON_FACE)
	draw_rect(Rect2(button.position, Vector2(button.size.x, 3.0)), BUTTON_LIP)
	draw_rect(button, BUTTON_LIP, false, 2.0)
	centered(_button_label(), button.position.y + button.size.y * 0.66, 14,
			Color("f4efe2"))

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
	# the game's name, so this only has to say what the list is for.
	centered("Choose a level.", inner.position.y + 17.0, 18)
	for i in order.size():
		var row := _row_rect(i)
		var picked: bool = i == game.menu_index
		if picked:
			# A burnt-in mark on the parchment. The old green block belonged to the
			# white card it used to sit on.
			draw_rect(row, Color(0.24, 0.13, 0.08, 0.50))
		text_at("%d.  %s" % [i + 1, game.level_title(order[i])],
				Vector2(row.position.x + 10, row.position.y + row.size.y - 6.0), 14,
				Color("ffeeca") if picked else INK)
	# What the highlighted level is, on the card below the list — which is what
	# that card is drawn for.
	var chosen: String = order[clampi(game.menu_index, 0, order.size() - 1)]
	wrapped(str(game.level_data(chosen).get("brief", "")), card, card.position.y + 18.0, 12)
	centered("W/S or the arrows to choose.", card.end.y - 10.0, 12)

func _message_panel() -> void:
	var title := str(game.level.get("tagline", ""))
	var detail := str(game.level.get("brief", ""))
	var foot := "One jump. No double jump. Unlimited retries."
	if game.state == game.State.PAUSED:
		title = "Take a breath."
		detail = "R: restart attempt    M: main menu"
	elif game.state == game.State.COMPLETE:
		title = "Course complete."
		detail = "%.1f seconds   /   %d retries" % [game.last_finish_time, game.deaths]
		if game.next_level_id() != "":
			foot = "Next: %s" % game.level_title(game.next_level_id())
	var card := _face("text_box")
	centered(title, card.position.y + 30.0, 22)
	wrapped(detail, card, card.position.y + 52.0, 12)
	wrapped(foot, card, card.end.y - 22.0, 12)
