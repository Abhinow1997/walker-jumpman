extends SceneTree
## Diagnostic: does The Climb actually climb? Not a test; makes no assertions.
##
## Walks a driven player up the whole tower one hop at a time, reporting what
## the ratcheting view and the moving fatal line are doing under him, then
## answers the three questions a climb raises that no other level does:
##
##   * does the view ever come back down (it must not)
##   * does the fatal line ever pass the ledge he is standing on (it must not)
##   * do the shafts drop stones where the level says they do
##
##     <godot> --path godot --headless --script tests/diag_ratchet.gd
##
## The climb is driven by teleport rather than by keys. A run that has to JUMP
## eighteen 120 px gaps in a row fails on the first one and tells you nothing
## about the seventeen above it; putting him on each ledge in turn asks the
## question this script is actually about, which is what the camera and the
## fatal line do as he gets there.
const Game = preload("res://game/session.gd")

var game: Node2D

func _initialize() -> void:
	call_deferred("run")

func step() -> void:
	await physics_frame
	await process_frame

## Every ledge, bottom first.
func ledges() -> Array:
	var out: Array = []
	for entry in game.level.solids:
		out.append([float(entry[0]), float(entry[1]), float(entry[2])])
	out.sort_custom(func(a, b): return a[1] > b[1])
	return out

func run() -> void:
	game = Game.new()
	game.test_mode = true
	game.level_id = "the_climb"
	root.add_child(game)
	await step()
	game.start_session()
	await step()

	print("The Climb: climb=%s  width=%d  fall_y=%d  sources=%d"
			% [game.climbing, int(game.level.width), int(game.level.fall_y),
			   game.level.get("rockfall", []).size()])
	print("camera pins at x %.0f (a level this wide leaves it nothing to do)"
			% game.camera.position.x)
	print("")
	print("  ledge          feet      view    fatal line   margin   stones")

	var lowest_view: float = -INF   # the largest y the camera has ever sat at
	var worst_margin: float = INF
	var descended := false
	for pad in ledges():
		# Put him on the middle of the ledge and let him settle onto it.
		game.player.position = Vector2(pad[0] + pad[2] / 2.0, pad[1] - 4.0)
		game.player.velocity = Vector2.ZERO
		for _i in 14:
			await physics_frame
		var view: float = game.camera.position.y
		var fatal: float = game.fatal_y()
		var margin: float = fatal - game.player.position.y
		worst_margin = minf(worst_margin, margin)
		if view > lowest_view + 0.5 and lowest_view > -INF:
			descended = true
			print("    *** the view came back DOWN to %.0f from %.0f"
					% [view, lowest_view])
		lowest_view = maxf(lowest_view, view)
		print("  y %-7.0f  %7.0f  %7.0f     %8.0f   %6.0f   %d"
				% [pad[1], game.player.position.y, view, fatal, margin,
				   game.stones.size()])

	print("")
	print("view only ever rose: %s" % [not descended])
	print("closest the fatal line came to his feet: %.0f px" % worst_margin)

	# --- the shafts ---------------------------------------------------------
	# Park him low in the tower and let the clock run, so the sources within a
	# screen of him have time to let go of something.
	print("")
	print("shafts, with him standing on the shore at y 648:")
	game.restart_attempt()
	await step()
	var seen: Dictionary = {}
	for _i in 420:
		await physics_frame
		for stone in game.stones:
			if is_instance_valid(stone):
				seen[int(round(stone.position.x))] = true
	print("  lanes that dropped something: %s" % [seen.keys()])

	print("")
	print("and with him on p13, three quarters of the way up:")
	game.player.position = Vector2(414, -344)
	for _i in 10:
		await physics_frame
	seen = {}
	var lowest_stone: float = -INF
	for _i in 420:
		await physics_frame
		for stone in game.stones:
			if is_instance_valid(stone):
				seen[int(round(stone.position.x))] = true
				lowest_stone = maxf(lowest_stone, stone.position.y)
	print("  lanes that dropped something: %s" % [seen.keys()])
	print("  furthest a stone got down the tower: y %.0f" % lowest_stone)

	# --- the punks stay put -------------------------------------------------
	print("")
	print("enemies, after ten seconds of chasing him across the shafts:")
	game.restart_attempt()
	await step()
	var home: Array = []
	for foe in game.enemies:
		home.append(foe.position)
	for _i in 600:
		await physics_frame
	for i in game.enemies.size():
		var foe = game.enemies[i]
		print("  %-8s started (%.0f, %.0f) now (%.0f, %.0f) alive=%s"
				% [foe.kind, home[i].x, home[i].y, foe.position.x,
				   foe.position.y, foe.alive()])

	# --- the archers actually shoot -----------------------------------------
	# Four of the seven are hunters, and they are the only enemy on this
	# mountain that can reach him at all: he is below them and out of arm's
	# reach for almost the whole level. Worth measuring rather than assuming,
	# because an archer who never fires is a decoration. He is parked a band
	# under each one, which is where a climber meets it.
	# Where can an archer actually REACH from a shelf? Not straight down: the
	# arrow leaves 34 above his feet, so a steep shot crosses the top of the
	# very ledge he is stood on and buries itself in it within a few pixels.
	# The shot has to be shallow enough to clear his own lip, which makes the
	# threatening position a diagonal one - and a switchback climb spends most
	# of its time diagonally below something. This sweeps the offsets to say
	# which of them actually cost health.
	print("")
	print("what an archer can reach, held at each offset for eight seconds:")
	var archer = null
	for foe in game.enemies:
		if foe.kind == "hunter":
			archer = foe
			break
	if archer == null:
		quit()
		return
	print("  (hunter at %.0f, %.0f)" % [archer.position.x, archer.position.y])
	for below in [0.0, 80.0, 160.0, 240.0, 320.0]:
		var row := "  %4.0f below: " % below
		for across in [60.0, 140.0, 220.0, 300.0, 380.0]:
			game.restart_attempt()
			await step()
			var spot: Vector2 = archer.position + Vector2(-across, below)
			game.player.position = spot
			game.player.velocity = Vector2.ZERO
			var before: int = game.player.health
			for _i in 480:
				# Pinned: this is a question about the archer, not about him.
				game.player.position = spot
				game.player.velocity = Vector2.ZERO
				await physics_frame
			row += "%4.0f across -%-3d  " % [across, before - game.player.health]
		print(row)
	quit()
