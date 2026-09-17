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

## Replaced by whatever hud_bars.json reports; this is only what the fallback
## rectangles are sized against if the art is missing. Keep it at NATIVE.
var bar_size := Vector2(320, 52)
## name -> {empty: Texture2D, clip: AtlasTexture, fill: Vector2}. `clip` is an
## AtlasTexture whose region is narrowed each frame, rather than
## draw_texture_rect_region, which renders the art as flat white here.
var bars := {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	## Linear, because the bar art is a reduction of a painted sheet rather than
	## pixel art, and because the HUD only lands texel-perfect at 1280x720 — at
	## any other window size BAR_SCALE x 1.5 x magnification is not an integer and
	## nearest sampling would break the frame's straight edges up unevenly.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_load_bars()

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

func _centred_over_level(text: String, y: float, font_size: int, color: Color = INK) -> void:
	var width := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	over_level(text, Vector2((640-width)/2, y), font_size, color)

## --- the panel the menu, the pause screen and the results share -------------
##
## The menu grew a row per level, so the panel is sized from its contents rather
## than being the one fixed rectangle it used to be. The session hit-tests
## clicks against button_rect() and row_at() rather than repeating the numbers.

const PANEL_W := 340.0
## The pause and results panel is the original 318x159 one, so PANEL_MID is set
## to leave it exactly where it was; the menu grows downward from the same middle.
const PANEL_MID := 182.5
const ROW_H := 22.0

func _panel_height() -> float:
	## Roughly six levels before the list runs into the button. Past that the
	## menu needs to scroll rather than grow.
	if game.state == game.State.MENU:
		return 140.0 + game.catalogue().size() * ROW_H
	return 159.0

func _panel_top() -> float:
	return PANEL_MID - _panel_height() / 2.0

func button_rect() -> Rect2:
	return Rect2(220, _panel_top() + _panel_height() - 47.0, 200, 34)

func _row_rect(i: int) -> Rect2:
	return Rect2((640 - PANEL_W) / 2.0 + 16.0, _panel_top() + 52.0 + i * ROW_H, PANEL_W - 32.0, ROW_H)

## Which level row the given point is over, or -1. Only meaningful on the menu.
func row_at(at: Vector2) -> int:
	if not is_instance_valid(game) or game.state != game.State.MENU:
		return -1
	for i in game.catalogue().size():
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
	## He starts on very little health on purpose, so the bar reads as a problem
	## before the bottle is ever found. Mana starts at three blasts of five, for
	## the same reason in the other direction: enough to learn what K does, not
	## enough to lean on it.
	var health_at := BAR_AT
	var mana_at := BAR_AT + Vector2(0, BAR_STEP)
	_bar("health", health_at, game.player.health_fraction(),
		Color("a23e36") if game.player.health_fraction() < 0.34 else Color("287c68"))
	_bar("mana", mana_at, game.player.mana_fraction(), Color("287c68"))
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
		_drink_prompt()
		return
	if game.state == game.State.DYING:
		_centred_over_level(game.death_reason, 155, 21, Color("a23e36"))
		_centred_over_level("Back at the start in a moment.", 180, 13)
		return
	# Edge to edge. It used to stop short of the two cream strips, which hid the
	# seam; with nothing bracketing the screen any more, a dimmed middle and two
	# bright bands read as a rendering fault rather than as a modal panel.
	draw_rect(Rect2(0,0,640,360), Color(0.10,0.16,0.20,0.16))
	var top := _panel_top()
	var h := _panel_height()
	var left := (640.0 - PANEL_W) / 2.0
	draw_rect(Rect2(left, top, PANEL_W, h), Color("fffdf7"))
	draw_rect(Rect2(left, top, PANEL_W, 4), Color("ef875f"))
	if game.state == game.State.MENU:
		_level_select(top)
	else:
		_message_panel(top)
	var button := button_rect()
	draw_rect(button, Color("287c68"))
	centered(_button_label(), button.position.y + 22.0, 14, Color("fffdf7"))

func _button_label() -> String:
	if game.state == game.State.PAUSED:
		return "ENTER  /  RESUME"
	if game.state == game.State.COMPLETE:
		# The last level has nothing after it, so finishing it replays instead.
		return "ENTER  /  NEXT LEVEL" if game.next_level_id() != "" else "ENTER  /  PLAY AGAIN"
	return "ENTER  /  START"

func _level_select(top: float) -> void:
	## The menu is the level select. It reads the order from levels/index.json
	## and each title from the level file itself, so adding a level is one line
	## in the index and nothing here.
	var order: Array = game.catalogue()
	centered("Choose a level.", top + 34, 20)
	for i in order.size():
		var row := _row_rect(i)
		var picked: bool = i == game.menu_index
		if picked:
			draw_rect(row, Color("287c68"))
		text_at("%d.  %s" % [i + 1, game.level_title(order[i])],
				Vector2(row.position.x + 10, row.position.y + 16), 14,
				Color("fffdf7") if picked else INK)
	var chosen: String = order[clampi(game.menu_index, 0, order.size() - 1)]
	var foot := top + 52.0 + order.size() * ROW_H
	centered(str(game.level_data(chosen).get("brief", "")), foot + 18.0, 12)
	centered("W/S or the arrows to choose.", foot + 34.0, 12)

func _message_panel(top: float) -> void:
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
	centered(title, top + 40, 24)
	centered(detail, top + 74, 12)
	centered(foot, top + 94, 12)
