extends SceneTree
## Development tool: what the lit stone over the finish costs to draw.
##
## It is built out of rows one art pixel tall — four passes of light through
## the hole, two down the shaft, three on the ground, about 535 rows — and it
## asks for a redraw every frame. That is worth a number rather than a shrug,
## because `_draw` runs whether or not the thing is in shot unless something
## stops it, and a level is mostly played out of sight of its own ending.
##
##     <godot> --path godot --script tests/diag_portal.gd
##
## Run without --headless; there is nothing to time without a renderer.
##
## Two things make the reading trustworthy and the first version of this had
## neither. One marker against this machine's frame-to-frame noise is hopeless
## — two samples of an IDENTICAL scene came back 1.5 ms apart — so it times a
## stack of COPIES and divides, and takes the FASTEST round of each state
## rather than the mean, because noise only ever adds.
const Game = preload("res://game/session.gd")
const Portal = preload("res://features/world/portal.gd")

const FRAMES := 120
const ROUNDS := 4
## How many extra markers are stacked on the real one. Twenty puts the
## difference well clear of the noise; the cost of one is that over twenty-one.
const COPIES := 20

var game: Node2D
var stack: Array[Node2D] = []

func _initialize() -> void:
	call_deferred("run")

func steps(n: int) -> void:
	for i in range(n):
		await physics_frame
		await process_frame

## One timed run, in milliseconds a frame. Two settling frames first: the frame
## after a visibility change rebuilds the canvas item and is not typical of the
## ones after it.
func sample() -> float:
	await steps(2)
	var started := Time.get_ticks_usec()
	for i in FRAMES:
		await RenderingServer.frame_post_draw
	return float(Time.get_ticks_usec() - started) / 1000.0 / float(FRAMES)

func calls() -> int:
	return int(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))

func show_all(on: bool) -> void:
	game.portal.visible = on
	for extra in stack:
		extra.visible = on

func weigh(label: String) -> void:
	var with_it: float = INF
	var without: float = INF
	var drawn := 0
	var bare := 0
	for round_i in ROUNDS:
		show_all(true)
		with_it = minf(with_it, await sample())
		drawn = calls()
		show_all(false)
		without = minf(without, await sample())
		bare = calls()
	show_all(true)
	print("%-12s  %d markers %6.3f ms   none %6.3f ms   ONE %6.3f ms   %d draw calls   state %d" % [
			label, COPIES + 1, with_it, without,
			(with_it - without) / float(COPIES + 1), drawn - bare, game.state])

func run() -> void:
	# Otherwise every sample comes back as the refresh rate and the rounds
	# differ only by how busy the machine happened to be.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
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
	# The arena cleared out. Sixteen seconds of sampling is long enough for two
	# bosses to beat him, and a run that ends in State.DYING stops the marker's
	# clock — the first attempt at this timed a marker that had quietly stopped
	# asking to be redrawn halfway through.
	for foe in game.enemies:
		foe.queue_free()
	game.enemies.clear()
	await steps(2)
	for i in COPIES:
		var extra := Portal.new()
		extra.game = game
		extra.position = game.portal.position
		game.add_child(extra)
		stack.append(extra)
	var f: Array = game.level.finish
	# Close enough that the whole marker is on screen and being drawn.
	game.player.position = Vector2(float(f[0]) - 150.0,
			float(f[1]) + float(f[3]) - 4.0)
	game.player.velocity = Vector2.ZERO
	for _i in 40:
		await physics_frame
	await weigh("in shot")
	# And again from the far end of the deck, where the marker is off the side
	# of the screen and _in_shot() should have stopped it asking for a redraw
	# at all. Still ON the deck: dropped off the end of it he falls, and a
	# falling player is a different scene to time.
	game.player.position = Vector2(float(f[0]) - 1400.0,
			float(f[1]) + float(f[3]) - 4.0)
	game.player.velocity = Vector2.ZERO
	for _i in 90:
		await physics_frame
	print("out of shot: %s   camera %s   marker %s" % [
			not game.portal._in_shot(), game.camera.position,
			game.portal.position])
	await weigh("out of shot")
	quit()
