extends SceneTree
## Development tool: the end-of-level marker, on every level that has one.
##
## Not a test. test_levels.gd says the goal is where the level says it is and
## that touching it finishes; this says whether the thing standing there looks
## like the way out of a fantasy coast or like a placeholder.
##
##     <godot> --path godot --script tests/capture_finish.gd
##
## Run without --headless; it needs a real renderer. He is parked to the LEFT
## of each marker on purpose: standing in it finishes the level and the picture
## that comes back is the results card.
const Game = preload("res://game/session.gd")

## Every level with a finish, and how far back to stand. Far enough that the
## whole marker is in frame with its ground under it; near enough that it is
## not a speck.
const SHOTS := [
	["first_steps", 150.0],
	["fractured_isles", 150.0],
	# 70 and not 150: the summit platform starts at x168 and the marker is at
	# 252, so a full stride back is off the edge of the tower.
	["the_climb", 70.0],
	["dragons_roost", 150.0],
	["greybox", 150.0],
]

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
	root.get_texture().get_image().save_png(output + "/" + label + ".png")
	print("shot: " + label)

func run() -> void:
	output = ProjectSettings.globalize_path("res://../evidence/finish")
	DirAccess.make_dir_recursive_absolute(output)
	var n := 0
	for entry in SHOTS:
		var id := str(entry[0])
		var back := float(entry[1])
		game = Game.new()
		game.test_mode = true
		game.level_id = id
		root.add_child(game)
		await steps(3)
		game.start_session()
		await steps(2)
		# Every gate open. The camera is clamped to the wall holding the player
		# in, so on a gated level the first picture back was the fight he had
		# been teleported out of rather than the end of the level.
		for wall in game.gate_walls:
			wall.collision_layer = 0
		game.gates.clear()
		game.gate_walls.clear()
		var f: Array = game.level.finish
		# On his feet at the marker's own foot line, a stride back from it.
		game.player.position = Vector2(float(f[0]) - back,
				float(f[1]) + float(f[3]) - 4.0)
		game.player.velocity = Vector2.ZERO
		for _i in 40:
			await physics_frame
		await steps(2)
		n += 1
		await shot("%02d-%s" % [n, id])
		game.queue_free()
		await steps(2)
	# A strip of the same marker a beat apart, because the half of this that
	# does not show up in a still is that it moves: the stone rises and falls,
	# the light breathes on a different clock, and sparks run up the shaft.
	game = Game.new()
	game.test_mode = true
	game.level_id = "dragons_roost"
	root.add_child(game)
	await steps(3)
	game.start_session()
	await steps(2)
	for wall in game.gate_walls:
		wall.collision_layer = 0
	game.gates.clear()
	game.gate_walls.clear()
	var f: Array = game.level.finish
	game.player.position = Vector2(float(f[0]) - 150.0,
			float(f[1]) + float(f[3]) - 4.0)
	game.player.velocity = Vector2.ZERO
	for _i in 40:
		await physics_frame
	for frame in 6:
		await shot("strip-%d" % frame)
		# A fifth of a second between frames: the bob is 2.6s and the pulse
		# 1.7s, so six of these walk about a quarter of the way through both.
		for _i in 12:
			await physics_frame
	print("%d shots in %s" % [n, output])
	quit()
