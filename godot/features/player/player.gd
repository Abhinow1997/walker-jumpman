extends CharacterBody2D

const Tuning = preload("res://features/player/tuning.gd")
# Swap this one line to change the protagonist's appearance.
# player_sprite.gd is the Anti-Davis sprite; player_visual.gd is the original
# procedural Wind-Up Knight rig, kept as a fallback that needs no art files.
const Visual = preload("res://features/player/player_sprite.gd")
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
var test_control: bool = false
var test_axis: float = 0.0
var test_jump_pressed: bool = false
var test_jump_held: bool = false

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
	if is_instance_valid(visual):
		visual.reset()

func on_death() -> void:
	## Appearance only; the session still owns the death state and retry timing.
	if is_instance_valid(visual):
		visual.on_death()

func _physics_process(delta: float) -> void:
	if not enabled:
		return
	tick += 1
	var axis := test_axis if test_control else Input.get_axis("move_left", "move_right")
	var held := test_jump_held if test_control else Input.is_action_pressed("jump")
	var pressed := test_jump_pressed if test_control else Input.is_action_just_pressed("jump")
	test_jump_pressed = false
	if not held:
		require_jump_release = false
	if is_on_floor() and velocity.y >= 0.0:
		last_floor_tick = tick
		opportunity_consumed = false
	if pressed and not require_jump_release:
		jump_request_tick = tick
	var rate: float = tuning.acceleration if not is_zero_approx(axis) else tuning.deceleration
	velocity.x = move_toward(velocity.x, axis * tuning.speed, rate * delta)
	if not is_zero_approx(axis):
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
