extends SceneTree
## The prompts on the play HUD: what they look like, and that they stand over
## the thing they are about rather than in the middle of the screen.
##
## Shoots each of them on First Steps, which is the one level that has them,
## and then the same stretch of The Fractured Isles to show that a level with
## `hints` off cues nothing at all.
##
##     <godot> --path godot --script tests/capture_hints.gd
##
## Run without --headless; it needs a real renderer.
const Game = preload("res://game/session.gd")

## First Steps, by x. The crate at 1524 stands inside the bandit's coach span
## (1392..2112), which is the one place both a lesson and an action cue are up
## together — and the case the old centred line could not lay out.
const ROCK := 1524.0
const BOTTLE := 2028.0
## The first pit opens at 549. Far enough back that the whole walk up to it is
## in frame, near enough that the lip is too.
const LIP := 440.0

var game: Node2D
var output: String
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func steps(n: int) -> void:
	for i in range(n):
		await physics_frame
		await process_frame

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [output, label])
	print("shot: %s" % label)

func check(id: String, passed: bool, observed: Dictionary) -> void:
	if not passed:
		failures += 1
	print(JSON.stringify({"id": id, "status": "PASS" if passed else "FAIL",
						  "observed": observed}))

func fresh(id: String) -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	game = Game.new()
	game.test_mode = true
	game.level_id = id
	root.add_child(game)
	await steps(3)
	game.start_session()
	await steps(2)
	for wall in game.gate_walls:
		wall.collision_layer = 0
	game.gates.clear()
	game.gate_walls.clear()
	# Nobody fighting him. The bandit on the second stretch knocked him off the
	# bottle mid-shoot the first time this ran, and a player in hurt-stun picks
	# nothing up — the pictures were of a man being punched, not of a prompt.
	for foe in game.enemies:
		foe.queue_free()
	game.enemies.clear()
	await steps(2)

## On his feet at x, with the camera settled on him.
func stand(x: float, y: float = 644.0) -> void:
	game.player.position = Vector2(x, y)
	game.player.velocity = Vector2.ZERO
	for _i in 40:
		await physics_frame
	await steps(2)

func run() -> void:
	output = ProjectSettings.globalize_path("res://../evidence/hints")
	DirAccess.make_dir_recursive_absolute(output)

	await fresh("first_steps")
	check("first-steps-teaches", game.hud.teaches(), {})

	# --- the first pit ------------------------------------------------------
	await stand(LIP)
	check("the-jump-lesson-is-owed-at-the-first-pit",
		not game.hud._coached("jump"), {"jumps": game.player.jumps})
	for _i in 20:
		await physics_frame
	await shot("00-jump")

	# --- the rock, with the bandit's lesson over it -------------------------
	await stand(ROCK - 26.0)
	var lift: Rect2 = game.hud.cue_box(
			game.carryable_in_reach().global_position, "E", "LIFT",
			game.hud.CUE_OVER_PROP)
	var lesson: Rect2 = game.hud.cue_box(
			game.player.position, "J", "STRIKE", game.hud.CUE_OVER_LESSON)
	check("the-lift-cue-stands-over-the-rock",
		absf(lift.get_center().x - game.to_hud(
				game.carryable_in_reach().global_position).x) < 1.0
		and lift.end.y < game.to_hud(
				game.carryable_in_reach().global_position).y,
		{"cue": lift, "rock": game.to_hud(
				game.carryable_in_reach().global_position)})
	check("and-the-lesson-stands-clear-above-it",
		lesson.end.y <= lift.position.y,
		{"lesson": lesson, "lift": lift})
	check("both-are-inside-the-frame",
		Rect2(0, 0, 640, 360).encloses(lift)
		and Rect2(0, 0, 640, 360).encloses(lesson),
		{"lift": lift, "lesson": lesson})
	# The fade wants a moment: the cue arrives at nothing and is up in 0.18s.
	for _i in 20:
		await physics_frame
	await shot("01-lift-and-lesson")

	# --- carrying it --------------------------------------------------------
	game.pick_up()
	for _i in 40:
		await physics_frame
	await steps(2)
	check("he-is-carrying-the-rock", game.player.is_carrying(),
		{"carrying": game.player.is_carrying()})
	await shot("02-throw")

	# --- the bottle ---------------------------------------------------------
	await fresh("first_steps")
	# A reason to want one: drink() refuses at full health and the cue says so.
	game.player.health = game.player.MAX_HEALTH - 40
	await stand(BOTTLE - 20.0)
	await shot("03-lift-the-bottle")
	game.pick_up()
	for _i in 40:
		await physics_frame
	await steps(2)
	check("he-is-holding-the-bottle",
		game.bottle_being_carried() != null,
		{"held": game.bottle_being_carried() != null})
	for _i in 20:
		await physics_frame
	await shot("04-drink")

	# --- nothing to drink ---------------------------------------------------
	game.player.health = game.player.MAX_HEALTH
	for _i in 20:
		await physics_frame
	check("a-full-bar-greys-the-cue",
		game.player.refill_full(game.bottle_being_carried().refills),
		{})
	await shot("05-already-full")

	# --- the bar the drink is filling ---------------------------------------
	await fresh("first_steps")
	game.player.health = game.player.MAX_HEALTH - 40
	await stand(BOTTLE - 20.0)
	game.pick_up()
	for _i in 40:
		await physics_frame
	var drinking: bool = game.drink()
	for _i in 30:
		await physics_frame
	check("he-is-drinking-the-milk",
		drinking and game.player.is_drinking()
		and str(game.drinking_bottle.refills) == "health",
		{"drinking": game.player.is_drinking()})
	var green: Rect2 = game.hud.bar_cue_box(game.hud.bar_rect("health"), "HEALTH")
	check("and-the-cue-stands-beside-the-green-bar",
		green.position.x > game.hud.bar_rect("health").end.x
		and absf(green.get_center().y
				- game.hud.bar_rect("health").get_center().y) < 1.0,
		{"cue": green, "bar": game.hud.bar_rect("health")})
	await shot("07-health-bar")

	# --- and the bar the blast spends ---------------------------------------
	await fresh("first_steps")
	await stand(BOTTLE - 20.0)
	check("no-mana-lesson-before-he-has-spent-any",
		not game.hud._first_mana(), {"blasts": game.player.blasts_thrown})
	game.player.test_control = true
	game.player.test_blast_pressed = true
	for _i in 12:
		await physics_frame
	game.player.test_blast_pressed = false
	for _i in 18:
		await physics_frame
	check("the-first-blast-names-the-mana-bar",
		game.player.blasts_thrown == 1 and game.hud._first_mana(),
		{"blasts": game.player.blasts_thrown, "mana": game.player.mana})
	await shot("08-mana-bar")
	# And it is over, for good, once it has been read.
	for _i in 160:
		await physics_frame
	check("and-says-it-once", not game.hud._first_mana()
		and game.hud.blast_done, {"done": game.hud.blast_done})

	# --- a level that does not prompt ---------------------------------------
	await fresh("fractured_isles")
	check("the-isles-do-not-teach", not game.hud.teaches(), {})
	var crate: Node2D = null
	for prop in game.crates:
		crate = prop
		break
	if crate != null:
		await stand(crate.position.x - 26.0, crate.position.y - 4.0)
		check("and-nothing-is-cued-over-a-rock-in-reach",
			game.carryable_in_reach() != null and not game.hud.teaches(),
			{"in_reach": game.carryable_in_reach() != null})
		await shot("06-isles-no-cue")
	print("HINT SHOTS: %d failures" % failures)
	quit()
