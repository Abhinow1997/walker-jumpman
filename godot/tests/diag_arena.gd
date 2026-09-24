extends SceneTree
## Diagnostic: does the dragon stay on screen inside a gated arena? Not a test;
## makes no assertions.
##
## A shut gate pulls the camera's far edge in to the wall, so the arena is
## framed and the wall lands on the right of the screen. A flyer holds a
## standoff of 340 to 470 from the player and backs AWAY when he gets closer
## than that, and nothing in features/combat/enemy.gd bounds its x — so a
## player who camps in the right-hand corner of a gated arena can in principle
## push the boss off the edge of his own fight.
##
## This walks the question rather than arguing it: park the player at the mouth,
## the middle and hard against the wall, run the fight, and count the frames
## the dragon's body was outside the visible 960.
##
##     <godot> --path godot --headless --script tests/diag_arena.gd
##     <godot> --path godot --headless --script tests/diag_arena.gd -- dragons_roost
const Game = preload("res://game/session.gd")

## How long to watch each station, in physics ticks. 900 is fifteen seconds,
## which is more than one full air phase and one full ground phase.
const WATCH := 900

var game: Node2D
var wyrm: Area2D

func _initialize() -> void:
	call_deferred("run")

func step() -> void:
	await physics_frame
	await process_frame

func watch(label: String, at: float) -> void:
	# The deck the boss took off from, which is the floor the fight happens on.
	game.player.position = Vector2(at, wyrm.home.y)
	game.player.velocity = Vector2.ZERO
	game.player.health = game.player.MAX_HEALTH
	wyrm.reset()
	wyrm.target = game.player
	wyrm.engaged = true
	await step()
	var off := 0
	var low := INF
	var high := -INF
	var furthest := 0.0
	for i in range(WATCH):
		await step()
		# Pinned: the question is what the dragon does about a player who does
		# not move, which is the worst case for a standoff.
		game.player.position.x = at
		game.player.health = game.player.MAX_HEALTH
		if not wyrm.alive():
			break
		low = minf(low, wyrm.position.x)
		high = maxf(high, wyrm.position.x)
		# Either edge. A standoff pushes it out through whichever side the
		# player is not on, so counting only the right would miss half of it.
		var past: float = maxf(
				wyrm.position.x - (game.camera.position.x + Game.VIEW_HALF.x),
				(game.camera.position.x - Game.VIEW_HALF.x) - wyrm.position.x)
		if past > 0.0:
			off += 1
			furthest = maxf(furthest, past)
	print("  %-22s x %6.0f..%-6.0f   off screen %3d/%d frames, worst %.0f px"
			% [label, low, high, off, WATCH, furthest])

func run() -> void:
	var level := "fractured_isles"
	for arg in OS.get_cmdline_user_args():
		level = arg
	game = Game.new()
	game.test_mode = true
	game.level_id = level
	root.add_child(game)
	game.start_session()
	game.player.test_control = true
	await step()
	for foe in game.enemies:
		if foe.is_boss():
			wyrm = foe
		else:
			foe.target = null
	if wyrm == null:
		print("%s has no boss" % level)
		quit()
		return
	var wall: float = float(game.gates.back()) if not game.gates.is_empty() else float(game.level.width)
	var mouth: float = wyrm.home.x - 690.0
	print("%s: boss at %.0f, wall at %.0f, arena %.0f wide"
			% [level, wyrm.home.x, wall, wall - mouth])
	await watch("at the mouth", mouth)
	await watch("mid arena", (mouth + wall) * 0.5)
	await watch("against the wall", wall - 20.0)
	quit()
