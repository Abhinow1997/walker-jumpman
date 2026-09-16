extends SceneTree
## The level pipeline: the catalogue, loading one level over another, and the
## menu that picks between them.
##
## Deliberately not about what is *in* a level — reachability and spacing are
## checked statically by scripts/check_levels.py, which does not need an engine.
## This is about the plumbing that lets there be more than one.
const Game = preload("res://game/session.gd")

var game: Node2D
var results: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func steps(n: int) -> void:
	for i in range(n):
		await physics_frame
		await process_frame

func check(id: String, passed: bool, observation: Dictionary) -> void:
	results.append({"id": id, "status": "PASS" if passed else "FAIL", "observed": observation})
	if not passed:
		failures += 1
	print(JSON.stringify(results.back()))

func _press(action: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event

func fresh(id: String = "") -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	game = Game.new()
	game.test_mode = true
	if id != "":
		game.level_id = id
	root.add_child(game)
	await steps(2)

func run() -> void:
	var order: Array = Game.catalogue()

	# --- the catalogue ------------------------------------------------------
	check("catalogue-is-ordered", order.size() >= 2 and order[0] == "first_steps",
		{"order": order})
	var titled := true
	var missing: Array = []
	for id in order:
		var data: Dictionary = Game.level_data(id)
		if data.is_empty() or not data.has("title"):
			titled = false
			missing.append(id)
	check("every-listed-level-loads", titled, {"missing": missing, "count": order.size()})

	# Every required key, for every level: a level missing one of these fails at
	# _build_world with a null dereference rather than saying what is wrong.
	for id in order:
		var data: Dictionary = Game.level_data(id)
		var keys := ["title", "width", "fall_y", "spawn", "solids", "hazards", "finish"]
		var absent: Array = []
		for key in keys:
			if not data.has(key):
				absent.append(key)
		check("schema-" + id, absent.is_empty(), {"missing_keys": absent})

	# --- defaults -----------------------------------------------------------
	await fresh()
	check("defaults-to-the-tutorial",
		game.level_id == "first_steps" and str(game.level.title) == "First Steps",
		{"level_id": game.level_id, "title": str(game.level.get("title", ""))})

	# --- booting straight into a level --------------------------------------
	await fresh("proving_ground")
	game.start_session()
	await steps(2)
	check("boots-into-a-named-level",
		str(game.level.title) == "Proving Ground" and game.state == Game.State.PLAYING,
		{"title": str(game.level.get("title", "")), "state": game.state})
	check("spawns-on-that-level's-ground", game.player.is_on_floor(),
		{"position": str(game.player.position)})

	# --- swapping a level in over another ------------------------------------
	await fresh()
	game.start_session()
	await steps(2)
	var before: float = float(game.level.width)
	var crates_before: int = game.crates.size()
	game.load_level("proving_ground")
	await steps(2)
	check("load_level-rebuilds-the-world",
		float(game.level.width) == 1280.0 and before == 1920.0,
		{"width_before": before, "width_after": float(game.level.width)})
	check("load_level-rebuilds-the-props",
		game.crates.size() == 1 and crates_before == 3,
		{"crates_before": crates_before, "crates_after": game.crates.size()})
	# The old level's solids must be gone, not merely invisible: a leftover
	# StaticBody2D from a 1920-wide level would be solid air in a 1280-wide one.
	var solids := 0
	for child in game.get_children():
		if child is StaticBody2D:
			solids += 1
	check("load_level-leaves-no-stale-geometry",
		solids == game.level.solids.size() + 2,
		{"bodies": solids, "expected": game.level.solids.size() + 2})
	check("load_level-returns-to-the-menu", game.state == Game.State.MENU,
		{"state": game.state})

	# --- chaining -----------------------------------------------------------
	await fresh()
	check("next-after-the-first", game.next_level_id() == order[1],
		{"next": game.next_level_id()})
	game.start_session()
	await steps(2)
	var advanced: bool = game.advance_level()
	await steps(2)
	check("finishing-loads-the-next",
		advanced and game.level_id == order[1] and game.state == Game.State.PLAYING,
		{"advanced": advanced, "level_id": game.level_id, "state": game.state})
	check("a-fresh-level-starts-on-zero",
		game.deaths == 0 and game.elapsed < 0.2,
		{"deaths": game.deaths, "elapsed": game.elapsed})

	await fresh(order[order.size() - 1])
	check("the-last-level-has-no-next", game.next_level_id() == "",
		{"level_id": game.level_id})
	game.start_session()
	await steps(2)
	check("the-last-level-cannot-advance", not game.advance_level(),
		{"level_id": game.level_id})

	# --- the menu -----------------------------------------------------------
	await fresh()
	game.open_menu()
	check("menu-opens-on-the-current-level", game.menu_index == 0 and game.state == Game.State.MENU,
		{"menu_index": game.menu_index, "state": game.state})
	game.menu_index = 1
	game.confirm()
	await steps(2)
	check("menu-starts-what-is-highlighted",
		game.level_id == order[1] and game.state == Game.State.PLAYING,
		{"level_id": game.level_id, "state": game.state})
	# Wraps rather than stopping: a dead key at each end of the list would be a
	# worse first impression than one that loops. Driven through the session's
	# own handler rather than repeating its arithmetic here, which is what the
	# first version of this check did - and it only passed because there were
	# two levels at the time.
	game.open_menu()
	game.menu_index = order.size() - 1
	game._unhandled_input(_press("menu_down"))
	check("the-list-wraps-forward", game.menu_index == 0, {"menu_index": game.menu_index})
	game._unhandled_input(_press("menu_up"))
	check("the-list-wraps-back", game.menu_index == order.size() - 1,
		{"menu_index": game.menu_index, "levels": order.size()})

	# --- themed levels ------------------------------------------------------
	# A theme swaps the whole world renderer, so the wrong answer here is a level
	# drawn twice or not at all rather than an error anything would report.
	await fresh("fractured_isles")
	check("a-themed-level-builds-its-scenery",
		is_instance_valid(game.scenery) and game.scenery.theme == "magic_cliffs",
		{"theme": str(game.level.get("theme", ""))})
	check("the-theme-art-is-imported", not game.scenery.pieces.is_empty(),
		{"pieces": game.scenery.pieces.size()})
	await fresh("first_steps")
	check("a-greybox-level-has-no-scenery", not is_instance_valid(game.scenery),
		{"theme": str(game.level.get("theme", ""))})

	# Tagged solids are still collision: the art a rectangle wears must not
	# change how many bodies the world has or where they are.
	await fresh("fractured_isles")
	var bodies := 0
	for child in game.get_children():
		if child is StaticBody2D:
			bodies += 1
	check("tagged-solids-are-still-solid", bodies == game.level.solids.size() + 2,
		{"bodies": bodies, "solids": game.level.solids.size()})

	var report := {"scope": "Level catalogue, loading and selection; not level content",
		"engine": Engine.get_version_info().string,
		"created_at": Time.get_datetime_string_from_system(true),
		"results": results, "failures": failures}
	var out := ProjectSettings.globalize_path("res://../evidence")
	DirAccess.make_dir_recursive_absolute(out)
	var file := FileAccess.open(out + "/levels-" + str(Time.get_unix_time_from_system()) + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("LEVEL TESTS: %d checks / %d failures" % [results.size(), failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
