extends Node2D
## The Wind-Up Knight: a copper clockwork toy, long forgotten in an attic and
## going green at the seams.
##
## A part-based rig plus a juice layer. Reads state from `body`; owns no gameplay
## logic and never touches position, velocity, or collision, so the whole
## protagonist can be swapped by replacing this one node.
##
## Styled from the reference animation sheet: oxidised copper over dark iron,
## near-black outlines, a toothed movement in the chest, a glass lens in a
## brimmed helm, and two-segment limbs so knees and elbows actually bend.
##
## The motion is deliberately stepped rather than smooth. A wind-up toy runs off
## an escapement, so the run cycle snaps between eight positions and the helm
## ratchets in fixed increments. Smoothness here would read as the wrong character.

const OUTLINE := Color("1f1712")
const IRON := Color("3b332c")
const IRON_LIT := Color("5c5148")
const COPPER_D := Color("6b3f28")
const COPPER := Color("9a5f38")
const COPPER_L := Color("c07a46")
const BRASS := Color("d99a57")
const BRASS_LIT := Color("f0c078")
const PATINA := Color("3d6b5c")
const PATINA_L := Color("5a9180")
const LENS := Color("a8e0e8")
const LENS_CORE := Color("f2fbfc")
const STEAM := Color("c9c2b4")

const SPEED_CAP := 160.0
const RATCHET := TAU / 8.0
# Drawn to y=-30 over an 18x28 collider. A small overhang is normal for a
# platformer, but keep it small: a body much larger than its hitbox makes the
# landing hard to read, and reading the landing is the whole design.
const NECK_Y := -22.0
const HIP_Y := -10.0
const THIGH := 5.0
const SHIN := 4.0
const UPPER_ARM := 4.5
const FOREARM := 4.5
const SHOULDER_F := Vector2(4, -20)
const SHOULDER_B := Vector2(-4, -20)
const KEY_PIVOT := Vector2(-11, -16)
const GEAR_AT := Vector2(0, -16)
# Squash stays shallow on purpose. A full 1/s volume inverse reads as melting at
# this size, and non-uniform scale shears every part rotation along with it.
const SQUASH_MIN := 0.80
const SQUASH_MAX := 1.16
const WIDEN := 0.55
# The rig's geometry is authored for the old 18x28 body. It is vector drawing, not
# pixel art, so scaling it is lossless and this stays a placeholder until the
# sprite replaces it wholesale. Dust is in world space and must not be scaled.
const RIG_SCALE := 2.0

var body: CharacterBody2D

# Animation clocks
var phase: float = 0.0          # run cycle, advanced by distance travelled
var key_turn: float = 0.0
var idle_t: float = 0.0
var tension: float = 1.0        # the spring: drains standing still, rewinds on the move

# Juice
var squash: float = 1.0
var squash_vel: float = 0.0
var lean: float = 0.0
var face_scale: float = 1.0

# Event tracking
var was_grounded: bool = true
var prev_vy: float = 0.0
var last_jumps: int = 0

# Death
var dying: bool = false
var death_t: float = 0.0

# Dust and debris, stored in world space so they stay put as the knight runs.
var motes: Array = []
var mote_seed: int = 0

var _gear_teeth: PackedVector2Array = PackedVector2Array()

func _ready() -> void:
	for i in 16:
		var a := float(i) * TAU / 16.0
		_gear_teeth.append(Vector2(cos(a), sin(a)) * (3.7 if i % 2 == 0 else 2.7))

func reset() -> void:
	phase = 0.0
	key_turn = 0.0
	idle_t = 0.0
	tension = 1.0
	squash = 1.0
	squash_vel = 0.0
	lean = 0.0
	face_scale = body.facing if is_instance_valid(body) else 1.0
	was_grounded = true
	prev_vy = 0.0
	last_jumps = body.jumps if is_instance_valid(body) else 0
	dying = false
	death_t = 0.0
	motes.clear()
	queue_redraw()

func on_death() -> void:
	if dying:
		return
	dying = true
	death_t = 0.0
	squash = 0.78
	squash_vel = 0.0
	_burst(Vector2(0, -12), 12, 1.7, COPPER)
	_burst(Vector2(0, -17), 7, 2.3, BRASS_LIT)
	_burst(Vector2(0, -14), 5, 1.4, PATINA_L)

func _physics_process(delta: float) -> void:
	# The live animation is driven from the player's physics step so pausing stops
	# it too. Death is the one state that must keep playing while control is off.
	if dying:
		death_t += delta
		squash = move_toward(squash, 0.74, delta * 1.1)
		_update_motes(delta)
		queue_redraw()

func advance(delta: float) -> void:
	var vx := body.velocity.x
	var speed := absf(vx)
	var grounded := body.is_on_floor()

	if grounded and not was_grounded:
		var impact := clampf(prev_vy / 300.0, 0.0, 1.4)
		squash = 1.0 - impact * 0.15
		squash_vel = 0.0
		_burst(Vector2(0, 0), int(2 + impact * 7.0), 0.5 + impact, COPPER_D)
	if body.jumps != last_jumps:
		last_jumps = body.jumps
		squash = 1.13
		squash_vel = 0.0
		_burst(Vector2(0, 0), 3, 0.7, COPPER_D)
		_burst(Vector2(-3, -12), 3, 0.5, STEAM)
	was_grounded = grounded
	prev_vy = body.velocity.y

	# The spring winds as he travels and slowly unwinds when he stands still.
	if speed > 8.0:
		tension = minf(1.0, tension + delta * 2.4)
		phase += speed * delta * 0.26
	else:
		tension = maxf(0.22, tension - delta * 0.4)
		idle_t += delta
	key_turn += (speed * 0.035 + 0.35 + tension * 1.1) * delta

	# Squash and stretch: a damped spring back to rest, volume preserved on draw.
	squash_vel += (1.0 - squash) * 620.0 * delta
	squash_vel *= 0.86
	squash += squash_vel * delta
	squash = clampf(squash, SQUASH_MIN, SQUASH_MAX)

	lean = move_toward(lean, clampf(vx / SPEED_CAP, -1.0, 1.0) * 0.07, delta * 1.6)
	face_scale = move_toward(face_scale, body.facing, delta * 18.0)

	_update_motes(delta)
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(body):
		return
	var grounded := body.is_on_floor() and not dying
	var vx := body.velocity.x
	var speed := absf(vx)
	var skidding := grounded and speed > 40.0 and signf(vx) != signf(body.facing)
	# Blend the airborne pose by vertical speed instead of snapping at the apex.
	var air := clampf(body.velocity.y / 200.0, -1.0, 1.0)
	var fall_mix := (air + 1.0) * 0.5

	var bob := 0.0
	var swing := 0.0          # front thigh; the back thigh mirrors it
	var knee_f := 0.15
	var knee_b := 0.15
	var arm := 0.0
	var elbow := 0.35
	var helm_tilt := 0.0
	var slack := 1.0 - tension

	if dying:
		swing = 0.55
		knee_f = 1.3
		knee_b = 0.5
		arm = 1.1
		elbow = 1.0
		helm_tilt = 0.4
	elif not grounded:
		# Rising tucks the legs and throws the arms up; falling reaches for ground.
		swing = lerpf(0.30, 0.34, fall_mix)
		knee_f = lerpf(1.45, 0.22, fall_mix)
		knee_b = lerpf(0.95, 0.55, fall_mix)
		arm = lerpf(-1.0, 0.55, fall_mix)
		elbow = lerpf(0.9, 0.25, fall_mix)
		helm_tilt = lerpf(-0.12, 0.16, fall_mix)
	elif skidding:
		swing = 0.42
		knee_f = 0.5
		knee_b = 0.8
		arm = -0.35
		elbow = 0.8
		helm_tilt = -0.14
		if int(phase * 6.0) % 3 == 0:
			_burst(Vector2(-signf(vx) * 5.0, 0), 1, 0.55, COPPER_D)
	elif speed > 8.0:
		# Eight-position run cycle. The escapement, not a smooth sine.
		var step := roundf(phase / RATCHET) * RATCHET
		swing = sin(step) * 0.42
		# A knee bends as its leg trails and swings through; that is the walk.
		knee_f = 0.12 + maxf(0.0, -sin(step)) * 1.05
		knee_b = 0.12 + maxf(0.0, sin(step)) * 1.05
		arm = -sin(step) * 0.44
		elbow = 0.3 + absf(sin(step)) * 0.35
		bob = -absf(sin(step)) * 1.2
		helm_tilt = roundf(sin(step * 2.0) * 2.0) * 0.02
	else:
		# Idle: he breathes while wound, and visibly sinks as the spring runs down.
		bob = sin(idle_t * 2.2) * 0.5 * tension + slack * 1.2
		swing = 0.04
		knee_f = 0.1 + slack * 0.35
		knee_b = 0.1 + slack * 0.35
		arm = 0.06 + slack * 0.26
		elbow = 0.25 + slack * 0.4
		helm_tilt = slack * 0.16

	var base := Transform2D(lean,
		Vector2((1.0 + (1.0 - squash) * WIDEN) * face_scale * RIG_SCALE, squash * RIG_SCALE),
		0.0, Vector2(0, bob * RIG_SCALE))

	_draw_arm(base, SHOULDER_B, -arm, elbow, COPPER_D, IRON)
	_draw_key(base)
	_draw_leg(base, Vector2(-3, HIP_Y), -swing, knee_b, COPPER_D, IRON)
	_draw_leg(base, Vector2(3, HIP_Y), swing, knee_f, COPPER, IRON_LIT)
	_draw_torso(base)
	_draw_gear(base)
	_draw_pauldron(base, arm)
	_draw_arm(base, SHOULDER_F, arm, elbow, COPPER_L, IRON_LIT)
	_draw_helm(base, helm_tilt, slack)

	draw_set_transform_matrix(Transform2D.IDENTITY)
	_draw_motes()

func _part(base: Transform2D, at: Vector2, rot: float) -> void:
	draw_set_transform_matrix(base * Transform2D(rot, Vector2.ONE, 0.0, at))

func _draw_leg(base: Transform2D, hip: Vector2, thigh_rot: float, knee_rot: float,
		tone: Color, boot: Color) -> void:
	## Two segments hinged at the knee. One straight rect per leg cannot carry a
	## walk cycle; the bend is what makes the stride read at this size.
	_part(base, hip, thigh_rot)
	draw_rect(Rect2(-2.3, -1.4, 4.6, THIGH + 2.0), OUTLINE)
	draw_rect(Rect2(-1.7, -0.9, 3.4, THIGH + 1.0), tone)
	draw_rect(Rect2(-1.7, -0.9, 1.1, THIGH + 1.0), COPPER_L)

	var knee := hip + Vector2(0, THIGH).rotated(thigh_rot)
	_part(base, knee, thigh_rot + knee_rot)
	draw_rect(Rect2(-2.1, -1.6, 4.2, SHIN + 2.4), OUTLINE)
	draw_rect(Rect2(-1.5, -1.1, 3.0, SHIN + 1.4), IRON)
	draw_rect(Rect2(-1.5, -1.1, 1.0, SHIN + 1.4), IRON_LIT)
	draw_rect(Rect2(-1.2, 0.6, 2.4, 1.0), COPPER_D)
	draw_rect(Rect2(-3.2, SHIN - 0.9, 6.4, 2.6), OUTLINE)
	draw_rect(Rect2(-2.7, SHIN - 0.5, 5.4, 1.7), boot)

func _draw_arm(base: Transform2D, shoulder: Vector2, arm_rot: float, elbow_rot: float,
		tone: Color, cuff: Color) -> void:
	_part(base, shoulder, arm_rot)
	draw_rect(Rect2(-1.9, -1.2, 3.8, UPPER_ARM + 1.8), OUTLINE)
	draw_rect(Rect2(-1.3, -0.7, 2.6, UPPER_ARM + 0.8), tone)

	var elbow := shoulder + Vector2(0, UPPER_ARM).rotated(arm_rot)
	_part(base, elbow, arm_rot + elbow_rot)
	draw_rect(Rect2(-1.7, -1.3, 3.4, FOREARM + 2.2), OUTLINE)
	draw_rect(Rect2(-1.2, -0.8, 2.4, FOREARM + 1.2), tone)
	draw_rect(Rect2(-1.9, FOREARM - 0.4, 3.8, 2.2), OUTLINE)
	draw_rect(Rect2(-1.4, FOREARM, 2.8, 1.4), cuff)

func _draw_torso(base: Transform2D) -> void:
	_part(base, Vector2(0, -16), 0.0)
	# Chamfered chest edge: the diagonal is what keeps him from reading as a box.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-8, -6.5), Vector2(3, -6.5), Vector2(8, -2.5), Vector2(8, 6.5),
		Vector2(-8, 6.5)]), OUTLINE)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-7, -5.5), Vector2(3, -5.5), Vector2(7, -2), Vector2(7, 5.5),
		Vector2(-7, 5.5)]), COPPER)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-7, -5.5), Vector2(3, -5.5), Vector2(7, -2), Vector2(7, -0.8),
		Vector2(-7, -0.8)]), COPPER_L)
	# Oxidation. The green is what makes the copper read as old rather than new.
	draw_rect(Rect2(-6.5, 1.0, 3.0, 2.2), PATINA)
	draw_rect(Rect2(-6.5, 1.0, 3.0, 0.8), PATINA_L)
	draw_rect(Rect2(4.2, 1.6, 2.4, 1.6), PATINA)
	draw_rect(Rect2(-3.0, -5.2, 2.0, 1.4), PATINA)
	# Panel seams and bolts.
	draw_rect(Rect2(-7, 3.6, 14, 0.8), COPPER_D)
	draw_rect(Rect2(-7, 4.4, 14, 2.1), IRON)
	draw_rect(Rect2(-7, 4.4, 14, 0.7), IRON_LIT)
	for bolt in [Vector2(-6, -3.4), Vector2(5, -0.2), Vector2(-6, 4.9), Vector2(5, 4.9)]:
		draw_rect(Rect2(bolt, Vector2(1.4, 1.4)), OUTLINE)
		draw_rect(Rect2(bolt, Vector2(0.8, 0.8)), BRASS)

func _draw_gear(base: Transform2D) -> void:
	## The movement, visible through the breastplate and turning off the same
	## spring as the key. Centred and toothed, as in the reference sheet.
	_part(base, GEAR_AT, 0.0)
	draw_circle(Vector2.ZERO, 4.6, OUTLINE)
	draw_circle(Vector2.ZERO, 4.0, COPPER_D)
	_part(base, GEAR_AT, -key_turn * 1.7)
	draw_colored_polygon(_gear_teeth, BRASS)
	draw_circle(Vector2.ZERO, 1.9, COPPER_D)
	draw_rect(Rect2(-2.2, -0.45, 4.4, 0.9), BRASS_LIT)
	draw_rect(Rect2(-0.45, -2.2, 0.9, 4.4), BRASS_LIT)
	_part(base, GEAR_AT, 0.0)
	draw_circle(Vector2.ZERO, 0.9, OUTLINE)

func _draw_pauldron(base: Transform2D, arm: float) -> void:
	## Sits proud of the shoulder line so it silhouettes instead of covering the chest.
	_part(base, SHOULDER_F + Vector2(0.5, -1.0), arm * 0.3)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-3.2, -2.6), Vector2(2.2, -3.4), Vector2(4.0, -1.0),
		Vector2(4.0, 2.6), Vector2(-3.2, 2.6)]), OUTLINE)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-2.5, -1.9), Vector2(2.0, -2.5), Vector2(3.3, -0.7),
		Vector2(3.3, 1.9), Vector2(-2.5, 1.9)]), COPPER_L)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-2.5, -1.9), Vector2(2.0, -2.5), Vector2(3.3, -0.7),
		Vector2(3.3, 0.2), Vector2(-2.5, 0.2)]), BRASS)
	draw_rect(Rect2(-1.0, 0.7, 2.2, 1.2), PATINA)

func _draw_helm(base: Transform2D, tilt: float, slack: float) -> void:
	var at := Vector2(0, NECK_Y + slack * 0.9)
	var rot := roundf(tilt / 0.04) * 0.04
	if dying:
		# The helm pops off and tumbles away when the spring lets go.
		at += Vector2(death_t * 30.0, -78.0 * death_t + 250.0 * death_t * death_t)
		rot = death_t * 9.0
	_part(base, at, rot)
	# Brimmed bucket helm.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-4.5, -8), Vector2(3.5, -8), Vector2(5.8, -5.5), Vector2(5.8, -1),
		Vector2(-5.8, -1), Vector2(-5.8, -5.5)]), OUTLINE)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-3.8, -7.2), Vector2(3.2, -7.2), Vector2(5.0, -5.2), Vector2(5.0, -1.6),
		Vector2(-5.0, -1.6), Vector2(-5.0, -5.2)]), IRON)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-3.8, -7.2), Vector2(3.2, -7.2), Vector2(5.0, -5.2), Vector2(-5.0, -5.2)]), IRON_LIT)
	draw_rect(Rect2(-2.6, -7.0, 1.6, 1.4), PATINA)
	# Brim.
	draw_rect(Rect2(-6.8, -1.8, 13.6, 2.4), OUTLINE)
	draw_rect(Rect2(-6.3, -1.4, 12.6, 1.4), IRON_LIT)
	# Glass lens in a bolted ring, dimming as the spring runs down.
	var eye := Vector2(2.6, -4.4)
	draw_circle(eye, 3.0, OUTLINE)
	draw_circle(eye, 2.4, COPPER_D)
	var glass := LENS
	glass.a = 0.4 + 0.6 * (1.0 - slack)
	draw_circle(eye, 1.8, glass)
	var core := LENS_CORE
	core.a = glass.a
	draw_circle(eye + Vector2(0.5, -0.5), 0.8, core)

func _draw_key(base: Transform2D) -> void:
	var at := KEY_PIVOT
	var spin := key_turn
	if dying:
		at += Vector2(-death_t * 44.0, -60.0 * death_t + 230.0 * death_t * death_t)
		spin = key_turn + death_t * 14.0
	if not dying:
		# Runs all the way to the breastplate edge; a 1 px gap reads as a floating part.
		draw_set_transform_matrix(base * Transform2D(0.0, Vector2.ONE, 0.0, at))
		draw_rect(Rect2(-0.5, -1.6, 5.0, 3.2), OUTLINE)
		draw_rect(Rect2(0, -1.1, 4.2, 2.2), IRON_LIT)
	# One bar through both loops keeps the key legible as a single part while it spins.
	_part(base, at, spin)
	draw_rect(Rect2(-5.6, -2.1, 11.2, 4.2), OUTLINE)
	draw_rect(Rect2(-5.6, -2.6, 4.6, 5.2), OUTLINE)
	draw_rect(Rect2(1.0, -2.6, 4.6, 5.2), OUTLINE)
	draw_rect(Rect2(-5.0, -1.5, 10.0, 3.0), BRASS)
	draw_rect(Rect2(-5.0, -2.0, 4.0, 4.0), BRASS)
	draw_rect(Rect2(1.0, -2.0, 4.0, 4.0), BRASS)
	draw_rect(Rect2(-5.0, -2.0, 4.0, 1.0), BRASS_LIT)
	draw_rect(Rect2(1.0, -2.0, 4.0, 1.0), BRASS_LIT)
	draw_rect(Rect2(-4.0, -1.0, 2.0, 2.0), COPPER_D)
	draw_rect(Rect2(2.0, -1.0, 2.0, 2.0), COPPER_D)
	draw_rect(Rect2(-1.6, -1.6, 3.2, 3.2), COPPER_L)

func _noise(n: int) -> float:
	## Deterministic, so headless captures and test runs stay reproducible.
	return absf(fmod(sin(float(n) * 12.9898) * 43758.5453, 1.0))

func _burst(at: Vector2, count: int, power: float, tint: Color) -> void:
	for i in count:
		mote_seed += 1
		var angle := PI + _noise(mote_seed) * PI
		var speed := (0.45 + _noise(mote_seed * 7) * 0.9) * power * 38.0
		var span := 0.2 + _noise(mote_seed * 11) * 0.24
		motes.append({
			"pos": global_position + at * RIG_SCALE + Vector2(_noise(mote_seed * 3) * 18.0 - 9.0, 0.0),
			"vel": Vector2(cos(angle) * 1.5, sin(angle)) * speed * RIG_SCALE,
			"life": span, "span": span,
			"size": 1.0 + roundf(_noise(mote_seed * 5) * 1.6) * RIG_SCALE,
			"tint": tint,
		})

func _update_motes(delta: float) -> void:
	var live: Array = []
	for m in motes:
		m.life -= delta
		if m.life <= 0.0:
			continue
		m.vel.y += 190.0 * RIG_SCALE * delta
		m.vel.x *= 0.93
		m.pos += m.vel * delta
		live.append(m)
	motes = live

func _draw_motes() -> void:
	var origin := global_position
	for m in motes:
		var fade: float = clampf(m.life / m.span, 0.0, 1.0)
		var tint: Color = m.tint
		tint.a = fade
		var size: float = maxf(1.0, m.size * fade)
		draw_rect(Rect2(m.pos - origin - Vector2(size, size) * 0.5, Vector2(size, size)), tint)
