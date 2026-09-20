extends Control

## The front end. Boots a session.gd of its own when a row is chosen, which is
## why project.godot starts here rather than at game/main.tscn.

const Session = preload("res://game/session.gd")
const Music = preload("res://game/music.gd")
const Storyboard = preload("res://ui/storyboard.gd")
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

## Where PRACTICE drops in. First Steps is the practice course: the same cliffs,
## sea and cast as The Fractured Isles, cut into five short stretches that each
## ask for one thing the player has not done yet.
##
## It is also the first level of the course now, so this row and NEW JOURNEY
## land in the same place. They are not the same thing — a journey carries on
## into the Isles when you reach the flag and this drops you in for the practice
## alone — but with no save files between them there is nothing yet to tell them
## apart. Worth collapsing into one row the day finishing a level records
## anything.
const PRACTICE_LEVEL := "first_steps"

## The menu's music. The same loop The Fractured Isles plays, because the pack
## ships one and the course is that level: the handoff is seamless rather than
## two tracks colliding. First Steps names the same track, so PRACTICE carries
## straight on from the menu as well — it used to be the one row that cut the
## music off, back when it booted a greybox slice.
const TRACK := "magic_cliffs"

var index: int = 0

func _ready() -> void:
	# The plates and the backdrop are opaque art, so the menu owns the whole
	# frame and the clear colour never shows.
	mouse_filter = Control.MOUSE_FILTER_STOP
	# session.gd registers the same actions when it boots, and both sides skip
	# any action that already exists, so whichever runs first wins harmlessly.
	Session.setup_input()
	# The Fractured Isles names this same loop, so NEW JOURNEY does not restart
	# it — see music.gd on why the node outlives this scene.
	Music.cue(get_tree(), TRACK)

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
			# The course order's first level — First Steps, and on into the Isles
			# when you reach its flag. Not named here: which level a new journey
			# opens on is index.json's decision, and this row follows the order.
			#
			# The one row that does not boot straight into its level: a new
			# journey opens on the storyboard, and that hands off to the level
			# named here when it ends or is skipped. PRACTICE deliberately does
			# not — it is the course played for its own sake, and an opening you
			# have already watched is not something to sit through again to
			# reach it.
			Storyboard.open(get_tree(), Session.catalogue()[0])
		"practice":
			_boot(PRACTICE_LEVEL, true)
		"select":
			# No save files exist, so this opens the session's own level list
			# instead: it boots without starting, which leaves it in State.MENU.
			# That list is every level that ships, not just the course — see
			# listing() in session.gd — so this row is how you pick one.
			_boot(Session.listing()[0], false)
		"quit":
			get_tree().quit()

func _boot(level_id: String, playing: bool) -> void:
	## Hands off to a session and takes the title out of the tree. The handoff
	## itself lives in Session.boot, because the storyboard makes the same one
	## at the end of the opening and the two must not drift: the session is
	## built there rather than by loading game/main.tscn so that level_id is set
	## before add_child, which is the order session.gd documents for booting
	## straight into a level.
	Session.boot(get_tree(), level_id, playing)

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
