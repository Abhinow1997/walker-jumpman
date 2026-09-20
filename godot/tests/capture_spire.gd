extends SceneTree
## Development tool: four views up The Spire, plus one of a stone in flight.
##
## Not a test; makes no assertions. tests/test_levels.gd says whether the climb
## behaves and scripts/check_levels.py says whether it is possible. This says
## what it looks like on the way up, which is the one question neither of those
## can answer — the level is drawn out of its own solids, so a ledge that reads
## as a painted background rock is a design fault nothing else would catch.
##
##     <godot> --path godot --script tests/capture_spire.gd
##
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

## Stand him on a ledge and let the view settle onto it, so each picture is
## framed the way it would be if he had climbed there.
func stand(at: Vector2) -> void:
	game.player.position = at - Vector2(0, 4)
	game.player.velocity = Vector2.ZERO
	for _i in 40:
		await physics_frame
	await steps(2)

func run() -> void:
	output = ProjectSettings.globalize_path("res://../evidence/levels")
	DirAccess.make_dir_recursive_absolute(output)
	game = Game.new()
	game.test_mode = true
	game.level_id = "the_spire"
	root.add_child(game)
	await steps(3)
	game.start_session()
	await steps(2)

	await shot("spire-01-shore")
	await stand(Vector2(780, 420))
	await shot("spire-02-first-flight")
	await stand(Vector2(468, 268))
	await shot("spire-03-the-breather")
	await stand(Vector2(444, -188))
	await shot("spire-04-high")
	# Off to one side of the flag: standing on it finishes the level, and the
	# picture that comes back is the course-complete panel rather than the top
	# of the tower.
	await stand(Vector2(196, -720))
	await shot("spire-05-summit")

	# A stone on its way down the middle shaft, caught level with him. Dropped
	# by hand rather than waited for so the picture is of a known height rather
	# than of whatever the clock happened to be doing.
	#
	# The restart is not optional. Every shot above this one moves him UP, which
	# is the only direction the level allows: putting him on p13 straight off
	# the summit is a drop of 380, the fatal line is at 320, and the picture
	# that came back was the shore he respawned on.
	game.restart_attempt()
	await steps(2)
	await stand(Vector2(414, -340))
	game._drop_stone(Vector2(504, -520))
	for _i in 18:
		await physics_frame
	await shot("spire-06-rockfall")
	print("stones in flight: %d" % game.stones.size())
	quit()
