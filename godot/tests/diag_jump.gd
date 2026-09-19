extends SceneTree
## Diagnostic: an enemy going up after a player standing above him, traced one
## PHYSICS TICK at a time. Not a test; makes no assertions. Prints the arc, the
## state, and the frame the fist lands on.
##
## Two things this exists to say out loud, both of which made the first versions
## of the combat suite's jump checks wrong:
##
##   * `await physics_frame` then `await process_frame` — what test_*.gd calls
##     steps(1) — is a PROCESS frame, not a physics tick. Godot runs up to eight
##     physics ticks inside one while it catches up, and how many depends on how
##     slow that frame happened to be. A player pinned once per step falls most
##     of a jump's height between pins, and a pose caught "next frame" can be
##     eight frames late. Awaiting physics_frame alone, as below, is exact.
##   * A fist reaches FORWARD, 12 to 30 px ahead of him. An enemy standing
##     directly under the player swings past him on both sides and connects with
##     nothing, however long he keeps at it — which is what a bandit who carries
##     a charge into the setup does, because he overruns.
const Game = preload("res://game/session.gd")
const Enemy = preload("res://features/combat/enemy.gd")
var game: Node2D

func _initialize() -> void:
	call_deferred("run")

func step() -> void:
	await physics_frame
	await process_frame

func run() -> void:
	game = Game.new()
	game.test_mode = true
	game.level_id = "fractured_isles"
	root.add_child(game)
	game.start_session()
	game.player.test_control = true
	await step()
	for parked in game.enemies:
		parked.target = null

	# A patch of ground 600 px above the level, where nothing else is: a floor,
	# and a ledge 90 px over it for the player to stand on.
	var deck := -600.0
	game._add_solid(Rect2(2200, deck, 500, 200))
	game._add_solid(Rect2(2600, deck - 90.0, 200, 20))
	await step()

	var foe := Enemy.new()
	foe.position = Vector2(2570, deck)
	foe.fall_limit = 1000.0
	foe.struck_player.connect(game._on_player_struck)
	game.add_child(foe)
	await step()
	foe.target = game.player
	foe.engaged = true
	game.player.position = Vector2(2620, deck - 90.0)
	game.player.velocity = Vector2.ZERO
	await step()

	var before: int = game.player.health
	var rows: Array = []
	for i in range(90):
		await physics_frame
		rows.append([i, foe.state, foe.position.x, foe.position.y,
			foe.grounded, game.player.health])
		if game.player.health < before:
			break
	print("hit_rect ", foe.data().get("hit_rect"), "  reach to ",
		foe.attack_range(), "  apex ", foe.jump_apex(),
		"  air time ", foe.air_time(), "  health ", before)
	print("player stands at ", game.player.position, ", ledge top ", deck - 90.0)
	for r in rows:
		print("%3d state=%d x=%8.2f y=%8.2f up=%s hp=%d" % [
			r[0], r[1], r[2], r[3], str(not r[4]), r[5]])
	print("ticks traced ", rows.size(), ", final health ", game.player.health)
	quit()
