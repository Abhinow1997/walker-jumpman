extends SceneTree
## The level pipeline: the catalogue, loading one level over another, and the
## menu that picks between them.
##
## Deliberately not about what is *in* a level — reachability and spacing are
## checked statically by scripts/check_levels.py, which does not need an engine.
## This is about the plumbing that lets there be more than one.
const Game = preload("res://game/session.gd")
const Enemy = preload("res://features/combat/enemy.gd")
const Music = preload("res://game/music.gd")
const Title = preload("res://ui/title.gd")
const Portal = preload("res://features/world/portal.gd")

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

func clear_foes_but_boss() -> void:
	## Everything before the boss put down, which is what a player who reached
	## its arena would have done. Its own gate is left to it.
	for foe in game.enemies:
		if is_instance_valid(foe) and not foe.is_boss():
			foe.health = 0
	await steps(4)

func clear_foes() -> void:
	## Empties the level of everyone who could interrupt. Used by the prompt
	## checks, which are about what the HUD says and not about a fight.
	for foe in game.enemies:
		foe.queue_free()
	game.enemies.clear()

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

	# --- the catalogue and the list -----------------------------------------
	# Two lists, and the difference between them is the point. `order` is the
	# COURSE: what NEW JOURNEY walks through, opening on the practice course and
	# carrying on into the Isles. listing() is what LOAD GAME OFFERS, which is
	# every level that ships — you may pick one that is on the way to nowhere.
	check("a-new-journey-opens-on-the-practice-course",
		order.size() >= 2 and order[0] == "first_steps"
		and order[1] == "fractured_isles",
		{"order": order})
	var rows: Array = Game.listing()
	# also_listed is empty now — Proving Ground was the only level off the course
	# and it has been removed — so the list is EXACTLY the course. The mechanism
	# that appends off-course extras is still live (see listing()); it just has
	# nothing to append.
	check("the-list-is-exactly-the-course",
		rows == Array(order),
		{"listing": rows, "order": order})
	check("the-course-comes-first-in-the-list",
		rows.slice(0, order.size()) == Array(order),
		{"listing": rows, "order": order})
	# The fixture is not content and must never be offered as any.
	check("the-fixture-is-not-on-the-list",
		not rows.has("greybox") and not order.has("greybox"),
		{"listing": rows})
	# The real chain rather than the stand-in one further down: the course is
	# four levels long now, so reaching the flag on each really does load the
	# next, and that is the thing a new journey is.
	await fresh("first_steps")
	check("first-steps-leads-into-the-isles",
		game.next_level_id() == "fractured_isles",
		{"next": game.next_level_id(), "order": Game.catalogue()})
	await fresh("fractured_isles")
	check("the-isles-lead-up-the-climb",
		game.next_level_id() == "the_climb",
		{"next": game.next_level_id(), "order": Game.catalogue()})
	await fresh("the_climb")
	check("and-the-climb-leads-to-the-roost",
		game.next_level_id() == "dragons_roost",
		{"next": game.next_level_id(), "order": Game.catalogue()})
	# And the Roost is the end of it. Nothing follows the final boss, so
	# finishing it replays it — see confirm() on State.COMPLETE.
	await fresh("dragons_roost")
	check("the-roost-is-the-end-of-the-course",
		game.next_level_id() == "" and order.back() == "dragons_roost",
		{"next": game.next_level_id(), "last": order.back()})
	# The Climb is on the course and not also in the list beside it: `order`
	# then `also_listed` minus what is already in it, so nothing appears twice.
	check("the-climb-is-on-the-course-once",
		order.count("the_climb") == 1 and Game.listing().count("the_climb") == 1,
		{"order": order, "listing": Game.listing()})
	# A level not on the course chains to nothing. The greybox fixture is the only
	# shipped level off the course now, so it stands in for the rule.
	await fresh("greybox")
	check("a-level-off-the-course-leads-nowhere",
		game.next_level_id() == "",
		{"next": game.next_level_id()})
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
	# The fixture, not a level anyone plays: both title-screen rows name the
	# level they want, so nothing but a test ever reaches this default.
	check("defaults-to-the-fixture",
		game.level_id == "greybox" and str(game.level.title) == "Greybox",
		{"level_id": game.level_id, "title": str(game.level.get("title", ""))})

	# --- booting straight into a level --------------------------------------
	await fresh("first_steps")
	game.start_session()
	await steps(2)
	check("boots-into-a-named-level",
		str(game.level.title) == "First Steps" and game.state == Game.State.PLAYING,
		{"title": str(game.level.get("title", "")), "state": game.state})
	check("spawns-on-that-level's-ground", game.player.is_on_floor(),
		{"position": str(game.player.position)})

	# --- swapping a level in over another ------------------------------------
	await fresh()
	game.start_session()
	await steps(2)
	var before: float = float(game.level.width)
	var crates_before: int = game.crates.size()
	game.load_level("the_climb")
	await steps(2)
	check("load_level-rebuilds-the-world",
		float(game.level.width) == 960.0 and before == 1920.0,
		{"width_before": before, "width_after": float(game.level.width)})
	check("load_level-rebuilds-the-props",
		game.crates.size() == 4 and crates_before == 3,
		{"crates_before": crates_before, "crates_after": game.crates.size()})
	# The old level's solids must be gone, not merely invisible: a leftover
	# StaticBody2D from a 1920-wide level would be solid air in a 1280-wide one.
	var solids := 0
	for child in game.get_children():
		if child is StaticBody2D:
			solids += 1
	var want_bodies: int = (game.level.solids.size() + 2
			+ game.level.get("gates", []).size()
			+ (1 if is_instance_valid(game.seal_wall) else 0))
	check("load_level-leaves-no-stale-geometry", solids == want_bodies,
		{"bodies": solids, "expected": want_bodies,
		 "gates": game.level.get("gates", []).size(),
		 "arena_wall": is_instance_valid(game.seal_wall)})
	check("load_level-returns-to-the-menu", game.state == Game.State.MENU,
		{"state": game.state})

	# --- the way out ---------------------------------------------------------
	# What stands in the goal is a node of its own now — features/world/portal.gd,
	# a lit stone over the finish — rather than a pennant drawn on the session's
	# canvas, because it moves and that canvas is redrawn once per level. So it
	# has to be built with the level and go with it: two of them after a swap is
	# the last level's exit still hanging in this one.
	var portals: Array = []
	for child in game.get_children():
		if child.get_script() == Portal:
			portals.append(child)
	check("one-way-out-per-level",
		portals.size() == 1 and game.portal == portals[0],
		{"found": portals.size()})
	check("and-it-stands-in-the-goal",
		game.portal.position == Portal.stand_at(game.level.finish),
		{"at": game.portal.position,
		 "want": Portal.stand_at(game.level.finish),
		 "finish": game.level.finish})
	# Added before the player, so he walks INTO the light rather than behind it.
	check("with-the-player-in-front-of-it",
		game.player.get_index() > game.portal.get_index(),
		{"portal": game.portal.get_index(), "player": game.player.get_index()})

	# The whole of it has to be in shot from its own foot line: it is the thing
	# the level ends on and a player standing under it must be able to see it.
	# Measured rather than asserted, because the room above his feet is a
	# consequence of CAMERA_DEADZONE and CAMERA_RECENTRE easing the camera onto
	# him, not a constant anybody wrote down.
	await fresh("first_steps")
	game.start_session()
	await steps(2)
	var foot: Vector2 = Portal.stand_at(game.level.finish)
	# Beside the marker, not in it: standing in it finishes the level.
	game.player.position = Vector2(foot.x - 60.0, foot.y - 4.0)
	game.player.velocity = Vector2.ZERO
	for _i in 40:
		await physics_frame
	await steps(2)
	var crown: float = foot.y - Portal.DROP - Portal.STONE.y - Portal.BOB
	var sky_line: float = game.camera.position.y - 270.0
	check("the-whole-of-it-is-in-shot-from-its-own-foot",
		game.state == Game.State.PLAYING and crown > sky_line,
		{"marker_top": crown, "screen_top": sky_line, "state": game.state})

	# --- the prompts ---------------------------------------------------------
	# One level teaches. `hints` turns on the cue over a thing you can lift,
	# throw or drink AND the level's own `coach` lines; every other level leaves
	# it out and shows neither, because a game still naming keys on its third
	# level has not taught them.
	var teaching: Array = []
	var dead_coaching: Array = []
	for id in shipped_ids:
		var data: Dictionary = Game.level_data(id)
		if bool(data.get("hints", false)):
			teaching.append(id)
		elif not Array(data.get("coach", [])).is_empty():
			dead_coaching.append(id)
	check("first-steps-is-the-only-level-that-prompts",
		teaching == ["first_steps"], {"teaching": teaching})
	# `hints` gates the coach lines too, so a level carrying them without it has
	# authored data that never appears — which looks like working content in the
	# file and is not.
	check("and-nobody-carries-coaching-that-can-never-show",
		dead_coaching.is_empty(), {"levels": dead_coaching})

	await fresh("first_steps")
	game.start_session()
	await steps(2)
	# Beside the rock at 1524, which stands inside the bandit's coach span —
	# the one place a lesson and an action cue are up together. The bandit
	# himself is lifted out: a player in hurt-stun lifts nothing, and these
	# checks are about prompts rather than about being punched.
	clear_foes()
	game.player.position = Vector2(1498.0, 644.0)
	game.player.velocity = Vector2.ZERO
	for _i in 40:
		await physics_frame
	await steps(2)
	var rock: Node2D = game.carryable_in_reach()
	check("there-is-a-rock-in-reach-to-cue", rock != null,
		{"at": game.player.position})
	# The claim the whole redesign rests on: the plate is centred on the THING,
	# not on the screen. It used to be a line of text at a fixed x whatever it
	# was about, so with two crates in reach it could not say which.
	var over_rock: Rect2 = game.hud.cue_box(rock.global_position, "E", "LIFT",
			game.hud.CUE_OVER_PROP)
	var rock_at: Vector2 = game.to_hud(rock.global_position)
	check("a-prompt-stands-over-the-thing-it-is-about",
		absf(over_rock.get_center().x - rock_at.x) < 1.0
		and over_rock.end.y < rock_at.y
		and Rect2(0.0, 0.0, 640.0, 360.0).encloses(over_rock),
		{"cue": over_rock, "rock": rock_at})
	# And it is held inside the frame wherever the thing is. Measured against a
	# point far off the left of the screen, which is what a prop behind him is.
	var off: Rect2 = game.hud.cue_box(
			game.player.position - Vector2(4000.0, 0.0), "E", "LIFT",
			game.hud.CUE_OVER_PROP)
	check("and-is-kept-in-frame-when-the-thing-is-not",
		Rect2(0.0, 0.0, 640.0, 360.0).encloses(off), {"cue": off})

	# It arrives rather than pops. The fade is what keeps a prompt from
	# flashing on the frame you step into range, and a fade that never finished
	# would be a prompt nobody ever saw — so both ends are checked.
	var cold: float = game.hud._cue_fade("probe", "lift")
	for _i in 20:
		await physics_frame
	var warm: float = game.hud._cue_fade("probe", "lift")
	check("a-prompt-fades-in-and-gets-all-the-way-there",
		cold < 0.2 and warm == 1.0, {"first_frame": cold, "settled": warm})

	# Lifting the rock must not retire the line telling him J is a fist. The
	# pick-up runs on the attack machinery, so it counted as a swing and did —
	# the prompt that told him to pick the rock up took the next lesson away.
	# See NOT_A_SWING in features/player/player.gd.
	check("the-fist-lesson-is-still-owed", not game.hud._coached("strike"),
		{"attacks": game.player.attacks_thrown})
	var lifted: bool = game.pick_up()
	for _i in 40:
		await physics_frame
	await steps(2)
	check("lifting-a-rock-is-not-throwing-a-punch",
		lifted and game.player.is_carrying()
		and not game.hud._coached("strike"),
		{"lifted": lifted, "carrying": game.player.is_carrying(),
		 "attacks": game.player.attacks_thrown,
		 "coached": game.hud._coached("strike")})
	# Throwing it IS pressing J at something, so that one does retire it.
	game.player.begin_throw()
	for _i in 30:
		await physics_frame
	check("but-throwing-it-is", game.hud._coached("strike"),
		{"attacks": game.player.attacks_thrown})

	# Nothing is cued on any other level, with the same rock in reach.
	await fresh("fractured_isles")
	game.start_session()
	await steps(2)
	var isle_rock: Node2D = null
	for prop in game.crates:
		isle_rock = prop
		break
	game.player.position = Vector2(isle_rock.position.x - 26.0,
			isle_rock.position.y - 4.0)
	game.player.velocity = Vector2.ZERO
	for _i in 40:
		await physics_frame
	await steps(2)
	check("and-no-level-but-the-first-cues-anything",
		game.carryable_in_reach() != null and not game.hud.teaches(),
		{"in_reach": game.carryable_in_reach() != null,
		 "teaches": game.hud.teaches()})

	# --- the jump, at the first pit -----------------------------------------
	# The first thing the game asks anyone to do. A gap does mime the jump, but
	# it mimes it while you are standing on the lip of a fall, so the lesson
	# runs from x240 to the edge and retires on the first jump he ever makes.
	var lines: Array = Game.level_data("first_steps").get("coach", [])
	var pit_x := 549.0
	check("the-jump-is-taught-before-the-first-pit",
		lines.size() == 3 and str(lines[0][3]) == "jump"
		# After the spawn, so the level does not open with a plate on his head;
		# up to the lip, which is a few px past where the pit starts because
		# that is where he can still stand; and nothing on the far side.
		and float(lines[0][0]) > float(Game.level_data("first_steps").spawn[0])
		and float(lines[0][0]) < pit_x
		and float(lines[0][1]) >= pit_x
		and float(lines[0][1]) < 684.0,
		{"line": lines[0] if not lines.is_empty() else [], "pit": pit_x})
	await fresh("first_steps")
	game.start_session()
	await steps(2)
	game.player.position = Vector2(440.0, 644.0)
	game.player.velocity = Vector2.ZERO
	for _i in 30:
		await physics_frame
	check("and-is-owed-until-he-makes-one",
		not game.hud._coached("jump") and game.player.jumps == 0,
		{"jumps": game.player.jumps})
	game.player.test_control = true
	game.player.test_jump_pressed = true
	for _i in 6:
		await physics_frame
	game.player.test_jump_pressed = false
	for _i in 40:
		await physics_frame
	check("then-never-again",
		game.player.jumps > 0 and game.hud._coached("jump"),
		{"jumps": game.player.jumps})

	# --- the two bars name themselves ---------------------------------------
	# Nothing explains the bars otherwise: the numbers beside them say how much
	# of something without saying of what.
	await fresh("first_steps")
	game.start_session()
	await steps(2)
	check("no-bar-is-named-for-nothing", game.hud.bar_lesson() == "",
		{"named": game.hud.bar_lesson()})
	# Drinking names the bar that bottle pours into — the milk at 2028 is
	# health, and the brew further on would be mana on the same rule.
	clear_foes()
	game.player.health = game.player.MAX_HEALTH - 40
	game.player.position = Vector2(2008.0, 644.0)
	game.player.velocity = Vector2.ZERO
	for _i in 40:
		await physics_frame
	var took: bool = game.pick_up()
	for _i in 40:
		await physics_frame
	var sipping: bool = game.drink()
	for _i in 10:
		await physics_frame
	check("drinking-names-the-bar-it-is-filling",
		took and sipping and game.player.is_drinking()
		and game.hud.bar_lesson() == "health",
		{"drinking": game.player.is_drinking(),
		 "named": game.hud.bar_lesson()})
	# Beside the bar and past its number, not over either — the bars are in
	# the corner and there is nothing above them to hang a plate from.
	var beside: Rect2 = game.hud.bar_cue_box(
			game.hud.bar_rect("health"), "HEALTH")
	var green: Rect2 = game.hud.bar_rect("health")
	check("and-stands-clear-of-the-bar-and-its-number",
		beside.position.x > green.end.x + 30.0
		and absf(beside.get_center().y - green.get_center().y) < 1.0
		and Rect2(0.0, 0.0, 640.0, 360.0).encloses(beside),
		{"cue": beside, "bar": green})
	check("and-the-two-bars-are-where-the-meters-draw-them",
		game.hud.bar_rect("mana").position
			== game.hud.bar_rect("health").position
				+ Vector2(0.0, game.hud.BAR_STEP),
		{"health": game.hud.bar_rect("health"),
		 "mana": game.hud.bar_rect("mana")})

	# The first blast names the other one, once.
	await fresh("first_steps")
	game.start_session()
	await steps(2)
	check("mana-is-not-named-before-any-is-spent",
		game.hud.bar_lesson() == "" and game.player.blasts_thrown == 0,
		{"named": game.hud.bar_lesson()})
	game.player.test_control = true
	game.player.test_blast_pressed = true
	for _i in 12:
		await physics_frame
	game.player.test_blast_pressed = false
	for _i in 12:
		await physics_frame
	check("the-first-blast-names-the-mana-bar",
		game.player.blasts_thrown == 1 and game.hud.bar_lesson() == "mana",
		{"blasts": game.player.blasts_thrown, "named": game.hud.bar_lesson()})
	# And it goes, for good. BLAST_HOLD is 2.4s; 180 ticks is three.
	for _i in 180:
		await physics_frame
	var spent: String = game.hud.bar_lesson()
	game.player.test_blast_pressed = true
	for _i in 12:
		await physics_frame
	game.player.test_blast_pressed = false
	for _i in 12:
		await physics_frame
	check("and-says-it-once-however-many-more-he-throws",
		spent == "" and game.hud.bar_lesson() == ""
		and game.player.blasts_thrown > 1,
		{"after_hold": spent, "now": game.hud.bar_lesson(),
		 "blasts": game.player.blasts_thrown})

	# --- chaining -----------------------------------------------------------
	# The shipped course is one level long, so there is nothing in it to chain
	# to. The chaining itself is still live code — a second course level is one
	# line in index.json — so the next few checks run against a stand-in order
	# rather than sit untested until the day somebody adds that line. Both ids
	# are real level files; only their membership of the course is pretend.
	var shipped: Array = order.duplicate()
	Game._catalogue = ["first_steps", "the_climb"]

	# Named rather than left to the default: the default is the fixture, and the
	# fixture is deliberately not a row on any course, pretend or otherwise. Both
	# ids are real level files; only the two-level chain between them is a stand-in
	# for the real course.
	await fresh("first_steps")
	check("next-after-the-first", game.next_level_id() == "the_climb",
		{"next": game.next_level_id()})
	game.start_session()
	await steps(2)
	var advanced: bool = game.advance_level()
	await steps(2)
	check("finishing-loads-the-next",
		advanced and game.level_id == "the_climb" and game.state == Game.State.PLAYING,
		{"advanced": advanced, "level_id": game.level_id, "state": game.state})
	# A second, not the fifth of one this used to allow. The point of the check
	# is that the clock and the death count belong to the level rather than to
	# the session, and any small number proves that; the old bound was really
	# measuring how fast the next level builds. steps() waits on PROCESS frames
	# and each one covers up to eight physics ticks, so a heavier level to load
	# means more of them inside the same two steps — and The Climb, at 48 solids
	# and 19 rock sources, was enough to put 13 ticks where 12 used to fit.
	check("a-fresh-level-starts-on-zero",
		game.deaths == 0 and game.elapsed < 1.0,
		{"deaths": game.deaths, "elapsed": game.elapsed})

	# --- the menu -----------------------------------------------------------
	# Still on the stand-in order: a one-row list cannot show that the highlight
	# picks a level or that the ends wrap.
	await fresh("first_steps")
	game.open_menu()
	check("menu-opens-on-the-current-level", game.menu_index == 0 and game.state == Game.State.MENU,
		{"menu_index": game.menu_index, "state": game.state})
	game.menu_index = 1
	game.confirm()
	await steps(2)
	check("menu-starts-what-is-highlighted",
		game.level_id == "the_climb" and game.state == Game.State.PLAYING,
		{"level_id": game.level_id, "state": game.state})
	# Wraps rather than stopping: a dead key at each end of the list would be a
	# worse first impression than one that loops. Driven through the session's
	# own handler rather than repeating its arithmetic here, which is what the
	# first version of this check did - and it only passed because there were
	# two levels at the time.
	game.open_menu()
	# The MENU's list, not the course. It wraps on listing(), which is the course
	# plus everything else the index offers, and taking the last row off
	# catalogue() only ever agreed with that while every also_listed id already
	# happened to be in the stand-in course above. The first one that was not
	# turned this wrap into an ordinary step down the list - the same bug the
	# comment above describes, one layer up.
	var last: int = Game.listing().size() - 1
	game.menu_index = last
	game._unhandled_input(_press("menu_down"))
	check("the-list-wraps-forward", game.menu_index == 0, {"menu_index": game.menu_index})
	game._unhandled_input(_press("menu_up"))
	check("the-list-wraps-back", game.menu_index == last,
		{"menu_index": game.menu_index, "rows": Game.listing().size()})

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

	# --- picking a level from the list ---------------------------------------
	# Loading a level, playing it, and opening the menu highlights the row you are
	# actually standing in. Shown on the last course level, which chains to nothing
	# once it is beaten — the same "leads nowhere" an off-course level used to show
	# here before Proving Ground was removed.
	await fresh("dragons_roost")
	game.start_session()
	await steps(2)
	check("a-picked-level-plays-and-leads-nowhere",
		game.level_id == "dragons_roost" and game.state == Game.State.PLAYING
		and game.next_level_id() == "",
		{"level_id": game.level_id, "state": game.state})
	game.open_menu()
	# --- the menu wears the kit's own plates ---------------------------------
	# Its buttons used to be flat rectangles in the kit's green, because every
	# plate on the sheet has a word baked into it and the confirm button says
	# four different things. scripts/extract_panels.py lifts the word off and
	# keeps the plate, and hud.gd draws it in three slices so the rounded ends
	# never stretch. See the buttons section of ui/art/PROVENANCE.md.
	var plates: Dictionary = game.hud.buttons
	check("the-buttons-wear-the-kits-plates",
		plates.size() >= 2 and plates.has("btn_go") and plates.has("btn_plain")
		and plates["btn_go"]["tex"] != null
		and float(plates["btn_go"]["cap"]) > 0.0,
		{"plates": plates.keys(),
		 "cap": plates["btn_go"]["cap"] if plates.has("btn_go") else -1.0})
	# The caps have to be small enough to leave something to stretch: the
	# plate is 118 wide in design units against buttons of 160 and 170, and a
	# cap of more than half of it would leave no middle at all.
	var button: Rect2 = game.hud.button_rect()
	check("and-there-is-a-middle-left-to-stretch",
		float(plates["btn_go"]["cap"]) * 0.5 * 2.0 < button.size.x
		and button.size.x > float(plates["btn_go"]["size"].x) * 0.5,
		{"cap": plates["btn_go"]["cap"], "button": button.size,
		 "plate": plates["btn_go"]["size"]})
	# --- the pause screen is a menu ------------------------------------------
	# It used to be two buttons and a line of prose: "R: restart attempt    M:
	# main menu", which is a keyboard-only instruction sitting next to two
	# things you can click, under a rule sheet reading "One jump. No double
	# jump. Unlimited retries." on the one screen you open when you already
	# know the rules. All four actions are plates in one row now.
	game.confirm()
	await steps(4)
	game.set_paused(true)
	await steps(2)
	var slots: Array[Rect2] = []
	for i in range(4):
		slots.append(game.hud.pause_slot(i))
	var laid_out := true
	for i in range(4):
		if slots[i].size.x <= 0.0 or slots[i].position.x < 0.0 \
				or slots[i].end.x > 640.0 or slots[i].end.y > 360.0:
			laid_out = false
		if i > 0 and slots[i].position.x < slots[i - 1].end.x:
			laid_out = false          # they must not overlap, or a click is a lottery
	check("the-pause-screen-lays-four-plates-in-a-row",
		game.state == Game.State.PAUSED and laid_out
		and slots[0] == game.hud.button_rect()
		and slots[1] == game.hud.restart_rect()
		and slots[2] == game.hud.menu_rect()
		and slots[3] == game.hud.music_rect(),
		{"slots": slots, "state": game.state})
	# One size for the whole row, and it has to actually fit: the long label
	# ran off both ends of its plate when the row went from two at 170 to four
	# at 140.
	var labels: Array = ["ENTER  /  RESUME", "R  /  RESTART", "M  /  MAIN MENU",
			"N  /  MUSIC OFF"]
	var fitted: int = game.hud.label_size(labels, slots[0].size.x)
	var widest := 0.0
	for label in labels:
		widest = maxf(widest, ThemeDB.fallback_font.get_string_size(
				str(label), HORIZONTAL_ALIGNMENT_LEFT, -1, fitted).x)
	check("and-one-label-size-that-fits-every-one-of-them",
		fitted >= game.hud.BUTTON_TEXT_MIN and widest <= slots[0].size.x,
		{"size": fitted, "widest_label": widest, "plate": slots[0].size.x})

	# The two that used to be prose are clicks now. What can go wrong with a
	# click is that two rects claim the same point — the session tests them in
	# one chain and the first match wins, so an overlap makes a click a
	# lottery. Each centre has to belong to exactly one of them.
	#
	# (The click itself is not driven here: the session reads the pointer off
	# hud.get_local_mouse_position() rather than off the event, and a headless
	# run has no pointer to warp. The chain in _unhandled_input is three lines
	# and the same shape the music toggle has had all along.)
	var claims := 0
	var stray := false
	for i in range(4):
		var centre: Vector2 = slots[i].get_center()
		var hits := 0
		for j in range(4):
			if slots[j].has_point(centre):
				hits += 1
		if hits != 1:
			stray = true
		if game.hud.row_at(centre) >= 0:
			stray = true          # the level list must not claim them either
		claims += hits
	check("every-plate-in-the-row-owns-its-own-clicks",
		claims == 4 and not stray, {"claims": claims, "overlapping": stray})

	# And off the pause screen none of them is anywhere, which is what stops a
	# click landing on a button that is not drawn.
	game.open_menu()
	await steps(2)
	check("the-row-is-nowhere-when-the-game-is-not-paused",
		game.state != Game.State.PAUSED
		and game.hud.restart_rect().size.x == 0.0
		and game.hud.menu_rect().size.x == 0.0
		and game.hud.music_rect().size.x == 0.0,
		{"state": game.state, "restart": game.hud.restart_rect(),
		 "menu": game.hud.menu_rect()})

	check("the-list-highlights-the-level-you-are-in",
		Game.listing()[game.menu_index] == "dragons_roost",
		{"menu_index": game.menu_index, "listing": Game.listing()})
	# And picking a row from the list plays it.
	game.menu_index = Game.listing().find("dragons_roost")
	game.confirm()
	await steps(6)
	check("the-list-can-start-the-picked-level",
		game.level_id == "dragons_roost",
		{"level_id": game.level_id, "state": game.state})

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
	check("the-isles-are-in-five-sections", gate_count == 4,
		{"gates": game.gates})
	# The last of the four is the one the boss stands behind, and it is the
	# whole reason it is there: the Dragon Lord used to block the way to the
	# flag with his body, and the dragon that replaced him flies 156 over your
	# head and blocks nothing at all, so without a wall the level could be
	# finished by running underneath it. Checked as three facts rather than as
	# a number, so moving the arena does not silently void it.
	var boss_home: float = -1.0
	for foe in game.enemies:
		if foe.is_boss():
			boss_home = foe.home.x
	var boss_section: int = game.section_of(boss_home)
	var flag_section: int = game.section_of(float(game.level.finish[0]))
	check("the-dragon-cannot-be-run-past",
		boss_home > 0.0 and boss_section < gate_count
		and game.section_holders(boss_section).size() == 1
		and flag_section > boss_section,
		{"boss_at": boss_home, "boss_section": boss_section,
		 "holders": game.section_holders(boss_section).size(),
		 "flag_section": flag_section})

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

	# Every "perch"-marked enemy is flagged perched and DOES hold its gate now —
	# the contract changed: they must be cleared like anyone else, they just start
	# out of reach on a shelf, snipe down into the fight, and come DOWN once the
	# ground below them is clear (see perched/descend in enemy.gd). Counted against
	# the level file, so it is about the rule and not the roster.
	var marked := 0
	for entry in game.level.enemies:
		if entry.size() > 3 and str(entry[3]) == "perch":
			marked += 1
	var perched := 0
	var perched_all_gate := true
	for foe in game.enemies:
		if foe.perched:
			perched += 1
			if not foe.holds_gate:
				perched_all_gate = false
	check("perch-enemies-are-flagged-and-hold-gate",
		marked > 0 and perched == marked and perched_all_gate,
		{"perched": perched, "marked_in_level": marked, "hold_gate": perched_all_gate,
		 "enemies": game.enemies.size()})

	# Clear it, and both the wall and the camera let go. The walk key goes up
	# first: left held down he strolls through the moment it opens, into the next
	# section's fight and then the pit past it, and every check below reads a
	# player who is somewhere else entirely.
	game.player.test_axis = 0.0
	# Watched tick by tick, because the thing under test is one frame wide. He is
	# standing against the wall, which is where a fight backed into a gate always
	# ends, so the far bound has the furthest possible distance to travel when it
	# lets go — about 570 px, which is what the camera used to cross in a single
	# frame the instant the last enemy fell.
	var worst_jump := 0.0
	var camera_was: float = game.camera.position.x
	for foe in game.section_holders(0):
		while foe.alive():
			foe.take_hit(60, foe.position - Vector2(40, 0))
			for _t in range(8):
				await physics_frame
				worst_jump = maxf(worst_jump, absf(game.camera.position.x - camera_was))
				camera_was = game.camera.position.x
	for _t in range(90):
		await physics_frame
		worst_jump = maxf(worst_jump, absf(game.camera.position.x - camera_was))
		camera_was = game.camera.position.x
	# A pan, not a cut. The release moves at most 2300 px/s, so 38 px in a tick;
	# following a running player is 6. The cut it replaced was 570 in one.
	check("an-opening-gate-pans-rather-than-cuts",
		worst_jump < 60.0,
		{"worst_px_in_one_tick": worst_jump,
		 "camera_x": game.camera.position.x})
	check("and-the-pan-finishes",
		game.camera.position.x > float(game.gates[0]) - Game.VIEW_HALF.x,
		{"camera_x": game.camera.position.x,
		 "was_held_at": float(game.gates[0]) - Game.VIEW_HALF.x + Game.GATE_INSET})
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

	# And the wall at the end is real, which is the whole point of adding it:
	# run at the flag with the dragon alive and you stop short of it. Parked
	# rather than fought, like the bandits above — what is under test is the
	# wall, and a dragon that knocks him off the deck mid-walk measures nothing.
	await fresh("fractured_isles")
	game.start_session()
	for foe in game.enemies:
		foe.target = null
	game.player.test_control = true
	game.player.position = Vector2(7000.0, 660.0)
	game.player.velocity = Vector2.ZERO
	await steps(3)
	game.player.test_axis = 1.0
	await steps(150)
	game.player.test_axis = 0.0
	var wall: float = float(game.gates.back())
	check("the-flag-cannot-be-reached-past-the-dragon",
		game.player.position.x < wall
		and game.player.position.x > wall - 80.0
		and float(game.level.finish[0]) > wall
		and game.state == Game.State.PLAYING,
		{"x": game.player.position.x, "wall": wall,
		 "finish": game.level.finish[0], "state": game.state})

	# --- the story cards around the dragon -----------------------------------
	# The Isles hold two panels: the standoff as he steps onto the Archway, and
	# the dragon leaving once it is beaten. Run with test_mode OFF, which is
	# the flag that collapses a card to its effect the same way it collapses
	# the level-swap fade — a suite that left it on would be checking the
	# shortcut instead of the thing.
	await fresh("fractured_isles")
	game.test_mode = false
	game.start_session()
	var card_x: float = float(game.level.cutscene[0].at)
	var wyrm: Area2D = null
	for foe in game.enemies:
		if foe.is_boss():
			wyrm = foe
	check("the-isles-hold-two-story-cards",
		game.story_cards.size() == 2 and wyrm != null
		and game.story_cards[0]["tex"] != null
		and game.story_cards[1]["tex"] != null
		and str(game.level.cutscene[1].after) == "boss_down",
		{"cards": game.story_cards.size(), "at": card_x,
		 "boss": wyrm != null})
	# Each card holds for as long as its own clip, not for a number written in
	# session.gd. Ten seconds of narration behind a 2.6 s default would be cut
	# off half way through it.
	check("a-card-holds-for-as-long-as-its-clip",
		game.story_cards[0]["voice"] != null
		and game.story_cards[0]["tail"] != null
		and game.story_cards[1]["voice"] != null
		and float(game.story_cards[0]["hold"]) > Game.STORY_HOLD + 4.0,
		{"hold": game.story_cards[0]["hold"],
		 "clip": game.story_cards[0]["voice"].get_length(),
		 "default": Game.STORY_HOLD})

	# Short of the line, on the deck. Nothing yet — and the dragon has not
	# noticed him either, which is the point of putting the line outside its
	# aggro: the picture is what starts the fight, not the walk in.
	#
	# 6900, not further back: the last hop into the Archway lands at 6888 and
	# everything behind that is the 36 px of open sea he crossed to get here.
	game.player.position = Vector2(card_x - 60.0, 660.0)
	game.player.velocity = Vector2.ZERO
	await steps(6)
	check("no-card-before-the-line",
		not game.story_running() and game.story_alpha() == 0.0
		and not game.story_layer.visible and not wyrm.engaged,
		{"alpha": game.story_alpha(), "engaged": wyrm.engaged,
		 "gap": wyrm.position.x - game.player.position.x})

	# Walked over it.
	game.player.test_control = true
	game.player.test_axis = 1.0
	for i in range(40):
		await steps(1)
		if game.story_running():
			break
	check("crossing-the-line-brings-the-card-up",
		game.story_running() and game.story_layer.visible
		and game.story_art.texture == game.story_cards[0]["tex"]
		and game.player.position.x >= card_x,
		{"x": game.player.position.x, "at": card_x,
		 "alpha": game.story_alpha()})
	# The subtitle under it, on the same scrim and in the same column the
	# opening's captions use. One line held for the whole card, and only on the
	# card that has one — the second is a picture of the dragon leaving and
	# there is nobody left to say anything about it.
	check("the-standoff-carries-its-line",
		game.story_line.visible
		and game.story_line.text == str(game.level.cutscene[0].caption)
		and game.story_line.text.contains("drake")
		and str(game.story_cards[1]["line"]) == "",
		{"line": game.story_line.text, "shown": game.story_line.visible,
		 "end_card": game.story_cards[1]["line"]})
	check("and-the-line-sits-inside-the-screen",
		game.story_line.position.y > 380.0
		and game.story_line.position.y + game.story_line.size.y <= 540.0
		and is_equal_approx(game.story_line.size.x, Game.VIEW_HALF.x * 2.0),
		{"top": game.story_line.position.y,
		 "bottom": game.story_line.position.y + game.story_line.size.y,
		 "width": game.story_line.size.x})

	# And the level's loop is pushed under the voice rather than stopped: a
	# stopped track restarts from the top and seams either side of the card.
	var loop: AudioStreamPlayer = root.get_node_or_null(Music.NODE)
	check("the-music-ducks-under-it-rather-than-stopping",
		Music.ducked and loop != null and loop.stream != null
		and str(loop.track) == str(game.level.music),
		{"ducked": Music.ducked,
		 "track": str(loop.track) if loop != null else "<no node>"})

	# And the level stops under it. He is still holding right and the dragon is
	# still alive; neither of them moves, and the level clock does not run.
	var held_x: float = game.player.position.x
	var wyrm_x: float = wyrm.position.x
	var clock_was: float = game.elapsed
	await steps(20)
	check("the-level-stops-while-it-is-up",
		is_equal_approx(game.player.position.x, held_x)
		and is_equal_approx(wyrm.position.x, wyrm_x)
		and is_equal_approx(game.elapsed, clock_was),
		{"player_moved": game.player.position.x - held_x,
		 "dragon_moved": wyrm.position.x - wyrm_x,
		 "clock_ran": game.elapsed - clock_was})

	# Out the other side: he has his legs back, the dragon is already up, and
	# the loop is back at its own level.
	for i in range(1200):
		await steps(1)
		if not game.story_running():
			break
	check("the-card-goes-and-the-fight-is-on",
		not game.story_running() and not game.story_layer.visible
		and game.player.enabled and wyrm.engaged and not Music.ducked,
		{"visible": game.story_layer.visible,
		 "enabled": game.player.enabled, "engaged": wyrm.engaged,
		 "ducked": Music.ducked})
	# And the track changes with it. The boss loop is named in the level and
	# picked by current_track(), which is asked every tick rather than cued
	# once — the next block leans on that.
	await steps(2)
	check("the-fight-brings-its-own-track-in",
		game.current_track() == str(game.level.boss_music)
		and str(loop.track) == str(game.level.boss_music)
		and str(game.level.boss_music) != str(game.level.music),
		{"want": game.current_track(), "playing": str(loop.track),
		 "level": str(game.level.music)})

	# Once a visit. Walked back off the line and over it again, and then a
	# retry, which puts every enemy back on its feet: neither brings it back.
	game.player.test_axis = 0.0
	game.player.position = Vector2(card_x - 60.0, 660.0)
	await steps(8)
	game.player.position = Vector2(card_x + 40.0, 660.0)
	await steps(8)
	var stayed_down: bool = not game.story_running()
	game.restart_attempt()
	await steps(8)
	check("it-plays-once-a-visit-and-not-on-a-retry",
		stayed_down and not game.story_running()
		and bool(game.story_cards[0]["seen"]),
		{"recrossed": not stayed_down, "after_retry": game.story_running(),
		 "seen": game.story_cards[0]["seen"]})

	# --- and the one at the end of the fight ---------------------------------
	# The order the level is built around: beaten, it FALLS, the card plays
	# over the body on the deck, and only then does it get up and fly out.
	# Checked as that order rather than as three separate facts, because the
	# order is the thing that was asked for.
	game.player.position = Vector2(card_x + 200.0, 660.0)
	game.player.velocity = Vector2.ZERO
	await steps(4)
	var _beaten: bool = wyrm.take_hit(wyrm.health, Vector2(card_x, 660.0))
	await physics_frame
	await physics_frame
	check("beating-it-is-not-yet-the-end-card",
		not wyrm.alive() and wyrm.visible and not wyrm.fallen()
		and not game.story_running(),
		{"alive": wyrm.alive(), "fallen": wyrm.fallen(),
		 "running": game.story_running()})
	# And the battle track goes with the killing blow. The two seconds it lies
	# there, the card and the climb out are the aftermath, and the level's own
	# loop is the bed for all three.
	check("the-battle-track-ends-with-the-fight",
		game.current_track() == str(game.level.music)
		and game.boss() == wyrm,
		{"track": game.current_track(), "plate_still_up": game.boss() == wyrm})
	# It stays down for two seconds. Counted in physics ticks rather than
	# steps(), because one step() covers up to eight of them and the whole
	# point of this check is the length of the beat.
	var down_ticks := 0
	while not wyrm.fallen() and down_ticks < 600:
		await physics_frame
		down_ticks += 1
	var down_secs: float = down_ticks / 60.0
	check("it-stays-down-for-two-seconds",
		absf(down_secs - Enemy.DOWN_TIME) < 0.3
		and absf(wyrm.position.y - 660.0) < 12.0,
		{"down_for": down_secs, "want": Enemy.DOWN_TIME,
		 "height_off_the_deck": 660.0 - wyrm.position.y})
	for i in range(600):
		await steps(1)
		if game.story_running():
			break
	# On the deck, not in the air, and still there: the picture is of it
	# leaving and it goes over the moment before it leaves.
	check("the-card-comes-up-when-it-has-finished-falling",
		game.story_running() and wyrm.visible
		and game.story_art.texture == game.story_cards[1]["tex"]
		and not game.player.enabled,
		{"running": game.story_running(), "body": wyrm.visible,
		 "on_the_deck": absf(wyrm.position.y - 660.0) < 40.0,
		 "enabled": game.player.enabled})
	# And it stays down under the picture — the freeze holds the departure as
	# well as the player.
	var lay_at: Vector2 = wyrm.position
	await steps(20)
	check("and-the-body-stays-down-while-it-plays",
		wyrm.position.is_equal_approx(lay_at) and game.story_running(),
		{"moved": wyrm.position - lay_at})
	for i in range(1200):
		await steps(1)
		if not game.story_running():
			break
	# The way on is still SHUT here: the body is on the deck and a boss holds
	# its wall until it is gone, which is what stops a player running out
	# through the ending. See section_clear.
	check("and-the-level-comes-back-with-the-wall-still-holding",
		not game.story_running() and game.player.enabled
		and game.gate_shut_at() < INF and not Music.ducked,
		{"enabled": game.player.enabled, "shut_at": game.gate_shut_at(),
		 "ducked": Music.ducked})
	# Then it leaves. The fly-away is the second half of the death and it runs
	# after the picture, not under it.
	var left: bool = false
	for i in range(900):
		await steps(1)
		if not wyrm.visible:
			left = true
			break
	check("and-then-it-flies-away",
		left and wyrm.position.y < lay_at.y - 100.0,
		{"gone": left, "climbed": lay_at.y - wyrm.position.y})
	# And with the body gone the plate goes too — it is the one thing that
	# outlasts the track, because an empty bar under a departing dragon is
	# what it is for.
	await steps(4)
	check("and-the-plate-and-the-wall-go-with-the-body",
		game.boss() == null and game.current_track() == str(game.level.music)
		and game.gate_shut_at() == INF,
		{"boss": game.boss() != null, "track": game.current_track(),
		 "shut_at": game.gate_shut_at()})

	# --- the arena shuts behind you -----------------------------------------
	# A boss fight is the one place walking back is blocked. Ordinary gates only
	# ever stop you going on, because a wall behind you in a fight takes away
	# the room you need — but the dragon is fenced into its arena, so a player
	# who walked west out of it stood somewhere it could not follow and the
	# fight simply stopped happening. See boss_arena in the level file.
	var walled: Array = []
	var bossed: Array = []
	for id in shipped_ids:
		var data: Dictionary = Game.level_data(id)
		if data.has("boss_arena"):
			walled.append(id)
		for entry in data.get("enemies", []):
			var kind := str(entry[2]) if entry.size() > 2 else "bandit"
			if bool(Enemy.PROFILES.get(kind, {}).get("boss", false)):
				if not bossed.has(id):
					bossed.append(id)
	walled.sort()
	bossed.sort()
	check("every-level-with-a-boss-says-where-its-arena-starts",
		not bossed.is_empty() and walled == bossed,
		{"sealed": walled, "with_a_boss": bossed})

	await fresh("fractured_isles")
	game.start_session()
	await steps(2)
	var arena_x: float = game.arena_line()
	var arena_boss: Node2D = null
	for foe in game.enemies:
		if foe.is_boss():
			arena_boss = foe
	# Inside its own section and behind every boss, or the wall would either
	# do nothing or shut the fight out of its own arena.
	var arena_box: Vector2 = game.section_bounds(game.section_of(arena_boss.home.x))
	check("and-the-line-is-inside-the-boss-section-and-behind-it",
		arena_x > arena_box.x and arena_x < arena_box.y and arena_boss.home.x > arena_x,
		{"line": arena_x, "section": arena_box, "boss": arena_boss.home.x})
	check("the-wall-is-built-and-open-before-the-fight",
		is_instance_valid(game.seal_wall) and not game.sealed
		and game.seal_wall.collision_layer == 0 and game.seal_at == arena_x,
		{"sealed": game.sealed, "at": game.seal_at})
	# Both of them are shut into the SAME room, which is the other half of it:
	# fenced to the section, the dragon could back out over the chasm the
	# player is now walled off from and off the side of the screen.
	check("and-the-dragon-is-fenced-to-the-same-room",
		arena_boss.fly_bounds == game.arena_of(arena_boss)
		and arena_boss.fly_bounds.x == arena_x,
		{"fence": arena_boss.fly_bounds, "arena": game.arena_of(arena_boss)})

	await clear_foes_but_boss()
	game.player.position = Vector2(arena_x + 48.0, 600.0)
	game.player.velocity = Vector2.ZERO
	for _i in 40:
		await physics_frame
	game._wake_boss()
	await steps(2)
	check("it-shuts-once-the-fight-is-on-and-he-is-inside",
		game.sealed and game.seal_wall.collision_layer == 1
		and arena_boss.engaged,
		{"sealed": game.sealed, "engaged": arena_boss.engaged,
		 "at": game.player.position.x})
	# Four seconds of holding left, which is 1280 px of intent against a wall
	# 48 away. Stopping at his own half-width past it is the wall working.
	game.player.test_control = true
	game.player.test_axis = -1.0
	var arena_west := INF
	for _i in 240:
		await physics_frame
		if game.state != Game.State.PLAYING:
			break
		arena_west = minf(arena_west, game.player.position.x)
	game.player.test_axis = 0.0
	check("and-he-cannot-walk-back-out-of-it",
		arena_west > arena_x and arena_west < arena_x + 24.0 and game.state == Game.State.PLAYING,
		{"furthest_west": arena_west, "wall": arena_x, "state": game.state})
	# The camera stops against it the way it stops against a gate, so he can
	# see he has run out of screen rather than out of floor.
	check("and-the-camera-stops-against-the-wall",
		absf((game.camera.position.x - 480.0)
				- (arena_x - game.GATE_INSET)) < 1.0,
		{"screen_left": game.camera.position.x - 480.0,
		 "want": arena_x - game.GATE_INSET})
	# And it opens again when the body is gone — the flag is past the gate at
	# 7800 and therefore outside the arena, so it has to.
	arena_boss.take_hit(arena_boss.health, game.player.global_position)
	for _i in 900:
		await physics_frame
		if game.boss() == null:
			break
	await steps(4)
	check("and-opens-again-when-the-fight-is-over",
		not game.sealed and game.seal_wall.collision_layer == 0
		and float(game.level.finish[0]) > arena_x,
		{"sealed": game.sealed, "flag": game.level.finish[0]})

	# --- and the Roost, which fights two of them -----------------------------
	# Its line is 816, the lip of the middle deck and the first ground past the
	# only gap in the level. NOT 1512, the lip of the deck the two bosses stand
	# on — which is where deriving the line from the deck would have put it,
	# and which leaves the west floating stone at 1188 outside its own fight.
	# Those two stones are the only way to reach the flying boss.
	await fresh("dragons_roost")
	game.start_session()
	await steps(2)
	var roost_line: float = game.arena_line()
	var roost_wing: Node2D = null
	var lord: Node2D = null
	for foe in game.enemies:
		if foe.is_flyer():
			roost_wing = foe
		elif foe.is_boss():
			lord = foe
	check("the-roost-seals-behind-both-of-its-bosses",
		roost_line == 816.0 and is_instance_valid(game.seal_wall)
		and roost_wing.home.x > roost_line and lord.home.x > roost_line,
		{"line": roost_line, "flyer": roost_wing.home.x,
		 "lord": lord.home.x})
	var perches: Array = []
	for entry in game.level.solids:
		if entry.size() > 4 and str(entry[4]) == "island_large":
			perches.append(float(entry[0]))
	perches.sort()
	check("and-keeps-both-perches-inside-the-room",
		perches.size() == 2 and perches[0] > roost_line
		and perches[0] < 1512.0,
		{"perches": perches, "line": roost_line})
	check("and-fences-its-flyer-to-the-same-room",
		roost_wing.fly_bounds == game.arena_of(roost_wing)
		and roost_wing.fly_bounds.x == roost_line,
		{"fence": roost_wing.fly_bounds})

	# Sealed the same way, and it holds against the same push.
	await clear_foes_but_boss()
	game.player.position = Vector2(roost_line + 48.0, 600.0)
	game.player.velocity = Vector2.ZERO
	for _i in 40:
		await physics_frame
	game._wake_boss()
	await steps(2)
	game.player.test_control = true
	game.player.test_axis = -1.0
	var roost_west := INF
	for _i in 240:
		await physics_frame
		if game.state != Game.State.PLAYING:
			break
		roost_west = minf(roost_west, game.player.position.x)
	game.player.test_axis = 0.0
	check("and-he-cannot-walk-back-across-the-gap",
		game.sealed and roost_west > roost_line
		and roost_west < roost_line + 24.0,
		{"furthest_west": roost_west, "wall": roost_line,
		 "sealed": game.sealed})

	# --- what the last fight is worth ---------------------------------------
	# Two bosses back to back, so their numbers are set against each other and
	# not one at a time. The Lord is the wall — 1500, twenty-five clean hits of
	# the jumped kick at 60, the biggest bar in the game — and the dragon over
	# him is 1140, nineteen, set BY THE LEVEL rather than by the kind. Two
	# 1500s back to back would make the last level longer than the one before
	# it rather than harder.
	await fresh("dragons_roost")
	game.start_session()
	await steps(2)
	var worth := {}
	var roost_wyrm: Area2D = null
	for foe in game.enemies:
		if foe.is_boss():
			worth[foe.kind] = foe.max_health
			if foe.is_flyer():
				roost_wyrm = foe
	check("the-last-fight-is-a-wall-and-a-harasser",
		int(worth.get("dragon_lord", 0)) == 1500
		and int(worth.get("dragon", 0)) == 1140
		and int(game.level.enemy_health["dragon"]) == 1140,
		{"health": worth, "level_says": game.level.enemy_health})
	# max_health and not health, so a retry — which puts every enemy back on
	# its feet — puts the same bar back rather than the profile's.
	var _cut: bool = roost_wyrm.take_hit(600, game.player.global_position)
	roost_wyrm.reset()
	check("and-a-retry-puts-that-same-bar-back",
		roost_wyrm.health == 1140 and roost_wyrm.max_health == 1140,
		{"health": roost_wyrm.health, "max": roost_wyrm.max_health})

	# And the same kind is the profile's own number on the level that fights it
	# alone: the override belongs to the Roost, not to dragons.
	await fresh("fractured_isles")
	game.start_session()
	await steps(2)
	var isles_wyrm: Area2D = null
	for foe in game.enemies:
		if foe.is_boss():
			isles_wyrm = foe
	check("and-the-isles-dragon-is-untouched-by-it",
		isles_wyrm.max_health == int(Enemy.PROFILES["dragon"]["health"])
		and isles_wyrm.max_health == 1500
		and not Game.level_data("fractured_isles").has("enemy_health"),
		{"isles": isles_wyrm.max_health,
		 "profile": Enemy.PROFILES["dragon"]["health"]})

	# --- beaten over the water -----------------------------------------------
	# The way the ending used to be lost. A flyer holds a standoff of 340 to
	# 470 and backs away from a player who crowds it, so whenever the player
	# is at the left end of the Archway the dragon is out over the gap — and
	# a dragon beaten there fell past fall_y, was deleted by _integrate, and
	# took the departure card with it. Measured before the fix: gone in 1.15 s
	# and no card ever. It now glides back to the nearest deck first.
	await fresh("fractured_isles")
	game.test_mode = false
	game.start_session()
	var sea: Area2D = null
	for foe in game.enemies:
		if foe.is_boss():
			sea = foe
		else:
			foe.target = null
	# The standoff card is not what is under test and it is ten seconds long.
	game.story_cards[0]["seen"] = true
	sea.reset()
	sea.target = game.player
	sea.engaged = true
	sea.aloft = true
	sea.grounded = false
	sea.deck_y = 660.0
	sea.mark_y = 660.0
	sea.air_left = 30.0
	# Its fence is the arena now — the deck, from 6912 — so in play it cannot
	# BE over the water on this level any more, and the next check is the one
	# that says so. This one is about the death glide, which is general flyer
	# behaviour and still has to work wherever a flyer does end up out there,
	# so the fence is taken off for the length of it.
	sea.fly_bounds = Vector2(-INF, INF)
	sea.position = Vector2(6700.0, 504.0)
	game.player.position = Vector2(6950.0, 660.0)
	game.player.velocity = Vector2.ZERO
	await steps(4)
	var over_water: bool = sea.position.x < 6912.0
	var _put_down: bool = sea.take_hit(sea.health, game.player.global_position)
	var sank := false
	for i in range(900):
		await physics_frame
		if not sea.visible:
			sank = true
			break
		if game.story_running():
			break
	check("beaten-over-the-water-it-still-comes-down-on-a-deck",
		over_water and not sank and game.story_running()
		and absf(sea.position.y - 660.0) < 12.0
		and sea.position.x >= 6912.0,
		{"killed_over_water": over_water, "fell_out_of_the_level": sank,
		 "card": game.story_running(), "landed_at": sea.position})

	# Neither of the dragon's cards can be skipped — both carry "skip": false,
	# because between them they are the only story this level tells and a
	# player who taps space out of habit at the first frame would never see
	# either.
	#
	# The keys are still SWALLOWED. A card is advanced from the playing branch
	# of the tick and owns the keyboard while it is up, so an escape that fell
	# through would pause the game behind the picture and stop it where it
	# stands with no key left that would start it again.
	await fresh("fractured_isles")
	game.test_mode = false
	game.start_session()
	var cut: Area2D = null
	for foe in game.enemies:
		if foe.is_boss():
			cut = foe
	game.player.position = Vector2(card_x + 24.0, 660.0)
	game.player.velocity = Vector2.ZERO
	await steps(6)
	check("the-card-is-up-and-refuses-to-be-skipped",
		game.story_running() and not cut.engaged
		and not bool(game.story_cards[0]["skip"])
		and not bool(game.story_cards[1]["skip"]),
		{"running": game.story_running(),
		 "skip": [game.story_cards[0]["skip"], game.story_cards[1]["skip"]]})
	var pressed_at: float = game.story_alpha()
	for action in ["jump", "confirm", "pause"]:
		game._unhandled_input(_press(action))
	await steps(2)
	check("space-enter-and-escape-do-not-get-past-it",
		game.story_running() and game.state == Game.State.PLAYING
		and not game.player.enabled and game.story_alpha() >= pressed_at,
		{"running": game.story_running(), "state": game.state,
		 "enabled": game.player.enabled, "alpha": game.story_alpha()})
	check("and-skip_story-says-so-rather-than-doing-it",
		not game.skip_story() and game.story_running(),
		{"skipped": not game.story_running()})
	for i in range(1200):
		await steps(1)
		if not game.story_running():
			break
	check("it-hands-the-level-back-when-it-is-good-and-ready",
		not game.story_running() and game.player.enabled
		and game.state == Game.State.PLAYING and not Music.ducked
		and cut.engaged,
		{"running": game.story_running(), "enabled": game.player.enabled,
		 "state": game.state, "ducked": Music.ducked, "engaged": cut.engaged})

	# A retry takes the level's own track back. The boss card does not play
	# again, so a fight track cued by the card and never dropped would follow
	# the player over the whole course on the way back to the Archway.
	game.restart_attempt()
	await steps(4)
	check("a-retry-takes-the-boss-track-back-off",
		game.current_track() == str(game.level.music)
		and str(loop.track) == str(game.level.music),
		{"want": game.current_track(), "playing": str(loop.track)})

	# With test_mode on — which is every other suite and every capture — the
	# cue still fires and the fight still starts, it just does not take ten
	# seconds of wall clock to do it.
	await fresh("fractured_isles")
	game.start_session()
	var quick: Area2D = null
	for foe in game.enemies:
		if foe.is_boss():
			quick = foe
	game.player.position = Vector2(card_x + 24.0, 660.0)
	game.player.velocity = Vector2.ZERO
	await steps(6)
	check("test_mode-starts-the-fight-without-the-card",
		not game.story_running() and bool(game.story_cards[0]["seen"])
		and quick.engaged,
		{"running": game.story_running(),
		 "seen": game.story_cards[0]["seen"], "engaged": quick.engaged})

	# --- The Dragon's Roost: two start panels, and BOTH bosses wake ----------
	# The final level opens its fight the same way the isles does, but with TWO
	# start panels back to back and two bosses to wake. The panel machinery is the
	# isles' and is tested above; what is new is the pair of cards and that the
	# cutscene wakes every boss, not just the first.
	await fresh("dragons_roost")
	game.start_session()
	await steps(2)
	var roost_lord: Area2D = null
	var roost_flyer: Area2D = null
	for foe in game.enemies:
		if foe.kind == "dragon_lord":
			roost_lord = foe
		elif foe.kind == "dragon":
			roost_flyer = foe
	check("the-roost-holds-two-dragon-lord-panels",
		game.story_cards.size() == 2
		and str(game.level.cutscene[0].panel) == "dragon_lord_fight_start"
		and str(game.level.cutscene[1].panel) == "dragon_lord_fight_start_2"
		and str(game.level.cutscene[0].audio) == "dragon_lord_fight"
		and game.story_cards[0]["tex"] != null and game.story_cards[1]["tex"] != null,
		{"cards": game.story_cards.size(),
		 "panels": [str(game.level.cutscene[0].panel), str(game.level.cutscene[1].panel)],
		 "audio": str(game.level.cutscene[0].get("audio", ""))})
	# Both panels are spoken over, so both carry a subtitle. The isles' second
	# card has none — it is a picture of the dragon leaving and there is nobody
	# left to talk over it — but this beat is an exchange, and the lines are
	# most of what it is for.
	check("both-roost-panels-carry-a-line",
		str(game.story_cards[0]["line"]) == str(game.level.cutscene[0].caption)
		and str(game.story_cards[1]["line"]) == str(game.level.cutscene[1].caption)
		and str(game.story_cards[0]["line"]).contains("Lugia")
		and str(game.story_cards[1]["line"]).contains("shatter")
		and str(game.story_cards[0]["line"]) != str(game.story_cards[1]["line"]),
		{"first": game.story_cards[0]["line"],
		 "second": game.story_cards[1]["line"]})
	# The one dialogue clip is spread across both panels: the first holds an
	# explicit slice rather than the whole 21 s, and the second keeps that clip
	# running instead of restarting, so the cut lands on the dialogue's own beat.
	check("the-dialogue-is-pinned-across-both-panels",
		bool(game.story_cards[1]["keep_audio"])
		and not bool(game.story_cards[0]["keep_audio"])
		and game.story_cards[0]["voice"] != null
		and float(game.story_cards[0]["voice"].get_length()) > 18.0
		and float(game.story_cards[0]["hold"]) < 10.0,
		{"card0_hold": game.story_cards[0]["hold"],
		 "card1_keeps_audio": game.story_cards[1]["keep_audio"],
		 "clip_len": snappedf(game.story_cards[0]["voice"].get_length(), 0.1)})
	# And the fight has its own battle track, cued the moment it starts and gone
	# again once both bosses are down.
	check("the-roost-fight-has-its-own-music",
		str(game.level.get("boss_music", "")) == "dragon_lord_fight"
		and str(game.level.get("music", "")) == "magic_cliffs",
		{"boss_music": str(game.level.get("boss_music", "")),
		 "music": str(game.level.get("music", ""))})
	# Walk over the cue. test_mode (set by fresh) collapses each card to its effect
	# — see _begin_story — so this drives the wake without sitting through the
	# panels, and the effect under test is that BOTH bosses come awake.
	game.player.position = Vector2(float(game.level.cutscene[0].at) - 40.0, 648.0)
	game.player.velocity = Vector2.ZERO
	game.player.test_control = true
	game.player.test_axis = 1.0
	for i in range(120):
		await steps(1)
		# Both panels collapse frame-by-frame in test_mode; wait until the second
		# has been reached so this checks the whole sequence, not just the first.
		if bool(game.story_cards[1]["seen"]):
			break
	check("the-roost-cutscene-wakes-both-bosses",
		roost_lord.engaged and roost_flyer.engaged
		and bool(game.story_cards[0]["seen"]) and bool(game.story_cards[1]["seen"]),
		{"lord": roost_lord.engaged, "dragon": roost_flyer.engaged,
		 "seen": [game.story_cards[0]["seen"], game.story_cards[1]["seen"]]})

	# The two panels are ONE beat: the second dissolves in over the first with the
	# level kept covered and the world frozen the whole time, rather than dropping
	# back to gameplay between them. Run with test_mode OFF so the pictures play.
	await fresh("dragons_roost")
	game.test_mode = false
	game.start_session()
	game.player.position = Vector2(float(game.level.cutscene[0].at) - 40.0, 648.0)
	game.player.velocity = Vector2.ZERO
	game.player.test_control = true
	game.player.test_axis = 1.0
	var xfade_first := false
	for i in range(120):
		await steps(1)
		if game.story_running() and game.story_art.texture == game.story_cards[0]["tex"]:
			xfade_first = true
			break
	# What is printed under each picture, read at the two moments the pictures
	# are up rather than off the level file — the file is checked above, and
	# what matters here is that the swap carries the line across with the art.
	var said_first: String = game.story_line.text
	game.player.test_axis = 0.0
	var xfade_swap := false
	var xfade_covered := true
	var xfade_frozen := true
	var xfade_second := false
	for i in range(1500):
		await steps(1)
		if game.story_phase == Game.Story.SWAP:
			xfade_swap = true
			# The level must stay covered and the player frozen through the cut.
			if game.story_dim.color.a < Game.STORY_DIM * 0.9:
				xfade_covered = false
			if game.player.enabled:
				xfade_frozen = false
		if game.story_art.texture == game.story_cards[1]["tex"] \
				and game.story_phase == Game.Story.HOLD \
				and game.story_art.modulate.a > 0.99:
			xfade_second = true
			break
	var said_second: String = game.story_line.text
	check("the-panels-cross-without-dropping-to-gameplay",
		xfade_first and xfade_swap and xfade_covered and xfade_frozen and xfade_second,
		{"panel1": xfade_first, "saw_swap": xfade_swap, "level_covered": xfade_covered,
		 "player_frozen": xfade_frozen, "panel2_full": xfade_second})
	check("and-each-panel-says-its-own-line",
		said_first == str(game.level.cutscene[0].caption)
		and said_second == str(game.level.cutscene[1].caption)
		and said_first != said_second and game.story_line.visible,
		{"first": said_first, "second": said_second,
		 "shown": game.story_line.visible})
	# Two lines of it, so it is taller than the isles' one-liner and the top of
	# the scrim has further to climb. It still has to clear the picture's bottom
	# edge and stay on the screen.
	check("and-the-line-under-them-stays-on-the-screen",
		game.story_line.position.y > 330.0
		and game.story_line.position.y + game.story_line.size.y <= 540.0
		and is_equal_approx(game.story_line.size.x, Game.VIEW_HALF.x * 2.0),
		{"top": game.story_line.position.y,
		 "bottom": game.story_line.position.y + game.story_line.size.y,
		 "width": game.story_line.size.x})

	# A level with no cards is untouched by any of it, which is most of them.
	await fresh("first_steps")
	game.start_session()
	await steps(4)
	check("a-level-with-no-card-never-freezes",
		game.story_cards.is_empty() and game.story_art.texture == null
		and not game.story_running(),
		{"cards": game.story_cards.size(),
		 "texture": game.story_art.texture != null})

	# A level with no gates is untouched by any of this.
	await fresh("greybox")
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

	# --- the boss track is mixed forward ------------------------------------
	# Two different things are called music here. The coast loop is a bed; the
	# battle track plays over a fight that is already loud with roars, fire and
	# blasts, and at the bed's fader it was reported inaudible and measured 3 dB
	# under a loop that is itself well back. See TRIM in music.gd and
	# tests/diag_music_levels.gd for the measurement.
	check("the-battle-track-is-louder-than-the-bed",
		Music._level_db("decisive_battle") > Music._level_db("magic_cliffs")
		and Music._level_db("magic_cliffs") == Music.LEVEL_DB,
		{"battle": Music._level_db("decisive_battle"),
		 "bed": Music._level_db("magic_cliffs")})
	# Loud, but not into the ceiling: the track's own peak is -2.0 dBFS, so the
	# trim has to leave at least that much headroom under 0.
	check("and-still-has-headroom-over-its-own-peak",
		Music._level_db("decisive_battle") <= -2.0,
		{"fader": Music._level_db("decisive_battle")})
	# The trim rides UNDER both of the things that are allowed to take the
	# music away: the player's mute, and a story card talking over it. A boss
	# track that ignored either would be the loudest bug in the game.
	Music.duck(self, true)
	var ducked_battle: float = Music._level_db("decisive_battle")
	Music.duck(self, false)
	check("the-duck-still-gets-under-it",
		ducked_battle == Music._level_db("decisive_battle") + Music.DUCK_DB,
		{"ducked": ducked_battle,
		 "open": Music._level_db("decisive_battle")})
	Music.silence(self, true)
	var muted_battle: float = Music._level_db("decisive_battle")
	Music.silence(self, false)
	check("and-mute-beats-it-outright",
		muted_battle == Music.SILENT_DB, {"muted": muted_battle})
	# Cued live, the node has to be wearing the trim — the volume is set per
	# track in cue() now, not once when the node is built.
	Music.cue(self, "decisive_battle")
	await steps(2)
	check("cueing-it-puts-the-trim-on-the-node",
		music.track == "decisive_battle"
		and absf(music.volume_db - Music._level_db("decisive_battle")) < 0.01,
		{"volume": music.volume_db,
		 "want": Music._level_db("decisive_battle")})
	# And going back to the bed takes it off again.
	Music.cue(self, "magic_cliffs")
	await steps(2)
	check("and-going-back-to-the-bed-takes-it-off",
		absf(music.volume_db - Music.LEVEL_DB) < 0.01,
		{"volume": music.volume_db})
	# Every track a boss fights to has to be one the mixer has an opinion about.
	# The two levels named the same one until the Roost's had to be swapped for
	# a clip that is actually in the repository — see TRIM in music.gd.
	var fights: Array = []
	for id in shipped_ids:
		var named := str(Game.level_data(id).get("boss_music", ""))
		if named != "" and not fights.has(named):
			fights.append(named)
	check("every-boss-track-is-one-the-mixer-knows",
		not fights.is_empty()
		and Array(fights).all(func(n): return Music.TRIM.has(n)),
		{"boss_tracks": fights, "trimmed": Music.TRIM.keys()})

	# A level with no music of its own stops it rather than carrying the wrong
	# track into a greybox slice.
	game.load_level("greybox")
	await steps(3)
	check("a-level-with-no-music-is-silent",
		not music.playing and music.track == "",
		{"playing": music.playing, "track": music.track})
	Music.hush(self)

	# --- the battle track lasts as long as the LAST boss --------------------
	# It belongs to the FIGHT, and the level's own loop is the bed for the
	# aftermath — the body on the deck, the card, the climb out. That is one
	# question on a level with one boss and a different one on The Dragon's
	# Roost, which fights two.
	#
	# It used to ask boss() and then whether THAT one was alive. The Roost
	# lists the dragon first, so beating the dragon dropped the track to the
	# coast loop with the Dragon Lord still swinging, and put it back four and
	# a half seconds later when the dragon's body finally left the level: a
	# hole in the middle of the last fight in the game. See boss_fighting() in
	# session.gd and tests/diag_boss_track.gd, which walks both levels through
	# both deaths in both orders.
	await fresh("dragons_roost")
	game.start_session()
	game.story_cards.clear()
	await steps(2)
	var pair_lord: Area2D = null
	var pair_wyrm: Area2D = null
	for foe in game.enemies:
		if foe.kind == "dragon_lord":
			pair_lord = foe
		elif foe.kind == "dragon":
			pair_wyrm = foe
	var _woke: bool = game._wake_boss()
	await steps(2)
	check("the-roost-fight-opens-on-the-battle-track",
		game.current_track() == "decisive_battle"
		and game.boss_fighting() != null,
		{"track": game.current_track()})

	# The dragon first, which is the way round that was broken.
	var _wyrm_out: bool = pair_wyrm.take_hit(pair_wyrm.health,
			game.player.global_position)
	await steps(2)
	check("and-it-holds-while-the-other-one-is-still-up",
		game.current_track() == "decisive_battle"
		and game.boss_fighting() == pair_lord and not pair_wyrm.alive(),
		{"track": game.current_track(), "dragon_alive": pair_wyrm.alive(),
		 "fighting": "<none>" if game.boss_fighting() == null
			else game.boss_fighting().kind})
	# Including while the body is leaving, which is when it used to come back.
	var flew_out := -1
	for i in range(900):
		await physics_frame
		if not pair_wyrm.visible:
			flew_out = i
			break
	await steps(2)
	check("and-through-the-body-leaving-the-level",
		flew_out >= 0 and game.current_track() == "decisive_battle",
		{"track": game.current_track(), "body_gone_after_s": flew_out / 60.0})

	# And the moment the last one falls it is the coast again, without waiting
	# for HIS body either.
	var _lord_out: bool = pair_lord.take_hit(pair_lord.health,
			game.player.global_position)
	await steps(2)
	check("and-the-last-one-down-hands-it-back-to-the-coast",
		game.current_track() == "magic_cliffs"
		and game.boss_fighting() == null and pair_lord.visible,
		{"track": game.current_track(), "body_still_there": pair_lord.visible})

	# The isles is the other half of the same rule, and the half that was
	# already right: one boss, and the track ends with the boss rather than
	# with its body. The plate outlasts it on purpose — an empty bar under a
	# departing dragon is the point, and a battle loop under it would undo it.
	await fresh("fractured_isles")
	game.start_session()
	game.story_cards.clear()
	await steps(2)
	var lone: Area2D = null
	for foe in game.enemies:
		if foe.is_boss():
			lone = foe
	var _lone_woke: bool = game._wake_boss()
	await steps(2)
	var lone_on: String = game.current_track()
	var _lone_out: bool = lone.take_hit(lone.health, game.player.global_position)
	await steps(2)
	check("and-one-boss-still-takes-its-track-with-it",
		lone_on == "decisive_battle" and game.current_track() == "magic_cliffs"
		and lone.visible and game.boss() == lone,
		{"fighting": lone_on, "beaten": game.current_track(),
		 "body_still_there": lone.visible, "plate_still_up": game.boss() == lone})

	# --- themed levels ------------------------------------------------------
	# A theme swaps the whole world renderer, so the wrong answer here is a level
	# drawn twice or not at all rather than an error anything would report.
	await fresh("fractured_isles")
	check("a-themed-level-builds-its-scenery",
		is_instance_valid(game.scenery) and game.scenery.theme == "magic_cliffs",
		{"theme": str(game.level.get("theme", ""))})
	check("the-theme-art-is-imported", not game.scenery.pieces.is_empty(),
		{"pieces": game.scenery.pieces.size()})
	await fresh("greybox")
	check("a-greybox-level-has-no-scenery", not is_instance_valid(game.scenery),
		{"theme": str(game.level.get("theme", ""))})

	# Tagged solids are still collision: the art a rectangle wears must not
	# change how many bodies the world has or where they are.
	await fresh("fractured_isles")
	var bodies := 0
	for child in game.get_children():
		if child is StaticBody2D:
			bodies += 1
	# The two end walls, one per section gate, and one behind the boss arena on
	# a level that has a boss. Spelled out rather than loosened to >=: the point
	# of the check is that a themed level builds no geometry a greybox one would
	# not, and a wall nobody asked for is exactly what it is here to catch.
	var expected: int = (game.level.solids.size() + 2
			+ game.level.get("gates", []).size()
			+ (1 if is_instance_valid(game.seal_wall) else 0))
	check("tagged-solids-are-still-solid", bodies == expected,
		{"bodies": bodies, "expected": expected,
		 "solids": game.level.solids.size(), "gates": game.gates.size(),
		 "arena_wall": is_instance_valid(game.seal_wall)})

	# --- a climbing level ---------------------------------------------------
	# The Climb is the only one, and the two rules it turns on are rules no
	# other level has: the view may not come back down, and the fatal line
	# rides with it instead of sitting at fall_y.
	await fresh("the_climb")
	game.start_session()
	await steps(2)
	check("a-climb-says-so", game.climbing and not game.level.get("gates", []),
		{"climbing": game.climbing, "gates": game.level.get("gates", []).size()})

	# One screen wide, so the camera has nothing left to do horizontally. This
	# is what the whole design rests on and it is a consequence of `width`
	# rather than of anything the level says, so it is worth pinning.
	var pinned: float = game.camera.position.x
	game.player.position = Vector2(900, 648)
	await steps(4)
	check("the-view-does-not-travel-sideways",
		is_equal_approx(game.camera.position.x, pinned) and is_equal_approx(pinned, 480.0),
		{"x": game.camera.position.x, "was": pinned})

	# Up the tower a ledge at a time. The view has to follow him up and then
	# refuse to give any of it back when he drops.
	game.restart_attempt()
	await steps(2)
	var lowest: float = game.camera.position.y
	var came_down := false
	# The middle of every fourth ledge up the mountain, READ OUT OF THE LEVEL
	# rather than written down here — it is 48 ledges and nearly 4000 px of
	# climb, and it has been relaid once already. Both coordinates matter: the
	# mark the view and the fatal line are measured from only moves when he is
	# STANDING, so dropping him at the spawn x and a ledge's y puts him in open
	# air over the sea and proves nothing.
	var pads: Array[Vector2] = []
	var rungs: Array = game.level.solids.duplicate()
	rungs.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	for i in rungs.size():
		if i > 0 and i % 4 == 0:
			pads.append(Vector2(float(rungs[i][0]) + float(rungs[i][2]) / 2.0,
								float(rungs[i][1])))
	for pad in pads:
		game.player.position = pad - Vector2(0, 4)
		game.player.velocity = Vector2.ZERO
		for _i in 12:
			await physics_frame
		came_down = came_down or game.camera.position.y > lowest + 0.5
		lowest = minf(lowest, game.camera.position.y)
	check("the-view-climbs-with-him",
		lowest < -2000.0 and not came_down and pads.size() > 8,
		{"view": lowest, "came_down": came_down, "rungs_stood_on": pads.size()})
	# Standing near the summit, the fatal line is a screen below HIM and nowhere
	# near the sea the level nominally ends at.
	check("the-fatal-line-climbs-too",
		game.fatal_y() < 0.0 and game.fatal_y() < float(game.level.fall_y),
		{"fatal": game.fatal_y(), "fall_y": game.level.fall_y,
		 "feet": game.player.position.y})
	# And it is what kills him: a drop of a screen and a half from up here is
	# fatal even though the sea is 1400 px further down.
	game.player.position.y += 460.0
	await steps(3)
	check("falling-off-the-bottom-is-fatal", game.state == Game.State.DYING,
		{"state": game.state, "feet": game.player.position.y})

	# A retry puts the view back at the foot of the tower. Without this the
	# second attempt starts with the fatal line still up at the summit.
	game.restart_attempt()
	await steps(2)
	check("a-retry-drops-the-view-back",
		game.camera.position.y > 500.0 and game.fatal_y() == float(game.level.fall_y),
		{"view": game.camera.position.y, "fatal": game.fatal_y()})

	# --- the shafts ---------------------------------------------------------
	# A source only lets go while he is below it and within about a screen, so
	# he has to be stood under one. Deliberately NOT the shore: the opening band
	# of the mountain has no rock over it at all, which is the bottom of the
	# difficulty curve and is why this check used to fail here.
	var lowest_source: Array = game.level.rockfall[0]
	for source in game.level.rockfall:
		if float(source[1]) > float(lowest_source[1]):
			lowest_source = source
	var under := Vector2.ZERO
	for entry in game.level.solids:
		var top: float = float(entry[1])
		if top > float(lowest_source[1]) and (under == Vector2.ZERO or top < under.y):
			under = Vector2(float(entry[0]) + float(entry[2]) / 2.0, top)
	game.player.position = under - Vector2(0, 4)
	game.player.velocity = Vector2.ZERO
	var dropped := 0
	for _i in 300:
		await physics_frame
		dropped = maxi(dropped, game.stones.size())
	check("the-shafts-drop-stones", dropped > 0,
		{"most_at_once": dropped, "stood_at": under,
		 "under_source": lowest_source})

	# One in the face costs him health, and it is the session that spends it —
	# the stone only reports the hit, exactly as an arrow does.
	game.restart_attempt()
	await steps(2)
	var full: int = game.player.health
	var stone = game._drop_stone(game.player.position - Vector2(0, 150))
	for _i in 30:
		await physics_frame
		if game.player.health < full:
			break
	check("a-stone-hurts-him", game.player.health < full,
		{"health": game.player.health, "was": full})

	# And he can take one out of the sky. Nothing else in the level rewards the
	# strike, so a rock that cannot be broken is a rock that can only be run from.
	game.restart_attempt()
	await steps(2)
	stone = game._drop_stone(game.player.position - Vector2(0, 400))
	var broke: bool = stone.take_hit(30, game.player.position)
	check("a-stone-can-be-struck-out-of-the-air", broke and stone.broken,
		{"broke": broke})

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
