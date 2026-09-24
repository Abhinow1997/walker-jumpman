extends SceneTree
## The blast thrown in mid-air, shot in the arena it was added for. Needs a
## renderer — run WITHOUT --headless.
##
## Two shots and one comparison. The numbers are asserted in test_combat; what
## this is for is the thing a test cannot answer — whether a standing throw
## pose reads in mid-air. The pack has no airborne blast frame (idle, walk,
## run, jump, fall, punch, kick, charge, blast, drink, carry, throw, hurt,
## death and nothing else), so he throws it in the pose he throws it standing
## and the arc has to carry it.
const Game = preload("res://game/session.gd")

const LEVEL := "dragons_roost"
const DECK := 648.0
## The left floating stone, which is where the fight is had from.
const STONE_X := 1141.0
const STONE_TOP := 552.0

var game: Node2D
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
	var at := "no blast in flight"
	if not game.blasts.is_empty():
		at = "blast %.0f above the deck" % (DECK - game.blasts[0].position.y)
	print("shot %-30s %-12s %s" % [label, (game.player.attack if game.player.attack != "" else "-"), at])

func check(id: String, passed: bool, observed: Dictionary) -> void:
	if not passed:
		failures += 1
	print(JSON.stringify({"id": id, "status": "PASS" if passed else "FAIL",
						  "observed": observed}))

## Feet down and nothing mid-swing. A committed move cannot be jumped out of,
## so a blast animation still running eats the next jump press.
func settled(at: Vector2) -> bool:
	game.player.position = at
	game.player.velocity = Vector2.ZERO
	for i in range(80):
		await physics_frame
		game.player.test_axis = 0.0
		if game.player.is_on_floor() and game.player.attack == "":
			return true
	return false

func clear_blasts() -> void:
	for b in game.blasts:
		if is_instance_valid(b):
			b.queue_free()
	game.blasts.clear()
	await step()

func run() -> void:
	output = ProjectSettings.globalize_path("res://../evidence/airblast")
	DirAccess.make_dir_recursive_absolute(output)
	game = Game.new()
	game.test_mode = true
	game.level_id = LEVEL
	root.add_child(game)
	game.start_session()
	game.player.test_control = true
	await step()
	var wyrm: Area2D = game.enemies[0]
	# Parked at its cruise, which is the height the whole mechanic is about. A
	# flyer with no target holds whatever height it is given.
	wyrm.target = null
	wyrm.aloft = true
	wyrm.grounded = false
	wyrm.deck_y = DECK
	wyrm.position = Vector2(STONE_X + 420.0,
							DECK - float(wyrm.prof.get("cruise", 156.0)))
	wyrm.velocity = Vector2.ZERO
	await step()

	# 01 — standing on the stone and throwing flat. The shot goes UNDER it.
	var _a: bool = await settled(Vector2(STONE_X, STONE_TOP))
	game.player.facing = 1.0
	game.player.mana = game.player.MAX_MANA
	game.player.test_blast_pressed = true
	var flat := -1.0
	for i in range(120):
		await step()
		if not game.blasts.is_empty():
			flat = DECK - game.blasts[0].position.y
			if game.blasts[0].position.x > wyrm.position.x - 180.0:
				break
	await shoot("airblast-01-flat-goes-under")
	check("a-flat-shot-flies-below-it",
		flat > 0.0 and flat < DECK - wyrm.position.y,
		{"blast_at": flat, "dragon_at": DECK - wyrm.position.y})
	await clear_blasts()

	# 02 — the same stone, the same button, jumped. The shot goes INTO it.
	var _b: bool = await settled(Vector2(STONE_X, STONE_TOP))
	game.player.facing = 1.0
	game.player.mana = game.player.MAX_MANA
	game.player.test_jump_pressed = true
	await physics_frame
	var fired := false
	var high := -1.0
	for i in range(160):
		if not fired and not game.player.is_on_floor() \
				and game.player.velocity.y >= -20.0:
			fired = true
			game.player.test_blast_pressed = true
		await step()
		if fired and not game.blasts.is_empty():
			if high < 0.0:
				# The moment of release, which is the shot that shows the
				# ability rather than its consequence: he is still off the
				# ground, in the standing throw pose the pack gives him.
				high = DECK - game.blasts[0].position.y
				check("he-is-still-airborne-when-it-leaves-his-hand",
					not game.player.is_on_floor(),
					{"feet_above_the_stone": STONE_TOP - game.player.position.y})
				await shoot("airblast-03-thrown-in-the-air")
			if game.blasts[0].position.x > wyrm.position.x - 200.0:
				break
	await shoot("airblast-02-jumped-goes-in")
	check("a-jumped-shot-flies-into-it",
		high > flat + 60.0,
		{"blast_at": high, "flat_was": flat, "dragon_at": DECK - wyrm.position.y})

	print("AIR BLAST CAPTURE: %d failures -> %s" % [failures, output])
	quit(1 if failures else 0)
