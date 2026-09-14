extends "res://features/combat/prop.gd"
## A bottle of milk: LF2's own health item.
##
## Two things at once. It is a pickup — stand near it, get prompted, drink, and
## the character plays LF2's weapon_drink frames with the bottle on his hand's
## weapon point. It is also a prop, so it can be knocked about and smashed like
## the crate, on exactly the same physics, with LF2's own glass debris.
##
## Smashing it destroys the health it was worth. That is a real choice rather
## than an oversight: swinging at everything in the level has a cost.
##
## Drinking takes time, so a bottle has a third state between "on the floor" and
## "gone": lifted. It is off the ground and in his hand, but not yet spent.
##
## It also has contents, which is what makes stopping worth doing. Drinking
## drains it and a punch spills it, and both the wait and the health are
## proportional to what is left, so a half-drunk bottle is a half-length top-up
## rather than a wasted one. An interrupted drink sets it back down; a drink
## broken by a hit knocks it out of his hand, and it falls and bounces on the
## same physics a punched bottle uses.
##
## Two areas, because the two jobs need different sizes. This node is the hit
## box; a child area is the much larger "am I near enough to drink" reach.

const PICKUP_LAYER := 128  # physics layer 8
## Generous on purpose: this is "am I near the bottle", not "am I touching it".
## The drawn bottle is tiny, far smaller than anything a player expects to have
## to stand on. Deliberately NOT scaled with the art: this is a distance in the
## level, and the level did not shrink when the cast did.
const REACH := Vector2(72, 88)

const GLOW := Color("f2e6c8")

## How much one bottle is worth, counted in health-bar segments rather than
## points, so "two bars" stays two bars whatever MAX_HEALTH is. The session
## reads it rather than hard-coding a number, so a weaker bottle is a spawn
## argument.
var heal_segments: int = 2
## How full it is, 0 to 1, in units of a whole bottle.
var contents: float = 1.0
## What a blow spills. Glass survives one hit and smashes on the second, so a
## cracked bottle is worth three quarters of a whole one.
const SPILL_PER_HIT := 0.25
var consumed: bool = false
## Raised to his mouth, mid-drink. Not spent: only a drink that runs its whole
## six seconds consumes the bottle.
var lifted: bool = false
var clock: float = 0.0
var reach: Area2D

func _configure() -> void:
	max_health = 20  # glass: anything breaks it in two hits
	# Taller than the 23 px it is drawn, deliberately. Every punch in the game
	# lands between y -55 and -25, measured from the feet; a hit box matching
	# the art would sit entirely underneath all of them and only the flying kick
	# and the blast could ever touch it. This lifts the box into reach without
	# changing where the bottle is drawn — see spin_lift below.
	body = Vector2(16, 27)
	spin_lift = 9.0
	art_rest = "bottle"
	art_spin = "bottle_spin"
	art_debris = "bottle_debris"
	# Six pieces: two of the capped body, four of the small shards.
	debris_types = [0, 0, 1, 1, 1, 1]

func _on_ready() -> void:
	reach = Area2D.new()
	reach.collision_layer = PICKUP_LAYER
	# Detects the player (layer 2) so the session can ask what is in reach.
	reach.collision_mask = 2
	var shape := RectangleShape2D.new()
	shape.size = REACH
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = Vector2(0, -REACH.y / 2.0)
	reach.add_child(collider)
	add_child(reach)

## True when the given body is close enough to be offered a drink. False once
## the bottle is gone, whether it was drunk or smashed.
func in_reach(target: Node2D) -> bool:
	if consumed or broken or not is_instance_valid(reach):
		return false
	return reach.overlaps_body(target)

func available() -> bool:
	return not consumed and not broken and not lifted and contents > 0.001

## Seconds it would take to finish from here, for the prompt.
func drink_seconds(player: Node) -> float:
	return contents * float(player.FULL_DRINK_TIME)

func set_contents(value: float) -> void:
	## Set from the player while he drinks, so the level is always holding the
	## truth about how much is left rather than a figure settled up afterwards.
	## An empty bottle is a spent one.
	contents = clampf(value, 0.0, 1.0)
	if contents <= 0.001:
		consume()

## A struck bottle leaks, which is the other half of why a drink can be short.
func take_hit(damage: int, from: Vector2) -> bool:
	var landed: bool = super.take_hit(damage, from)
	if landed and not broken:
		contents = maxf(0.0, contents - SPILL_PER_HIT)
	return landed

func drop_from(at: Vector2, push: Vector2) -> void:
	## Knocked out of his hand. It re-enters the world where he was standing and
	## falls under the same physics a punched bottle uses, so a dropped bottle
	## and a struck one behave identically rather than being two special cases.
	lifted = false
	position = at
	at_rest = false
	motion = push
	var dir := signf(push.x)
	if is_zero_approx(dir):
		dir = 1.0
	spin_rate = dir * SPIN_MAX * 0.8
	_update_sprite()
	queue_redraw()

func lift() -> void:
	## Off the floor and into his hand for the duration of the drink. The world
	## copy has to disappear — the drink animation holds the same bottle — but
	## nothing is spent yet.
	lifted = true
	_update_sprite()
	queue_redraw()

func lower() -> void:
	## The drink was interrupted. Back it goes, exactly where it was.
	lifted = false
	_update_sprite()
	queue_redraw()

## The base shows the sprite whenever the prop is intact, which would undo both
## lift() and consume() on the next step.
func _update_sprite() -> void:
	super._update_sprite()
	if (consumed or lifted) and is_instance_valid(sprite):
		sprite.visible = false

## A bottle already drunk, or currently in his hand, is not there to be hit.
func _hittable() -> bool:
	return not consumed and not lifted

func _rest_offset() -> Vector2:
	# A slow bob. Rounded to whole pixels: a pixel-art sprite sliding on
	# fractional coordinates shimmers against the background grid.
	return Vector2(0, roundf(sin(clock * 2.4) * 2.0) - 2.0)

func reset() -> void:
	super.reset()
	consumed = false
	lifted = false
	contents = 1.0
	clock = 0.0
	if is_instance_valid(reach):
		reach.monitoring = true

func consume() -> void:
	## Vanishes on the spot rather than fading away. The drink animation puts the
	## same bottle in his hand on the same frame, and a copy left fading on the
	## floor reads as a second bottle.
	if consumed:
		return
	consumed = true
	lifted = false
	if is_instance_valid(reach):
		reach.monitoring = false
	if is_instance_valid(sprite):
		sprite.visible = false
	queue_redraw()

func _shatter() -> void:
	super._shatter()
	# Smashed glass is no longer a drink, and the prompt must clear at once.
	if is_instance_valid(reach):
		reach.monitoring = false

func _prop_process(_delta: float) -> void:
	if consumed or lifted:
		if is_instance_valid(sprite):
			sprite.visible = false
		return
	clock += _delta
	queue_redraw()

func _draw() -> void:
	super._draw()
	if consumed or broken or lifted or not at_rest:
		return
	## Halo behind the bottle. Drawn here rather than as a sprite so it stays
	## under the art: a parent CanvasItem draws before its children. Only while
	## it is sitting still — a bottle skidding across the floor with a glow
	## following it reads as a bug.
	var pulse := 0.55 + 0.45 * sin(clock * 2.4)
	var centre := Vector2(0, -13)
	for i in 3:
		var tint := GLOW
		tint.a = 0.10 * pulse * float(3 - i)
		draw_circle(centre, 10.0 + float(i) * 5.0, tint)
