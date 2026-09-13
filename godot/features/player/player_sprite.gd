extends Node2D
## Anti-Davis, sliced out of the Little Fighter 2 character pack by A01 (2003,
## lf-empire.de). Fan-made LF2 content: fine for coursework, not for release.
## Source sheets live in Assests/Anti-Davis; scripts/extract_anti_davis.py turns
## them into the strips in art/anti_davis and is the only way those are made.
##
## Drop-in replacement for player_visual.gd: same interface (`body`, reset,
## advance, on_death), so the protagonist swaps without touching movement code.
##
## Reads state from `body` and owns no gameplay logic. In particular it does not
## time the attacks: the player does, because the hitbox and the drawing have to
## open on the same frame. Here that is just `body.attack` and `body.attack_frame`.
##
## Every animation, its per-frame timing and the cell geometry come from
## moves.json. Adding a move is an edit to the extractor, not to this file.

const Moveset = preload("res://features/player/moveset.gd")
const ART := "res://features/player/art/anti_davis/"

## The sheets are drawn facing right, which is body.facing = 1. Flip this if a
## future character's art faces the other way.
const ART_FACES := 1.0

## Turning mirrors the sprite by easing its horizontal scale through zero, and a
## sprite at zero width is a sliver of paper for a tenth of a second. The scale
## is floored at TURN_NARROW instead, and he stretches up by TURN_LIFT as he
## narrows, so the turn reads as a body pivoting on its feet. The pivot puts the
## feet on the node origin, so stretching cannot lift him off the ground.
## Set TURN_NARROW to 1.0 for an instant flip with no turn at all.
const TURN_RATE := 22.0
const TURN_NARROW := 0.55
const TURN_LIFT := 0.06

## Below WALK_SPEED he is standing; above RUN_SPEED the run cycle reads. In
## between is the acceleration ramp, which is short but visible off a standstill.
const WALK_SPEED := 8.0
const RUN_SPEED := 150.0

## Pixel art does not tolerate rotation, and only tolerates a little scaling.
## Lean is off entirely; squash is kept shallow and can be switched off here.
## In the Disney-era platformers this is chasing, all deformation lived in the
## drawn frames, not in a transform applied to them.
const USE_SQUASH := true
const SQUASH_MIN := 0.90
const SQUASH_MAX := 1.08
const WIDEN := 0.40

const DUST := Color("6b6257")

var body: CharacterBody2D
var sprite: AnimatedSprite2D
var playing: String = ""

## An object in his hand. LF2 never draws one into a character frame — it draws
## the body, then stamps the object at that frame's weapon point — so the drink
## frames are empty-handed and the bottle has to be put back here.
##
## Deliberately generic: set the texture and its offset and it appears on any
## frame that has a weapon point, and vanishes on any frame that does not. A
## future weapon is a different texture, not different code. Whoever starts the
## action sets it; reset() clears it.
var held_texture: Texture2D = null
var held_offset: Vector2 = Vector2.ZERO
var held: Sprite2D

var squash: float = 1.0
var squash_vel: float = 0.0
var face_scale: float = 1.0
var was_grounded: bool = true
var prev_vy: float = 0.0
var last_jumps: int = 0
var dying: bool = false
var death_t: float = 0.0

var motes: Array = []
var mote_seed: int = 0

func _ready() -> void:
	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = _build_frames()
	sprite.centered = true
	sprite.offset = Moveset.pivot()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	# Added after the body so it draws in front of it: the bottle is at his mouth,
	# on the near side of his face.
	held = Sprite2D.new()
	held.centered = true
	held.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	held.visible = false
	add_child(held)
	_play("idle")

func _build_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var cell := Moveset.cell()
	for key in Moveset.animations():
		var spec: Dictionary = Moveset.animation(key)
		var path: String = ART + str(spec.file)
		if not ResourceLoader.exists(path):
			push_warning("player_sprite: no sheet for '%s' at %s (run scripts/extract_anti_davis.py, then --import)" % [key, path])
			continue
		var sheet: Texture2D = load(path)
		frames.add_animation(key)
		frames.set_animation_loop(key, bool(spec.loop))
		var durations: Array = spec.durations
		for i in durations.size():
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(i * cell.x, 0, cell.x, cell.y)
			# SpriteFrames frame durations are relative to the animation speed,
			# so the speed is pinned at 1 fps and each frame carries its own
			# length in seconds. LF2 holds frames for uneven times and the
			# attacks depend on that: the charge sits on its commit frame twice
			# as long as anything around it.
			frames.add_frame(key, atlas, float(durations[i]))
		frames.set_animation_speed(key, 1.0)
	return frames

func _play(key: String) -> void:
	## Falls back to idle so a missing sheet degrades instead of erroring. The
	## sheets are committed, so this should not fire; it stays as a guard for the
	## case where they are present but not yet imported, which renders nothing at
	## all rather than erroring, and is easy to mistake for a code fault.
	var wanted := key if sprite.sprite_frames.has_animation(key) else "idle"
	if wanted == playing or not sprite.sprite_frames.has_animation(wanted):
		return
	playing = wanted
	sprite.play(wanted)

func _show_frame(key: String, frame: int) -> void:
	## Attacks are stepped by the player, not by the AnimatedSprite2D's own
	## clock, so that the frame on screen is exactly the frame whose hitbox is
	## live. Two clocks would drift and the hit would stop matching the drawing.
	if not sprite.sprite_frames.has_animation(key):
		_play("idle")
		return
	if playing != key:
		playing = key
		sprite.stop()
		sprite.animation = key
	sprite.frame = clampi(frame, 0, sprite.sprite_frames.get_frame_count(key) - 1)

func reset() -> void:
	squash = 1.0
	squash_vel = 0.0
	face_scale = body.facing if is_instance_valid(body) else 1.0
	was_grounded = true
	prev_vy = 0.0
	last_jumps = body.jumps if is_instance_valid(body) else 0
	dying = false
	death_t = 0.0
	motes.clear()
	held_texture = null
	held_offset = Vector2.ZERO
	if is_instance_valid(held):
		held.visible = false
	if is_instance_valid(sprite):
		sprite.modulate = Color.WHITE
		playing = ""
		_play("idle")
	queue_redraw()

func on_death() -> void:
	if dying:
		return
	dying = true
	death_t = 0.0
	_play("death")
	_burst(Vector2(0, -20), 10, 1.4)

func _physics_process(delta: float) -> void:
	# Death must keep animating while control is off; pausing must not.
	if dying:
		death_t += delta
		if playing == "idle":
			# No death sheet: dim the sprite so the failure still reads.
			sprite.modulate = Color(1, 1, 1).lerp(Color(0.45, 0.2, 0.2), minf(death_t * 4.0, 1.0))
		_update_motes(delta)
		queue_redraw()

func advance(delta: float) -> void:
	var speed := absf(body.velocity.x)
	var grounded := body.is_on_floor()

	if grounded and not was_grounded:
		var impact := clampf(prev_vy / 600.0, 0.0, 1.4)
		squash = 1.0 - impact * 0.10
		squash_vel = 0.0
		_burst(Vector2.ZERO, int(2 + impact * 7.0), 0.5 + impact)
	if body.jumps != last_jumps:
		last_jumps = body.jumps
		squash = 1.07
		squash_vel = 0.0
		_burst(Vector2.ZERO, 3, 0.7)
	was_grounded = grounded
	prev_vy = body.velocity.y

	squash_vel += (1.0 - squash) * 620.0 * delta
	squash_vel *= 0.86
	squash += squash_vel * delta
	squash = clampf(squash, SQUASH_MIN, SQUASH_MAX)

	face_scale = move_toward(face_scale, body.facing * ART_FACES, delta * TURN_RATE)

	# An attack overrides the locomotion pose for its whole duration; the player
	# has already decided which frame of it is showing.
	if body.attack != "":
		_show_frame(body.attack, body.attack_frame)
	elif not grounded:
		_play("rise" if body.velocity.y < 0.0 else "fall")
	elif speed > 40.0 and signf(body.velocity.x) != signf(body.facing):
		_play("skid")
	elif speed > RUN_SPEED:
		_play("run")
	elif speed > WALK_SPEED:
		_play("walk")
	else:
		_play("idle")

	_apply_transform()
	_update_held()
	_update_motes(delta)
	queue_redraw()

func _update_held() -> void:
	## Follows the weapon point of whatever frame is showing. The held sprite is
	## a sibling of the body, not a child of it, so squash and the turn stretch
	## do not deform the bottle; only the mirror is applied.
	if not is_instance_valid(held):
		return
	var point = Moveset.wpoint(body.attack, body.attack_frame) if body.attack != "" else null
	if held_texture == null or point == null:
		held.visible = false
		return
	var side := -1.0 if face_scale < 0.0 else 1.0
	held.texture = held_texture
	held.offset = held_offset
	held.position = Vector2(point.x * side, point.y)
	held.scale = Vector2(side, 1.0)
	held.visible = true

func _apply_transform() -> void:
	var stretch_y := squash if USE_SQUASH else 1.0
	var stretch_x := (1.0 + (1.0 - squash) * WIDEN) if USE_SQUASH else 1.0
	# face_scale still crosses zero, which is what mirrors the sprite and its
	# offset together and keeps the body centred on the collider through the
	# flip. Only the width it is allowed to reach there is clamped.
	var turn := absf(face_scale)
	var facing := -1.0 if face_scale < 0.0 else 1.0
	stretch_x *= TURN_NARROW + (1.0 - TURN_NARROW) * turn
	stretch_y *= 1.0 + (1.0 - turn) * TURN_LIFT
	sprite.scale = Vector2(stretch_x * facing, stretch_y)

func _noise(n: int) -> float:
	## Deterministic, so headless captures and test runs stay reproducible.
	return absf(fmod(sin(float(n) * 12.9898) * 43758.5453, 1.0))

func _burst(at: Vector2, count: int, power: float) -> void:
	for i in count:
		mote_seed += 1
		var angle := PI + _noise(mote_seed) * PI
		var speed := (0.45 + _noise(mote_seed * 7) * 0.9) * power * 76.0
		var span := 0.2 + _noise(mote_seed * 11) * 0.24
		motes.append({
			"pos": global_position + at + Vector2(_noise(mote_seed * 3) * 18.0 - 9.0, 0.0),
			"vel": Vector2(cos(angle) * 1.5, sin(angle)) * speed,
			"life": span, "span": span,
			"size": 2.0 + roundf(_noise(mote_seed * 5) * 1.6) * 2.0,
		})

func _update_motes(delta: float) -> void:
	var live: Array = []
	for m in motes:
		m.life -= delta
		if m.life <= 0.0:
			continue
		m.vel.y += 380.0 * delta
		m.vel.x *= 0.93
		m.pos += m.vel * delta
		live.append(m)
	motes = live

func _draw() -> void:
	## Dust only. It lives in world space so puffs stay planted as the player runs.
	var origin := global_position
	for m in motes:
		var fade: float = clampf(m.life / m.span, 0.0, 1.0)
		var tint := DUST
		tint.a = fade * 0.8
		var size: float = maxf(1.0, m.size * fade)
		draw_rect(Rect2(m.pos - origin - Vector2(size, size) * 0.5, Vector2(size, size)), tint)
