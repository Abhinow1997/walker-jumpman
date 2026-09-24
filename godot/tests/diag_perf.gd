extends SceneTree
## Throwaway diagnostic: run first_steps with the archer firing and watch for a
## node leak (arrows piling up) or a slow physics step. Delete after use.
const Game = preload("res://game/session.gd")

var game: Node2D

func _initialize() -> void:
	call_deferred("run")

func steps(n: int) -> void:
	for i in range(n):
		await physics_frame
		await process_frame

func descendants(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		c += 1 + descendants(ch)
	return c

func run() -> void:
	game = Game.new()
	game.test_mode = true
	game.level_id = "first_steps"
	root.add_child(game)
	game.start_session()
	game.player.test_control = true
	await steps(3)
	# Stand the player in the archer's firing range so he shoots repeatedly, and
	# arm everyone as in real play.
	var hunter: Area2D = null
	for e in game.enemies:
		e.target = game.player
		if e.kind == "hunter":
			hunter = e
	if hunter:
		hunter.position = Vector2(1120, 640); hunter.home = hunter.position
	game.player.position = Vector2(900, 640)

	print("phase          | phys_ms")
	var a := await _avg_phys(300)
	print("with-enemies   | %.3f" % a)
	# Now silence the enemies' per-frame work and re-measure, to isolate their cost.
	for e in game.enemies:
		e.set_physics_process(false)
	var b := await _avg_phys(300)
	print("enemies-frozen | %.3f" % b)
	print("DIAG DONE")

func _avg_phys(n: int) -> float:
	var total := 0.0
	for i in range(n):
		await physics_frame
		await process_frame
		total += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	return total / float(n) * 1000.0
	game.queue_free()
	await process_frame
	quit(0)
