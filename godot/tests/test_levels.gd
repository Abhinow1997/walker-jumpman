extends SceneTree
## The level pipeline: the catalogue, loading one level over another, and the
## menu that picks between them.
##
## Deliberately not about what is *in* a level — reachability and spacing are
## checked statically by scripts/check_levels.py, which does not need an engine.
## This is about the plumbing that lets there be more than one.
const Game = preload("res://game/session.gd")
const Music = preload("res://game/music.gd")
const Title = preload("res://ui/title.gd")

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

## Every level file on disk, course or not. The schema checks below use this
## rather than the catalogue: a level off the course is still shipped and still
## playable — First Steps is what PRACTICE boots — so it still has to load.
func all_levels() -> Array:
	var ids: Array = []
	for name in DirAccess.get_files_at("res://levels"):
		if name.ends_with(".json") and name != "index.json":
			ids.append(name.trim_suffix(".json"))
	ids.sort()
	return ids

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
	# The course is the themed level and nothing else: NEW JOURNEY boots
	# order[0], and it must not open on a greybox slice. first_steps and
	# proving_ground are still shipped and still reachable — see index.json and
	# the title screen's PRACTICE row — they are simply not the course.
	check("the-course-starts-in-the-isles",
		order.size() >= 1 and order[0] == "fractured_isles",
		{"order": order})
	check("no-greybox-on-the-course",
		not order.has("first_steps") and not order.has("proving_ground"),
		{"order": order})
	var shipped_ids: Array = all_levels()
	check("every-level-on-the-course-exists",
		not order.is_empty() and Array(order).all(func(id): return shipped_ids.has(id)),
		{"order": order, "on_disk": shipped_ids})
	var titled := true
	var missing: Array = []
	for id in shipped_ids:
		var data: Dictionary = Game.level_data(id)
		if data.is_empty() or not data.has("title"):
			titled = false
			missing.append(id)
	check("every-shipped-level-loads", titled,
		{"missing": missing, "count": shipped_ids.size()})

	# Every required key, for every level: a level missing one of these fails at
	# _build_world with a null dereference rather than saying what is wrong.
	for id in shipped_ids:
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
		solids == game.level.solids.size() + 2 + game.level.get("gates", []).size(),
		{"bodies": solids, "expected": game.level.solids.size() + 2,
		 "gates": game.level.get("gates", []).size()})
	check("load_level-returns-to-the-menu", game.state == Game.State.MENU,
		{"state": game.state})

	# --- chaining -----------------------------------------------------------
	# The shipped course is one level long, so there is nothing in it to chain
	# to. The chaining itself is still live code — a second course level is one
	# line in index.json — so the next few checks run against a stand-in order
	# rather than sit untested until the day somebody adds that line. Both ids
	# are real level files; only their membership of the course is pretend.
	var shipped: Array = order.duplicate()
	Game._catalogue = ["first_steps", "proving_ground"]

	await fresh()
	check("next-after-the-first", game.next_level_id() == "proving_ground",
		{"next": game.next_level_id()})
	game.start_session()
	await steps(2)
	var advanced: bool = game.advance_level()
	await steps(2)
	check("finishing-loads-the-next",
		advanced and game.level_id == "proving_ground" and game.state == Game.State.PLAYING,
		{"advanced": advanced, "level_id": game.level_id, "state": game.state})
	check("a-fresh-level-starts-on-zero",
		game.deaths == 0 and game.elapsed < 0.2,
		{"deaths": game.deaths, "elapsed": game.elapsed})

	# --- the menu -----------------------------------------------------------
	# Still on the stand-in order: a one-row list cannot show that the highlight
	# picks a level or that the ends wrap.
	await fresh()
	game.open_menu()
	check("menu-opens-on-the-current-level", game.menu_index == 0 and game.state == Game.State.MENU,
		{"menu_index": game.menu_index, "state": game.state})
	game.menu_index = 1
	game.confirm()
	await steps(2)
	check("menu-starts-what-is-highlighted",
		game.level_id == "proving_ground" and game.state == Game.State.PLAYING,
		{"level_id": game.level_id, "state": game.state})
	# Wraps rather than stopping: a dead key at each end of the list would be a
	# worse first impression than one that loops. Driven through the session's
	# own handler rather than repeating its arithmetic here, which is what the
	# first version of this check did - and it only passed because there were
	# two levels at the time.
	game.open_menu()
	var last: int = Game.catalogue().size() - 1
	game.menu_index = last
	game._unhandled_input(_press("menu_down"))
	check("the-list-wraps-forward", game.menu_index == 0, {"menu_index": game.menu_index})
	game._unhandled_input(_press("menu_up"))
	check("the-list-wraps-back", game.menu_index == last,
		{"menu_index": game.menu_index, "levels": Game.catalogue().size()})

	# Back to the real course, and the shape it actually has: one level, with
	# nothing after it, so finishing it replays rather than advancing.
	Game._catalogue = shipped
	await fresh(order[order.size() - 1])
	check("the-last-level-has-no-next", game.next_level_id() == "",
		{"level_id": game.level_id})
	game.start_session()
	await steps(2)
	check("the-last-level-cannot-advance", not game.advance_level(),
		{"level_id": game.level_id})

	# --- an off-course level -------------------------------------------------
	# First Steps is shipped and playable but not on the course, which the level
	# list only knows about. So it loads, it plays, and opening the list over it
	# highlights the course's first row rather than the level you are standing
	# in — there is no row for that level to highlight. Confirming then starts
	# the course, which is the only thing the list offers.
	await fresh("first_steps")
	game.start_session()
	await steps(2)
	check("an-off-course-level-still-plays",
		game.level_id == "first_steps" and game.state == Game.State.PLAYING
		and game.next_level_id() == "",
		{"level_id": game.level_id, "state": game.state})
	game.open_menu()
	check("the-list-cannot-highlight-an-off-course-level",
		game.menu_index == 0 and Game.catalogue()[game.menu_index] == "fractured_isles",
		{"menu_index": game.menu_index, "order": Game.catalogue()})

	# --- sections hold the player until the fight is over --------------------
	# The rule the Isles are built on: you do not walk past a fight. Checked on
	# the real level rather than a fixture, because the thing most likely to be
	# wrong is a gate on the wrong side of a chokepoint.
	await fresh("fractured_isles")
	game.start_session()
	# Parked, but alive: what is under test is the wall, and a bandit who beats
	# him back to the spawn mid-check measures nothing. Alive is what matters —
	# a parked enemy still holds its gate.
	for foe in game.enemies:
		foe.target = null
	await steps(2)
	var gate_count: int = game.gates.size()
	check("the-isles-are-in-four-sections", gate_count == 3,
		{"gates": game.gates})
	check("the-boss-platform-has-no-gate",
		game.section_of(float(game.level.finish[0])) == gate_count,
		{"section": game.section_of(float(game.level.finish[0]))})

	# Section one, unfought: the wall is solid and the camera is held back to it.
	game.player.position = Vector2(2100, 648)
	await steps(3)
	check("an-unfought-section-is-shut",
		not game.section_clear(0) and game.gate_shut_at() == float(game.gates[0]),
		{"clear": game.section_clear(0), "shut_at": game.gate_shut_at()})
	var limit: float = float(game.gates[0]) - Game.VIEW_HALF.x + Game.GATE_INSET
	check("the-camera-stops-at-the-shut-gate",
		game.camera.position.x <= limit + 0.5,
		{"camera_x": game.camera.position.x, "limit": limit})
	# Walked into the wall at full speed for a second. He has to end up against
	# it — reaching it and stopping, not dying or turning round somewhere short,
	# which would pass this check while proving nothing.
	game.player.test_control = true
	game.player.test_axis = 1.0
	await steps(60)
	check("the-wall-holds-him-in",
		game.player.position.x < float(game.gates[0])
		and game.player.position.x > float(game.gates[0]) - 80.0
		and game.state == Game.State.PLAYING,
		{"x": game.player.position.x, "gate": float(game.gates[0]),
		 "state": game.state})

	# The perches must not be what holds it, or nothing would ever open: they sit
	# 240 px up, and both the blast and the arrow fly flat.
	var perches := 0
	for foe in game.enemies:
		if not foe.holds_gate:
			perches += 1
	check("perched-enemies-hold-no-gate", perches == 6,
		{"perches": perches, "enemies": game.enemies.size()})

	# Clear it, and both the wall and the camera let go. The walk key goes up
	# first: left held down he strolls through the moment it opens, into the next
	# section's fight and then the pit past it, and every check below reads a
	# player who is somewhere else entirely.
	game.player.test_axis = 0.0
	for foe in game.section_holders(0):
		while foe.alive():
			foe.take_hit(60, foe.position - Vector2(40, 0))
			await steps(2)
	await steps(3)
	check("clearing-a-section-opens-it",
		game.section_clear(0) and game.section_of(game.player.position.x) == 0
		and game.gate_shut_at() == INF,
		{"clear": game.section_clear(0), "shut_at": game.gate_shut_at(),
		 "section": game.section_of(game.player.position.x)})
	game.player.position = Vector2(2100, 648)
	game.player.velocity = Vector2.ZERO
	await steps(2)
	check("still-on-his-feet-to-be-walked",
		game.state == Game.State.PLAYING, {"state": game.state})
	# Watched for rather than sampled at the end: the pit is 37 px past the open
	# gate, so a player left walking is dead and back at the spawn within the
	# second, and the last frame of a 60-step walk says nothing about the gate.
	game.player.test_axis = 1.0
	var crossed := false
	for i in range(60):
		await steps(1)
		if game.player.position.x > float(game.gates[0]):
			crossed = true
			break
	game.player.test_axis = 0.0
	check("he-walks-on-once-it-is-clear", crossed,
		{"x": game.player.position.x, "gate": float(game.gates[0]),
		 "state": game.state})

	# A retry puts the enemies back up, so the gate has to shut again on its own.
	game.restart_attempt()
	await steps(4)
	check("a-retry-shuts-the-gate-again",
		not game.section_clear(0) and game.gate_shut_at() == float(game.gates[0]),
		{"clear": game.section_clear(0), "shut_at": game.gate_shut_at()})

	# A level with no gates is untouched by any of this.
	await fresh("first_steps")
	game.start_session()
	await steps(2)
	check("a-level-with-no-gates-is-never-held",
		game.gates.is_empty() and game.gate_shut_at() == INF,
		{"gates": game.gates, "shut_at": game.gate_shut_at()})

	# --- music follows the level --------------------------------------------
	# A level names its own track and the title screen names the same one, which
	# is what makes NEW JOURNEY seamless: the node lives under the tree root, so
	# it outlives the scene swap, and cueing a track already playing is a no-op.
	check("the-title-and-the-isles-name-one-track",
		Title.TRACK == str(Game.level_data("fractured_isles").get("music", "")),
		{"title": Title.TRACK,
		 "level": str(Game.level_data("fractured_isles").get("music", ""))})

	await fresh("fractured_isles")
	var music: Node = root.get_node_or_null(Music.NODE)
	check("a-themed-level-cues-its-music",
		music != null and music.playing and music.track == "magic_cliffs"
		and music.stream != null and music.stream.loop,
		{"playing": music != null and music.playing,
		 "track": "" if music == null else music.track,
		 "loop": music != null and music.stream != null and music.stream.loop})
	# It has to be the one node, not one per session: every fresh() above built
	# a session, and a music player per session would be a stack of them all
	# playing the same loop slightly out of step.
	var players := 0
	for child in root.get_children():
		if child is AudioStreamPlayer:
			players += 1
	check("there-is-only-one-music-node", players == 1, {"players": players})

	# Cued again, it must not start over. Measured on the playback clock: the
	# dummy audio driver a headless run uses still advances it.
	await steps(20)
	var was: float = music.get_playback_position()
	Music.cue(self, "magic_cliffs")
	await steps(1)
	check("cueing-the-track-again-does-not-restart-it",
		music.get_playback_position() >= was and was > 0.0,
		{"position": music.get_playback_position(), "was": was})

	# A level with no music of its own stops it rather than carrying the wrong
	# track into a greybox slice.
	game.load_level("first_steps")
	await steps(3)
	check("a-level-with-no-music-is-silent",
		not music.playing and music.track == "",
		{"playing": music.playing, "track": music.track})
	Music.hush(self)

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
	# The two end walls, plus one wall per section gate. Spelled out rather than
	# loosened to >=: the point of the check is that a themed level builds no
	# geometry a greybox one would not, and a wall nobody asked for is exactly
	# what it is here to catch.
	var expected: int = game.level.solids.size() + 2 + game.level.get("gates", []).size()
	check("tagged-solids-are-still-solid", bodies == expected,
		{"bodies": bodies, "expected": expected,
		 "solids": game.level.solids.size(), "gates": game.gates.size()})

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
