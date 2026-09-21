extends SceneTree
## Development tool: what the sealed dragon arena looks like from inside it.
##
## diag_arena_seal.gd says he cannot get west of 6912 with the fight on. This
## says what that looks like — the wall is invisible, so the thing that has to
## read is the framing: the camera stops with the line just inside the left
## edge, the way it stops against a gate on the right, so you can see you have
## run out of screen rather than out of floor.
##
##     <godot> --path godot --script tests/capture_arena.gd
##
## Run without --headless; it needs a real renderer.
const Game = preload("res://game/session.gd")

## Both boss levels, and where each cues its fight.
const SHOTS := [["fractured_isles", 6960.0], ["dragons_roost", 900.0]]

var game: Node2D
var output: String

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

## Holds left until he stops moving, which against the wall is at once.
func press_west(ticks: int) -> void:
	game.player.test_control = true
	game.player.test_axis = -1.0
	for i in ticks:
		await physics_frame
	game.player.test_axis = 0.0
	await steps(2)

func walk(id: String, cue: float, n: int) -> void:
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
	var deck: float = game.player.position.y
	for foe in game.enemies:
		if is_instance_valid(foe) and not foe.is_boss():
			foe.health = 0
	await steps(4)

	# Before: the fight has not started, the wall is open, and the way back is
	# a way back.
	game.player.position = Vector2(game.seal_at + 48.0, deck - 8.0)
	game.player.velocity = Vector2.ZERO
	for _i in 40:
		await physics_frame
	await press_west(90)
	await shot("%02d-%s-open" % [n, id])

	# After: the bosses are awake and the same push west goes nowhere.
	game.player.position = Vector2(cue, deck - 8.0)
	game.player.velocity = Vector2.ZERO
	for _i in 30:
		await physics_frame
	game._wake_boss()
	await steps(2)
	await press_west(180)
	print("%s: sealed=%s  he is at %.0f  wall at %.0f  screen left edge %.0f" % [
		id, game.sealed, game.player.position.x, game.seal_at,
		game.camera.position.x - 480.0])
	await shot("%02d-%s-sealed" % [n + 1, id])

func run() -> void:
	output = ProjectSettings.globalize_path("res://../evidence/arena")
	DirAccess.make_dir_recursive_absolute(output)
	var n := 1
	for entry in SHOTS:
		await walk(str(entry[0]), float(entry[1]), n)
		n += 2
	quit()
