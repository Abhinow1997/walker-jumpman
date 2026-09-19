extends SceneTree
## Diagnostic: which of a level's own gaps can each enemy kind leap? Not a test;
## makes no assertions. Walks every kind up to every hole in the floor and says
## whether it crossed or held the lip.
##
## The arithmetic is in enemy.gd — reach is leap_speed * air_time(), less the
## stride he stops short by and the bit he aims past the far lip — but a number
## does not tell you whether the far side is higher, or whether there is a rock
## in the way. This runs it on the real course.
##
##     <godot> --path godot --headless --script tests/diag_gaps.gd
##     <godot> --path godot --headless --script tests/diag_gaps.gd -- proving_ground
##
## The enemy chases a bare Node2D rather than the player: it has a position to
## walk toward and nothing else, so nobody takes damage, nobody dies, and a
## failed attempt cannot restart the attempt and quietly reset every position
## the probe is measuring.
const Game = preload("res://game/session.gd")
const Enemy = preload("res://features/combat/enemy.gd")
const KINDS := ["bandit", "mark", "hunter"]

var game: Node2D

func _initialize() -> void:
	call_deferred("run")

func step() -> void:
	await physics_frame
	await process_frame

## The floor's top surface at a column, or INF. Same question enemy.gd asks.
func surface_at(x: float, top: float, bottom: float) -> float:
	var query := PhysicsRayQueryParameters2D.create(
		Vector2(x, top), Vector2(x, bottom), 1)
	query.collide_with_areas = false
	var hit := game.get_world_2d().direct_space_state.intersect_ray(query)
	return INF if hit.is_empty() else float(hit.position.y)

## Every hole in the floor, found by walking the level rather than by reading the
## solids: [near lip x, far lip x, near top y, far top y].
func holes(width: float, floor_y: float) -> Array:
	var found: Array = []
	var x := 24.0
	var last := surface_at(x, -200.0, floor_y)
	while x < width - 24.0:
		var here := surface_at(x, -200.0, floor_y)
		if here == INF and last != INF:
			# A lip. Find the far side.
			var near_y := last
			var near_x := x - 12.0
			var y := x
			while y < width - 24.0:
				var over := surface_at(y, near_y - 200.0, near_y + 200.0)
				if over != INF:
					found.append([near_x, y, near_y, over])
					break
				y += 12.0
			if y >= width - 24.0:
				found.append([near_x, width, near_y, INF])
		last = here
		x += 12.0
	return found

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
	for parked in game.enemies:
		parked.target = null
	# Out of everyone's way, and off the route so he cannot fall down a hole.
	game.player.position = Vector2(game.player.position.x, -2000.0)

	var mark := Node2D.new()
	game.add_child(mark)

	var width := float(game.level.get("width", 4096))
	var floor_y := float(game.level.get("fall_y", 1000))
	var gaps := holes(width, floor_y)
	print("%s: %d gap(s)" % [level, gaps.size()])
	for kind in KINDS:
		var reach := 0.0
		for g in gaps:
			var near_x: float = g[0]
			var far_x: float = g[1]
			var near_y: float = g[2]
			var far_y: float = g[3]
			if far_y == INF:
				continue
			# Stand him back from the lip on the SAME floor. A fixed offset is not
			# good enough — on this course 80 px back from one lip is inside the
			# previous hole, and an enemy who starts in a pit reads as an enemy
			# who walked into one.
			var stand := near_x
			var back := 12.0
			while back <= 120.0:
				if absf(surface_at(near_x - back, near_y - 40.0, near_y + 8.0) - near_y) < 2.0:
					stand = near_x - back
				else:
					break
				back += 12.0
			if stand == near_x:
				print("  %-7s gap %6.0f..%-6.0f  no run-up: skipped" % [kind, near_x, far_x])
				continue
			var foe := Enemy.new()
			foe.kind = kind
			foe.position = Vector2(stand, near_y)
			foe.fall_limit = floor_y
			game.add_child(foe)
			await step()
			reach = foe.leap_speed * foe.air_time()
			mark.position = Vector2(far_x + 60.0, far_y)
			foe.target = mark
			foe.engaged = true
			var across := false
			for i in range(500):
				await physics_frame
				if foe.grounded and foe.position.x > far_x:
					across = true
					break
				if not foe.alive():
					break
			print("  %-7s gap %6.0f..%-6.0f %5.0f px wide, %+4.0f px rise: %s" % [
				kind, near_x, far_x, far_x - near_x, near_y - far_y,
				"CROSSED" if across else ("FELL IN" if not foe.alive() else "held the lip")])
			foe.queue_free()
			await step()
		print("  %-7s air travel %.0f px, so about %.0f px of flat gap\n" % [
			kind, reach, reach - 38.0])
	quit()
