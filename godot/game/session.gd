extends Node2D

const Player = preload("res://features/player/player.gd")
const Hud = preload("res://ui/hud.gd")
const Crate = preload("res://features/combat/crate.gd")
const Blast = preload("res://features/combat/blast.gd")
const Bottle = preload("res://features/combat/bottle.gd")
const Brew = preload("res://features/combat/brew.gd")
const Enemy = preload("res://features/combat/enemy.gd")
const Arrow = preload("res://features/combat/arrow.gd")
const Scenery = preload("res://features/world/scenery.gd")
const Music = preload("res://game/music.gd")
const LEVEL_DIR := "res://levels/"
## What boots, and what every test gets unless it asks for something else.
##
## Deliberately the fixture rather than a level anyone plays: see the why_note in
## levels/greybox.json. Nothing reaches this default in normal play — the title
## screen names the level for both of its rows — so it is the suites' stage and
## nobody else's.
const DEFAULT_LEVEL := "greybox"

## Half the 960x540 viewport. The camera centres on its own position, so this
## is both where it starts and how close to either end of the level it may get
## before the edge would come into shot.
const VIEW_HALF := Vector2(480, 270)
## The HUD is laid out in a 640x360 design space and every coordinate in hud.gd
## is written in it. The viewport is 960x540, so the layer is scaled back up to
## keep the HUD the size it has always been on screen rather than reflowing it.
const HUD_SCALE := 960.0 / 640.0

## Appended to, never reordered: the tests record `state` as a number.
enum State { MENU, PLAYING, PAUSED, DYING, COMPLETE }
var state: State = State.MENU
## Which level this session is running. Assign before add_child() to boot into
## one directly; load_level() is the way to change it once it is running.
var level_id: String = DEFAULT_LEVEL
## Which row the level-select menu is sitting on.
var menu_index: int = 0
static var _catalogue: Array = []
## The extra ids the level list offers beyond the course — see listing().
static var _also_listed: Array = []
static var _levels: Dictionary = {}
var player: CharacterBody2D
var camera: Camera2D
var hud: Control
## Draws the world for a level with a `theme`. Null for the greybox levels,
## which session.gd draws procedurally in _draw() instead.
var scenery: Node2D
## How far the camera may travel vertically, worked out from the level in
## _build_world. The camera used to be pinned at y 500 for every level, which was
## invisible while every level was flat and hid the lower half of the first one
## that was not: the player simply walked off the bottom of the screen.
var view_top: float = 500.0
var view_bottom: float = 500.0
var level: Dictionary
## The section walls, one per entry in the level's `gates`, and the x each one
## stands on. A wall is a real StaticBody2D built once and switched in and out of
## the World layer, rather than added and freed, so nothing has to be rebuilt in
## the middle of a fight.
var gates: Array = []
var gate_walls: Array[StaticBody2D] = []
var hazard_areas: Array[Area2D] = []
var crates: Array[Area2D] = []
var bottles: Array[Area2D] = []
var enemies: Array[Area2D] = []
## The bottle currently in his hand, for the six seconds a drink takes. Held
## separately from bottle_in_reach because the two diverge the moment he steps
## away mid-drink, which is exactly the case that has to be caught.
var drinking_bottle: Area2D = null
var blasts: Array[Node2D] = []
## Arrows in flight, the archer's. Like blasts, they outlive whoever fired them
## and are cleared on reset and level change.
var arrows: Array[Node2D] = []
var goal: Area2D
var deaths: int = 0
var elapsed: float = 0.0
var retry_remaining: float = 0.0
var death_reason: String = ""
var last_finish_time: float = 0.0
var test_mode: bool = false
var contact_settle_ticks: int = 0

func _ready() -> void:
	process_physics_priority = 10
	setup_input()
	_make_fade()
	_build_world()

## Which level is loaded. Set it before add_child() to boot straight into one;
## the default is the tutorial, which is what every test expects.
func load_level(id: String) -> void:
	## Tears the world down and builds the next one in place. The session node
	## itself survives, so the camera, the HUD and every signal the level does
	## not own are re-made rather than re-wired from outside.
	level_id = id
	menu_index = maxi(listing().find(id), 0)
	_clear_world()
	_build_world()
	deaths = 0
	elapsed = 0.0
	last_finish_time = 0.0
	state = State.MENU

func _clear_world() -> void:
	## remove_child before queue_free: freeing is deferred, and a solid still in
	## the tree for one more frame would collide with the level replacing it.
	for child in get_children():
		if child == fade_layer:
			continue  # the black covering the swap outlives the world under it
		remove_child(child)
		child.queue_free()
	hazard_areas.clear()
	crates.clear()
	bottles.clear()
	enemies.clear()
	blasts.clear()
	arrows.clear()
	goal = null
	scenery = null
	player = null
	camera = null
	gates.clear()
	gate_walls.clear()
	hud = null
	drinking_bottle = null

func _build_world() -> void:
	level = level_data(level_id).duplicate(true)
	if level.is_empty():
		return
	# Whatever this level names, or silence. Asking for the track already playing
	# does nothing, so arriving from the title screen — which plays the same loop
	# The Fractured Isles does — carries straight on rather than starting over.
	# A greybox level names none and the music stops. See music.gd.
	Music.cue(get_tree(), str(level.get("music", "")))
	# First child, so it is behind everything, and before the solids so that the
	# terrain it generates from them is already on screen when they exist.
	var theme := str(level.get("theme", ""))
	if theme != "":
		scenery = Scenery.new()
		scenery.game = self
		scenery.theme = theme
		add_child(scenery)
	for entry in level.solids:
		_add_solid(Rect2(entry[0], entry[1], entry[2], entry[3]))
	_add_solid(Rect2(-64, 0, 64, 860))
	_add_solid(Rect2(level.width, 0, 64, 860))
	for entry in level.hazards:
		hazard_areas.append(_add_area(Rect2(entry[0], entry[1], entry[2], entry[3]), 8, true))
	var f: Array = level.finish
	goal = _add_area(Rect2(f[0], f[1], f[2], f[3]), 16, false)
	# Crates are added before the player so he draws over them, and they are
	# Area2D with no collision mask: they are targets, never obstacles. Walking
	# into one does nothing, so no crate can block or alter the platforming route.
	for entry in level.get("crates", []):
		var crate := Crate.new()
		crate.position = Vector2(entry[0], entry[1])
		# A crate is knocked about when hit, so it needs to know where the level
		# gives up on anything that falls.
		crate.fall_limit = float(level.fall_y)
		crates.append(crate)
		add_child(crate)
	# [x, y] or [x, y, segments]. The third value is BAR SEGMENTS, not points:
	# [470, 640, 2] is a bottle worth two of the bar's five bars. It used to be
	# raw points, so an old level file's 50 would now read as fifty bars — check
	# any level authored before this changed.
	#
	# "bottles" is the white milk bottle and fills the health bar; "brews" is the
	# brown one and fills the mana bar. Both are the same prop on the same
	# physics and both land in `bottles`, which is the list of things that can be
	# drunk rather than the list of milk.
	for entry in level.get("bottles", []):
		_add_bottle(Bottle.new(), entry)
	for entry in level.get("brews", []):
		_add_bottle(Brew.new(), entry)
	# Spawned before the player so he draws in front of them, and so `target`
	# can be handed over the moment he exists.
	# [x, y] per enemy, or [x, y, "kind"] to pick which one — "bandit" (the
	# default) or "mark". More is another entry, not more code. `kind` is set
	# before add_child so it is in place when the enemy reads its manifest.
	#
	# A fourth value "perch" says this one does not hold its section's gate. See
	# holds_gate in enemy.gd for why some cannot be allowed to.
	for entry in level.get("enemies", []):
		var foe := Enemy.new()
		foe.position = Vector2(entry[0], entry[1])
		if entry.size() > 2 and str(entry[2]) != "":
			foe.kind = str(entry[2])
		if entry.size() > 3 and str(entry[3]) == "perch":
			foe.holds_gate = false
		foe.fall_limit = float(level.fall_y)
		foe.struck_player.connect(_on_player_struck)
		foe.fired_arrow.connect(_on_arrow_fired)
		enemies.append(foe)
		add_child(foe)
	_build_gates()
	player = Player.new()
	player.blast_fired.connect(_on_blast_fired)
	player.drink_ended.connect(_on_drink_ended)
	player.threw.connect(_on_threw)
	add_child(player)
	player.reset_at(Vector2(level.spawn[0], level.spawn[1]))
	_measure_view()
	camera = Camera2D.new()
	camera.position = Vector2(VIEW_HALF.x, camera_home_y())
	# Straight back to a hard cut: a retry or a level swap is a cut, not a pan.
	camera_held = 0.0
	add_child(camera)
	var layer := CanvasLayer.new()
	layer.scale = Vector2(HUD_SCALE, HUD_SCALE)
	add_child(layer)
	hud = Hud.new()
	hud.game = self
	layer.add_child(hud)
	# Guarded: _build_world runs again on every level change, and connecting a
	# second time would pause the game twice for one lost focus.
	if not get_window().focus_exited.is_connected(_on_focus_lost):
		get_window().focus_exited.connect(_on_focus_lost)
	queue_redraw()

## --- sections ---------------------------------------------------------------
##
## A level may cut itself into sections with `gates`: a list of x positions, each
## the end wall of one section, so three gates make four. While any enemy in a
## section still holds it, that section's wall is solid and the camera stops with
## the wall at the right edge of the screen — you can see you have run out of
## screen rather than out of floor, which is the beat-em-up convention and the
## reason the wall does not need to be drawn. Clearing the section opens both.
##
## Nothing blocks going back. The rule is about not skipping a fight, and a wall
## behind the player only takes away the room he needs to fight in.
##
## A level with no `gates` — both greybox levels — behaves exactly as before.

## How wide the wall is, and how far above and below the level it runs. Tall
## enough that nothing jumps it: the level's own ceiling is well inside this.
const GATE_WALL := Vector2(24.0, 2400.0)
## How far inside the right edge of the screen the wall sits while it is shut.
## Without it the camera stops with the wall exactly on the edge, and a player
## standing against the wall is half off the screen — he is the one thing that
## must never be clipped. A sliver of the ground past the wall shows instead,
## which costs nothing: the wall is at the edge either way.
const GATE_INSET := 48.0

func _build_gates() -> void:
	gates.clear()
	gate_walls.clear()
	for entry in level.get("gates", []):
		var x := float(entry)
		gates.append(x)
		# Built once and switched in and out of the World layer by _sync_gates,
		# rather than created and freed as fights start and end.
		var wall := _add_solid(Rect2(x, -GATE_WALL.y / 2.0, GATE_WALL.x, GATE_WALL.y))
		gate_walls.append(wall)

func section_of(x: float) -> int:
	## Which section a point is in. The last section has no gate, so anything
	## past the final one belongs to it.
	for i in gates.size():
		if x < float(gates[i]):
			return i
	return gates.size()

func section_bounds(index: int) -> Vector2:
	var low: float = 0.0 if index <= 0 else float(gates[index - 1])
	var high: float = float(level.get("width", 0)) if index >= gates.size() else float(gates[index])
	return Vector2(low, high)

func section_holders(index: int) -> Array:
	## The enemies whose gate this is: spawned inside the section and not marked
	## as a perch. Judged on `home`, where it was placed, rather than on where it
	## has walked to — an enemy that chases the player over a line must not hand
	## its gate to the next section.
	var bounds := section_bounds(index)
	var out: Array = []
	for foe in enemies:
		if is_instance_valid(foe) and foe.holds_gate 				and bounds.x <= foe.home.x and foe.home.x < bounds.y:
			out.append(foe)
	return out

func section_clear(index: int) -> bool:
	for foe in section_holders(index):
		if foe.alive():
			return false
	return true

func gate_shut_at() -> float:
	## The x of the wall holding the player in, or INF when he is free to go on.
	## Only his own section can hold him: everything behind him is already clear
	## by definition, and everything ahead is somebody else's fight.
	if gates.is_empty() or not is_instance_valid(player):
		return INF
	var index := section_of(player.position.x)
	if index >= gates.size() or section_clear(index):
		return INF
	return float(gates[index])

func _sync_gates() -> void:
	## One pass a frame: each wall is solid exactly while its own section is not
	## clear. Driven off alive() rather than off a death signal, so a retry —
	## which puts every enemy back on its feet — closes the walls again with no
	## extra bookkeeping.
	for i in gate_walls.size():
		var wall := gate_walls[i]
		if not is_instance_valid(wall):
			continue
		# Layer 1 is World, which is the only thing the player collides with.
		# Dropping to 0 leaves the body in place and lets him walk through it.
		wall.collision_layer = 0 if section_clear(i) else 1

func _add_bottle(bottle: Node2D, entry: Array) -> void:
	## One bottle of either kind, placed and registered. The kind is already
	## settled by the class — see brew.gd on why it cannot be a field set here.
	bottle.position = Vector2(entry[0], entry[1])
	# A bottle is knocked about when hit, same as a crate.
	bottle.fall_limit = float(level.fall_y)
	if entry.size() > 2:
		bottle.refill_segments = int(entry[2])
	bottles.append(bottle)
	add_child(bottle)

## Finishing a level loads the next one in the index. Empty on the last level,
## where there is nothing to advance to.
func next_level_id() -> String:
	var order := catalogue()
	var i := order.find(level_id)
	if i < 0 or i + 1 >= order.size():
		return ""
	return order[i + 1]

func advance_level() -> bool:
	var next := next_level_id()
	if next == "":
		return false
	_swap_now(next)
	return true

# --- the swap between levels -------------------------------------------------

## Changing level is a cut: one frame the flag, the next the new spawn, with
## every pixel on screen different and the music with it. It reads worst at the
## finish, which is where it is always seen — the flag sits about 350 past the
## point the camera stops, so the player is already pressed against the edge of
## a frame that then changes all at once. The screen dips to black and back
## instead, and the swap happens while it is dark.
##
## Presentation only. load_level() and advance_level() still do the work in one
## synchronous call, and test_mode takes that path directly, so a test can call
## confirm(), step two frames and read the result as it always could.
const FADE_OUT := 0.22
const FADE_IN := 0.30
## A moment held at full black between the two halves. Without it the darkest
## frame lasts a single tick and the dip reads as a blink, not a transition.
const FADE_HOLD := 0.09

## Which half is running. Deliberately NOT part of State: the game is still
## COMPLETE or MENU while the screen happens to be dark, and State is recorded
## by the tests as a number that must not shift.
enum Fade { NONE, OUT, HOLD, IN }
var fade_phase: Fade = Fade.NONE
var fade_clock: float = 0.0
## Built in _ready and skipped by _clear_world, because the whole point is that
## it is still covering the screen while the world underneath it is replaced.
var fade_layer: CanvasLayer
var fade_rect: ColorRect
## The level to load once the screen is black. Empty replays the current one.
var swap_to: String = ""

func _make_fade() -> void:
	fade_layer = CanvasLayer.new()
	# Above the HUD, which _build_world adds at the default layer 0.
	fade_layer.layer = 100
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_layer.add_child(fade_rect)
	add_child(fade_layer)

## Take the next level behind a fade. `next_id` empty replays this one.
func begin_swap(next_id: String) -> void:
	if test_mode:
		_swap_now(next_id)
		return
	if fade_phase != Fade.NONE:
		return  # already going; a second confirm must not stack another swap
	swap_to = next_id
	fade_phase = Fade.OUT
	fade_clock = 0.0

func _swap_now(next_id: String) -> void:
	## The swap itself, in one place so the faded path and the immediate one
	## cannot drift. Empty means stay on this level and start it again.
	if next_id != "":
		load_level(next_id)
	start_session()

## Drives the dip. Returns true on the tick the world was replaced, so the
## caller can end its frame there and let the new level start on the next one.
func _advance_fade(delta: float) -> bool:
	fade_clock += delta
	var swapped := false
	match fade_phase:
		Fade.OUT:
			if fade_clock >= FADE_OUT:
				_swap_now(swap_to)
				swap_to = ""
				swapped = true
				fade_phase = Fade.HOLD
				fade_clock = 0.0
		Fade.HOLD:
			if fade_clock >= FADE_HOLD:
				fade_phase = Fade.IN
				fade_clock = 0.0
		Fade.IN:
			if fade_clock >= FADE_IN:
				fade_phase = Fade.NONE
				fade_clock = 0.0
	if is_instance_valid(fade_rect):
		fade_rect.color.a = fade_alpha()
	return swapped

## How black the screen is, 0 to 1. Public so a capture can assert the dip.
func fade_alpha() -> float:
	match fade_phase:
		Fade.OUT:
			return clampf(fade_clock / FADE_OUT, 0.0, 1.0)
		Fade.HOLD:
			return 1.0
		Fade.IN:
			return clampf(1.0 - fade_clock / FADE_IN, 0.0, 1.0)
	return 0.0

## The course order, from levels/index.json. Static because it is the same for
## every session and the menu reads it before a session has been started.
## THE COURSE: what NEW JOURNEY plays through and what each level chains into.
## Not what the level list shows — see listing(), which is a superset.
static func catalogue() -> Array:
	if _catalogue.is_empty():
		_read_index()
	return _catalogue

## EVERY LEVEL THE MENU OFFERS: the course, then anything the index also lists,
## then nothing else. A level can be picked from LOAD GAME without being part of
## the journey, which is the difference between "playable" and "on the course" —
## Proving Ground is playable and is not on the way to anywhere.
##
## Derived from catalogue() rather than read separately, so a test that stands a
## pretend course up in _catalogue gets a menu that matches it.
static func listing() -> Array:
	var out: Array = catalogue().duplicate()
	if _also_listed.is_empty():
		_read_index()
	for id in _also_listed:
		if not out.has(id) and not _hidden(id):
			out.append(id)
	return out

## A level that says `"listed": false` stays out of the list however it is
## reached. The test fixture is the only one, and it is one so that nobody is
## ever offered it as something to play.
static func _hidden(id: String) -> bool:
	return not bool(level_data(id).get("listed", true))

static func _read_index() -> void:
	var text := FileAccess.get_file_as_string(LEVEL_DIR + "index.json")
	var parsed = JSON.parse_string(text) if not text.is_empty() else null
	if parsed == null:
		push_error("levels: %sindex.json is missing or unreadable" % LEVEL_DIR)
	if _catalogue.is_empty():
		_catalogue = parsed.get("order", []) if parsed else []
		# An index that parses but lists nothing would leave the menu indexing
		# an empty array, so it falls back rather than crashing on the title screen.
		if _catalogue.is_empty():
			push_error("levels: index.json lists no levels")
			_catalogue = [DEFAULT_LEVEL]
	if _also_listed.is_empty():
		_also_listed = parsed.get("also_listed", []) if parsed else []

## One level file, parsed once. The menu needs every level's title before any of
## them is loaded, so this is keyed by id rather than held by the session.
static func level_data(id: String) -> Dictionary:
	if not _levels.has(id):
		var text := FileAccess.get_file_as_string(LEVEL_DIR + id + ".json")
		if text.is_empty():
			push_error("levels: %s%s.json is missing" % [LEVEL_DIR, id])
			_levels[id] = {}
		else:
			var parsed = JSON.parse_string(text)
			_levels[id] = parsed if parsed else {}
	return _levels[id]

static func level_title(id: String) -> String:
	return str(level_data(id).get("title", id))

## How high and low the camera may look, from the level's own geometry: never
## far above its highest ledge, never past the line a fall is fatal at.
const SKY_ABOVE := 240.0
const BELOW_FALL := 40.0
## How fast the camera gives back the ground a shut gate was holding it off, in
## px per second. The worst case is finishing a fight with your back to the wall,
## which is about 570 px and takes a bit under two thirds of a second — a pan at
## roughly twice a running player's speed. It used to be one frame.
const GATE_RELEASE := 900.0
## How far behind its own target the camera is being held right now. A shut gate
## is the only thing that sets it and it decays to nothing once the gate lets go,
## so it is zero for the whole of ordinary play — which is why nothing about
## ordinary following changed.
var camera_held: float = 0.0

## The camera only moves when the player leaves a band this tall around its
## centre. Without it the view bobs on every jump, since one jump rises 107.
const CAMERA_DEADZONE := 90.0
## How quickly the view settles back onto him once he lands, per physics tick.
const CAMERA_RECENTRE := 0.06

func _measure_view() -> void:
	var highest: float = INF
	for entry in level.get("solids", []):
		highest = minf(highest, float(entry[1]))
	if highest == INF:
		highest = 500.0
	view_top = highest - SKY_ABOVE + VIEW_HALF.y
	view_bottom = float(level.get("fall_y", 860)) + BELOW_FALL - VIEW_HALF.y
	if view_bottom < view_top:
		# The whole level fits in one screen, so there is nothing to follow.
		view_top = (view_top + view_bottom) * 0.5
		view_bottom = view_top

## A level that names camera_y pins the camera there. The two greybox levels do,
## to keep the framing they were built and screenshotted with; anything authored
## since simply follows, which is what a level with height needs.
func camera_home_y() -> float:
	if level.has("camera_y"):
		return float(level.camera_y)
	if not is_instance_valid(player):
		return clampf(float(level.get("spawn", [0, 500])[1]), view_top, view_bottom)
	return clampf(player.position.y, view_top, view_bottom)

func _follow_y(current: float) -> float:
	if level.has("camera_y"):
		return float(level.camera_y)
	var target: float = current
	if player.position.y < current - CAMERA_DEADZONE:
		target = player.position.y + CAMERA_DEADZONE
	elif player.position.y > current + CAMERA_DEADZONE:
		target = player.position.y - CAMERA_DEADZONE
	# Once he is standing again, ease back onto him. Without this the camera
	# keeps whatever offset the last descent left it with, which puts the horizon
	# a deadzone above his feet and makes him look waist-deep in the sea.
	if player.is_on_floor():
		target = lerpf(target, player.position.y, CAMERA_RECENTRE)
	return clampf(target, view_top, view_bottom)

## Static, and public, because the title screen needs the same menu_up/menu_down/
## confirm bindings before any session exists. Registering is idempotent, so
## whichever of the two runs first defines them and the other no-ops.
static func setup_input() -> void:
	## W/S and the up/down arrows are free during play — movement is A/D and the
	## left/right arrows — so the menu can have them without a mode switch.
	var actions := {"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT], "jump": [KEY_SPACE], "drink": [KEY_E], "attack": [KEY_J, KEY_X], "blast": [KEY_K, KEY_C], "pause": [KEY_ESCAPE, KEY_P], "restart": [KEY_R], "confirm": [KEY_ENTER], "menu": [KEY_M], "menu_up": [KEY_W, KEY_UP], "menu_down": [KEY_S, KEY_DOWN]}
	for action in actions:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in actions[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)

## Installs a session as the current scene and frees the screen it replaces.
## Static, and public, because two front-end screens hand off this way now: the
## title's rows and the opening storyboard they lead into. The order is the
## point — level_id is set before add_child, which is what boots straight into a
## level instead of into DEFAULT_LEVEL and then changing its mind one frame
## later. Returns the session so the caller can carry a fade across the handoff.
static func boot(tree: SceneTree, id: String, playing: bool) -> Node2D:
	if tree == null:
		return null
	var game = new()
	game.level_id = id
	var outgoing := tree.current_scene
	tree.root.add_child(game)
	tree.current_scene = game
	if playing:
		game.start_session()
	if outgoing != null:
		outgoing.queue_free()
	return game

func _add_solid(rect: Rect2) -> StaticBody2D:
	## Returns the body, which the level's own geometry ignores and the section
	## walls keep: a gate has to be able to switch its own wall off.
	var body := StaticBody2D.new()
	body.position = rect.position + rect.size / 2
	body.collision_layer = 1
	body.collision_mask = 2
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	return body

func _add_area(rect: Rect2, layer: int, spikes: bool) -> Area2D:
	var area := Area2D.new()
	area.position = rect.position
	area.collision_layer = layer
	area.collision_mask = 2
	if spikes:
		# Three exact triangular trigger silhouettes; no oversized invisible box.
		for i in range(3):
			var triangle := CollisionPolygon2D.new()
			var x := float(i) * rect.size.x / 3.0
			var half := rect.size.x / 6.0
			triangle.polygon = PackedVector2Array([Vector2(x, rect.size.y), Vector2(x + half, 0), Vector2(x + half * 2.0, rect.size.y)])
			area.add_child(triangle)
	else:
		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		collision.shape = shape
		collision.position = rect.size / 2.0
		area.add_child(collision)
	add_child(area)
	return area

func start_session() -> void:
	if state == State.PLAYING:
		return
	deaths = 0
	restart_attempt()

func restart_attempt() -> void:
	state = State.PLAYING
	elapsed = 0.0
	retry_remaining = 0.0
	# Area2D overlaps are physics-step snapshots. Discard pre-teleport contacts
	# until the broadphase has observed the reset, preventing a phantom second death.
	contact_settle_ticks = 2
	# A crate the player already broke has to come back, or every retry hands
	# them a slightly emptier level than the one they died in.
	for crate in crates:
		crate.reset()
	for bottle in bottles:
		bottle.reset()
	for foe in enemies:
		foe.reset()
		foe.target = player
	drinking_bottle = null
	for blast in blasts:
		if is_instance_valid(blast):
			blast.queue_free()
	blasts.clear()
	for arrow in arrows:
		if is_instance_valid(arrow):
			arrow.queue_free()
	arrows.clear()
	player.reset_at(Vector2(level.spawn[0], level.spawn[1]))
	player.enabled = true
	camera.position = Vector2(VIEW_HALF.x, camera_home_y())
	# Straight back to a hard cut: a retry or a level swap is a cut, not a pan.
	camera_held = 0.0

func set_paused(value: bool) -> void:
	if value and state == State.PLAYING:
		state = State.PAUSED
		player.enabled = false
	elif not value and state == State.PAUSED:
		state = State.PLAYING
		player.enabled = true
		player.require_jump_release = true
		player.jump_request_tick = -1000

func _on_focus_lost() -> void:
	if not test_mode:
		set_paused(true)

func _on_player_struck(damage: int, from: Vector2) -> void:
	## A punk landed one. He decides he hit; the player decides whether the blow
	## counts, because only the player knows about its own invulnerable window.
	if state != State.PLAYING:
		return
	var _landed: bool = player.take_damage(damage, from)

func enemies_down() -> int:
	var n := 0
	for foe in enemies:
		if not foe.alive():
			n += 1
	return n

func _on_blast_fired(at: Vector2, direction: float) -> void:
	## The projectile belongs to the level, not to the player: once thrown it
	## keeps its own heading and must not follow him if he turns or dies.
	var blast := Blast.new()
	blast.direction = direction
	blast.position = at
	blasts.append(blast)
	add_child(blast)
	# Everyone gets told. The blast itself is not given the roster and is never
	# told who guarded it — an enemy decides on his own whether he saw it coming
	# in time to get his arms up, which is what makes the answer to a guard be
	# "throw it from closer" rather than anything the projectile knows about.
	# See warn_of_blast in features/combat/enemy.gd.
	# Only as far as the thing can actually fly. An enemy who braces for a blast
	# that dies of old age two hundred px short of him is bracing for nothing,
	# and would stay braced through a fight he is not in.
	for foe in enemies:
		if is_instance_valid(foe) and foe.alive() \
				and absf(foe.global_position.x - at.x) <= Blast.RANGE:
			foe.warn_of_blast(at, direction, Blast.SPEED)

func _on_arrow_fired(at: Vector2, direction: float, damage: int) -> void:
	## The archer's arrow is a level object too: it keeps its heading and reports
	## its hit the same way a melee blow does, through the player's own window.
	var arrow := Arrow.new()
	arrow.direction = direction
	arrow.damage = damage
	arrow.position = at
	arrow.struck_player.connect(_on_player_struck)
	arrows.append(arrow)
	add_child(arrow)

## How close he has to be to pick something up. Generous, like the bottle's
## drink reach: this is "am I standing at it", not "am I touching it".
const PICKUP_RANGE := Vector2(54.0, 70.0)

func carryable_in_reach() -> Node2D:
	## The nearest thing he could pick up, or null. Crates and bottles are the
	## same question, so they are asked it the same way rather than the bottle
	## keeping its own private answer.
	var best: Node2D = null
	var best_gap := INF
	for prop in (crates + bottles):
		if not is_instance_valid(prop) or not prop.can_be_carried():
			continue
		var gap: Vector2 = prop.global_position - player.global_position
		if absf(gap.x) > PICKUP_RANGE.x or absf(gap.y) > PICKUP_RANGE.y:
			continue
		if absf(gap.x) < best_gap:
			best_gap = absf(gap.x)
			best = prop
	return best

func pick_up() -> bool:
	## Lifts whatever is at his feet. Deliberately not automatic on contact: the
	## tutorial is teaching that picking things up is an action, the same reason
	## drinking is not automatic.
	if state != State.PLAYING or player.is_carrying():
		return false
	var prop := carryable_in_reach()
	if prop == null:
		return false
	return player.begin_pickup(prop, bool(prop.heavy))

func bottle_being_carried() -> Node2D:
	## The bottle in his hands, or null. The HUD asks so it can prompt to drink
	## rather than to pick up.
	if not player.is_carrying():
		return null
	return player.carrying if bottles.has(player.carrying) else null

func _on_threw(object: Node2D, velocity: Vector2) -> void:
	## The object leaves his hands and becomes a live thing again. Everything
	## after this is prop.gd: it flies, it hits what is on the Hittable layer,
	## and it comes apart on whatever it reaches first.
	if is_instance_valid(object):
		object.launch(velocity)

func drink() -> bool:
	## Starts a six-second drink on the bottle in reach. Deliberately not
	## automatic on touch: the tutorial is teaching that the action exists, which
	## a silent pickup does not do. Drinking at full health is refused rather
	## than wasting the bottle, and so is drinking a brown one on full mana.
	##
	## Nothing is spent and nothing is restored here — see _on_drink_ended.
	## He has to be holding it. Picking it up is its own beat now, so the bottle
	## is lifted first and drunk second.
	if state != State.PLAYING or not player.is_carrying():
		return false
	var held: Node2D = player.carrying
	if not bottles.has(held) or not held.available():
		return false
	if player.refill_full(held.refills):
		return false
	if not player.begin_drink(held.refill_segments, held.contents, held.refills):
		return false
	# The bottle leaves the ground the moment he raises it, and the one in his
	# hand is drawn by the visual at the frame's weapon point, exactly as LF2
	# composites a held object.
	# Already in his hands, so nothing is lifted here. Six seconds from now
	# _on_drink_ended decides whether it was spent.
	held.set_drinking(true)
	drinking_bottle = held
	return true

func _on_drink_ended(_completed: bool, reason: String) -> void:
	## The only place a bottle is ever spent, and it is spent by the mouthful.
	## Whatever he swallowed comes out of the bottle; an empty one is gone, and
	## anything left goes back on the floor to be finished later.
	if not is_instance_valid(drinking_bottle):
		drinking_bottle = null
		return
	var bottle: Area2D = drinking_bottle
	drinking_bottle = null
	bottle.set_drinking(false)
	bottle.set_contents(player.last_drink_left)
	# He is still holding it, whatever stopped him — a drink interrupted is a
	# bottle lowered from his mouth, not dropped, so he can start again without
	# bending down for it. Only draining it takes it off his hands.
	if bottle.consumed and player.carrying == bottle:
		player.drop_carried()

func crates_broken() -> int:
	var count := 0
	for crate in crates:
		if crate.broken:
			count += 1
	return count

func resolve_contacts(fatal: bool, finished: bool) -> void:
	if state != State.PLAYING:
		return
	if fatal:
		state = State.DYING
		deaths += 1
		retry_remaining = 0.55
		player.enabled = false
		player.velocity = Vector2.ZERO
		player.on_death()
	elif finished:
		state = State.COMPLETE
		last_finish_time = elapsed
		player.enabled = false
		player.velocity = Vector2.ZERO

func _physics_process(delta: float) -> void:
	# Ahead of the state machine, and a swap ends the tick: the world it just
	# built should start on the next one, not half way through this one.
	if fade_phase != Fade.NONE and _advance_fade(delta):
		return
	if state == State.DYING:
		retry_remaining -= delta
		if retry_remaining <= 0:
			restart_attempt()
	elif state == State.PLAYING:
		elapsed += delta
		blasts = blasts.filter(func(b): return is_instance_valid(b))
		arrows = arrows.filter(func(a): return is_instance_valid(a))
		# He carries the bottle now, so he cannot walk away from it — the old
		# out-of-reach interruption is gone with the reach. What can still
		# happen is losing hold of it: knocked out of his hands, or smashed
		# while he drinks.
		if player.is_drinking() and (not is_instance_valid(drinking_bottle)
				or player.carrying != drinking_bottle):
			player.interrupt_drink(player.DRINK_LEFT)
		elif player.is_drinking():
			# The bottle empties as he drinks, not when he stops.
			drinking_bottle.set_contents(player.drink_fill_left())
		var fatal := player.position.y > float(level.fall_y)
		death_reason = "Missed the landing" if fatal else "Watch the spikes"
		# An empty bar is fatal on the same terms as a pit: the session decides,
		# the player only spends the health. Checked before the hazards so the
		# reason names what actually finished him.
		if not fatal and player.health <= 0:
			fatal = true
			death_reason = "Beaten by the bandits"
		for hazard in hazard_areas:
			fatal = fatal or hazard.overlaps_body(player)
		if contact_settle_ticks > 0:
			contact_settle_ticks -= 1
		else:
			resolve_contacts(fatal, goal.overlaps_body(player))
		_sync_gates()
		# Lookahead is a world distance and does not scale with the viewport; the
		# bound is half the viewport, so the camera stops before either end of the
		# level would come into shot.
		#
		# A shut gate pulls that far bound in to itself, which is what makes the
		# wall legible: the fight is framed, and the wall lands exactly on the
		# right edge of the screen rather than somewhere off in the dark.
		var far: float = float(level.width) - VIEW_HALF.x
		var shut := gate_shut_at()
		if shut < INF:
			far = minf(far, shut - VIEW_HALF.x + GATE_INSET)
		# Tightens at once, lets go slowly. Walking into a fight should frame it
		# on the frame you arrive; walking out of one should pan.
		#
		# This is the only smoothing on the camera's x and it exists for one
		# moment: the frame the last enemy in a section falls. A shut gate holds
		# the far edge at the wall; clearing the section moved that edge to the
		# end of the level in a single frame, so a player who finished the fight
		# pressed against the wall — which is where a fight backed into a gate
		# always ends — got the whole world yanked 570 px sideways under him,
		# usually while still mid-swing.
		#
		# Kept as the DISTANCE the camera is being held back rather than as a
		# smoothed position, because that number is exactly zero for the whole of
		# ordinary play: no gate, nothing held, camera on its mark to the pixel
		# the way it has always been. Only the release is eased, and only while
		# it lasts.
		var want: float = maxf(player.position.x + 200, VIEW_HALF.x)
		var bound: float = maxf(far, VIEW_HALF.x)
		if want > bound:
			camera_held = want - bound          # held: exact, and it snaps
		else:
			camera_held = maxf(0.0, camera_held - GATE_RELEASE * delta)
		camera.position.x = want - camera_held
		camera.position.y = _follow_y(camera.position.y)
	if is_instance_valid(hud):
		hud.queue_redraw()
	# The background parallaxes against the camera, so it is redrawn with it.
	if is_instance_valid(scenery):
		scenery.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed("menu_up") and state == State.MENU:
		menu_index = posmod(menu_index - 1, listing().size())
	elif event.is_action_pressed("menu_down") and state == State.MENU:
		menu_index = posmod(menu_index + 1, listing().size())
	elif event.is_action_pressed("confirm"):
		confirm()
	elif event.is_action_pressed("pause"):
		set_paused(state != State.PAUSED)
	elif event.is_action_pressed("drink"):
		# One key for both beats: drink what you are already holding, or lift
		# what is at your feet.
		if not drink():
			pick_up()
	elif event.is_action_pressed("restart") and state in [State.PLAYING, State.PAUSED, State.DYING]:
		restart_attempt()
	elif event.is_action_pressed("menu") and state in [State.PAUSED, State.COMPLETE]:
		open_menu()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var at: Vector2 = hud.get_local_mouse_position()
		var row: int = hud.row_at(at)
		if state == State.MENU and row >= 0:
			menu_index = row
			confirm()
		elif hud.button_rect().has_point(at):
			confirm()

func open_menu() -> void:
	## The menu opens on the level you were just in, not back at the top.
	state = State.MENU
	menu_index = maxi(listing().find(level_id), 0)
	if is_instance_valid(player):
		player.enabled = false

func confirm() -> void:
	## One button, three meanings: start the highlighted level, resume, or take
	## the next one. Reachable from the keyboard and from the HUD button alike.
	match state:
		State.MENU:
			# The list, not the course: LOAD GAME offers every level that ships.
			var rows := listing()
			var pick: String = rows[clampi(menu_index, 0, rows.size() - 1)]
			begin_swap(pick if pick != level_id else "")
		State.COMPLETE:
			# The last level has nowhere to advance to, so it replays instead.
			begin_swap(next_level_id())
		State.PAUSED:
			set_paused(false)

func _draw() -> void:
	if level.is_empty():
		return
	# The flag and the painted area names belong to the LEVEL rather than to
	# either renderer, so both get them. They used to live in the greybox block
	# below, which a themed level skips wholesale — so on The Fractured Isles the
	# finish was an invisible rectangle you walked into and six authored signs
	# were never once on screen. scenery.gd draws cliffs and set dressing from
	# the solids and has no idea where the level ends; this does.
	_draw_markers()
	# A themed level draws its world in scenery.gd from this same level data.
	# Everything below is the original greybox, kept for the levels without one.
	if is_instance_valid(scenery):
		return
	var ink := Color("25354a")
	# Hazard and finish decoration read their geometry from the level data now, so a
	# future rescale moves the art with the collision instead of drifting off it.
	var floor_y: float = level.solids[0][1]
	var width: float = level.width
	# Label positions are world coordinates and scaled with the level, but the
	# viewport did not scale, so font sizes and line widths stay as they were:
	# one world unit is still one on-screen logical pixel.
	# All visual assets are original Godot vector drawing, not recovered art.
	draw_rect(Rect2(-800, -400, 3600, 1800), Color("f6f3ec"))
	for x in range(0, int(width) + 1, 64):
		draw_line(Vector2(x, 160), Vector2(x, floor_y), Color("e7e5df"), 1)
	for y in range(192, int(floor_y) + 1, 64):
		draw_line(Vector2(0, y), Vector2(width, y), Color("e7e5df"), 1)
	# Hill peaks are level data. A level that names none gets six spaced evenly
	# across its width, so a new level is never authored against a blank sky.
	var hills: Array = level.get("hills", [])
	if hills.is_empty():
		for i in range(6):
			hills.append(width * (float(i) + 0.5) / 6.0)
	for x in hills:
		draw_colored_polygon(PackedVector2Array([Vector2(x-190,floor_y),Vector2(x,floor_y-190),Vector2(x+190,floor_y)]), Color("e4e8e3"))
	for entry in level.solids:
		var r := Rect2(entry[0], entry[1], entry[2], entry[3])
		draw_rect(r, ink)
		draw_rect(Rect2(r.position, Vector2(r.size.x, 8)), Color("438e7d"))
		for x in range(int(r.position.x)+24, int(r.end.x), 48):
			draw_line(Vector2(x, r.position.y+24), Vector2(x+14, r.position.y+38), Color("405166"), 2)
	for entry in level.hazards:
		var spike_base: float = entry[1] + entry[3]
		var spike_w: float = entry[2] / 3.0
		for i in range(3):
			var x: float = entry[0] + i * spike_w
			draw_colored_polygon(PackedVector2Array([Vector2(x,spike_base),Vector2(x+spike_w*0.5,entry[1]),Vector2(x+spike_w,spike_base)]), Color("d24e42"))

## The flag and the signs — see the note in _draw about why these are not part of
## the greybox above.
func _draw_markers() -> void:
	var font := ThemeDB.fallback_font
	var ink := Color("25354a")
	var f: Array = level.finish
	var finish_x: float = float(f[0])
	var foot: float = float(f[1]) + float(f[3])
	var mast: float = float(f[1]) - 28.0
	# Warm rather than the old green: against the greybox anything read, but on
	# grass a green pennant disappears into the hill behind it. This is the
	# menu's own accent, which is the one colour in the game nothing else on a
	# cliff is wearing.
	draw_line(Vector2(finish_x + 6, foot), Vector2(finish_x + 6, mast), ink, 6)
	draw_colored_polygon(PackedVector2Array([
		Vector2(finish_x + 10, mast), Vector2(finish_x + 64, mast + 20),
		Vector2(finish_x + 10, mast + 48)]), Color("ef875f"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(finish_x + 10, mast), Vector2(finish_x + 36, mast + 10),
		Vector2(finish_x + 10, mast + 20)]), Color("ffeeca"))
	# Signs are painted on the background from the level file: [x, y, heading]
	# or [x, y, heading, subtitle]. They were three hard-coded draw_string calls
	# naming First Steps' own zones, which no second level could ever reuse.
	#
	# Outlined, because these now sit over painted sky and cliffs rather than
	# over a flat greybox page: dark text alone vanished against the rock.
	for marker in level.get("signs", []):
		var at := Vector2(float(marker[0]), float(marker[1]))
		draw_string_outline(font, at, str(marker[2]), HORIZONTAL_ALIGNMENT_LEFT,
				-1, 15, 5, Color("f6f3ec"))
		draw_string(font, at, str(marker[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ink)
		if marker.size() > 3:
			var under := at + Vector2(0.0, 22.0)
			draw_string_outline(font, under, str(marker[3]),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 5, Color("f6f3ec"))
			draw_string(font, under, str(marker[3]), HORIZONTAL_ALIGNMENT_LEFT,
					-1, 13, ink)
