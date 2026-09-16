extends Area2D
## An enemy: closes on the player and strikes when it is near enough to land a
## blow. HOW it closes, how hard it hits and how much it can take are its own —
## see PROFILES. The bandit rushes you with a committed dash, Mark walks through
## your blows and answers with a heavy one, the hunter keeps his distance and shoots.
##
## One script, a roster of enemies. Which one this is comes from `kind` — the
## folder under art/ and the stem of its manifest, and the row it reads from
## PROFILES — so a bandit and a mark are the same code pointed at different art
## and different numbers. It defaults to the bandit, the enemy this game had
## before there was more than one.
##
## Art is Little Fighter 2, cut by scripts/extract_<kind>.py and scaled 0.75 like
## the rest of the cast, so an enemy shares the player's palette and painted look
## rather than sitting beside it in a different decade of pixel art. Fan-ripped
## LF2 content: fine for coursework, not for release — see the PROVENANCE.md in
## each art/<kind>/ folder.
##
## Nothing here is specific to one enemy. The manifest shape is shared, so a new
## kind is a new art folder and a new extractor, not new code — its frames, its
## reach and its hit box all come from the manifest.
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

const ART_ROOT := "res://features/combat/art/"
## An enemy entry that names no kind is the bandit, the one this game had first.
const DEFAULT_KIND := "bandit"

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

## Each enemy fights to its own personality. One script still, but the numbers
## and the approach are read from here, keyed by kind. A kind with no row falls
## back to DEFAULT_PROFILE, the plain walker this started as.
##
##   style       how it closes, and what it is
##   walker      walks in and jabs — the original
##   charger     dashes the last stretch: it commits, and it hurts to stand there
##   bruiser     slow and heavy, and armoured mid-swing — you cannot trade with him
##   archer      keeps his distance and looses arrows; forced to his fists up close
##
## Fields: health, speed (walk), damage (per melee hit), cooldown (between
## attacks), stagger (hurt time), knock (knockback taken, scaled), aggro (approach
## range), armor (super-armour during its own attack). Charger adds charge_speed
## and charge_range; archer adds fire_range, fire_min, shoot_cooldown and
## arrow_damage.
const DEFAULT_PROFILE := {
	"style": "walker", "health": MAX_HEALTH, "speed": WALK_SPEED,
	"damage": 20, "cooldown": ATTACK_COOLDOWN, "stagger": STAGGER_TIME,
	"knock": 1.0, "aggro": AGGRO_RANGE, "armor": false,
}
const PROFILES := {
	# The rusher: light on his feet, closes with a committed dash.
	"bandit": {
		"style": "charger", "health": 100, "speed": 84.0, "damage": 20,
		"cooldown": 0.68, "stagger": 0.28, "knock": 1.1, "aggro": 340.0,
		"armor": false, "charge_speed": 215.0, "charge_range": 200.0,
	},
	# The bruiser: soaks damage, hits like a truck, and will not be staggered out
	# of his own swing. Slow enough that the answer is footwork, not trading.
	"mark": {
		"style": "bruiser", "health": 175, "speed": 46.0, "damage": 32,
		"cooldown": 1.05, "stagger": 0.12, "knock": 0.3, "aggro": 300.0,
		"armor": true,
	},
	# The archer: keeps his distance and looses arrows, kiting backwards to hold
	# the gap open. Light and fragile, and forced to his fists if you close in.
	"hunter": {
		"style": "archer", "health": 82, "speed": 78.0, "damage": 14,
		"cooldown": 0.7, "stagger": 0.32, "knock": 1.25, "aggro": 520.0,
		"armor": false, "fire_range": 430.0, "fire_min": 150.0,
		"shoot_cooldown": 1.05, "arrow_damage": 12,
	},
}

## A charge is a committed dash: it runs at most this long, then he pulls up with
## a moment's recovery. That whiff window is the counter to standing your ground.
const CHARGE_TIME := 0.6
const CHARGE_RECOVER := 0.3

enum State { IDLE, WALK, PUNCH, HURT, DEAD, CHARGE, SHOOT }

## The session connects this; it owns the player's health, not the enemy.
signal struck_player(damage: int, from: Vector2)
## The archer looses an arrow: the session spawns it as its own travelling object,
## so it outlives the archer that fired it.
signal fired_arrow(at: Vector2, direction: float, damage: int)

## Which enemy this is: the folder under art/ and the stem of its manifest. Set
## by the spawner before add_child(); left at the default it is the bandit.
var kind: String = DEFAULT_KIND

## Manifests cached per kind, so a level holding both a bandit and a mark loads
## each one once rather than once per body on screen.
static var _data_by_kind: Dictionary = {}

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
## One draw of the bow looses one arrow, however long the release frame is held.
var fired: bool = false
## Set by whoever spawns him.
var home: Vector2 = Vector2.ZERO
var fall_limit: float = INF
var target: Node2D = null

var sprite: AnimatedSprite2D
var art_faces: float = -1.0
## Texture pixel to world unit, read from the manifest in _ready.
var art_scale: float = 1.0

## Personality, resolved from PROFILES in _ready. Kept in fields rather than read
## from the dict each frame so the hot path stays cheap and readable.
var prof: Dictionary = DEFAULT_PROFILE
var style: String = "walker"
var max_health: int = MAX_HEALTH
var speed: float = WALK_SPEED
var aggro: float = AGGRO_RANGE
var attack_cooldown: float = ATTACK_COOLDOWN
var stagger_time: float = STAGGER_TIME
var knock: float = 1.0
var armor: bool = false
## Whether his feet are on the floor this frame — a charge and the archer's kiting
## both need floor under them, and an airborne enemy is left to its momentum.
var grounded: bool = true

func profile() -> Dictionary:
	return PROFILES.get(kind, DEFAULT_PROFILE)

func art_dir() -> String:
	return ART_ROOT + kind + "/"

func data() -> Dictionary:
	if not _data_by_kind.has(kind):
		var path := art_dir() + kind + ".json"
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			push_error("enemy: %s is missing. Run scripts/extract_%s.py." % [path, kind])
			_data_by_kind[kind] = {"animations": {}, "cell": [1, 1], "origin": [0, 0],
					"faces": -1, "render_scale": 1.0,
					"hit_frame": 0, "hit_rect": [0, 0, 0, 0], "hit_damage": 0}
		else:
			_data_by_kind[kind] = JSON.parse_string(text)
	return _data_by_kind[kind]

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
	# Personality first, so his health and reach are his own before anything reads them.
	prof = profile()
	style = str(prof.get("style", "walker"))
	max_health = int(prof.get("health", MAX_HEALTH))
	speed = float(prof.get("speed", WALK_SPEED))
	aggro = float(prof.get("aggro", AGGRO_RANGE))
	attack_cooldown = float(prof.get("cooldown", ATTACK_COOLDOWN))
	stagger_time = float(prof.get("stagger", STAGGER_TIME))
	knock = float(prof.get("knock", 1.0))
	armor = bool(prof.get("armor", false))
	health = max_health
	art_faces = float(data().get("faces", -1))
	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = _build_frames()
	sprite.centered = true
	sprite.offset = _pivot()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	## The sheet is at the rip's own resolution; the node carries the
	## three-quarter cast size, the same as the player's.
	art_scale = float(data().get("render_scale", 1.0))
	sprite.scale = Vector2(art_faces, 1.0) * art_scale
	add_child(sprite)
	_play("idle")

func _pivot() -> Vector2:
	## Puts his feet on the node origin, so he stands on the floor line
	## and mirrors about his own body rather than about the cell. In texture
	## pixels: the node's art_scale applies to the offset along with the art.
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
		var path: String = art_dir() + str(spec.file)
		if not ResourceLoader.exists(path):
			push_warning("enemy: no sheet at %s (run scripts/extract_%s.py, then --import)" % [path, kind])
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

func attack_damage() -> int:
	## What his blow costs the player. From his profile; the manifest's hit_damage
	## is only the fallback for a kind with no profile.
	return int(prof.get("damage", data().get("hit_damage", 0)))

# --- the contract -----------------------------------------------------------

func take_hit(damage: int, from: Vector2) -> bool:
	## prop.gd's contract. Returns false once he is down, so a strike passes
	## through a corpse and keeps looking for something else to hit.
	if state == State.DEAD:
		return false
	health -= damage
	facing = 1.0 if from.x > global_position.x else -1.0
	var away := -facing
	# Knockback is scaled by how much the blow weighs against him: a bruiser barely
	# rocks, the light archer gets thrown.
	velocity.x = away * KNOCK_X * clampf(float(damage) / KNOCK_REFERENCE, 0.4, 1.6) * knock
	if health <= 0:
		health = 0
		state = State.DEAD
		dead_t = 0.0
		clock = 0.0
		frame = 0
		landed_this_punch = false
		_show("hurt", 0)
		return true
	# Super-armour: a bruiser does not drop his own swing for a single blow — he
	# eats it and follows through, which is why standing in front of him and
	# trading does not work. Only being put down stops him. Everyone else, and the
	# bruiser between swings, staggers as normal.
	if armor and _attacking():
		return true
	clock = 0.0
	frame = 0
	landed_this_punch = false
	state = State.HURT
	stagger = stagger_time
	_show("hurt", 0)
	return true

func _attacking() -> bool:
	return state == State.PUNCH or state == State.CHARGE or state == State.SHOOT

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
			struck_player.emit(attack_damage(), global_position)
			return

# --- step -------------------------------------------------------------------

func reset() -> void:
	position = home
	health = max_health
	state = State.IDLE
	facing = -1.0
	clock = 0.0
	frame = 0
	velocity = Vector2.ZERO
	cooldown = 0.0
	stagger = 0.0
	dead_t = 0.0
	grounded = true
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
		State.CHARGE:
			_advance_charge(delta)
		State.SHOOT:
			_advance_shoot(delta)
		_:
			_advance_chase(delta)

	_integrate(delta)
	if is_instance_valid(sprite):
		sprite.scale = Vector2(facing * art_faces, 1.0) * art_scale

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
		grounded = false
		return
	var floor_y := _floor_below(prev_y)
	if floor_y != INF and position.y >= floor_y:
		position.y = floor_y
		velocity.y = 0.0
		grounded = true
	else:
		grounded = false

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
		_recover()

## After a completed attack: back to neutral, then wait out the cooldown.
func _recover() -> void:
	state = State.IDLE
	clock = 0.0
	cooldown = attack_cooldown
	velocity.x = 0.0
	_play("idle")

func _start_punch() -> void:
	state = State.PUNCH
	clock = 0.0
	frame = 0
	landed_this_punch = false
	velocity.x = 0.0
	_show("punch", 0)

func _advance_chase(delta: float) -> void:
	if not is_instance_valid(target):
		velocity.x = 0.0
		_play("idle")
		return
	var gap: float = target.global_position.x - global_position.x
	var reachable: bool = absf(target.global_position.y - global_position.y) < 60.0
	if absf(gap) > 0.5:
		facing = signf(gap)

	# Airborne — a knock carried him off the floor — so let his momentum carry
	# rather than steering him in mid-air.
	if not grounded:
		_play("idle")
		return

	# The archer fights at range; his whole approach is different.
	if style == "archer":
		_advance_archer(delta, gap, reachable)
		return

	# In range and off cooldown: strike.
	if reachable and absf(gap) <= attack_range() and cooldown <= 0.0:
		_start_punch()
		return

	# The charger commits a dash to close the last stretch from mid-range.
	if reachable and cooldown <= 0.0 and style == "charger" \
			and absf(gap) > attack_range() \
			and absf(gap) <= float(prof.get("charge_range", 200.0)) \
			and _floor_ahead(24.0):
		_start_charge()
		return

	# Otherwise walk him in, or hold at idle out of range.
	if reachable and absf(gap) <= aggro and absf(gap) > attack_range() * 0.8:
		state = State.WALK
		velocity.x = signf(gap) * speed
		_play("walk")
		return
	state = State.IDLE
	velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
	_play("idle")

# --- the charger's dash ------------------------------------------------------

func _start_charge() -> void:
	## Commit to a dash at the player. Fast, but side-steppable: standing still in
	## front of it is what gets punished.
	state = State.CHARGE
	clock = 0.0
	velocity.x = facing * float(prof.get("charge_speed", 200.0))
	_play("walk")

func _advance_charge(delta: float) -> void:
	if not is_instance_valid(target):
		_recover()
		return
	clock += delta
	velocity.x = facing * float(prof.get("charge_speed", 200.0))
	_play("walk")
	var gap: float = target.global_position.x - global_position.x
	var reachable: bool = absf(target.global_position.y - global_position.y) < 60.0
	if reachable and absf(gap) <= attack_range():
		_start_punch()
		return
	# He pulls up if he overruns the player, runs out of floor, or the dash has
	# run its length — the whiff leaves him briefly open, which is its counter.
	if signf(gap) != facing or not _floor_ahead(20.0) or clock >= CHARGE_TIME:
		state = State.IDLE
		velocity.x = 0.0
		cooldown = maxf(cooldown, CHARGE_RECOVER)

# --- the archer --------------------------------------------------------------

func _advance_archer(delta: float, gap: float, level: bool) -> void:
	var agap := absf(gap)
	# Someone closed to melee range: put his fists up. An archer up close is in
	# trouble, and the jab is his only answer there.
	if agap <= attack_range() and cooldown <= 0.0:
		_start_punch()
		return
	# Level with him, in range, and reloaded: draw the bow and loose.
	if cooldown <= 0.0 and level and agap > attack_range() \
			and agap <= float(prof.get("fire_range", 430.0)):
		_start_shoot()
		return
	# Otherwise hold the gap: close in if too far, kite backwards if too near, but
	# only onto floor — he will not back off a ledge to keep his distance.
	var want := 0.0
	if agap > float(prof.get("fire_range", 430.0)):
		want = signf(gap)
	elif agap < float(prof.get("fire_min", 150.0)):
		want = -signf(gap)
	if want != 0.0 and _floor_ahead(24.0, want):
		state = State.WALK
		velocity.x = want * speed
		_play("walk")
		return
	state = State.IDLE
	velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
	_play("idle")

func _start_shoot() -> void:
	state = State.SHOOT
	clock = 0.0
	fired = false
	velocity.x = 0.0
	_show("shoot", 0)

func _advance_shoot(delta: float) -> void:
	velocity.x = 0.0
	clock += delta
	# He tracks the player through the draw, so the arrow leaves pointed at him.
	if is_instance_valid(target) and absf(target.global_position.x - global_position.x) > 0.5:
		facing = signf(target.global_position.x - global_position.x)
	var holds := _durations("shoot")
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
	_show("shoot", index)
	# The arrow leaves on the release frame — the last one — exactly once.
	if index == holds.size() - 1 and not fired:
		fired = true
		var at := global_position + Vector2(facing * 22.0, -34.0)
		fired_arrow.emit(at, facing, int(prof.get("arrow_damage", 12)))
	if done:
		state = State.IDLE
		clock = 0.0
		cooldown = float(prof.get("shoot_cooldown", attack_cooldown))
		_play("idle")

func _floor_ahead(dist: float, dir: float = 0.0) -> bool:
	## Is there ground a short way off in the given direction (his facing by
	## default)? Keeps a charge from diving off a ledge, and the archer from kiting
	## backwards off one.
	var d := dir if dir != 0.0 else facing
	var x := position.x + d * dist
	var query := PhysicsRayQueryParameters2D.create(
		Vector2(x, position.y - 8.0), Vector2(x, position.y + 40.0), WORLD)
	query.collide_with_areas = false
	return not get_world_2d().direct_space_state.intersect_ray(query).is_empty()
