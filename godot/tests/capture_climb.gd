extends SceneTree
## Development tool: eight views up The Climb, plus one of a stone in flight.
##
## Not a test; makes no assertions. tests/test_levels.gd says whether the climb
## behaves, tests/diag_climb.gd says whether it can be climbed on the controls,
## and scripts/check_levels.py says whether it is possible on paper. This says
## what it looks like on the way up, which is the one question none of those can
## answer — the level is drawn out of its own solids, so a ledge that reads as a
## painted background rock is a design fault nothing else would catch.
##
##     <godot> --path godot --script tests/capture_climb.gd
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

## The ledges bottom-first, with each shelf's pieces merged into one surface.
func ledges() -> Array:
	var raw: Array = []
	for entry in game.level.solids:
		raw.append([float(entry[0]), float(entry[0]) + float(entry[2]), float(entry[1])])
	raw.sort_custom(func(a, b): return a[2] > b[2] if a[2] != b[2] else a[0] < b[0])
	var out: Array = []
	for rung in raw:
		if not out.is_empty() and absf(out[-1][2] - rung[2]) < 0.5 and rung[0] <= out[-1][1] + 0.5:
			out[-1][1] = maxf(out[-1][1], rung[1])
		else:
			out.append(rung)
	return out

func run() -> void:
	output = ProjectSettings.globalize_path("res://../evidence/levels")
	DirAccess.make_dir_recursive_absolute(output)
	game = Game.new()
	game.test_mode = true
	game.level_id = "the_climb"
	root.add_child(game)
	await steps(3)
	game.start_session()
	await steps(2)

	# Read out of the level rather than written down: it is 48 ledges and has
	# been relaid three times already. Six views spaced up the mountain, so the
	# set shows the bands changing — grass and sea at the bottom, bare rock and
	# open sky at the top.
	var rungs: Array = ledges()
	var marks := {0: "01-shore", 8: "02-green-steps", 16: "03-last-grass",
				  26: "04-into-the-cloud", 36: "05-bare-rock",
				  rungs.size() - 2: "06-the-needle"}
	for i in rungs.size():
		if not marks.has(i):
			continue
		var rung: Array = rungs[i]
		await stand(Vector2((rung[0] + rung[1]) / 2.0, rung[2]))
		await shot("climb-" + str(marks[i]))

	# The summit, off to one side of the flag: standing on it finishes the
	# level, and the picture that comes back is the results panel.
	var top: Array = rungs[rungs.size() - 1]
	await stand(Vector2(top[0] + 32.0, top[2]))
	await shot("climb-07-summit")

	# A stone on its way down, caught level with him. Dropped by hand rather
	# than waited for, so the picture is of a known height.
	#
	# The restart is not optional. Every shot above this one moves him UP, which
	# is the only direction the level allows: putting him back down the mountain
	# off the summit is a drop of thousands against a fatal line of 320, and the
	# picture that came back was the shore he respawned on.
	game.restart_attempt()
	await steps(2)
	var mid: Array = rungs[30]
	await stand(Vector2((mid[0] + mid[1]) / 2.0, mid[2]))
	for source in game.level.rockfall:
		if absf(float(source[1]) - mid[2]) < 420.0:
			game._drop_stone(Vector2(float(source[0]), float(source[1])))
	for _i in 22:
		await physics_frame
	await shot("climb-08-rockfall")
	print("stones in flight: %d" % game.stones.size())
	quit()
