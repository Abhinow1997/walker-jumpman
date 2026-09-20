extends SceneTree
## The final boss fight, shot beat by beat. Needs a renderer — run WITHOUT
## --headless.
##
## It is a capture rather than a pose sheet because almost nothing about this
## fight is a pose. The dragon has two phases and fourteen animations, thirteen
## of which are decoded out of watermarked preview gifs by
## scripts/extract_dragon.py, and the thing worth photographing is what it does
## with them: the perch, the roar it launches with, the cruise, a pass and the
## strike at the bottom of it, fire in the air, the landing, the walk, the claw,
## fire standing, and the ending.
##
## Every shot also asserts, so a decoder that broke or a phase that stopped
## coming round fails here rather than looking slightly wrong in a screenshot.
const Game = preload("res://game/session.gd")

const LEVEL := "dragons_roost"
const DECK := 648.0

var game: Node2D
var wyrm: Area2D
var output: String
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func step() -> void:
	await physics_frame
	await process_frame

func shoot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png("%s/%s.png" % [output, label])
	assert(err == OK)
	print("shot %-30s %-10s %4.0f above the deck" % [
		label, wyrm.sprite.animation, DECK - wyrm.position.y])

func check(id: String, passed: bool, observed: Dictionary) -> void:
	if not passed:
		failures += 1
	print(JSON.stringify({"id": id, "status": "PASS" if passed else "FAIL",
						  "observed": observed}))

## Hold the player on his mark while the world runs. Every shot here is about
## what the dragon is doing, so the player is a fixed point rather than
## something driving the fight.
func hold(at: float, ticks: int) -> void:
	for i in range(ticks):
		game.player.position = Vector2(at, DECK)
		game.player.velocity = Vector2.ZERO
		game.player.health = game.player.MAX_HEALTH
		await step()

## Run until the dragon is doing the thing we came to photograph.
func until(at: float, limit: int, test: Callable) -> bool:
	for i in range(limit):
		game.player.position = Vector2(at, DECK)
		game.player.velocity = Vector2.ZERO
		game.player.health = game.player.MAX_HEALTH
		await step()
		if test.call():
			return true
	return false

## Put it in the air on a clean clock, with the player where the shot wants him.
##
## Set up rather than waited for, on purpose. The fight runs on its own timers —
## nine seconds up, seven down, four between specials — so a capture that waited
## for each beat in turn would photograph whatever the cycle happened to be
## doing by the time the previous shot finished. It did exactly that: the
## landing shot caught a swoop and the flying breath never came round at all.
func airborne(at: float, left: float = 20.0) -> void:
	wyrm.reset()
	wyrm.target = game.player
	wyrm.engaged = true
	wyrm.aloft = true
	wyrm.grounded = false
	wyrm.deck_y = DECK
	wyrm.position.y = DECK - float(wyrm.prof.get("cruise", 150.0))
	wyrm.air_left = left
	wyrm.mark_y = DECK
	game.player.position = Vector2(at, DECK)
	game.player.velocity = Vector2.ZERO
	await step()

func on_foot(at: float, left: float = 20.0) -> void:
	wyrm.reset()
	wyrm.target = game.player
	wyrm.engaged = true
	wyrm.ground_left = left
	game.player.position = Vector2(at, DECK)
	game.player.velocity = Vector2.ZERO
	await step()

## The middle of a move's own chosen band, which is where it will throw it.
func band_middle(move: String) -> float:
	var band: Array = wyrm.move_data(move).get("range", [120.0, 180.0])
	return wyrm.home.x - (float(band[0]) + float(band[1])) * 0.5

func run() -> void:
	output = ProjectSettings.globalize_path("res://../evidence/dragon")
	DirAccess.make_dir_recursive_absolute(output)
	game = Game.new()
	game.test_mode = true
	game.level_id = LEVEL
	root.add_child(game)
	game.start_session()
	game.player.test_control = true
	await step()
	wyrm = game.enemies[0] if game.enemies.size() > 0 else null
	check("the-roost-has-a-dragon-in-it",
		wyrm != null and wyrm.kind == "dragon", {"enemies": game.enemies.size()})
	if wyrm == null:
		quit(1)
		return
	var near: float = wyrm.home.x - 260.0
	var close: float = wyrm.home.x - 150.0

	# 01 — on its perch, from outside its aggro. This is the whole reason a
	# flyer is placed like a grounded enemy: you walk in and it is sitting
	# there, in the pack's own ground idle.
	await hold(wyrm.home.x - wyrm.aggro - 40.0, 20)
	await shoot("dragon-01-perched")
	check("it-waits-on-the-ground",
		not wyrm.aloft and wyrm.sprite.animation == "idle",
		{"aloft": wyrm.aloft, "playing": wyrm.sprite.animation})

	# 02 — the roar. Three frames of the take-off turn to face the player
	# head-on with the wings thrown wide, and it is the only moment in the
	# whole pack drawn straight at the camera.
	await on_foot(wyrm.home.x - 400.0, 0.0)
	var roared := await until(wyrm.home.x - 400.0, 120, func():
		return wyrm.shift >= 0.0 and wyrm.shift_up and wyrm.shift_frame() >= 3)
	await shoot("dragon-02-the-roar")
	check("it-roars-before-it-launches", roared,
		{"frame": wyrm.shift_frame(), "playing": wyrm.sprite.animation})

	# 03 — cruising. The point of the shot is the gap: this is the height a
	# jump from the deck cannot reach.
	await airborne(wyrm.home.x - 400.0)
	var up := await until(wyrm.home.x - 400.0, 200, func():
		return wyrm.swoop < 0.0 and wyrm.shift < 0.0 \
			and absf((DECK - wyrm.position.y)
					 - float(wyrm.prof.get("cruise", 0.0))) < 8.0)
	await shoot("dragon-03-cruising")
	check("it-holds-its-cruise", up,
		{"held": DECK - wyrm.position.y, "cruise": wyrm.prof.get("cruise", 0.0)})

	# 04, 05 — a pass: half way down, which is the telegraph, and the strike on
	# the frame the blow is live, with its wings driven below its own body.
	# That downstroke is where the hit box comes from.
	var diving := await until(wyrm.home.x - 380.0, 300, func():
		return wyrm.swoop >= 0.0 and DECK - wyrm.position.y < 110.0 \
			and DECK - wyrm.position.y > 60.0)
	await shoot("dragon-04-the-pass")
	check("a-pass-comes-down", diving, {"at": DECK - wyrm.position.y})
	var bit := await until(wyrm.home.x - 380.0, 300, func():
		return wyrm.state == wyrm.State.PUNCH and wyrm.move == "swoop" \
			and wyrm.frame >= int(wyrm.move_data("swoop").get("hit_frame", 0)))
	await shoot("dragon-05-the-strike")
	check("the-strike-is-on-screen", bit,
		{"move": wyrm.move, "frame": wyrm.frame, "at": DECK - wyrm.position.y})

	# 06 — the flying breath. It drops to the player's own level at range and
	# hoses along the deck, which is the one air attack that is not a pass.
	var fire_at := band_middle("fire_air")
	await airborne(fire_at)
	wyrm.special_ready = 0.0
	var breathed := await until(fire_at, 300, func():
		return wyrm.move == "fire_air" and wyrm.state == wyrm.State.PUNCH \
			and wyrm.frame >= int(wyrm.move_data("fire_air").get("hit_frame", 0)))
	await shoot("dragon-06-fire-in-the-air")
	check("it-breathes-fire-in-flight", breathed,
		{"move": wyrm.move, "frame": wyrm.frame})

	# 07 — coming down. When its time in the air runs out it lands, and the
	# landing is committed: nothing interrupts it.
	await airborne(near, 0.0)
	var landing := await until(near, 200, func():
		return wyrm.shift >= 0.0 and not wyrm.shift_up and wyrm.shift_frame() >= 2)
	await shoot("dragon-07-landing")
	check("it-comes-down-of-its-own-accord", landing,
		{"frame": wyrm.shift_frame(), "playing": wyrm.sprite.animation})

	# 08 — on its feet and walking in: a different animation, a different speed
	# and a different attack from anything it does in the air.
	await on_foot(wyrm.home.x - 500.0)
	var walking := await until(wyrm.home.x - 500.0, 200, func():
		return not wyrm.aloft and wyrm.shift < 0.0 and wyrm.state == wyrm.State.WALK)
	await shoot("dragon-08-on-its-feet")
	check("it-walks-on-the-ground", walking,
		{"playing": wyrm.sprite.animation, "state": wyrm.state})

	# 09, 10 — its two ground attacks: the claw up close, and the standing fire
	# breath from the band the plume actually covers.
	await on_foot(close)
	var clawed := await until(close, 300, func():
		return wyrm.move == "claw" and wyrm.state == wyrm.State.PUNCH \
			and wyrm.frame >= int(wyrm.move_data("claw").get("hit_frame", 0)))
	await shoot("dragon-09-the-claw")
	check("it-claws-on-the-ground", clawed, {"move": wyrm.move, "frame": wyrm.frame})
	var ground_fire_at := band_middle("fire")
	await on_foot(ground_fire_at)
	wyrm.special_ready = 0.0
	var burned := await until(ground_fire_at, 300, func():
		return wyrm.move == "fire" and wyrm.state == wyrm.State.PUNCH \
			and wyrm.frame >= int(wyrm.move_data("fire").get("hit_frame", 0)))
	await shoot("dragon-10-fire-on-the-ground")
	check("it-breathes-fire-standing", burned,
		{"move": wyrm.move, "frame": wyrm.frame})

	# 11, 12, 13 — the ending. Beaten, it goes down on the deck in the pack's
	# own collapse, then gets up and climbs out of the level. The gate it was
	# holding opens the moment it is beaten, not when the body is cleared.
	await airborne(near)
	var shut_before: float = game.gate_shut_at()
	var _down: bool = wyrm.take_hit(wyrm.health, game.player.global_position)
	check("the-flag-opens-when-it-is-beaten",
		shut_before < INF and game.gate_shut_at() == INF,
		{"was": shut_before, "now": game.gate_shut_at()})
	var fell := await until(near, 300, func():
		return wyrm.sprite.animation == "death" and wyrm.grounded)
	await shoot("dragon-11-beaten")
	check("it-collapses-on-the-deck", fell,
		{"playing": wyrm.sprite.animation, "grounded": wyrm.grounded})
	await until(near, 300, func(): return wyrm.aloft)
	await hold(near, 26)
	await shoot("dragon-12-flying-away")
	var gone := await until(near, 300, func(): return not wyrm.visible)
	await shoot("dragon-13-gone")
	check("it-is-out-of-the-level", gone,
		{"visible": wyrm.visible, "up": DECK - wyrm.position.y})

	print("DRAGON CAPTURE: %d failures -> %s" % [failures, output])
	quit(1 if failures else 0)
