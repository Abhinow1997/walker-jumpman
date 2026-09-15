extends Area2D
## The Bandit: walks the player down and throws a punch when he is close enough
## to land one.
##
## Art is the Little Fighter 2 bandit, cut by scripts/extract_bandit.py and
## scaled 0.75 like the rest of the cast, so he shares the player's palette and
## painted look rather than sitting beside it in a different decade of pixel
## art. Fan-ripped LF2 content: fine for coursework, not for release — see
## features/combat/art/bandit/PROVENANCE.md.
##
## Nothing here is specific to one pack. The manifest shape is shared, so
## pointing ART and DATA at another enemy's folder swaps him wholesale.
##
## He satisfies prop.gd's contract — Hittable layer, take_hit(damage, from) —
## without extending it. A struck crate tumbles and shatters; a struck bandit
## staggers and plays a hurt animation, so almost none of prop.gd's body would
## have been used. The contract is what matters, and every one of the player's
## attacks already works against him because of it.
##
## Deliberately an Area2D with no collision mask, like the props: the player
## walks through him. A solid enemy in a corridor this narrow pins the player
## against geometry with no way out, and this level has no room to dodge.

const ART := "res://features/combat/art/bandit/"
const DATA := ART + "bandit.json"

const HITTABLE := 64   # physics layer 7, the layer the player's strikes query
const PLAYER := 2      # physics layer 2, what his own punch looks for
const WORLD := 1       # what he stands on

## "The same energy as the user." Five jabs, two flying kicks, or three blasts —
## the player's whole moveset is calibrated against a health bar this size, so
## he reads as an even match rather than a punching bag.
const MAX_HEALTH := 100

## Hit box, matched to the drawn body (~26 x 51) and kept just inside it.
const BODY := Vector2(22, 45)

## Slower than the player's 320 on purpose: he must always be outrunnable. The
## player's answer to a bandit he does not want to fight is to leave.
const WALK_SPEED := 70.0
## Starts walking at this distance. Where he commits to a punch is derived from
## his own reach — see attack_range() — rather than hard-coded, so swapping the
## enemy art cannot leave him swinging at air from out of range.
const AGGRO_RANGE := 280.0
## He may not chain punches; the gap is the player's window to answer.
const ATTACK_COOLDOWN := 0.8
## Struck, he cannot act. Long enough that the player's two-jab combo lands in
## full, short enough that it is not a stun-lock.
const STAGGER_TIME := 0.3
## Knocked back by a blow, scaled by its damage against this.
const KNOCK_REFERENCE := 40.0
const KNOCK_X := 90.0
const GRAVITY := 1440.0
## How long the body lies there before it is cleared.
const DEAD_LINGER := 1.6

enum State { IDLE, WALK, PUNCH, HURT, DEAD }

## The session connects this; it owns the player's health, not the enemy.
signal struck_player(damage: int, from: Vector2)

static var _data: Dictionary = {}

var health: int = MAX_HEALTH
var state: State = State.IDLE
var facing: float = -1.0
var clock: float = 0.0
var frame: int = 0
var velocity: Vector2 = Vector2.ZERO
var cooldown: float = 0.0
var stagger: float = 0.0
var dead_t: float = 0.0
## One punch may only land once, however many frames its box is open for.
var landed_this_punch: bool = false
## Set by whoever spawns him.
var home: Vector2 = Vector2.ZERO
var fall_limit: float = INF
var target: Node2D = null

var sprite: AnimatedSprite2D
var art_faces: float = -1.0

static func data() -> Dictionary:
	if _data.is_empty():
		var text := FileAccess.get_file_as_string(DATA)
		if text.is_empty():
			push_error("enemy: %s is missing. Run scripts/extract_bandit.py." % DATA)
			_data = {"animations": {}, "cell": [1, 1], "origin": [0, 0], "faces": -1,
					 "hit_frame": 0, "hit_rect": [0, 0, 0, 0], "hit_damage": 0}
		else:
			_data = JSON.parse_string(text)
	return _data

func _init() -> void:
	collision_layer = HITTABLE
	# He detects nothing by standing there; his punch queries for itself.
	collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = BODY
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = Vector2(0, -BODY.y / 2.0)
	add_child(collider)

func _ready() -> void:
	home = position
	art_faces = float(data().get("faces", -1))
	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = _build_frames()
	sprite.centered = true
	sprite.offset = _pivot()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	_play("idle")

func _pivot() -> Vector2:
	## Puts his feet on the node origin, so he stands on the floor line
	## and mirrors about his own body rather than about the cell.
	var cell: Array = data().get("cell", [1, 1])
	var origin: Array = data().get("origin", [0, 0])
	return Vector2(float(cell[0]) / 2.0 - float(origin[0]),
				   float(cell[1]) / 2.0 - float(origin[1]))

func _build_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var cell: Array = data().get("cell", [1, 1])
	for key in data().get("animations", {}):
		var spec: Dictionary = data()["animations"][key]
		var path: String = ART + str(spec.file)
		if not ResourceLoader.exists(path):
			push_warning("enemy: no sheet at %s (run scripts/extract_bandit.py, then --import)" % path)
			continue
		var sheet: Texture2D = load(path)
		frames.add_animation(key)
		frames.set_animation_loop(key, bool(spec.loop))
		var durations: Array = spec.durations
		for i in durations.size():
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(i * float(cell[0]), 0, float(cell[0]), float(cell[1]))
			# Same arrangement as the player: speed pinned at 1 and each frame
			# carrying its own length, so the punch can hold on its extended
			# frame the way the pack's own preview does.
			frames.add_frame(key, atlas, float(durations[i]))
		frames.set_animation_speed(key, 1.0)
	return frames

func _play(key: String) -> void:
	if not is_instance_valid(sprite) or not sprite.sprite_frames.has_animation(key):
		return
	if sprite.animation == key and sprite.is_playing():
		return
	sprite.play(key)

func _show(key: String, index: int) -> void:
	## Attacks are stepped by this script rather than by the AnimatedSprite2D's
	## own clock, so the frame on screen is the frame whose hit box is live.
	if not is_instance_valid(sprite) or not sprite.sprite_frames.has_animation(key):
		return
	if sprite.animation != key:
		sprite.stop()
		sprite.animation = key
	sprite.frame = clampi(index, 0, sprite.sprite_frames.get_frame_count(key) - 1)

func _durations(key: String) -> Array:
	return data().get("animations", {}).get(key, {}).get("durations", [])

func alive() -> bool:
	return state != State.DEAD

func reach() -> float:
	## How far his fist gets from his own origin, straight off the hit box.
	var r: Array = data().get("hit_rect", [0, 0, 0, 0])
	return float(r[0]) + float(r[2])

func attack_range() -> float:
	## He commits a little inside his reach, so the blow lands on the player's
	## box rather than stopping a pixel short of it.
	return reach() + 4.0

# --- the contract -----------------------------------------------------------

func take_hit(damage: int, from: Vector2) -> bool:
	## prop.gd's contract. Returns false once he is down, so a strike passes
	## through a corpse and keeps looking for something else to hit.
	if state == State.DEAD:
		return false
	health -= damage
	facing = 1.0 if from.x > global_position.x else -1.0
	var away := -facing
	velocity.x = away * KNOCK_X * clampf(float(damage) / KNOCK_REFERENCE, 0.4, 1.6)
	clock = 0.0
	frame = 0
	landed_this_punch = false
	if health <= 0:
		health = 0
		state = State.DEAD
		dead_t = 0.0
	else:
		state = State.HURT
		stagger = STAGGER_TIME
	_show("hurt", 0)
	return true

# --- his own attack ---------------------------------------------------------

func _hit_box() -> Rect2:
	var r: Array = data().get("hit_rect", [0, 0, 0, 0])
	var box := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	# Written facing forward, mirrored with him, exactly as the player's are.
	if facing < 0.0:
		box.position.x = -(box.position.x + box.size.x)
	box.position += global_position
	return box

func _try_to_land() -> void:
	if landed_this_punch:
		return
	var box := _hit_box()
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := RectangleShape2D.new()
	shape.size = box.size
	query.shape = shape
	query.transform = Transform2D(0.0, box.position + box.size / 2.0)
	query.collision_mask = PLAYER
	query.collide_with_areas = false
	query.collide_with_bodies = true
	for result in get_world_2d().direct_space_state.intersect_shape(query, 4):
		if result.collider == target:
			landed_this_punch = true
			struck_player.emit(int(data().get("hit_damage", 0)), global_position)
			return

# --- step -------------------------------------------------------------------

func reset() -> void:
	position = home
	health = MAX_HEALTH
	state = State.IDLE
	facing = -1.0
	clock = 0.0
	frame = 0
	velocity = Vector2.ZERO
	cooldown = 0.0
	stagger = 0.0
	dead_t = 0.0
	landed_this_punch = false
	visible = true
	_play("idle")

func _floor_below(from_y: float) -> float:
	var query := PhysicsRayQueryParameters2D.create(
		Vector2(position.x, from_y - 8.0), Vector2(position.x, position.y + 2.0), WORLD)
	query.collide_with_areas = false
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return INF if hit.is_empty() else float(hit.position.y)

func _physics_process(delta: float) -> void:
	if cooldown > 0.0:
		cooldown = maxf(0.0, cooldown - delta)

	match state:
		State.DEAD:
			_advance_dead(delta)
		State.HURT:
			_advance_hurt(delta)
		State.PUNCH:
			_advance_punch(delta)
		_:
			_advance_chase(delta)

	_integrate(delta)
	if is_instance_valid(sprite):
		sprite.scale = Vector2(facing * art_faces, 1.0)

func _integrate(delta: float) -> void:
	velocity.y += GRAVITY * delta
	var prev_y := position.y
	position += velocity * delta
	if position.y > fall_limit:
		# Walked into a pit. Gone, rather than falling for ever and leaving a
		# live target the player can never reach.
		state = State.DEAD
		dead_t = DEAD_LINGER
		visible = false
		return
	if velocity.y < 0.0:
		return
	var floor_y := _floor_below(prev_y)
	if floor_y != INF and position.y >= floor_y:
		position.y = floor_y
		velocity.y = 0.0

func _advance_dead(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
	dead_t += delta
	var holds := _durations("hurt")
	if holds.is_empty():
		return
	# Runs the hurt animation out and stays on its last frame, which is the pack's
	# collapsed heap — the closest thing it has to a death pose.
	var t := 0.0
	var index := holds.size() - 1
	for i in holds.size():
		t += float(holds[i])
		if dead_t < t:
			index = i
			break
	_show("hurt", index)
	if dead_t >= DEAD_LINGER:
		visible = false

func _advance_hurt(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 500.0 * delta)
	stagger -= delta
	clock += delta
	var holds := _durations("hurt")
	var t := 0.0
	var index := 0
	for i in holds.size():
		t += float(holds[i])
		index = i
		if clock < t:
			break
	_show("hurt", mini(index, 1))  # first two frames only: recoil, not collapse
	if stagger <= 0.0:
		state = State.IDLE
		clock = 0.0

func _advance_punch(delta: float) -> void:
	velocity.x = 0.0
	clock += delta
	var holds := _durations("punch")
	if holds.is_empty():
		state = State.IDLE
		return
	var t := 0.0
	var index := holds.size() - 1
	var done := true
	for i in holds.size():
		t += float(holds[i])
		if clock < t:
			index = i
			done = false
			break
	frame = index
	_show("punch", index)
	if index == int(data().get("hit_frame", 0)):
		_try_to_land()
	if done:
		state = State.IDLE
		clock = 0.0
		cooldown = ATTACK_COOLDOWN

func _advance_chase(delta: float) -> void:
	if not is_instance_valid(target):
		velocity.x = 0.0
		_play("idle")
		return
	var gap: float = target.global_position.x - global_position.x
	var reachable: bool = absf(target.global_position.y - global_position.y) < 60.0
	if absf(gap) > 0.5:
		facing = signf(gap)

	if reachable and absf(gap) <= attack_range() and cooldown <= 0.0:
		state = State.PUNCH
		clock = 0.0
		frame = 0
		landed_this_punch = false
		velocity.x = 0.0
		_show("punch", 0)
		return
	if reachable and absf(gap) <= AGGRO_RANGE and absf(gap) > attack_range() * 0.8:
		state = State.WALK
		velocity.x = signf(gap) * WALK_SPEED
		_play("walk")
		return
	state = State.IDLE
	velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
	_play("idle")
