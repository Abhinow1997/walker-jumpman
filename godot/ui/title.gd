extends Control

## The front end. Boots a session.gd of its own when a row is chosen, which is
## why project.godot starts here rather than at game/main.tscn.

const Session = preload("res://game/session.gd")
const BACKDROP := preload("res://ui/art/title_bg.png")

## Each plate is its own sheet crop, already scaled to the size it is drawn at,
## so nearest-neighbour filtering lands one texel per pixel. Reordering these
## reorders the menu; nothing else knows the sequence.
const ROWS := [
	{"tex": preload("res://ui/art/new_journey.png"), "act": "journey"},
	{"tex": preload("res://ui/art/load_game.png"), "act": "select"},
	{"tex": preload("res://ui/art/practice.png"), "act": "practice"},
	{"tex": preload("res://ui/art/quit.png"), "act": "quit"},
]

const PLATE := Vector2(320, 64)
const FIRST_ROW_Y := 212.0
## Plate height plus the gap between them.
const ROW_PITCH := 74.0
## The backdrop is authored at the viewport size, so the design space below is
## the viewport and needs no scaling.
const DESIGN := Vector2(960, 540)

## Unselected plates are dimmed rather than the selected one being enlarged:
## the art is drawn 1:1 and any scaling would resample it under nearest filtering.
const DIM := Color(0.62, 0.66, 0.70)
## Picked out of the cracks in the plates so the highlight belongs to the art.
const GLOW := Color(0.31, 0.85, 0.91)

## Where PRACTICE drops in. Proving Ground is the prototyping slice, so it is
## the sandbox; NEW JOURNEY instead starts the course at its first level and
## advances through it. Using DEFAULT_LEVEL here would make the two rows
## identical, since it is also the first level in the course.
const PRACTICE_LEVEL := "proving_ground"

var index: int = 0

func _ready() -> void:
	# The plates and the backdrop are opaque art, so the menu owns the whole
	# frame and the clear colour never shows.
	mouse_filter = Control.MOUSE_FILTER_STOP
	# session.gd registers the same actions when it boots, and both sides skip
	# any action that already exists, so whichever runs first wins harmlessly.
	Session.setup_input()

func _plate_rect(row: int) -> Rect2:
	return Rect2(Vector2((DESIGN.x - PLATE.x) * 0.5, FIRST_ROW_Y + row * ROW_PITCH), PLATE)

func _row_at(point: Vector2) -> int:
	for i in ROWS.size():
		if _plate_rect(i).has_point(point):
			return i
	return -1

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed("menu_up"):
		index = posmod(index - 1, ROWS.size())
		queue_redraw()
	elif event.is_action_pressed("menu_down"):
		index = posmod(index + 1, ROWS.size())
		queue_redraw()
	elif event.is_action_pressed("confirm"):
		_choose(index)
	else:
		return
	get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hovered := _row_at(event.position)
		if hovered >= 0 and hovered != index:
			index = hovered
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var row := _row_at(event.position)
		if row >= 0:
			index = row
			queue_redraw()
			_choose(row)

func _choose(row: int) -> void:
	match ROWS[row]["act"]:
		"journey":
			# The course order's first level, so adding a prologue ahead of
			# first_steps in index.json changes where NEW JOURNEY lands.
			_boot(Session.catalogue()[0], true)
		"practice":
			_boot(PRACTICE_LEVEL, true)
		"select":
			# No save files exist, so this opens the session's own level list
			# instead: it boots without starting, which leaves it in State.MENU.
			_boot(Session.catalogue()[0], false)
		"quit":
			get_tree().quit()

func _boot(level_id: String, playing: bool) -> void:
	## Hands off to a session and takes the title out of the tree. The session is
	## built here rather than by loading game/main.tscn so that level_id is set
	## before add_child, which is the order session.gd documents for booting
	## straight into a level.
	var game := Session.new()
	game.level_id = level_id
	var outgoing := get_tree().current_scene
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	if playing:
		game.start_session()
	outgoing.queue_free()

func _draw() -> void:
	draw_texture_rect(BACKDROP, Rect2(Vector2.ZERO, DESIGN), false)
	for i in ROWS.size():
		var rect := _plate_rect(i)
		var picked := i == index
		draw_texture_rect(ROWS[i]["tex"], rect, false, Color.WHITE if picked else DIM)
		if picked:
			draw_rect(rect.grow(2.0), GLOW, false, 2.0)
			# Sits in the gap to the left of the column, pointing at the row.
			var mid := rect.position.y + PLATE.y * 0.5
			draw_colored_polygon(PackedVector2Array([
				Vector2(rect.position.x - 26.0, mid - 11.0),
				Vector2(rect.position.x - 26.0, mid + 11.0),
				Vector2(rect.position.x - 10.0, mid),
			]), GLOW)
	var font := ThemeDB.fallback_font
	var hint := "ARROW KEYS: Move Selection    SPACE: Confirm"
	# Shadowed: the hint sits over grass and cliff edge, which is too busy for
	# flat text.
	draw_string(font, Vector2(1.0, 523.0), hint, HORIZONTAL_ALIGNMENT_CENTER,
				DESIGN.x, 15, Color(0.0, 0.0, 0.0, 0.7))
	draw_string(font, Vector2(0.0, 522.0), hint, HORIZONTAL_ALIGNMENT_CENTER,
				DESIGN.x, 15, Color(0.95, 0.97, 0.98))
