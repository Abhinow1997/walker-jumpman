extends Area2D
## A rock shed by the isles overhead: it falls down one lane, hurts whatever it
## catches on the way, and breaks on the first thing solid under it.
##
## Deliberately NOT a prop. features/combat/prop.gd is the throwable rock, and
## everything it does — resting, being lifted, carried, launched, skidding,
## settling — is weight this does not carry. More to the point, a prop resolves
## its hits against the Hittable layer, which the player is deliberately not on,
## so it can never be the thing that hurts him. This can. It is the only object
## in the game that damages the player without an attacker behind it.
##
## It wears the prop's own art, so the rock falling past is visibly the same
## rock sitting on the ledge: the same six-frame boulder, the same drawn shatter.
##
## Hits are resolved with a synchronous shape query rather than an Area2D
## callback, exactly as the blast and the arrow do, so a stone falling at 900 px
## a second cannot step over the player between two frames and so the timing is
## something a test can pin down.

const Items := preload("res://features/combat/items.gd")

const PLAYER := 2    # physics layer 2: his body, and the only one on it
const WORLD := 1     # physics layer 1: the ledge it breaks on
const HITTABLE := 64 # physics layer 7: so his strike and his blast can meet it

## Reported to the session, which owns his health, on the same terms a punch or
## an arrow is. The session then lets the player decide whether his invulnerable
## window eats it.
signal struck_player(damage: int, from: Vector2)

## Slower than the 1200 a knocked prop falls at. A stone is a thing you are
## meant to read and step around, and at prop gravity it crosses the screen in
## under a second, which is not long enough to do anything about.
const GRAVITY := 900.0
## Terminal, so a stone that has fallen the height of the tower is still
## something you can see coming rather than a line.
const FALL_MAX := 620.0
const SPIN := 5.2

## Out of a hundred. Three of them is not fatal on its own, and that is the
## point: the rock is dangerous because of WHERE it hits you, not how hard. A
## hit zeroes his movement input for a quarter of a second — see is_hurt() in
## player.gd — so one caught mid-jump drops him straight out of the air, and
## over this level there is nothing under him.
const DAMAGE := 18

## How far into its own art the collision sits, and what the strike has to
## overlap to break it. The drawn rock is 36 x 48 at three-quarter scale.
const BODY := Vector2(26.0, 34.0)

var speed: float = 0.0
var fall_limit: float = INF
var broken: bool = false
var spin: float = 0.0
var frames: Array[Texture2D] = []
var break_frames: Array[Texture2D] = []
var break_t: float = 0.0
var sprite: Sprite2D

func _init() -> void:
	collision_layer = HITTABLE
	# Like every other target: it is queried, it does not query. Its own hits
	# are the shape casts below.
	collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = BODY
	var collider := CollisionShape2D.new()
	collider.shape = shape
	add_child(collider)

func _ready() -> void:
	z_index = 3
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	for i in Items.frames("rock"):
		frames.append(Items.frame("rock", i))
	for i in Items.frames("rock_break"):
		break_frames.append(Items.frame("rock_break", i))
	sprite = Sprite2D.new()
	sprite.centered = true
	sprite.scale = Vector2.ONE * Items.render_scale()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if not frames.is_empty():
		sprite.texture = frames[0]
	add_child(sprite)

func _physics_process(delta: float) -> void:
	if broken:
		_run_break(delta)
		return
	speed = minf(speed + GRAVITY * delta, FALL_MAX)
	var step := speed * delta
	position.y += step
	spin += SPIN * delta
	if is_instance_valid(sprite):
		sprite.rotation = spin
	if position.y > fall_limit:
		queue_free()          # into the sea, with nothing to break against
		return
	_resolve(step)

func _resolve(step: float) -> void:
	## One query for both answers. The box is stretched upward by the distance
	## covered this tick, so a fast stone sweeps the space it crossed instead of
	## sampling the point it happens to have landed on.
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(BODY.x, BODY.y + step)
	query.shape = shape
	query.transform = Transform2D(0.0, global_position - Vector2(0.0, step / 2.0))
	query.collision_mask = PLAYER | WORLD
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var ground := false
	for result in space.intersect_shape(query, 4):
		var col = result.collider
		if col == null:
			continue
		if col is StaticBody2D:
			ground = true
			continue
		# The only body on the PLAYER layer is the player. He is answered first
		# and the stone is spent on him: a stone that hits him AND the ledge he
		# is standing on should not read as two separate rocks.
		struck_player.emit(DAMAGE, global_position)
		shatter()
		return
	if ground:
		shatter()

func take_hit(damage: int, _from: Vector2) -> bool:
	## Punched or blasted out of the sky. Any connecting blow does it — there is
	## no health to spend, because a rock you have to hit twice in the air is a
	## rock you will never hit twice.
	if broken or damage <= 0:
		return false
	shatter()
	return true

func shatter() -> void:
	if broken:
		return
	broken = true
	# Nothing left to hit and nothing left to hit it: the wreckage is a picture.
	collision_layer = 0
	speed = 0.0
	break_t = 0.0
	if is_instance_valid(sprite):
		sprite.rotation = 0.0
		if not break_frames.is_empty():
			sprite.texture = break_frames[0]

## Seconds a frame of the drawn shatter, matching the crate's own break_step, so
## the rock coming apart in the air reads at the same speed as one coming apart
## on the ground.
const BREAK_STEP := 0.07

func _run_break(delta: float) -> void:
	break_t += delta
	var index := int(break_t / BREAK_STEP)
	if break_frames.is_empty() or index >= break_frames.size():
		queue_free()
		return
	if is_instance_valid(sprite):
		sprite.texture = break_frames[index]
