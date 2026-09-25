extends SceneTree
## Diagnostic: what each level costs to run, side by side. Not a test; makes no
## assertions.
##
## Written to answer "why is First Steps laggier than the others", which decor
## counts and enemy counts both failed to explain — the Isles has more of both.
##
##     <godot> --path godot --headless --script tests/diag_levelcost.gd
##
## HEADLESS MEASURES SCRIPT AND PHYSICS, NOT DRAWING. There is no rendering
## server doing real work here, so a level that is slow because of what _draw
## lays down per frame will NOT show up in these numbers. Node counts and the
## physics step will. If every level looks the same here and one of them still
## stutters in a window, the cost is in drawing and this script cannot see it.

const Game = preload("res://game/session.gd")
const LEVELS := ["first_steps", "fractured_isles", "the_climb", "dragons_roost"]
const WARMUP := 30
const SAMPLE := 180

var game: Node2D

func _initialize() -> void:
	call_deferred("run")

func descendants(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		c += 1 + descendants(ch)
	return c

func run() -> void:
	print("level               nodes  enemies  decor  build_ms  step_ms  worst_ms")
	for id in LEVELS:
		if is_instance_valid(game):
			game.queue_free()
			await process_frame
		var t0 := Time.get_ticks_usec()
		game = Game.new()
		game.test_mode = true
		game.level_id = id
		root.add_child(game)
		game.start_session()
		var build_ms := float(Time.get_ticks_usec() - t0) / 1000.0
		game.player.test_control = true
		for i in WARMUP:
			await physics_frame
		var total := 0.0
		var worst := 0.0
		for i in SAMPLE:
			var s := Time.get_ticks_usec()
			await physics_frame
			var ms := float(Time.get_ticks_usec() - s) / 1000.0
			total += ms
			worst = maxf(worst, ms)
		var decor := 0
		if game.has_method("get") and game.level.has("decor"):
			decor = game.level["decor"].size()
		print("%-18s %6d %8d %6d %9.2f %8.3f %9.3f" % [
			id, descendants(game), game.enemies.size(), decor,
			build_ms, total / float(SAMPLE), worst])
	quit()
