extends SceneTree
## Development tool: shoots the level-select menu and the opening view of every
## level in the catalogue, so adding a level to the index is one command away
## from a picture of it.
##
## Not a test; makes no assertions. scripts/check_levels.py is what says whether
## a level is playable. This says what it looks like.
## Run without --headless; it needs a real renderer.
const Game = preload("res://game/session.gd")

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

func fresh(id: String) -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	game = Game.new()
	game.test_mode = true
	game.level_id = id
	root.add_child(game)
	await steps(3)

func run() -> void:
	output = ProjectSettings.globalize_path("res://../evidence/levels")
	DirAccess.make_dir_recursive_absolute(output)
	var order: Array = Game.catalogue()

	# The menu, once per row, so a long title running into the panel edge shows
	# up here rather than in a screenshot someone takes later.
	await fresh(order[0])
	for i in order.size():
		game.menu_index = i
		game.state = Game.State.MENU
		await steps(2)
		await shot("menu-%d-%s" % [i + 1, order[i]])

	# Each level from its spawn, and again from the flag, which is the pair that
	# shows whether the geometry and the decoration agree at both ends.
	for id in order:
		await fresh(id)
		game.start_session()
		await steps(3)
		await shot("level-%s-start" % id)
		# Midway as well: a level long enough to join two areas has a seam in the
		# middle that neither end shot would ever show.
		await _stand_at(float(game.level.width) * 0.5)
		await shot("level-%s-middle" % id)
		await _stand_at(float(game.level.finish[0]) - 160.0)
		await shot("level-%s-finish" % id)

	print("LEVEL SHEET: written to " + output)
	game.queue_free()
	await process_frame
	quit()

func _stand_at(x: float) -> void:
	## Puts him on whatever floor is under that x, rather than at the spawn
	## height. A descending level would otherwise photograph him mid-fall.
	var best: float = INF
	for entry in game.level.solids:
		var x0: float = float(entry[0])
		var x1: float = x0 + float(entry[2])
		if x >= x0 and x <= x1:
			best = minf(best, float(entry[1]))
	game.player.position = Vector2(x, best if best != INF else game.player.position.y)
	game.player.velocity = Vector2.ZERO
	await steps(8)
