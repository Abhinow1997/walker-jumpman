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
##
## He does his own gravity and his own floor-finding — see _integrate — which is
## also what lets him jump. The terrain is his problem rather than the player's
## free win: a gap is measured and leapt if he can make it, a ledge is climbed,
## and a player who jumps over his head is followed up. See the jump block below
## and _maybe_jump, which is where all of that is decided.

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
## range), armor (super-armour during its own attack), leap (how fast he may
## travel through the air, which is what decides how wide a gap he can clear).
## Charger adds charge_speed and charge_range; archer adds fire_range, fire_min,
## shoot_cooldown and arrow_damage.
const DEFAULT_PROFILE := {
	"style": "walker", "health": MAX_HEALTH, "speed": WALK_SPEED,
	"damage": 20, "cooldown": ATTACK_COOLDOWN, "stagger": STAGGER_TIME,
	"knock": 1.0, "aggro": AGGRO_RANGE, "armor": false, "leap": 170.0,
}
const PROFILES := {
	# The rusher: light on his feet, closes with a committed dash.
	# He leaps as hard as he charges: 215 px/s carries him 161 px through a
	# 0.75 s hop, which is every gap on the course bar the two widest.
	"bandit": {
		"style": "charger", "health": 100, "speed": 84.0, "damage": 20,
		"cooldown": 0.68, "stagger": 0.28, "knock": 1.1, "aggro": 340.0,
		"armor": false, "charge_speed": 215.0, "charge_range": 200.0,
		"leap": 215.0,
	},
	# The bruiser: soaks damage, hits like a truck, and will not be staggered out
	# of his own swing. Slow enough that the answer is footwork, not trading.
	# Heavy in the air as well as on the ground: 150 px/s is 112 px of hop, which
	# takes the Isles' short gaps and stops dead at its chasms. Not lower — at
	# 110 he could not clear a single hole on the course and the whole thing was
	# decoration on him. Not higher either: a bruiser who can follow you over a
	# chasm leaves you nowhere to put the fight down.
	"mark": {
		"style": "bruiser", "health": 175, "speed": 46.0, "damage": 32,
		"cooldown": 1.05, "stagger": 0.12, "knock": 0.3, "aggro": 300.0,
		"armor": true, "leap": 150.0,
	},
	# The archer: keeps his distance and looses arrows, kiting backwards to hold
	# the gap open. Light and fragile, and forced to his fists if you close in.
	# Light, so he gets across a gap easily — but he only ever jumps to keep his
	# footing. An archer who leaps at you has given up the one thing he is for;
	# see the leap gate in _maybe_jump.
	"hunter": {
		"style": "archer", "health": 82, "speed": 78.0, "damage": 14,
		"cooldown": 0.7, "stagger": 0.32, "knock": 1.25, "aggro": 520.0,
		"armor": false, "fire_range": 430.0, "fire_min": 150.0,
		"shoot_cooldown": 1.05, "arrow_damage": 12, "leap": 195.0,
	},
}

## A charge is a committed dash: it runs at most this long, then he pulls up with
## a moment's recovery. That whiff window is the counter to standing your ground.
const CHARGE_TIME := 0.6
const CHARGE_RECOVER := 0.3

# --- the jump ----------------------------------------------------------------
#
# Deliberately a little weaker than the player's, and measured the same way:
# apex = v^2 / 2g. His is 640^2/(2*1920) = 106.7 px; this is 540^2/(2*1440) =
# 101.3. So every step on the course he can climb, they can follow him up, and
# there is nowhere he can stand that they can reach and he cannot leave.
#
# It also has to stay UNDER the perch ledges. The hunters on the Isles' high
# shelves sit 144 px above the deck at the lowest — see holds_gate — and the
# whole gate design rests on them being out of the fight. 101 px of jump keeps
# them up there, and DROP_LIMIT keeps them from coming down.
const JUMP_VELOCITY := -540.0
## How far ahead he looks for the edge he is about to walk off.
const EDGE_PROBE := 20.0
## Landings are searched outward in steps this size. Coarse on purpose: this runs
## per enemy per frame and 12 px is finer than any ledge on the course.
const LANDING_STEP := 12.0
## He aims this far PAST the lip he is clearing rather than at it, so a jump that
## is a pixel short still puts him on the ledge instead of in the wall.
const LANDING_INSET := 18.0
## The biggest drop he will take on purpose, by jumping or by stepping off a
## ledge. Under the 144 px perches for the reason above, and under the player's
## own jump, so he never puts himself somewhere the player cannot follow.
const DROP_LIMIT := 120.0
## After a jump: a moment on the floor before the next one. Long after a leap at
## the player, so he cannot pogo on your head; short after a platforming hop, or
## a staircase would take him all day.
const HOP_RECOVER := 0.9
const STEP_RECOVER := 0.25
## Landing from his own jump leaves him briefly flat-footed — the counter to an
## enemy who follows you into the air.
const LAND_RECOVER := 0.16

enum State { IDLE, WALK, PUNCH, HURT, DEAD, CHARGE, SHOOT, JUMP }

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
## Counts down after a blow lands, exactly as the player's does. Until now a hit
## on an enemy was legible only from the recoil frame, which the bruiser eats
## outright through his super-armour — so the one enemy you most need feedback
## from was the one that gave you none.
##
## Kept in step with HURT_FLASH and HURT_TINT in features/player/player_sprite.gd
## by a check in test_combat.gd: being hit has to read the same whoever it
## happens to.
var hurt_flash: float = 0.0
const HURT_FLASH := 0.35
const HURT_TINT := Color(1.0, 0.42, 0.38)
var dead_t: float = 0.0
## One punch may only land once, however many frames its box is open for.
var landed_this_punch: bool = false
## One draw of the bow looses one arrow, however long the release frame is held.
var fired: bool = false
## Set by whoever spawns him.
var home: Vector2 = Vector2.ZERO
## Whether the fight has started. Until it has he stands where the level put
## him, which is what `aggro` is for: without that gate every enemy in the level
## sets off the moment it loads and the first hunter arrives while the player is
## still on the opening ledge.
##
## Once it HAS started, aggro stops gating him and he follows. Backing off three
## steps and watching a bruiser give up, turn round and stand there reads as him
## being broken rather than as an escape — and the fight you walked away from is
## one the section gate will not let you leave anyway.
##
## Set by walking into his aggro range or by being hit from outside it, so a
## blast from across the room starts a fight rather than poking a statue.
## Cleared only by a retry: see reset().
var engaged: bool = false
## Whether this one holds its section's gate shut — see the sections block in
## session.gd. True for anything standing on ground the player runs along.
##
## The level marks the exceptions with "perch". The four on the Isles' high
## ledges stand 144 px above the deck and more: the player's jump apexes at 107,
## and both the blast and the arrow fly dead flat, so there is no way at all to
## kill them. A gate waiting on one of those could never open, and an unopenable
## gate is a worse bug than a sniper you have to run past.
##
## Their own jump does not change that: it is smaller than the player's, and
## DROP_LIMIT stops them stepping off a shelf that high — see the jump block.
var holds_gate: bool = true
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
## How fast he may travel horizontally through a jump, which is what sets the
## widest gap he can clear: reach = leap_speed * air_time().
var leap_speed: float = 170.0
## Whether his feet are on the floor this frame — a charge and the archer's kiting
## both need floor under them, and an airborne enemy is left to its momentum.
var grounded: bool = true
## Counts down after a jump, so he cannot pogo. Separate from `cooldown` because
## that one gates his fists: a landed enemy must be able to punch immediately.
var hop_cooldown: float = 0.0

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
	leap_speed = float(prof.get("leap", 170.0))
	health = max_health
	art_faces = float(data().get("faces", -1))
	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = _build_frames()
	sprite.centered = true
	sprite.offset = _pivot()
	## Linear, for the reason player_sprite.gd gives: this is painted LF2 art at
	## 0.75, not pixel art, and it only lands texel-perfect at two window sizes.
	## The whole cast shares the filter or a bandit standing next to him would be
	## visibly harder-edged than he is.
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
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
	# Hit from anywhere, by anything: that is a fight started, even if it came
	# from a blast fired well outside his aggro range.
	engaged = true
	# Set here rather than in any of the branches below, so every blow that lands
	# flashes: the killing one, the one a bruiser shrugs off mid-swing, and the
	# ordinary one that staggers him.
	hurt_flash = HURT_FLASH
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
	hurt_flash = 0.0
	engaged = false
	dead_t = 0.0
	grounded = true
	hop_cooldown = 0.0
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
	if hop_cooldown > 0.0:
		hop_cooldown = maxf(0.0, hop_cooldown - delta)

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
		State.JUMP:
			_advance_jump(delta)
		_:
			_advance_chase(delta)

	_integrate(delta)
	if hurt_flash > 0.0:
		hurt_flash = maxf(0.0, hurt_flash - delta)
	if is_instance_valid(sprite):
		sprite.scale = Vector2(facing * art_faces, 1.0) * art_scale
		# Fades back to white on its own clock, so the flash outlives the recoil
		# frame and a blow still registers on something that never staggered.
		sprite.modulate = Color.WHITE.lerp(HURT_TINT, hurt_flash / HURT_FLASH)

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
	# He plants his feet to swing — unless they are not on the ground, in which
	# case the swing rides the jump it was thrown from. Zeroing this in mid-air
	# would stop him dead over a gap and drop him into it.
	if grounded:
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

## After a completed attack: back to neutral, then wait out the cooldown. A swing
## thrown in mid-air goes back to falling rather than to standing, so the rest of
## the leap still happens.
func _recover() -> void:
	clock = 0.0
	cooldown = attack_cooldown
	if not grounded:
		state = State.JUMP
		return
	state = State.IDLE
	velocity.x = 0.0
	_play("idle")

func _start_punch() -> void:
	state = State.PUNCH
	clock = 0.0
	frame = 0
	landed_this_punch = false
	# Same reason as _advance_punch: planting his feet is only possible if they
	# are on something. A swing thrown mid-leap keeps the leap.
	if grounded:
		velocity.x = 0.0
	_show("punch", 0)

func _advance_chase(delta: float) -> void:
	if not is_instance_valid(target):
		velocity.x = 0.0
		_play("idle")
		return
	var gap: float = target.global_position.x - global_position.x
	# Positive when the player is ABOVE him, which is the direction that matters:
	# it is the one he answers with a jump.
	var rise: float = global_position.y - target.global_position.y
	var reachable: bool = absf(rise) < 60.0
	if absf(gap) > 0.5:
		facing = signf(gap)

	# Airborne — a knock carried him off the floor — so let his momentum carry
	# rather than steering him in mid-air. He wears the jump pose while it lasts;
	# he is in the air, however he got there.
	if not grounded:
		_show("jump", 0 if velocity.y < 0.0 else 1)
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

	if absf(gap) <= aggro:
		engaged = true

	# Over whatever is in the way: a gap, a step up, or a player who has taken to
	# the air. Ahead of the walk, because every one of those is a case where
	# walking is the wrong answer — and ahead of the `reachable` test, because a
	# player one ledge up is exactly who this is for.
	if engaged and _maybe_jump(gap, rise):
		return

	# Otherwise walk him in, or hold at idle out of range. `engaged` rather than
	# the aggro range: once the fight is on he keeps coming, however far the
	# player backs off — and `_following` rather than `reachable`, so a ledge
	# between them is something he walks up to and jumps, not something that
	# makes him forget the fight.
	if engaged and _following(rise) and absf(gap) > attack_range() * 0.8 \
			and _can_step(signf(gap)):
		state = State.WALK
		velocity.x = signf(gap) * speed
		_play("walk")
		return
	state = State.IDLE
	velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
	_play("idle")

# --- the jump ----------------------------------------------------------------

func jump_apex() -> float:
	## How high his own jump gets him, straight off the constants: v^2 / 2g.
	return JUMP_VELOCITY * JUMP_VELOCITY / (2.0 * GRAVITY)

func air_time() -> float:
	## How long he is off the ground for a jump that lands where it started.
	return -2.0 * JUMP_VELOCITY / GRAVITY

func _launch_for(dist: float, rise: float) -> float:
	## The horizontal speed that lands him `dist` away on ground `rise` px above
	## his feet — negative rise for a drop. The descending root of the same
	## envelope scripts/check_levels.py measures the player's jumps with, so an
	## enemy's reach and a player's are computed by one piece of arithmetic.
	##
	## -1 if his jump cannot rise that far at all.
	var u := -JUMP_VELOCITY
	var under := u * u - 2.0 * GRAVITY * rise
	if under < 0.0:
		return -1.0
	return dist * GRAVITY / (u + sqrt(under))

func _surface_at(x: float, top: float, bottom: float) -> float:
	## The highest solid surface in that column between two heights, or INF.
	var query := PhysicsRayQueryParameters2D.create(
		Vector2(x, top), Vector2(x, bottom), WORLD)
	query.collide_with_areas = false
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return INF if hit.is_empty() else float(hit.position.y)

func _following(rise: float) -> bool:
	## Is the player close enough in HEIGHT to be worth walking toward? One jump
	## above him, or a drop he would be willing to take. Beyond that there is no
	## route and he holds his ground — which is what keeps a deck enemy from
	## shuffling under a hunter's perch for ever.
	return rise <= jump_apex() + 40.0 and rise >= -DROP_LIMIT

func _can_step(dir: float) -> bool:
	## Is walking that way safe? Floor a stride ahead, or a drop short enough to
	## take on purpose. He will not walk into a pit: falling in was how an enemy
	## used to open his own section's gate for free, and one who strolls off a
	## cliff mid-chase reads as broken rather than as reckless.
	if _floor_ahead(EDGE_PROBE, dir):
		return true
	return _surface_at(position.x + dir * EDGE_PROBE,
			position.y + 4.0, position.y + DROP_LIMIT) != INF

func _landing_ahead(dir: float) -> float:
	## The horizontal speed that would put him on the nearest ledge he can reach
	## that way, or -1 if there is nowhere to land. Searched outward, so the near
	## side of a gap wins over anything beyond it, and aimed a little PAST each
	## lip so a jump that comes up short still lands on top of it.
	var apex := jump_apex()
	var limit := leap_speed * air_time()
	var d := EDGE_PROBE
	# Whether the search has passed over open air yet. Without this the very
	# first probe can come back with the top of the lip he is already standing
	# on — a "landing" 20 px away and level with his feet, which he would take,
	# and which puts him in the hole. A landing has to be somewhere else: over
	# the void, or higher up.
	var void_seen := false
	while d <= limit:
		var surface := _surface_at(position.x + dir * d,
				position.y - apex - 8.0, position.y + DROP_LIMIT)
		if surface == INF:
			void_seen = true
		else:
			var rise := position.y - surface     # + = the ledge is above him
			if (void_seen or rise > 8.0) and rise <= apex - 8.0:
				var want := _launch_for(d + LANDING_INSET, rise)
				if want > 0.0 and want <= leap_speed:
					return want
		d += LANDING_STEP
	return -1.0

func _maybe_jump(gap: float, rise: float) -> bool:
	## Decide and commit a jump. True if he left the ground.
	if not grounded or hop_cooldown > 0.0:
		return false
	var dir := signf(gap)
	if dir == 0.0:
		dir = facing

	# Going up after him. The player who jumps clean over an enemy's head, or
	# stands on the step above him and swings down, used to be untouchable: every
	# attack in this game is thrown flat, so anything higher than the 60 px
	# `reachable` band was safe ground. Now it is answered.
	#
	# Melee only. An archer who leaps at you has abandoned the one thing he is
	# for, and his answer to height is to back up and shoot.
	#
	# The floor check is what stops this being a way to farm him: a player
	# hanging in the air over a chasm is bait, and an enemy who takes it throws
	# himself into the pit and opens his own section's gate.
	if style != "archer" and rise > 40.0 and rise <= jump_apex() \
			and absf(gap) <= leap_speed * air_time() * 0.7 and cooldown <= 0.0 \
			and _surface_at(position.x + gap, position.y - jump_apex() - 8.0,
					position.y + DROP_LIMIT) != INF:
		_start_jump(clampf(gap / air_time(), -leap_speed, leap_speed), HOP_RECOVER)
		return true

	# The ground ahead has run out. A gap and a step up read the same to a floor
	# probe — both are "nothing to walk onto" — and the answer to both is the
	# same, so this does not care which it is.
	#
	# A shut section gate reads that way too: its wall is 2400 px tall, so a
	# probe standing inside it reports nothing and he hops over. Harmless — he
	# never collided with that wall in the first place, it is a barrier for the
	# player's camera and feet only — but it is why an enemy at a gate line may
	# be seen jumping at nothing.
	if _floor_ahead(EDGE_PROBE, dir):
		return false
	var want := _landing_ahead(dir)
	if want < 0.0:
		return false
	_start_jump(dir * want, STEP_RECOVER)
	return true

func _start_jump(vx: float, recover: float) -> void:
	state = State.JUMP
	clock = 0.0
	velocity = Vector2(vx, JUMP_VELOCITY)
	grounded = false
	hop_cooldown = recover
	landed_this_punch = false
	if absf(vx) > 1.0:
		facing = signf(vx)
	_show("jump", 0)

func _advance_jump(delta: float) -> void:
	## Committed, exactly like the charge: no steering in the air. What he leaves
	## the ground with is what he lands with, so a jump is a decision he can be
	## made to regret rather than a homing missile.
	clock += delta
	_show("jump", 0 if velocity.y < 0.0 else 1)
	# A swing thrown out of the jump. Nothing special about it — the same fists
	# and the same hit box, which rides the sprite and is therefore high when he
	# is high. That is the whole point of going up after someone.
	if is_instance_valid(target) and cooldown <= 0.0 and style != "archer":
		var gap: float = target.global_position.x - global_position.x
		var rise: float = global_position.y - target.global_position.y
		if absf(gap) <= attack_range() and absf(rise) < 60.0:
			_start_punch()
			return
	if grounded:
		state = State.IDLE
		velocity.x = 0.0
		# Flat-footed for a moment on landing: the counter to an enemy who
		# follows you into the air is to be somewhere else when he comes down.
		cooldown = maxf(cooldown, LAND_RECOVER)
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
	# He has not noticed the player yet, so he stands where the level put him.
	#
	# This gate was missing, and its absence was not subtle: "too far to shoot"
	# below means walk in, and it had no upper bound, so every archer in the level
	# set off toward the player the instant it loaded. The first hunter was 1920
	# away at spawn and arrived while the player was still on the opening ledge.
	# The melee styles were always gated this way — see the aggro test at the foot
	# of _advance_chase — and the archer simply never got the same check.
	#
	# Same as those: it only holds him until the fight starts. After that he
	# closes the gap like anyone else, because an archer who lets you stroll out
	# of his range and then forgets you is not a fight.
	if agap <= aggro:
		engaged = true
	if not engaged:
		state = State.IDLE
		velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
		_play("idle")
		return
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
	# Nothing to shoot and ground in the way: he jumps it like anyone else.
	# _maybe_jump gives him the platforming half only — see the style gate on the
	# leap there — so he crosses a gap to reach his firing line and never hops at
	# the player.
	if _maybe_jump(gap, global_position.y - target.global_position.y):
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
