extends Control
var game: Node2D
const INK := Color("25354a")

## The health bar is the mech-healthbar asset, cut into a full and an empty
## version by scripts/extract_healthbar.py. The empty one is drawn, then the
## full one clipped to the player's health, so the segments and the amber
## under-bar fill together and a segment can sit half-lit at the clip edge.
const HEALTHBAR := "res://ui/art/healthbar.json"
const HEALTHBAR_ART := "res://ui/art/"
## Drawn at twice its size. At 1:1 a 53 px bar is dwarfed by 12 px HUD text.
const HB_SCALE := 2.0

var hb_empty: Texture2D
## An AtlasTexture whose region is narrowed each frame, rather than
## draw_texture_rect_region, which renders the art as flat white here.
var hb_clip: AtlasTexture
var hb_size := Vector2(53, 12)
var hb_fill := Vector2(13, 44)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load_healthbar()

func _load_healthbar() -> void:
	var text := FileAccess.get_file_as_string(HEALTHBAR)
	if text.is_empty():
		push_warning("hud: %s is missing. Run scripts/extract_healthbar.py." % HEALTHBAR)
		return
	var data: Dictionary = JSON.parse_string(text)
	hb_size = Vector2(float(data.size[0]), float(data.size[1]))
	hb_fill = Vector2(float(data.fill_x0), float(data.fill_x1))
	var empty_path: String = HEALTHBAR_ART + str(data.files.empty)
	var full_path: String = HEALTHBAR_ART + str(data.files.full)
	if not ResourceLoader.exists(empty_path) or not ResourceLoader.exists(full_path):
		push_warning("hud: health bar art not imported yet; falling back to a plain bar")
		return
	hb_empty = load(empty_path)
	hb_clip = AtlasTexture.new()
	hb_clip.atlas = load(full_path)

func text_at(text: String, position: Vector2, size_px: int = 14, color: Color = INK) -> void:
	draw_string(ThemeDB.fallback_font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

func centered(text: String, y: float, font_size: int, color: Color = INK) -> void:
	var width := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	text_at(text, Vector2((640-width)/2, y), font_size, color)

func _health(at: Vector2) -> void:
	## He starts on very little health on purpose, so the bar reads as a problem
	## before the bottle is ever found: one segment of five, and the heart is the
	## only thing saying what it means.
	var fraction: float = clampf(game.player.health_fraction(), 0.0, 1.0)
	if hb_empty == null or hb_clip == null:
		# The art is generated, so a fresh checkout that has not been imported
		# yet still gets a readable bar rather than nothing at all.
		text_at("HEALTH %d" % game.player.health, at + Vector2(0,15), 12)
		draw_rect(Rect2(at.x+80, at.y+8, 110, 8), Color("daddd6"))
		draw_rect(Rect2(at.x+80, at.y+8, 110*fraction, 8),
			Color("a23e36") if fraction < 0.34 else Color("287c68"))
		return
	draw_texture_rect(hb_empty, Rect2(at, hb_size * HB_SCALE), false)
	# Rounded to whole source pixels, or the clip edge shimmers between two
	# columns as health changes and the pixel art stops looking like pixel art.
	var edge := roundf(lerpf(hb_fill.x, hb_fill.y, fraction))
	if edge > 0.0:
		hb_clip.region = Rect2(0, 0, edge, hb_size.y)
		draw_texture_rect(hb_clip, Rect2(at, Vector2(edge, hb_size.y) * HB_SCALE), false)
	# Baseline matched to the rest of the strip rather than to the bar.
	text_at("%d" % game.player.health, Vector2(at.x + hb_size.x * HB_SCALE + 10, 353), 12)

func _drink_prompt() -> void:
	## Only while a bottle is in reach. The bottle is not picked up on contact
	## because the point of it here is to teach that drinking is an action.
	if game.player.is_drinking():
		_drink_progress()
		return
	if game.bottle_in_reach == null:
		return
	var full: bool = game.player.health >= game.player.MAX_HEALTH
	# The wait is whatever is left in that bottle, not a flat six seconds, so the
	# prompt has to quote the real figure or a part-drunk bottle looks unchanged.
	var wait: float = game.bottle_in_reach.drink_seconds(game.player)
	var label := "ALREADY FULL" if full else "HOLD E  /  DRINK  %0.1fs" % wait
	# Clear of the ground line, so it never sits on top of the level geometry.
	draw_rect(Rect2(245,256,150,26), Color("fffdf7"))
	draw_rect(Rect2(245,256,150,3), Color("ef875f"))
	centered(label, 275, 13, Color("daddd6") if full else INK)

func _drink_progress() -> void:
	## Seconds of a looping animation and nothing else reads as the game having
	## hung. The countdown is the only thing telling the player that standing
	## still is the mechanic rather than a fault — and since health now arrives
	## mouthful by mouthful, the bar beside it is moving too.
	var progress: float = game.player.drink_progress()
	var left: float = game.player.drink_remaining()
	draw_rect(Rect2(245,250,150,34), Color("fffdf7"))
	draw_rect(Rect2(245,250,150,3), Color("287c68"))
	centered("KEEP STILL   %0.1fs" % left, 268, 13)
	draw_rect(Rect2(255,273,130,5), Color("daddd6"))
	draw_rect(Rect2(255,273,130*progress,5), Color("287c68"))

func _draw() -> void:
	if not is_instance_valid(game):
		return
	draw_rect(Rect2(0,0,640,74), Color("f6f3ec"))
	text_at("WALKER / JUMPMAN", Vector2(22,27), 18)
	text_at("FIRST STEPS", Vector2(497,27), 14)
	text_at("A/D: move  Space: jump  J: attack  K: blast  E: drink  R: retry  Esc: pause", Vector2(22,50), 12)
	draw_rect(Rect2(22,63,596,3), Color("daddd6"))
	var progress: float = clampf((game.player.position.x-128)/1704, 0, 1)
	draw_rect(Rect2(22,63,596*progress,3), Color("287c68"))
	# Five pixels taller than it was: the health bar is 24 px at double size and
	# the old 25 px strip left it hanging off the bottom of the screen.
	draw_rect(Rect2(0,330,640,30), Color("f6f3ec"))
	_health(Vector2(22,333))
	text_at("No lives. Just another try.", Vector2(176,353), 12)
	text_at("RETRIES %02d     %04.1fs" % [game.deaths, game.elapsed], Vector2(440,353), 13)
	if game.state == game.State.PLAYING:
		_drink_prompt()
		return
	if game.state == game.State.DYING:
		draw_rect(Rect2(180,128,280,68), Color("fff9ee"))
		centered(game.death_reason, 155, 21, Color("a23e36"))
		centered("Back at the start in a moment.", 180, 13)
		return
	draw_rect(Rect2(0,74,640,261), Color(0.10,0.16,0.20,0.16))
	draw_rect(Rect2(163,103,318,159), Color("fffdf7"))
	draw_rect(Rect2(163,103,318,4), Color("ef875f"))
	var title := "First steps. Real jumps."
	var detail := "Cross two gaps. Clear the spikes. Reach the flag."
	var button := "ENTER  /  START"
	if game.state == game.State.PAUSED:
		title = "Take a breath."
		detail = "R: restart attempt    M: main menu"
		button = "ENTER  /  RESUME"
	elif game.state == game.State.COMPLETE:
		title = "Course complete."
		detail = "%.1f seconds   /   %d retries" % [game.last_finish_time, game.deaths]
		button = "ENTER  /  PLAY AGAIN"
	centered(title, 143, 24)
	centered(detail, 177, 12)
	centered("One jump. No double jump. Unlimited retries.", 197, 12)
	draw_rect(Rect2(220,215,200,34), Color("287c68"))
	centered(button, 237, 14, Color("fffdf7"))
