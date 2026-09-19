extends SceneTree
## Diagnostic: the dip to black that covers a level change. Runs WITHOUT
## test_mode on purpose — that is the flag session.gd uses to skip the fade and
## swap immediately, so a test that set it would prove nothing here.
const Game = preload("res://game/session.gd")
var game: Node2D
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func step() -> void:
	await physics_frame
	await process_frame

func check(id: String, passed: bool, observed: Dictionary) -> void:
	if not passed:
		failures += 1
	print(JSON.stringify({"id": id, "status": "PASS" if passed else "FAIL",
						  "observed": observed}))

func run() -> void:
	var shipped: Array = Game.catalogue().duplicate()
	# A two-level course, so the dip has somewhere to land. The shipped order is
	# one level long and would replay instead of advancing.
	Game._catalogue = ["first_steps", "proving_ground"]

	game = Game.new()
	game.level_id = "first_steps"
	root.add_child(game)
	game.start_session()
	await step()
	check("clear-while-playing", is_zero_approx(game.fade_alpha()),
		{"alpha": game.fade_alpha()})

	game.state = Game.State.COMPLETE
	game.confirm()
	var started: String = game.level_id
	var peak := 0.0
	var swap_alpha := -1.0
	var swap_tick := -1
	var trace: Array = []
	for i in range(90):
		await step()
		var a: float = game.fade_alpha()
		peak = maxf(peak, a)
		if swap_tick < 0 and game.level_id != started:
			swap_tick = i
			swap_alpha = a
		if i % 5 == 0:
			trace.append(snappedf(a, 0.01))

	check("screen-reaches-full-black", peak > 0.98, {"peak": snappedf(peak, 0.01)})
	check("the-level-did-change", game.level_id == "proving_ground",
		{"level_id": game.level_id})
	check("swap-happened-behind-the-black", swap_alpha > 0.98,
		{"alpha_at_swap": snappedf(swap_alpha, 0.01), "tick": swap_tick})
	check("screen-comes-back", is_zero_approx(game.fade_alpha()),
		{"alpha": game.fade_alpha()})
	check("playing-again-after-the-dip", game.state == Game.State.PLAYING,
		{"state": game.state})
	print("alpha every 5 ticks: %s" % str(trace))

	# test_mode must still cut straight through, or every suite slows to a crawl.
	var quick := Game.new()
	quick.test_mode = true
	quick.level_id = "first_steps"
	root.add_child(quick)
	quick.start_session()
	quick.state = Game.State.COMPLETE
	quick.confirm()
	check("test_mode-swaps-with-no-fade",
		quick.level_id == "proving_ground" and is_zero_approx(quick.fade_alpha()),
		{"level_id": quick.level_id, "alpha": quick.fade_alpha()})

	Game._catalogue = shipped
	print("FADE DIAG: %d failure(s)" % failures)
	quit()
