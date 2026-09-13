extends CharacterBody2D

const Tuning = preload("res://features/player/tuning.gd")
const Moveset = preload("res://features/player/moveset.gd")
# Swap this one line to change the protagonist's appearance.
# player_sprite.gd is the Anti-Davis sprite; player_visual.gd is the original
# procedural Wind-Up Knight rig, kept as a fallback that needs no art files.
const Visual = preload("res://features/player/player_sprite.gd")

## Fired when the blast animation reaches the frame that releases the projectile.
## The session spawns it, not the player: once thrown it must not move with him.
signal blast_fired(at: Vector2, direction: float)

## Physics layer 7. The strike is a shape query against this and nothing else,
## so anything that wants to be hittable has to be on it. See combat/crate.gd.
const HITTABLE := 64

## How each move behaves. What it looks like, how long each frame lasts and
## where it hits all come from moves.json, which the extractor generates from
## the pack; this table is only about how a move interacts with input and
## movement, which is a game design decision and not in the pack.
##
##   ground   must be standing on the floor to start it
##   chain    move this one buffers into when attack is pressed again
##   planted  ignores the movement axis for its duration
##   drive    forced forward speed, for moves that carry you
##   ends_on_land  an air move that is cut short by touching down
##   loops         the animation repeats; the move's length is decided elsewhere
##
## Not every entry is an attack. `drink` runs on exactly the same machinery and
## simply has no hit frames, which is the point: one clock, one set of rules for
## "the character is committed to an animation", rather than a second system.
## It is the only looping entry: LF2 drew four drink frames, and six seconds of
## drinking is those four frames over and over.
const MOVES := {
	"punch_a": {"ground": true,  "chain": "punch_b", "planted": true},
	"punch_b": {"ground": true,  "chain": "",        "planted": true},
	"kick":    {"ground": false, "chain": "",        "planted": false, "ends_on_land": true},
	"charge":  {"ground": true,  "chain": "",        "planted": false, "drive": 300.0},
	"blast":   {"ground": true,  "chain": "",        "planted": true,  "spawn_frame": 4},
	"drink":   {"ground": true,  "chain": "",        "planted": true,  "loops": true},
}

## Attacking at or above this speed becomes the shoulder charge instead of a
## jab. Matches player_sprite.gd's RUN_SPEED so the move matches the pose he is
## already in when the button goes down.
const CHARGE_FROM := 150.0
## Where the projectile leaves his hand, relative to his feet. Read off the
## blast animation's release frame.
const BLAST_MUZZLE := Vector2(30.0, -46.0)

## Health starts low so the bottle has something to do. Nothing takes health
## away yet: spikes and falls are still instant death, which is this game's
## existing rule and not something a health bar should quietly replace. So for
## now it only goes up, and it is the hook damage will hang off later.
const MAX_HEALTH := 100
const START_HEALTH := 25
## The health bar draws five slots (ui/art/healthbar.json), so health is counted
## in segments and "a bottle is worth two bars" stays true whatever MAX_HEALTH is.
const HEALTH_SEGMENTS := 5

## Seconds to drink a completely full bottle. A part-full one takes its share:
## a bottle half drunk, or cracked by a punch, is half the wait and half the
## health. Nothing here is all-or-nothing — he keeps whatever he swallowed and
## the bottle keeps the rest — so stopping is a decision about how long to stand
## still, not a gamble on losing the lot.
const FULL_DRINK_TIME := 6.0

## Why a drink stopped. The session cares about the difference: a drink he
## walked out of leaves the bottle standing, a drink he was hit during drops it.
const DRINK_HIT := "hit"
const DRINK_MOVED := "moved"
const DRINK_JUMPED := "jumped"
const DRINK_ATTACKED := "attacked"
const DRINK_KNOCKED := "knocked off his feet"
const DRINK_LEFT := "moved away"
const DRINK_EMPTY := "emptied the bottle"
const DRINK_FULL := "already full"

## Emitted whenever a drink stops. `reason` is one of the DRINK_* constants, and
## `last_drink_consumed` says how much of a full bottle went with it.
signal drink_ended(completed: bool, reason: String)

var tuning = Tuning.new()
var visual: Node2D
var enabled: bool = false
var tick: int = 0
var last_floor_tick: int = -1000
var jump_request_tick: int = -1000
var opportunity_consumed: bool = false
var require_jump_release: bool = true
var facing: float = 1.0
var jumps: int = 0
var health: int = START_HEALTH
var test_control: bool = false
var test_axis: float = 0.0
var test_jump_pressed: bool = false
var test_jump_held: bool = false

## Attack state. `attack` is "" whenever he is not mid-move, and the visual
## reads these three to decide what to draw; it owns none of them.
var attack: String = ""
var attack_frame: int = 0
var attack_clock: float = 0.0
var chain_queued: bool = false
## Targets this swing has already connected with. One swing hits a given target
## once, however many frames of it overlap.
var struck: Array = []
var blast_released: bool = false
## How much the bottle currently being drunk is worth, and whether it has been
## applied yet. Health lands partway through the animation rather than on the
## key press, so the bar moves when he actually tips the bottle back.
## Seconds into the current drink; how full the bottle was when he raised it;
## what a whole bottle of it is worth; and fractional health carried between
## frames, because health is an integer and a sip is not.
var drink_t: float = 0.0
var drink_fill: float = 1.0
var drink_segments: int = 0
var drink_pool: float = 0.0
## Fraction of a full bottle drunk by the drink that just ended, and how much
## was left in it. The session reads these to settle up with the bottle.
var last_drink_consumed: float = 0.0
var last_drink_left: float = 0.0
var hits_landed: int = 0
var attacks_thrown: int = 0
var test_attack_pressed: bool = false
var test_blast_pressed: bool = false

func _ready() -> void:
	name = "Player"
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 2.0
	# Sized to the Anti-Davis body, not to a blanket x2 of the old box. He is drawn
	# ~37 x 73 px, but most of that is swinging arms and hair spikes; torso and legs
	# are about this box. A hitbox wider than the drawn body kills the player on
	# spikes that visibly missed, so it stays inside the silhouette on purpose.
	var shape := RectangleShape2D.new()
	shape.size = Vector2(20, 56)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = Vector2(0, -28)
	add_child(collider)
	visual = Visual.new()
	visual.body = self
	add_child(visual)

func reset_at(spawn: Vector2) -> void:
	position = spawn
	velocity = Vector2.ZERO
	last_floor_tick = -1000
	jump_request_tick = -1000
	opportunity_consumed = false
	require_jump_release = true
	test_jump_pressed = false
	jumps = 0
	health = START_HEALTH
	drink_pool = 0.0
	_finish_drink(false, "retry")
	_end_attack()
	test_attack_pressed = false
	test_blast_pressed = false
	if is_instance_valid(visual):
		visual.reset()

func on_death() -> void:
	## Appearance only; the session still owns the death state and retry timing.
	_finish_drink(false, "died")
	_end_attack()
	if is_instance_valid(visual):
		visual.on_death()

# --- health ----------------------------------------------------------------

func heal(amount: int) -> int:
	## Returns how much was actually restored, which is zero at full health.
	## The caller decides whether a drink that heals nothing should still be
	## spent; this only reports.
	var before := health
	health = clampi(health + amount, 0, MAX_HEALTH)
	return health - before

func health_fraction() -> float:
	return float(health) / float(MAX_HEALTH)

func segment_health() -> int:
	## One slot of the health bar, in points.
	return int(round(float(MAX_HEALTH) / float(HEALTH_SEGMENTS)))

func begin_drink(segments: int, fill: float) -> bool:
	## Starts a drink on a bottle that is `fill` full (0 to 1) and worth
	## `segments` bars when whole. The caller has already decided the drink is
	## allowed; this only refuses when he is not in a position to start —
	## mid-move, or off the ground.
	if not can_attack() or not is_on_floor():
		return false
	if fill <= 0.0:
		return false
	if not begin_attack("drink"):
		return false
	drink_segments = segments
	drink_fill = clampf(fill, 0.0, 1.0)
	drink_t = 0.0
	return true

func is_drinking() -> bool:
	return attack == "drink"

func drink_span() -> float:
	## How long this particular drink takes: proportional to what is left in the
	## bottle, so a half-empty or cracked one is a correspondingly shorter wait.
	return drink_fill * FULL_DRINK_TIME

func drink_remaining() -> float:
	return maxf(0.0, drink_span() - drink_t)

func drink_fill_left() -> float:
	## How full the bottle in his hand is right now. The session pushes this into
	## the bottle every frame, so its contents are live rather than settled up at
	## the end — a drink cut off by anything at all still leaves the bottle
	## holding exactly what he did not swallow.
	if not is_drinking():
		return 0.0
	return maxf(0.0, drink_fill - drink_t / FULL_DRINK_TIME)

func drink_progress() -> float:
	## 0 to 1 through *this* drink. The HUD needs it: seconds of a looping
	## animation with no visible clock reads as the game being stuck.
	var span := drink_span()
	if not is_drinking() or span <= 0.0:
		return 0.0
	return clampf(drink_t / span, 0.0, 1.0)

func interrupt_drink(reason: String) -> void:
	## Ends a drink from outside. The session calls it when he walks out of
	## reach, and it is the hook damage hangs off: pass DRINK_HIT and the bottle
	## is knocked out of his hand rather than set down.
	_finish_drink(false, reason)

func _finish_drink(completed: bool, reason: String) -> void:
	if attack != "drink":
		return
	# Measured against a *full* bottle, which is the unit the bottle stores its
	# contents in. Health is already in him: it went in as he swallowed.
	last_drink_consumed = drink_t / FULL_DRINK_TIME
	last_drink_left = maxf(0.0, drink_fill - last_drink_consumed)
	_end_attack()
	drink_ended.emit(completed, reason)

func _advance_drink(delta: float) -> void:
	if not is_on_floor():
		_finish_drink(false, DRINK_KNOCKED)
		return
	var span := drink_span()
	# Clamped so the last frame cannot overshoot and credit him for more of the
	# bottle than was in it.
	var step: float = minf(delta, maxf(0.0, span - drink_t))
	drink_t += step
	# Health arrives as he swallows rather than in a lump at the end, so a drink
	# cut short is worth exactly the part of it he got through.
	drink_pool += step / FULL_DRINK_TIME * float(drink_segments * segment_health())
	var whole := int(floor(drink_pool))
	if whole > 0:
		drink_pool -= float(whole)
		heal(whole)
	if health >= MAX_HEALTH:
		# Topped up with some still in the bottle. Stop rather than pour the
		# rest away — he can come back for it.
		_finish_drink(true, DRINK_FULL)
		return
	if drink_t >= span:
		_finish_drink(true, DRINK_EMPTY)

# --- attacks ---------------------------------------------------------------

func can_attack() -> bool:
	return enabled and attack == ""

func _choose_attack() -> String:
	## Context picks the move, so one button covers the whole ground moveset and
	## the player never has to learn a motion input to see all of it.
	if not is_on_floor():
		return "kick"
	if absf(velocity.x) >= CHARGE_FROM:
		return "charge"
	return "punch_a"

func begin_attack(key: String) -> bool:
	if not MOVES.has(key) or not Moveset.has(key):
		return false
	if MOVES[key].get("ground", false) and not is_on_floor():
		return false
	attack = key
	attack_frame = 0
	attack_clock = 0.0
	chain_queued = false
	blast_released = false
	struck.clear()
	# A drink is not a swing, and must not inflate the attacks-thrown figure the
	# evidence run reports.
	if key != "drink":
		attacks_thrown += 1
	return true

func _end_attack() -> void:
	attack = ""
	attack_frame = 0
	attack_clock = 0.0
	chain_queued = false
	blast_released = false
	drink_t = 0.0
	drink_fill = 1.0
	drink_segments = 0
	# drink_pool is deliberately NOT cleared: it is the fraction of a health
	# point already swallowed but not yet worth a whole one. Dropping it on every
	# stop would quietly lose most of a bottle drunk in short sips.
	struck.clear()

func _advance_attack(delta: float) -> void:
	if attack == "":
		return
	attack_clock += delta
	var rules: Dictionary = MOVES[attack]
	if rules.get("loops", false):
		# The animation repeats for as long as the move runs, rather than its
		# length deciding when the move is over.
		var span := Moveset.length(attack)
		if span > 0.0:
			attack_clock = fmod(attack_clock, span)
	attack_frame = Moveset.frame_at(attack, attack_clock)

	if attack == "drink":
		# No hit frames, no chain, and its own clock decides when it ends.
		_advance_drink(delta)
		return
	if rules.has("spawn_frame") and not blast_released and attack_frame >= int(rules.spawn_frame):
		blast_released = true
		blast_fired.emit(global_position + Vector2(BLAST_MUZZLE.x * facing, BLAST_MUZZLE.y), facing)

	_resolve_hits()

	# An air move that lands has nothing left to say; cutting it keeps him from
	# standing on the floor still kicking.
	if rules.get("ends_on_land", false) and is_on_floor() and attack_clock > 0.06:
		_end_attack()
		return
	if attack_clock < Moveset.length(attack):
		return
	var chain: String = rules.get("chain", "")
	if chain_queued and chain != "" and Moveset.has(chain):
		begin_attack(chain)
	else:
		_end_attack()

func _resolve_hits() -> void:
	var hits := Moveset.hits(attack, attack_frame)
	if hits.is_empty():
		return
	var space := get_world_2d().direct_space_state
	for hit in hits:
		var box: Rect2 = hit.rect
		# The art is drawn facing right and the boxes are transcribed in that
		# space, so both mirror together and the hit stays on the fist.
		if facing < 0.0:
			box.position.x = -(box.position.x + box.size.x)
		box.position += global_position
		var query := PhysicsShapeQueryParameters2D.new()
		var shape := RectangleShape2D.new()
		shape.size = box.size
		query.shape = shape
		query.transform = Transform2D(0.0, box.position + box.size / 2.0)
		query.collision_mask = HITTABLE
		query.collide_with_areas = true
		query.collide_with_bodies = false
		for result in space.intersect_shape(query, 16):
			var target = result.collider
			if target == null or struck.has(target) or not target.has_method("take_hit"):
				continue
			if target.take_hit(int(hit.damage), global_position):
				struck.append(target)
				hits_landed += 1

# --- step ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not enabled:
		return
	tick += 1
	var axis := test_axis if test_control else Input.get_axis("move_left", "move_right")
	var held := test_jump_held if test_control else Input.is_action_pressed("jump")
	var pressed := test_jump_pressed if test_control else Input.is_action_just_pressed("jump")
	var attack_pressed := test_attack_pressed if test_control else Input.is_action_just_pressed("attack")
	var blast_pressed := test_blast_pressed if test_control else Input.is_action_just_pressed("blast")
	test_jump_pressed = false
	test_attack_pressed = false
	test_blast_pressed = false

	if attack == "drink":
		# Read before `planted` zeroes the axis, so this sees the movement key
		# even though the drink itself never moves him. Running before dispatch
		# means the same press then does whatever it was going to do.
		if not is_zero_approx(axis):
			_finish_drink(false, DRINK_MOVED)
		elif pressed:
			_finish_drink(false, DRINK_JUMPED)
		elif attack_pressed or blast_pressed:
			_finish_drink(false, DRINK_ATTACKED)

	if attack == "":
		if blast_pressed:
			begin_attack("blast")
		elif attack_pressed:
			begin_attack(_choose_attack())
	elif attack_pressed:
		# Buffered, not immediate: pressing during the jab queues the cross and
		# it starts when the jab finishes, so the combo reads as two hits.
		chain_queued = true
	_advance_attack(delta)

	var rules: Dictionary = MOVES.get(attack, {})
	if rules.get("planted", false):
		axis = 0.0
	# A committed move cannot be jumped out of. The request is dropped rather
	# than buffered, so it does not fire the instant the move ends.
	if attack != "" and is_on_floor():
		pressed = false

	if not held:
		require_jump_release = false
	if is_on_floor() and velocity.y >= 0.0:
		last_floor_tick = tick
		opportunity_consumed = false
	if pressed and not require_jump_release:
		jump_request_tick = tick
	if rules.has("drive"):
		velocity.x = move_toward(velocity.x, facing * float(rules.drive), tuning.acceleration * delta)
	else:
		var rate: float = tuning.acceleration if not is_zero_approx(axis) else tuning.deceleration
		velocity.x = move_toward(velocity.x, axis * tuning.speed, rate * delta)
	# Facing is frozen mid-move, otherwise the hitbox could flip away from the
	# fist between the wind-up and the contact frame.
	if not is_zero_approx(axis) and attack == "":
		facing = signf(axis)
	velocity.y = minf(velocity.y + tuning.gravity * delta, tuning.terminal_velocity)
	if not opportunity_consumed and tick - last_floor_tick <= tuning.coyote_ticks and tick - jump_request_tick <= tuning.buffer_ticks:
		velocity.y = tuning.jump_velocity
		opportunity_consumed = true
		jump_request_tick = -1000
		jumps += 1
	move_and_slide()
	position.x = maxf(position.x, 20.0)
	visual.advance(delta)
