extends Node2D
## Hunter's arrow: a straight-flying projectile, independent of the archer once
## loosed — it keeps its own heading and clock, so killing him mid-flight does
## not cancel it, exactly like the player's blast keeps flying past its thrower.
##
## The LF2 rip carries Hunter's bow-draw frames but no arrow object (LF2 keeps the
## arrow in a separate file), so the shaft is drawn here rather than cut from a
## sheet. It resolves its hit with a synchronous shape query, like the blast, so
## the timing is exact and testable rather than an Area2D callback a frame late.

const SPEED := 470.0
## Dies before the level edge; a projectile that flies forever is one you cannot
## reason about in a test.
const RANGE := 660.0
const PLAYER := 2   # physics layer 2: the player's body, what it is looking for
const WORLD := 1    # physics layer 1: a wall stops it

## The session owns the player's health, so the arrow reports its hit the same way
## a melee blow does and lets the player decide whether its invulnerable window
## eats the damage.
signal struck_player(damage: int, from: Vector2)

var direction: float = 1.0
var damage: int = 12
var travelled: float = 0.0
var finished: bool = false

func _ready() -> void:
	# Mirror the shaft by heading; carry the cast's three-quarter scale.
	scale = Vector2(direction, 1.0) * 0.75
	z_index = 4
	queue_redraw()

func _physics_process(delta: float) -> void:
	if finished:
		return
	var step := SPEED * delta
	position.x += step * direction
	travelled += step
	if travelled >= RANGE:
		_done()
		return
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(20.0, 8.0)
	query.shape = shape
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = PLAYER | WORLD
	query.collide_with_areas = false
	query.collide_with_bodies = true
	for result in space.intersect_shape(query, 4):
		var col = result.collider
		if col == null:
			continue
		if col is StaticBody2D:
			_done()   # thuds into a wall and stops
			return
		# The only body on the PLAYER layer is the player himself.
		struck_player.emit(damage, global_position)
		_done()
		return

func _done() -> void:
	finished = true
	queue_free()

func _draw() -> void:
	# A short arrow pointing +x; the node mirrors it by heading through scale.x.
	var wood := Color(0.42, 0.29, 0.16)
	var metal := Color(0.78, 0.80, 0.84)
	var fletch := Color(0.78, 0.27, 0.24)
	draw_line(Vector2(-14.0, 0.0), Vector2(10.0, 0.0), wood, 2.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(9.0, -4.0), Vector2(17.0, 0.0), Vector2(9.0, 4.0)]), metal)
	draw_line(Vector2(-14.0, 0.0), Vector2(-18.0, -4.0), fletch, 1.5)
	draw_line(Vector2(-14.0, 0.0), Vector2(-18.0, 4.0), fletch, 1.5)
