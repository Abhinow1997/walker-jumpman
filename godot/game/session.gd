extends Node2D

const Player = preload("res://features/player/player.gd")
const Hud = preload("res://ui/hud.gd")
const Crate = preload("res://features/combat/crate.gd")
const Blast = preload("res://features/combat/blast.gd")
const Bottle = preload("res://features/combat/bottle.gd")
const Enemy = preload("res://features/combat/enemy.gd")
const Items = preload("res://features/combat/items.gd")
enum State { MENU, PLAYING, PAUSED, DYING, COMPLETE }
var state: State = State.MENU
var player: CharacterBody2D
var camera: Camera2D
var hud: Control
var level: Dictionary
var hazard_areas: Array[Area2D] = []
var crates: Array[Area2D] = []
var bottles: Array[Area2D] = []
var enemies: Array[Area2D] = []
## The bottle the player is currently standing near, or null. The HUD reads it
## to know whether to prompt, and drink() reads it to know what to consume.
var bottle_in_reach: Area2D = null
## The bottle currently in his hand, for the six seconds a drink takes. Held
## separately from bottle_in_reach because the two diverge the moment he steps
## away mid-drink, which is exactly the case that has to be caught.
var drinking_bottle: Area2D = null
var blasts: Array[Node2D] = []
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
	level = JSON.parse_string(FileAccess.get_file_as_string("res://levels/first_steps.json"))
	_setup_input()
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
	# [x, y] or [x, y, segments]. The third value is health-BAR SEGMENTS, not
	# health points: [470, 640, 2] is a bottle worth two of the bar's five bars.
	# It used to be raw points, so an old level file's 50 would now read as fifty
	# bars — check any level authored before this changed.
	for entry in level.get("bottles", []):
		var bottle := Bottle.new()
		bottle.position = Vector2(entry[0], entry[1])
		# A bottle is knocked about when hit, same as a crate.
		bottle.fall_limit = float(level.fall_y)
		if entry.size() > 2:
			bottle.heal_segments = int(entry[2])
		bottles.append(bottle)
		add_child(bottle)
	# Spawned before the player so he draws in front of them, and so `target`
	# can be handed over the moment he exists.
	# [x, y] per punk. More is another entry, not more code.
	for entry in level.get("enemies", []):
		var foe := Enemy.new()
		foe.position = Vector2(entry[0], entry[1])
		foe.fall_limit = float(level.fall_y)
		foe.struck_player.connect(_on_player_struck)
		enemies.append(foe)
		add_child(foe)
	player = Player.new()
	player.blast_fired.connect(_on_blast_fired)
	player.drink_ended.connect(_on_drink_ended)
	add_child(player)
	player.reset_at(Vector2(level.spawn[0], level.spawn[1]))
	camera = Camera2D.new()
	camera.position = Vector2(320, 500)
	add_child(camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.game = self
	layer.add_child(hud)
	get_window().focus_exited.connect(_on_focus_lost)
	queue_redraw()

func _setup_input() -> void:
	var actions := {"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT], "jump": [KEY_SPACE], "drink": [KEY_E], "attack": [KEY_J, KEY_X], "blast": [KEY_K, KEY_C], "pause": [KEY_ESCAPE, KEY_P], "restart": [KEY_R], "confirm": [KEY_ENTER], "menu": [KEY_M]}
	for action in actions:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in actions[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)

func _add_solid(rect: Rect2) -> void:
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
	bottle_in_reach = null
	drinking_bottle = null
	for blast in blasts:
		if is_instance_valid(blast):
			blast.queue_free()
	blasts.clear()
	player.reset_at(Vector2(level.spawn[0], level.spawn[1]))
	player.enabled = true
	camera.position = Vector2(320, 500)

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

func drink() -> bool:
	## Starts a six-second drink on the bottle in reach. Deliberately not
	## automatic on touch: the tutorial is teaching that the action exists, which
	## a silent pickup does not do. Drinking at full health is refused rather
	## than wasting the bottle.
	##
	## Nothing is spent and nothing is restored here — see _on_drink_ended.
	if state != State.PLAYING or bottle_in_reach == null:
		return false
	if not bottle_in_reach.available():
		return false
	if player.health >= player.MAX_HEALTH:
		return false
	if not player.begin_drink(bottle_in_reach.heal_segments, bottle_in_reach.contents):
		return false
	# The bottle leaves the ground the moment he raises it, and the one in his
	# hand is drawn by the visual at the frame's weapon point, exactly as LF2
	# composites a held object.
	player.visual.held_texture = Items.frame("bottle_drink", 0)
	player.visual.held_offset = Items.pivot("bottle_drink")
	# Lifted, not consumed. Six seconds from now _on_drink_ended decides which
	# it was, and an interrupted drink puts the bottle back on the floor.
	bottle_in_reach.lift()
	drinking_bottle = bottle_in_reach
	return true

func _on_drink_ended(_completed: bool, reason: String) -> void:
	## The only place a bottle is ever spent, and it is spent by the mouthful.
	## Whatever he swallowed comes out of the bottle; an empty one is gone, and
	## anything left goes back on the floor to be finished later.
	player.visual.held_texture = null
	player.visual.held_offset = Vector2.ZERO
	if not is_instance_valid(drinking_bottle):
		drinking_bottle = null
		return
	var bottle: Area2D = drinking_bottle
	drinking_bottle = null
	bottle.set_contents(player.last_drink_left)
	if bottle.consumed or bottle.broken:
		return
	if reason == player.DRINK_HIT:
		# Struck mid-drink: it leaves his hand rather than being set down. From
		# about mouth height and behind him, offset clear of his own sprite —
		# dropped dead centre it spends its first frames hidden behind him and
		# reads as having vanished rather than fallen.
		# Offsets and impulse are character-scale and scaled with the art (x0.75).
		bottle.drop_from(player.global_position + Vector2(-player.facing * 12.0, -25.5),
			Vector2(-player.facing * 97.5, -142.5))
	else:
		bottle.lower()

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
	if state == State.DYING:
		retry_remaining -= delta
		if retry_remaining <= 0:
			restart_attempt()
	elif state == State.PLAYING:
		elapsed += delta
		blasts = blasts.filter(func(b): return is_instance_valid(b))
		bottle_in_reach = null
		for bottle in bottles:
			# A bottle the player smashed is no longer a drink, which in_reach
			# accounts for along with one already drunk.
			if bottle.in_reach(player):
				bottle_in_reach = bottle
				break
		# Walking away mid-drink is the one interruption the player cannot see
		# himself doing, because the drink plants him: it takes a knock, or a
		# bottle skidding off, to separate them. Checked against the bottle he
		# is actually drinking, not whatever happens to be nearest now.
		if player.is_drinking() and (not is_instance_valid(drinking_bottle)
				or not drinking_bottle.in_reach(player)):
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
		# Lookahead scales with the world; the 320 bound is half the viewport, which
		# did not scale, so the player now sees less of the level ahead than before.
		camera.position.x = clampf(player.position.x + 200, 320, float(level.width) - 320)
	if is_instance_valid(hud):
		hud.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed("confirm"):
		if state in [State.MENU, State.COMPLETE]:
			start_session()
		elif state == State.PAUSED:
			set_paused(false)
	elif event.is_action_pressed("pause"):
		set_paused(state != State.PAUSED)
	elif event.is_action_pressed("drink"):
		drink()
	elif event.is_action_pressed("restart") and state in [State.PLAYING, State.PAUSED, State.DYING]:
		restart_attempt()
	elif event.is_action_pressed("menu") and state in [State.PAUSED, State.COMPLETE]:
		state = State.MENU
		player.enabled = false
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Rect2(220, 215, 200, 34).has_point(hud.get_local_mouse_position()):
			if state in [State.MENU, State.COMPLETE]:
				start_session()
			elif state == State.PAUSED:
				set_paused(false)

func _draw() -> void:
	if level.is_empty():
		return
	var font := ThemeDB.fallback_font
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
	# Six hills across the wider level; three left gaps you could see straight through.
	for x in [140, 520, 900, 1240, 1560, 1860]:
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
	var f: Array = level.finish
	var finish_x: float = f[0]
	var mast: float = f[1] - 28.0
	draw_line(Vector2(finish_x+6, f[1]+f[3]), Vector2(finish_x+6, mast), ink, 6)
	draw_colored_polygon(PackedVector2Array([Vector2(finish_x+10,mast),Vector2(finish_x+64,mast+20),Vector2(finish_x+10,mast+48)]), Color("287c68"))
	draw_string(font, Vector2(66, 502), "01 / GET MOVING", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ink)
	draw_string(font, Vector2(66, 524), "Read the landing. Then jump.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ink)
	draw_string(font, Vector2(948, 454), "02 / MIND THE GAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ink)
	draw_string(font, Vector2(1756, 450), "FINISH", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ink)
