extends Area2D
## Shared behaviour for the things in the level a punch can connect with.
##
## Everything here is what a struck object does in LF2: a blow that does not
## destroy it knocks it into the air, it tumbles through the angles the pack
## drew for it, lands, has the bounce damped out of it, skids, and settles. When
## its health finally runs out it shatters into that object's own debris.
##
## THE CONTRACT. Anything the player can hit must do exactly two things:
##
##   1. Sit on the Hittable physics layer (HITTABLE below). The player's strike
##      is a shape query against that layer and nothing else, so a target that
##      is not on it is invisible to every attack.
##   2. Expose `take_hit(damage: int, from: Vector2) -> bool`, returning true if
##      the hit counted. `from` is the attacker's position, so the target knows
##      which way it was struck. Returning false — already broken, invulnerable,
##      mid-stagger — means the strike ignores it and keeps looking.
##
## Both are satisfied by extending this. A subclass supplies numbers and art
## names in `_configure()` and nothing else is required; the crate and the
## bottle differ only in that. A future enemy can either extend this or
## implement the two points itself.
##
## Props never block movement: an Area2D with no collision mask, so the player
## walks through them and no prop, wherever it ends up, can alter the route.

const Items = preload("res://features/combat/items.gd")

const HITTABLE := 64  # physics layer 7
const WORLD := 1      # physics layer 1: what it lands on

# --- being knocked about ----------------------------------------------------

## The cast and the props were resampled to 0.75 so they stand alongside the
## 50 px CC0 street enemies, and their physics has to come with them. A box
## two-thirds the size thrown the same distance flies clean out of punching
## range — which silently broke the jab-into-cross combo, because the cross
## arrived after the jab had knocked the crate past the end of his fist.
##
## Lengths and speeds scale. Ratios (BOUNCE, SKID), rates (SPIN_MAX), times
## (BREAK_TIME) and game numbers (KNOCK_REFERENCE) must not: they are already
## independent of size.
##
## This is how big a prop is in the WORLD. How big its sheet is, is a separate
## number the extractor publishes as render_scale — the sheets are written at
## the LF2 sheet's own resolution and are not scaled at all. Set this back to
## 1.0 only if the props themselves get bigger, never because the art did.
const ART_SCALE := 0.75

## Heavier than the player's own gravity. A prop that hangs in the air reads as
## cardboard; these are meant to have weight.
const GRAVITY := 1600.0 * ART_SCALE
## Knock from a blow of KNOCK_REFERENCE damage, scaled by the real damage. Tuned
## against gravity rather than guessed: a jab is 20, so it lifts a prop about
## 14 px and skids it roughly half its own width — plainly knocked, but still
## inside punching range for the follow-up. At 200 the hop was three pixels,
## which reads as the thing being bolted down. A shoulder charge is 55 and
## launches it properly.
##
## Deliberately not scaled by health: how hard something is thrown is a property
## of the blow, not of how much punishment the thing happens to take.
const KNOCK_REFERENCE := 40.0
const KNOCK_X := 170.0 * ART_SCALE
const KNOCK_Y := 420.0 * ART_SCALE
const BOUNCE := 0.38       # vertical speed surviving a landing
const SKID := 0.62         # horizontal speed kept through a bounce
const FRICTION := 620.0 * ART_SCALE    # ground drag once it stops bouncing
const BOUNCE_MIN := 55.0 * ART_SCALE   # below this it slides instead of bouncing
const REST_SPEED := 10.0 * ART_SCALE   # below this it is done moving
const SPIN_MAX := 18.0     # tumble frames per second at a full-weight blow

## A prop is never destroyed by the blow that first lands on it. A shoulder
## charge carries 55 and a flying kick 60, both more than most props' whole
## health, so without this the heavy moves erase the thing where it stands and
## the player never sees it move at all. Surviving on its last splinter costs
## one extra hit and buys the launch. Once it has been hit, normal arithmetic
## applies and anything can finish it.
const SURVIVES_FIRST_BLOW := true

# --- breaking ---------------------------------------------------------------

## How long the wreckage lives. Long enough for pieces to bounce once and
## settle, which is what makes it read as breaking rather than vanishing.
const BREAK_TIME := 0.95
## How many drawn rotations each debris fragment has. The LF2 strips draw four
## apiece and are laid out as fragment type * 4 + rotation; a sheet that draws
## each piece once sets this to 1 and lists its pieces in `debris_types`.
var debris_spins: int = 4
## How many tumble steps make a full turn when an object spins its own sprite
## rather than stepping through drawn angles. Eight, matching the eight drawn
## rotations of the sheets that do have them, so both turn at the same rate.
const SPRITE_TURN_STEPS := 8.0

# --- configuration, set by the subclass in _configure() ---------------------

var max_health: int = 40
## Hit box. Kept just inside the drawn art so a punch that visibly grazes the
## edge does not miss.
var body: Vector2 = Vector2(48, 48)
var art_rest: String = ""
## Frames per second of the resting animation, when `art_rest` holds more than
## one frame. Zero — the default, and every LF2 prop — holds frame 0 forever.
var rest_fps: float = 0.0
var art_spin: String = ""
var art_debris: String = ""
## An in-place shatter strip: the object coming apart where it stood, played once
## before its pieces are thrown. Empty for anything with no such art — the crate
## and the bottle break straight into debris, exactly as they always have.
var art_break: String = ""
## Seconds per frame of that strip.
var break_step: float = 0.07
## Whether a tumbling object turns by rotating its one sprite instead of stepping
## through drawn angles. False for anything with a drawn tumble: rotating the
## crate on top of LF2's six angles would turn it twice. True for something
## round with no angles drawn, which otherwise sails through the air rigid.
var spins_sprite: bool = false
## One entry per debris piece, naming which fragment of the strip it is. Weight
## it toward the smaller fragments or a break looks like the thing split into a
## few identical lumps.
var debris_types: Array = [0]
## Two-handed. A heavy prop is hoisted overhead, slows the carrier down and can
## only be thrown; a light one rides in his hand and can still be used for what
## it is. LF2's own distinction, and the reason it draws two pick-up poses.
var heavy: bool = true
## Where on the prop the carrier's hand goes, relative to its own origin. The
## default is its base, which is right for something rested on both palms; a
## small object held in one hand sets this to its middle.
var carry_anchor: Vector2 = Vector2.ZERO
## What it does to whatever it lands on when thrown.
var throw_damage: int = 45
## How far above the origin the spin frames are drawn, and the half-height the
## debris bursts from. Defaults to half the hit box, which is right when the box
## matches the art. A prop whose box is deliberately taller than what is drawn —
## a small pickup that would otherwise sit under every punch in the game — sets
## this to half its real drawn height so the art does not float.
var spin_lift: float = -1.0

# --- state ------------------------------------------------------------------

## Texture pixel to world unit, read from the items manifest in _ready. Not the
## same thing as ART_SCALE: that one is a world size, this one is a resolution.
var art_render: float = 1.0
var health: int = 0
var broken: bool = false
var flash: float = 0.0
var shake_dir: float = 1.0

## Where it was placed. Retry puts it back here, or a prop the player knocked
## across the level would start the next attempt wherever it landed.
var home: Vector2 = Vector2.ZERO
var motion: Vector2 = Vector2.ZERO
var at_rest: bool = true
var spin_phase: float = 0.0
var spin_rate: float = 0.0
## The level's fall line, set by whoever spawns it. A prop knocked into a pit
## has to end somewhere; falling forever would leave a live target the player
## can never reach again.
var fall_limit: float = INF

## In his hands: physics is suspended and the carrier places it every frame.
var carried: bool = false
## In flight after being thrown, and what this throw has already hit — one throw
## may not hit the same target twice on consecutive frames.
var thrown: bool = false
var throw_struck: Array = []

## Every frame of `art_rest`, for a prop whose resting art animates. The first
## is `rest_frame`, which is all a still prop ever draws.
var rest_frames: Array[Texture2D] = []
var rest_clock: float = 0.0
var break_t: float = 0.0
## Inside the drawn shatter, before the pieces fly. Only ever true for a prop
## with an `art_break` strip.
var breaking: bool = false
var break_frames: Array[Texture2D] = []
var debris: Array = []
var debris_seed: int = 0
## Floor height for the wreckage, relative to the prop, measured when it
## shatters — something broken in mid-air drops its pieces to the real ground
## rather than to wherever it happened to be.
var debris_floor: float = 0.0

## Frames are built once. Drawing the debris as AtlasTextures keeps it on the
## same code path the prop sprites already use.
var rest_frame: Texture2D
var spin_frames: Array[Texture2D] = []
var debris_frames: Array[Texture2D] = []
var sprite: Sprite2D

# --- subclass hooks ---------------------------------------------------------

## Fill in the configuration above. Called before anything is built.
func _configure() -> void:
	pass

## Extra setup once the sprite exists.
func _on_ready() -> void:
	pass

## Extra per-step work: idle animation and the like.
func _prop_process(_delta: float) -> void:
	pass

func _resting_frame() -> Texture2D:
	## The frame of the resting animation showing now, or the only one there is.
	## The clock runs whether it is on the floor or in the air, so a glow that
	## pulses keeps pulsing while the thing is being carried or thrown.
	if rest_fps <= 0.0 or rest_frames.size() < 2:
		return rest_frame
	return rest_frames[int(rest_clock * rest_fps) % rest_frames.size()]

## Where the resting sprite sits, for props that bob or lean in place.
func _rest_offset() -> Vector2:
	return Vector2.ZERO

## False while the prop is present but should ignore strikes.
func _hittable() -> bool:
	return true

# --- lifecycle --------------------------------------------------------------

func _init() -> void:
	_configure()
	if spin_lift < 0.0:
		spin_lift = body.y / 2.0
	health = max_health
	collision_layer = HITTABLE
	# Targets do not detect anything themselves; the strike queries them.
	collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = body
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = Vector2(0, -body.y / 2.0)
	add_child(collider)

func _ready() -> void:
	home = position
	art_render = Items.render_scale()
	## Linear, as for the cast: the crates and bottles are painted LF2 items on
	## the same 0.75 and pick up the same uneven sampling at other window sizes.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if art_rest != "":
		rest_frame = Items.frame(art_rest, 0)
		for i in Items.frames(art_rest):
			rest_frames.append(Items.frame(art_rest, i))
	for i in Items.frames(art_spin):
		spin_frames.append(Items.frame(art_spin, i))
	for i in Items.frames(art_debris):
		debris_frames.append(Items.frame(art_debris, i))
	for i in Items.frames(art_break):
		break_frames.append(Items.frame(art_break, i))
	sprite = Sprite2D.new()
	sprite.centered = true
	sprite.scale = Vector2(art_render, art_render)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(sprite)
	_on_ready()
	_update_sprite()

func reset() -> void:
	## The session restarts the whole attempt on death, so a prop the player
	## broke, threw or carried off has to come back, whole and where it started.
	position = home
	z_index = 0
	face_forward()
	health = max_health
	broken = false
	carried = false
	thrown = false
	throw_struck.clear()
	flash = 0.0
	motion = Vector2.ZERO
	at_rest = true
	spin_phase = 0.0
	spin_rate = 0.0
	break_t = 0.0
	breaking = false
	rest_clock = 0.0
	debris.clear()
	_update_sprite()
	queue_redraw()

## True when the player could pick this up right now.
func can_be_carried() -> bool:
	return not broken and not carried and not thrown and at_rest and _hittable()

func pick_up() -> void:
	## Off the floor. Physics stops; the carrier owns its position from here.
	##
	## Props are spawned before the player so they draw behind him, which is
	## right for something on the floor and wrong for something in his hand — a
	## bottle held at his hip disappeared into his leg. In his hands it goes in
	## front; launch() and reset() put it back.
	z_index = 1
	carried = true
	thrown = false
	at_rest = true
	motion = Vector2.ZERO
	spin_rate = 0.0
	spin_phase = 0.0
	_update_sprite()

func face_forward() -> void:
	## Back to its own orientation once it is out of his hands.
	if is_instance_valid(sprite):
		sprite.scale = Vector2(art_render, art_render)

func place_at(where: Vector2, side: float = 1.0) -> void:
	## Driven every frame by the carrier's current weapon point. `side` mirrors
	## it with him: a tipped bottle drawn facing right while he faces left
	## points away from his own mouth.
	position = where + Vector2(carry_anchor.x * side, carry_anchor.y)
	if is_instance_valid(sprite):
		sprite.scale = Vector2(-art_render if side < 0.0 else art_render, art_render)

func launch(velocity: Vector2) -> void:
	## Thrown. It re-enters the world on the same physics a punched prop uses,
	## and until it lands it hurts whatever it catches.
	z_index = 0
	face_forward()
	carried = false
	thrown = true
	throw_struck.clear()
	at_rest = false
	motion = velocity
	var dir := signf(velocity.x)
	spin_rate = (dir if not is_zero_approx(dir) else 1.0) * SPIN_MAX * 1.3
	_update_sprite()

func _strike_in_flight() -> void:
	## Everything on the Hittable layer is fair game — crates, bottles and the
	## bandits. The player is not on that layer, so his own throw cannot come
	## back at him.
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := RectangleShape2D.new()
	shape.size = body
	query.shape = shape
	query.transform = Transform2D(0.0, global_position + Vector2(0, -body.y / 2.0))
	query.collision_mask = HITTABLE
	query.collide_with_areas = true
	query.collide_with_bodies = false
	for result in get_world_2d().direct_space_state.intersect_shape(query, 8):
		var target = result.collider
		if target == self or target == null or throw_struck.has(target):
			continue
		if not target.has_method("take_hit"):
			continue
		if target.take_hit(throw_damage, global_position):
			throw_struck.append(target)
			# It connected, so it is spent. A box that hits something and stays
			# whole reads as weightless.
			_shatter()
			return

func take_hit(damage: int, from: Vector2) -> bool:
	if broken or carried or not _hittable():
		return false
	var intact := health >= max_health
	health -= damage
	flash = 1.0
	shake_dir = 1.0 if from.x < global_position.x else -1.0
	if health <= 0 and intact and SURVIVES_FIRST_BLOW:
		health = 1
	if health <= 0:
		_shatter()
		return true
	# Survived, so it is knocked rather than dented. The blow's weight decides
	# how hard, which is what makes a jab and a shoulder charge feel different
	# against the same object.
	var power := clampf(float(damage) / KNOCK_REFERENCE, 0.35, 1.8)
	at_rest = false
	motion = Vector2(shake_dir * KNOCK_X * power, -KNOCK_Y * power)
	spin_rate = shake_dir * SPIN_MAX * power
	return true

# --- motion -----------------------------------------------------------------

func _floor_below(from_y: float) -> float:
	## Where the ground is underneath, or INF over a gap. Cast from just above
	## where it was to just past where it is now, so a fast fall cannot step
	## straight through a thin platform between two frames.
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		Vector2(position.x, from_y - 8.0), Vector2(position.x, position.y + 2.0), WORLD)
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	return INF if hit.is_empty() else float(hit.position.y)

func _integrate(delta: float) -> void:
	motion.y += GRAVITY * delta
	var prev_y := position.y
	position += motion * delta
	spin_phase += spin_rate * delta

	if position.y > fall_limit:
		_shatter()
		return
	if motion.y < 0.0:
		return
	var floor_y := _floor_below(prev_y)
	if floor_y == INF or position.y < floor_y:
		return

	position.y = floor_y
	if thrown:
		# A thrown prop does not bounce; it lands and comes apart.
		_shatter()
		return
	if motion.y > BOUNCE_MIN:
		motion.y = -motion.y * BOUNCE
		motion.x *= SKID
		spin_rate *= 0.55
		return
	# Down for good. It slides on the floor until the drag takes the rest.
	motion.y = 0.0
	motion.x = move_toward(motion.x, 0.0, FRICTION * delta)
	spin_rate = move_toward(spin_rate, 0.0, 26.0 * delta)
	if absf(motion.x) < REST_SPEED:
		at_rest = true
		motion = Vector2.ZERO
		spin_rate = 0.0
		spin_phase = 0.0

# --- breaking ---------------------------------------------------------------

func _noise(n: int) -> float:
	## Deterministic, so headless captures and test runs stay reproducible.
	return absf(fmod(sin(float(n) * 12.9898) * 43758.5453, 1.0))

func _shatter() -> void:
	broken = true
	break_t = 0.0
	at_rest = true
	motion = Vector2.ZERO
	# With a drawn shatter, the object comes apart where it stands first and the
	# pieces are not thrown until that has played. Without one — the crate, the
	# bottle — the pieces go immediately, which is what both have always done.
	breaking = not break_frames.is_empty()
	if breaking:
		if is_instance_valid(sprite):
			sprite.visible = true
			sprite.texture = break_frames[0]
			sprite.offset = Items.pivot(art_break)
			sprite.position = Vector2.ZERO
			sprite.rotation = 0.0
		return
	_scatter()

func _scatter() -> void:
	## Throws the pieces and takes the body off the screen. Called straight from
	## _shatter for anything with no drawn break, and at the end of the strip for
	## anything that has one.
	var floor_y := _floor_below(position.y - 4.0)
	debris_floor = 0.0 if floor_y == INF else maxf(0.0, floor_y - position.y)
	debris.clear()
	for i in debris_types.size():
		debris_seed += 1
		var sx := _noise(debris_seed * 3) - 0.5
		var sy := _noise(debris_seed * 5)
		# Thrown outward from inside the object, and carried by whatever it was
		# already doing, so something broken in flight scatters downrange.
		debris.append({
			"type": debris_types[i],
			"pos": Vector2(sx * body.x * 0.8, -sy * spin_lift * 1.8 - 4.0),
			"vel": Vector2((sx * 150.0 + shake_dir * 70.0) * ART_SCALE + motion.x * 0.4,
						   (-60.0 - sy * 270.0) * ART_SCALE + motion.y * 0.3),
			"spin": (0.4 + _noise(debris_seed * 7)) * 26.0 * (1.0 if sx > 0.0 else -1.0),
			"phase": _noise(debris_seed * 11) * float(debris_spins),
			"rest": false,
		})
	if is_instance_valid(sprite):
		sprite.visible = false

func _update_break(delta: float) -> void:
	break_t += delta
	if breaking:
		var span := break_step * float(break_frames.size())
		if break_t < span:
			var index := clampi(int(break_t / break_step), 0, break_frames.size() - 1)
			if is_instance_valid(sprite):
				sprite.texture = break_frames[index]
			return
		# The drawn break has finished coming apart. Now the pieces go, and the
		# debris clock starts from zero so BREAK_TIME still means what it says.
		breaking = false
		break_t = 0.0
		_scatter()
		return
	if break_t >= BREAK_TIME:
		debris.clear()
		queue_redraw()
		return
	for piece in debris:
		if piece.rest:
			continue
		piece.vel.y += 1150.0 * ART_SCALE * delta
		piece.vel.x *= 0.985
		piece.pos += piece.vel * delta
		piece.phase += piece.spin * delta
		if piece.pos.y >= debris_floor:
			piece.pos.y = debris_floor
			if absf(piece.vel.y) < 60.0 * ART_SCALE:
				piece.rest = true
				piece.vel = Vector2.ZERO
			else:
				# One damped bounce, then it skitters and settles.
				piece.vel.y = -piece.vel.y * 0.34
				piece.vel.x *= 0.55
				piece.spin *= 0.45
	queue_redraw()

# --- step and draw ----------------------------------------------------------

func _physics_process(delta: float) -> void:
	if flash > 0.0:
		flash = maxf(0.0, flash - delta * 6.0)
	rest_clock += delta
	if broken:
		_update_break(delta)
		return
	if carried:
		# In his hands. The carrier places it; gravity and the floor do not.
		_update_sprite()
		return
	if not at_rest:
		_integrate(delta)
		if thrown and not broken:
			_strike_in_flight()
	_update_sprite()
	_prop_process(delta)

func _update_sprite() -> void:
	if not is_instance_valid(sprite):
		return
	if broken:
		# Visible through a drawn shatter; gone once the pieces are doing the work.
		sprite.visible = breaking
		return
	sprite.visible = true
	if at_rest or (spin_frames.is_empty() and not spins_sprite):
		sprite.texture = _resting_frame()
		sprite.offset = Items.pivot(art_rest)
		sprite.position = _rest_offset()
		sprite.rotation = 0.0
	elif spin_frames.is_empty():
		# No drawn angles, so the one sprite turns. Its resting frame stands on
		# its own base, so the texture is pushed down half a cell to sit centred
		# on the node and the node is lifted to the object's middle — otherwise
		# it would swing around its own feet like a hinge.
		sprite.texture = _resting_frame()
		sprite.offset = Items.pivot(art_rest) + Vector2(0, float(Items.cell(art_rest).y) * 0.5)
		sprite.position = Vector2(0, -spin_lift)
		sprite.rotation = spin_phase * TAU / SPRITE_TURN_STEPS
	else:
		sprite.texture = spin_frames[posmod(int(spin_phase), spin_frames.size())]
		# The spin frames are originned to their middle, so the sprite is lifted
		# half a body: a thing in the air turns about its centre, not its base.
		sprite.offset = Items.pivot(art_spin)
		sprite.position = Vector2(0, -spin_lift)
		sprite.rotation = 0.0
	var glare := 1.0 + flash * 1.2
	sprite.modulate = Color(glare, glare, glare, 1.0)

func _draw() -> void:
	if debris.is_empty() or debris_frames.is_empty():
		return
	# Drawn here rather than by a node, so the texture-to-world scale that every
	# prop sprite gets from its own node has to be applied by hand.
	var size := Vector2(Items.cell(art_debris)) * art_render
	var half := size * 0.5
	# Pieces hold full opacity while they are still moving and only fade over the
	# last third, so the break does not dissolve before it has finished landing.
	var fade: float = clampf((BREAK_TIME - break_t) / (BREAK_TIME * 0.35), 0.0, 1.0)
	for piece in debris:
		var spin: int = posmod(int(piece.phase), debris_spins)
		var index: int = int(piece.type) * debris_spins + spin
		if index < 0 or index >= debris_frames.size():
			continue
		draw_texture_rect(debris_frames[index], Rect2(piece.pos - half, size),
						  false, Color(1, 1, 1, fade))
