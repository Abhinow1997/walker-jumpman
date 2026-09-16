extends Node2D
## The energy blast the character throws, as its own travelling object.
##
## Independent of the player once fired: it keeps its own direction and clock, so
## turning around or dying mid-flight does not move or cancel it. Like the
## player's strike it resolves hits with a synchronous shape query rather than
## Area2D overlap callbacks, which keeps hit timing exact and testable instead of
## arriving a physics frame late.

const Moveset = preload("res://features/player/moveset.gd")
const ART := "res://features/player/art/anti_davis/"

const SPEED := 560.0
## Dies well before the level edge. A projectile that flies forever is a
## projectile you cannot reason about in a test.
const RANGE := 620.0
const HITTABLE := 64  # physics layer 7
const WORLD := 1      # physics layer 1: it should not pass through a wall

var direction: float = 1.0
var travelled: float = 0.0
var struck: bool = false
var clock: float = 0.0
var sprite: AnimatedSprite2D
var hit_rect: Rect2 = Rect2()
var damage: int = 0
var already_hit: Array = []
var finished: bool = false

func _ready() -> void:
	var ball: Dictionary = Moveset.ball()
	var r: Array = ball.get("hit_rect", [0, 0, 1, 1])
	hit_rect = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	damage = int(ball.get("damage", 0))
	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = _build_frames(ball)
	sprite.centered = true
	var c: Array = Moveset.data().get("ball_cell", [1, 1])
	var o: Array = Moveset.data().get("ball_origin", [0, 0])
	sprite.offset = Vector2(float(c[0]) / 2.0 - float(o[0]), float(c[1]) / 2.0 - float(o[1]))
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(direction, 1.0) * Moveset.render_scale()
	add_child(sprite)
	if sprite.sprite_frames.has_animation("fly"):
		sprite.play("fly")

func _build_frames(ball: Dictionary) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var c: Array = Moveset.data().get("ball_cell", [1, 1])
	var size := Vector2i(int(c[0]), int(c[1]))
	for key in ["fly", "hit"]:
		var spec: Dictionary = ball.get(key, {})
		if spec.is_empty():
			continue
		var path: String = ART + str(spec.file)
		if not ResourceLoader.exists(path):
			push_warning("blast: no sheet at %s" % path)
			continue
		var sheet: Texture2D = load(path)
		frames.add_animation(key)
		frames.set_animation_loop(key, bool(spec.loop))
		var durations: Array = spec.durations
		for i in durations.size():
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(i * size.x, 0, size.x, size.y)
			# SpriteFrames durations are relative to the animation speed, so the
			# speed is pinned at 1 fps and each frame carries its own length.
			frames.add_frame(key, atlas, float(durations[i]))
		frames.set_animation_speed(key, 1.0)
	return frames

func _world_rect() -> Rect2:
	## Mirror the box when travelling left, the same way the sprite is mirrored.
	var r := hit_rect
	if direction < 0.0:
		r.position.x = -(r.position.x + r.size.x)
	return Rect2(global_position + r.position, r.size)

func _physics_process(delta: float) -> void:
	if finished:
		return
	if struck:
		clock += delta
		if clock >= Moveset.ball().get("hit", {}).get("durations", [0.3]).reduce(
				func(a, b): return a + float(b), 0.0):
			finished = true
			queue_free()
		return

	var step := SPEED * delta
	position.x += step * direction
	travelled += step
	if travelled >= RANGE:
		_impact(false)
		return

	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := RectangleShape2D.new()
	var box := _world_rect()
	shape.size = box.size
	query.shape = shape
	query.transform = Transform2D(0.0, box.position + box.size / 2.0)
	query.collision_mask = HITTABLE | WORLD
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var landed := false
	for result in space.intersect_shape(query, 8):
		var target = result.collider
		if target == null or already_hit.has(target):
			continue
		if target.has_method("take_hit"):
			if target.take_hit(damage, global_position):
				already_hit.append(target)
				landed = true
		elif target is StaticBody2D:
			landed = true
	if landed:
		_impact(true)

func _impact(show_burst: bool) -> void:
	## Out of range fizzles silently; a real contact gets the burst.
	if not show_burst or not sprite.sprite_frames.has_animation("hit"):
		finished = true
		queue_free()
		return
	struck = true
	clock = 0.0
	sprite.play("hit")
