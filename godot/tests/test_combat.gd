extends SceneTree
## Combat checks: the moveset, its hit geometry, and what it must not break.
##
## Same shape and reporting as test_game.gd, kept separate because these assert
## on a different thing: test_game.gd is about whether the platformer still
## behaves, this is about whether a swing connects when and where it should.
##
## Written against real crates in the real level, not synthetic fixtures, so a
## hitbox that is off by twenty pixels shows up here rather than in a screenshot.
const Game = preload("res://game/session.gd")
const Moveset = preload("res://features/player/moveset.gd")

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

func fresh() -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	game = Game.new()
	game.test_mode = true
	root.add_child(game)
	game.start_session()
	game.player.test_control = true
	await steps(3)

## Put him on the ground a given distance from a crate, facing it.
func stand_near(crate: Area2D, offset: float) -> void:
	game.player.position = Vector2(crate.position.x + offset, crate.position.y)
	game.player.velocity = Vector2.ZERO
	game.player.facing = -1.0 if offset > 0.0 else 1.0
	await steps(2)

## Run the current attack to completion, with a tick cap so a move that never
## ends fails the test instead of hanging the run.
func finish_attack(cap: int = 90) -> int:
	var ticks := 0
	# The press is only consumed on the next physics step, so wait for the move
	# to begin before waiting for it to end. Without this the function returns
	# immediately and every assertion after it reads a swing that never happened.
	while game.player.attack == "" and ticks < 4:
		await steps(1)
		ticks += 1
	while game.player.attack != "" and ticks < cap:
		await steps(1)
		ticks += 1
	return ticks

## Drinks and stands still for the whole six seconds. Nothing is restored and
## nothing is spent until it finishes, so a test that checks straight after
## game.drink() reads the value from before he ever raised the bottle.
## The cap is generous: six seconds is 360 physics ticks.
func finish_drink(cap: int = 480) -> bool:
	if not game.drink():
		return false
	var ticks := 0
	while game.player.attack == "drink" and ticks < cap:
		await steps(1)
		ticks += 1
	return ticks < cap

func run() -> void:
	await fresh()
	var crates: Array = game.crates
	check("level-has-targets", crates.size() > 0, {"crates": crates.size()})

	# --- the data the whole system rests on --------------------------------
	var missing: Array = []
	for key in ["punch_a", "punch_b", "kick", "charge", "blast"]:
		if not Moveset.has(key):
			missing.append(key)
	check("moves-manifest-complete", missing.is_empty(), {"missing": missing})
	var boxed := 0
	for key in ["punch_a", "punch_b", "kick", "charge"]:
		for f in Moveset.frame_count(key):
			boxed += Moveset.hits(key, f).size()
	check("moves-have-hitboxes", boxed >= 6, {"hitbox_frames": boxed})

	# --- ground punch -------------------------------------------------------
	var crate: Area2D = crates[0]
	await stand_near(crate, -40.0)
	var full: int = crate.health
	game.player.test_attack_pressed = true
	await steps(1)
	check("punch-starts", game.player.attack == "punch_a", {"attack": game.player.attack})
	await finish_attack()
	check("punch-damages-crate", crate.health < full and not crate.broken,
		{"health": crate.health, "from": full})
	check("punch-ends", game.player.attack == "", {"attack": game.player.attack})

	# One swing, one hit: several frames of a move must not stack damage.
	await fresh()
	crate = game.crates[0]
	await stand_near(crate, -40.0)
	var before: int = crate.health
	game.player.test_attack_pressed = true
	await finish_attack()
	# Exactly one jab's worth: > 0 proves it connected at all, <= 20 proves the
	# move's several frames did not each apply damage.
	check("one-swing-one-hit", before - crate.health > 0 and before - crate.health <= 20,
		{"damage": before - crate.health})

	# --- facing -------------------------------------------------------------
	# The same punch from the same distance on the wrong side must miss. This is
	# what catches a hitbox that was not mirrored with the sprite.
	await fresh()
	crate = game.crates[0]
	await stand_near(crate, -40.0)
	game.player.facing = -1.0  # crate is to his right; he faces away
	game.player.test_attack_pressed = true
	await finish_attack()
	check("punch-misses-behind", crate.health == crate.max_health, {"health": crate.health})

	# --- out of range -------------------------------------------------------
	await fresh()
	crate = game.crates[0]
	await stand_near(crate, -180.0)
	game.player.test_attack_pressed = true
	await finish_attack()
	check("punch-misses-far", crate.health == crate.max_health, {"health": crate.health})

	# --- combo --------------------------------------------------------------
	await fresh()
	crate = game.crates[0]
	await stand_near(crate, -40.0)
	game.player.test_attack_pressed = true
	await steps(2)
	game.player.test_attack_pressed = true  # queued during the jab
	await steps(2)
	var chained := false
	for i in range(40):
		await steps(1)
		if game.player.attack == "punch_b":
			chained = true
			break
	check("jab-chains-into-cross", chained, {"attack": game.player.attack})
	await finish_attack()
	check("combo-breaks-crate", crate.broken, {"health": crate.health})

	# --- air kick -----------------------------------------------------------
	await fresh()
	game.player.test_jump_pressed = true
	await steps(6)
	check("airborne", not game.player.is_on_floor(), {"y": game.player.position.y})
	game.player.test_attack_pressed = true
	await steps(1)
	check("air-attack-is-kick", game.player.attack == "kick", {"attack": game.player.attack})
	# Landing must cut the kick short rather than leaving him kicking on the floor.
	var land_ticks := 0
	while not game.player.is_on_floor() and land_ticks < 120:
		await steps(1)
		land_ticks += 1
	await steps(3)
	check("kick-ends-on-landing", game.player.attack == "", {"attack": game.player.attack})

	# --- shoulder charge ----------------------------------------------------
	await fresh()
	game.player.test_axis = 1
	await steps(20)
	check("at-run-speed", absf(game.player.velocity.x) >= game.player.CHARGE_FROM,
		{"velocity_x": game.player.velocity.x})
	game.player.test_attack_pressed = true
	await steps(1)
	check("running-attack-is-charge", game.player.attack == "charge", {"attack": game.player.attack})
	await finish_attack()

	# The shoulder charge carries more than a crate's whole health, so without
	# the survive-the-first-blow rule it erases an untouched crate on the spot
	# and the launch is never seen. It must knock the box, not delete it.
	await fresh()
	crate = game.crates[0]
	var charge_home: Vector2 = crate.position
	game.player.position = Vector2(crate.position.x - 260, crate.position.y)
	game.player.test_axis = 1
	await steps(20)
	game.player.test_attack_pressed = true
	await steps(1)
	check("charge-starts-against-crate", game.player.attack == "charge",
		{"attack": game.player.attack})
	var lift: float = crate.position.y
	for i in range(50):
		await steps(1)
		lift = minf(lift, crate.position.y)
	check("charge-knocks-crate-instead-of-erasing-it",
		not crate.broken and crate.health < crate.max_health,
		{"broken": crate.broken, "health": crate.health})
	check("charge-launches-crate", lift < charge_home.y - 20.0,
		{"peak_lift_px": charge_home.y - lift})

	# Once it has been hit, ordinary arithmetic applies and anything finishes it.
	crate.take_hit(20, crate.position - Vector2(40, 0))
	check("second-blow-breaks-it", crate.broken, {"health": crate.health})

	# A grounded punch plants him; the charge does not.
	await fresh()
	await stand_near(game.crates[0], -40.0)
	game.player.test_axis = 1
	game.player.test_attack_pressed = true
	await steps(4)
	check("punch-plants-him", absf(game.player.velocity.x) < 1.0,
		{"velocity_x": game.player.velocity.x})
	await finish_attack()

	# --- blast --------------------------------------------------------------
	await fresh()
	crate = game.crates[0]
	# Well out of punching range, so only a projectile can reach it.
	await stand_near(crate, -300.0)
	game.player.test_blast_pressed = true
	await steps(1)
	check("blast-starts", game.player.attack == "blast", {"attack": game.player.attack})
	var spawned := false
	for i in range(40):
		await steps(1)
		if game.blasts.size() > 0:
			spawned = true
			break
	check("blast-spawns-projectile", spawned, {"blasts": game.blasts.size()})
	# An untouched crate survives any single blow, so the first blast knocks it
	# rather than destroying it; a second finishes the job.
	var travel := 0
	while crate.health >= crate.max_health and travel < 200:
		await steps(1)
		travel += 1
	check("blast-reaches-distant-crate",
		crate.health < crate.max_health and not crate.broken,
		{"health": crate.health, "ticks": travel})
	# Capped: an uncapped wait turns any failure to build the scene into a hang
	# rather than a failed check.
	var recover := 0
	while game.player.attack != "" and recover < 90:
		await steps(1)
		recover += 1
	game.player.test_blast_pressed = true
	var second := 0
	while not crate.broken and second < 240:
		await steps(1)
		second += 1
	check("second-blast-breaks-distant-crate", crate.broken,
		{"health": crate.health, "ticks": second})

	# The projectile must not outlive its range.
	await fresh()
	game.player.position = Vector2(200, 640)
	game.player.facing = -1.0
	await steps(2)
	game.player.test_blast_pressed = true
	await steps(60)
	await steps(120)
	check("blast-expires", game.blasts.is_empty(), {"live": game.blasts.size()})

	# --- retry restores targets --------------------------------------------
	await fresh()
	crate = game.crates[0]
	await stand_near(crate, -40.0)
	game.player.test_attack_pressed = true
	await finish_attack()
	var damaged: int = crate.health
	game.restart_attempt()
	await steps(2)
	check("retry-restores-crates",
		crate.health == crate.max_health and not crate.broken and damaged < crate.max_health,
		{"after_retry": crate.health, "while_damaged": damaged})
	check("retry-returns-crate-home",
		crate.position == crate.home and crate.at_rest,
		{"position": str(crate.position), "home": str(crate.home)})

	# --- combat must not alter the platformer -------------------------------
	await fresh()
	check("crates-are-not-solid", game.player.get_collision_mask() == 1,
		{"mask": game.player.get_collision_mask()})
	# Walk straight through a crate: it is a target, not an obstacle.
	crate = game.crates[0]
	game.player.position = Vector2(crate.position.x - 70, crate.position.y)
	game.player.test_axis = 1
	await steps(40)
	check("walks-through-crate", game.player.position.x > crate.position.x + 20,
		{"player_x": game.player.position.x, "crate_x": crate.position.x})

	# --- the crate as a physical object ------------------------------------
	# LF2 does not bolt a box to the floor: hitting it knocks it into the air,
	# it tumbles, lands, skids and settles. These pin that it moves, that the
	# weight of the blow matters, and that it always comes back down.
	await fresh()
	crate = game.crates[0]
	var home: Vector2 = crate.position
	await stand_near(crate, -40.0)
	game.player.test_attack_pressed = true
	# Track the whole flight rather than sampling the end of it: the hop is over
	# in a quarter of a second, well before the punch animation finishes, so a
	# check afterwards sees a crate that has already landed and calls it bolted
	# down.
	var peak: float = crate.position.y
	for i in range(40):
		await steps(1)
		peak = minf(peak, crate.position.y)
	check("hit-knocks-crate-airborne", peak < home.y - 6.0,
		{"peak_lift_px": home.y - peak})

	var settle_ticks := 0
	while not crate.at_rest and settle_ticks < 180:
		await steps(1)
		settle_ticks += 1
	check("crate-settles", crate.at_rest and settle_ticks < 180,
		{"ticks": settle_ticks, "at_rest": crate.at_rest})
	check("crate-lands-back-on-the-floor", is_equal_approx(crate.position.y, home.y),
		{"y": crate.position.y, "home_y": home.y})
	check("crate-knocked-away-from-the-blow", crate.position.x > home.x,
		{"x": crate.position.x, "home_x": home.x})

	# A jab should nudge it; a kick should send it. Same crate, same spot.
	await fresh()
	crate = game.crates[0]
	home = crate.position
	crate.take_hit(20, crate.position - Vector2(40, 0))
	var light_ticks := 0
	while not crate.at_rest and light_ticks < 180:
		await steps(1)
		light_ticks += 1
	var light: float = crate.position.x - home.x
	crate.reset()
	await steps(1)
	crate.take_hit(39, crate.position - Vector2(40, 0))
	var heavy_ticks := 0
	while not crate.at_rest and heavy_ticks < 180:
		await steps(1)
		heavy_ticks += 1
	var heavy: float = crate.position.x - home.x
	check("heavier-blow-sends-it-further", heavy > light and light > 0.0,
		{"light_px": light, "heavy_px": heavy})

	# Knocked into a pit it has to end somewhere, not fall forever.
	await fresh()
	crate = game.crates[0]
	crate.position = Vector2(960, 400)   # over the first gap
	crate.at_rest = false
	crate.motion = Vector2(0, 120)
	var pit_ticks := 0
	while not crate.broken and pit_ticks < 180:
		await steps(1)
		pit_ticks += 1
	check("crate-in-a-pit-does-not-fall-forever", crate.broken,
		{"broken": crate.broken, "y": crate.position.y, "ticks": pit_ticks})

	# --- health and the bottle ---------------------------------------------
	await fresh()
	check("level-has-a-bottle", game.bottles.size() > 0, {"bottles": game.bottles.size()})
	check("starts-on-low-health",
		game.player.health == game.player.START_HEALTH
		and game.player.health < game.player.MAX_HEALTH,
		{"health": game.player.health, "max": game.player.MAX_HEALTH})

	var bottle: Area2D = game.bottles[0]
	# Far from it: no prompt, and drinking does nothing.
	game.player.position = Vector2(bottle.position.x - 400, bottle.position.y)
	await steps(3)
	check("no-prompt-when-away", game.bottle_in_reach == null, {"in_reach": game.bottle_in_reach != null})
	var health_before: int = game.player.health
	check("drink-refused-when-away", not game.drink() and game.player.health == health_before,
		{"health": game.player.health})

	# Standing on it: prompt appears, drinking restores and consumes.
	game.player.position = Vector2(bottle.position.x, bottle.position.y)
	await steps(3)
	check("prompt-when-near", game.bottle_in_reach == bottle, {"in_reach": game.bottle_in_reach != null})
	# Checked before he raises it: the bottle starts emptying on the first frame
	# of the drink, so a moment later this is legitimately a frame short of six.
	check("full-bottle-quotes-six-seconds",
		absf(bottle.drink_seconds(game.player) - 6.0) < 0.01,
		{"seconds": bottle.drink_seconds(game.player)})
	health_before = game.player.health

	# Drinking is an animation, not an instant effect: he plays LF2's own
	# weapon_drink frames, with the bottle stamped on each frame's weapon point.
	var drank: bool = game.drink()
	await steps(1)
	check("drink-plays-animation", drank and game.player.attack == "drink",
		{"attack": game.player.attack})
	check("bottle-appears-in-hand",
		game.player.visual.held.visible
		and Moveset.wpoint("drink", game.player.attack_frame) != null,
		{"visible": game.player.visual.held.visible,
		 "wpoint": str(Moveset.wpoint("drink", game.player.attack_frame))})
	check("health-not-granted-on-keypress", game.player.health == health_before,
		{"health": game.player.health, "before": health_before})
	check("bottle-not-spent-on-keypress", not bottle.consumed and bottle.lifted,
		{"consumed": bottle.consumed, "lifted": bottle.lifted})
	var two_bars: int = bottle.heal_segments * game.player.segment_health()
	check("a-bottle-is-worth-two-bars", two_bars == 40, {"points": two_bars})

	var drink_ticks := 0
	while game.player.attack == "drink" and drink_ticks < 480:
		await steps(1)
		drink_ticks += 1
	# Six seconds at 60 Hz is 360 ticks. A little slack for the frame the
	# threshold is crossed on, but it must not be a third of a second out.
	check("drink-takes-six-seconds", absi(drink_ticks - 360) <= 6,
		{"ticks": drink_ticks, "expected": 360})
	check("drink-restores-two-bars",
		game.player.health == health_before + two_bars,
		{"before": health_before, "after": game.player.health, "restored": two_bars})
	check("drink-animation-ends", game.player.attack == "" and drink_ticks < 480,
		{"attack": game.player.attack, "ticks": drink_ticks})
	check("hand-empties-after-drinking", not game.player.visual.held.visible,
		{"visible": game.player.visual.held.visible})
	check("drink-consumes-bottle", bottle.consumed and game.bottle_in_reach == null,
		{"consumed": bottle.consumed})
	check("consumed-bottle-cannot-be-drunk-twice", not game.drink(), {"health": game.player.health})

	# --- drinking is drained by the mouthful --------------------------------
	# Stopping is not a forfeit. He keeps what he swallowed, the bottle keeps
	# the rest, and the next drink on it is correspondingly shorter.
	await fresh()
	bottle = game.bottles[0]
	game.player.position = bottle.position
	await steps(3)
	health_before = game.player.health
	var _sip: bool = game.drink()
	await steps(180)  # three seconds: half of it
	check("health-arrives-while-drinking",
		game.player.is_drinking() and game.player.health > health_before,
		{"health": game.player.health, "before": health_before})
	check("bottle-empties-as-he-drinks", absf(bottle.contents - 0.5) < 0.05,
		{"contents": bottle.contents})
	game.player.test_axis = 1
	await steps(2)
	game.player.test_axis = 0
	await steps(3)
	var half_health: int = game.player.health
	check("stopping-keeps-what-he-drank",
		absi(half_health - (health_before + two_bars / 2)) <= 2,
		{"health": half_health, "before": health_before, "expected": health_before + two_bars / 2})
	check("stopping-leaves-the-rest-in-the-bottle",
		bottle.available() and absf(bottle.contents - 0.5) < 0.05,
		{"contents": bottle.contents, "available": bottle.available()})
	check("part-bottle-quotes-a-shorter-wait",
		absf(bottle.drink_seconds(game.player) - 3.0) < 0.3,
		{"seconds": bottle.drink_seconds(game.player)})
	var second_ticks := 0
	var _resume: bool = game.drink()
	while game.player.is_drinking() and second_ticks < 480:
		await steps(1)
		second_ticks += 1
	check("second-sitting-takes-only-what-is-left", absi(second_ticks - 180) <= 8,
		{"ticks": second_ticks, "expected": 180})
	check("two-sittings-restore-the-whole-bottle",
		game.player.health == health_before + two_bars and bottle.consumed,
		{"health": game.player.health, "expected": health_before + two_bars})

	# A half-full bottle is a half-length drink from the start.
	await fresh()
	bottle = game.bottles[0]
	bottle.contents = 0.5
	game.player.position = bottle.position
	await steps(3)
	health_before = game.player.health
	var half_ticks := 0
	var _halfdrink: bool = game.drink()
	while game.player.is_drinking() and half_ticks < 480:
		await steps(1)
		half_ticks += 1
	check("half-bottle-takes-half-the-time", absi(half_ticks - 180) <= 8,
		{"ticks": half_ticks, "expected": 180})
	check("half-bottle-is-worth-half", absi(game.player.health - (health_before + two_bars / 2)) <= 2,
		{"health": game.player.health, "expected": health_before + two_bars / 2})

	# A punched bottle leaks, so its condition sets the wait too.
	await fresh()
	bottle = game.bottles[0]
	check("an-untouched-bottle-is-full", absf(bottle.contents - 1.0) < 0.001,
		{"contents": bottle.contents})
	bottle.take_hit(20, bottle.position - Vector2(40, 0))
	await steps(2)
	check("a-blow-spills-the-bottle", bottle.contents < 1.0 and not bottle.broken,
		{"contents": bottle.contents, "broken": bottle.broken})
	check("cracked-bottle-is-a-shorter-drink",
		bottle.drink_seconds(game.player) < 6.0 and bottle.available(),
		{"seconds": bottle.drink_seconds(game.player)})

	# --- interrupting a drink ----------------------------------------------
	# None of these may spend the bottle. He keeps his mouthful and the bottle
	# keeps the rest, so stopping is a decision rather than a punishment.
	for case in [
		{"id": "moving", "act": "axis"},
		{"id": "jumping", "act": "jump"},
		{"id": "attacking", "act": "attack"},
		{"id": "walking-out-of-reach", "act": "teleport"},
	]:
		await fresh()
		bottle = game.bottles[0]
		game.player.position = bottle.position
		await steps(3)
		health_before = game.player.health
		var started: bool = game.drink()
		await steps(60)  # a full second in
		match case.act:
			"axis":
				game.player.test_axis = 1
				await steps(2)
				game.player.test_axis = 0
			"jump":
				game.player.test_jump_pressed = true
				await steps(2)
			"attack":
				game.player.test_attack_pressed = true
				await steps(2)
			"teleport":
				game.player.position.x = bottle.position.x + 400
				await steps(3)
		await steps(3)
		check("%s-stops-the-drink" % case.id,
			started and not game.player.is_drinking(),
			{"started": started, "attack": game.player.attack})
		check("%s-keeps-the-mouthful" % case.id,
			game.player.health > health_before
			and game.player.health < health_before + two_bars,
			{"health": game.player.health, "before": health_before})
		check("%s-leaves-the-rest-in-the-bottle" % case.id,
			not bottle.consumed and not bottle.lifted and bottle.available()
			and bottle.contents < 1.0,
			{"consumed": bottle.consumed, "contents": bottle.contents})
		check("%s-empties-the-hand" % case.id, not game.player.visual.held.visible,
			{"visible": game.player.visual.held.visible})

	# --- a hit knocks it out of his hand -------------------------------------
	# The one interruption that does not set the bottle down. It falls from
	# about mouth height and bounces on the same physics a punched bottle uses.
	await fresh()
	bottle = game.bottles[0]
	var floor_y: float = bottle.position.y
	game.player.position = bottle.position
	await steps(3)
	health_before = game.player.health
	var _hitdrink: bool = game.drink()
	await steps(60)
	game.player.interrupt_drink(game.player.DRINK_HIT)
	await steps(1)
	check("a-hit-stops-the-drink", not game.player.is_drinking(), {"attack": game.player.attack})
	check("a-hit-drops-the-bottle",
		not bottle.lifted and not bottle.at_rest and bottle.available(),
		{"lifted": bottle.lifted, "at_rest": bottle.at_rest})
	check("a-dropped-bottle-starts-above-the-floor", bottle.position.y < floor_y - 8.0,
		{"y": bottle.position.y, "floor": floor_y})
	var fall_ticks := 0
	var bounces := 0
	var rising := false
	while not bottle.at_rest and fall_ticks < 300:
		var was_rising := rising
		rising = bottle.motion.y < 0.0
		if rising and not was_rising and fall_ticks > 2:
			bounces += 1
		await steps(1)
		fall_ticks += 1
	check("a-dropped-bottle-bounces", bounces >= 1,
		{"bounces": bounces, "ticks": fall_ticks})
	check("a-dropped-bottle-settles-on-the-floor",
		bottle.at_rest and absf(bottle.position.y - floor_y) < 1.0,
		{"y": bottle.position.y, "floor": floor_y, "ticks": fall_ticks})
	check("a-dropped-bottle-can-still-be-drunk",
		bottle.available() and bottle.contents > 0.0 and bottle.contents < 1.0,
		{"contents": bottle.contents})

	# At full health the bottle is refused rather than wasted.
	await fresh()
	bottle = game.bottles[0]
	game.player.position = Vector2(bottle.position.x, bottle.position.y)
	game.player.health = game.player.MAX_HEALTH
	await steps(3)
	check("drink-refused-at-full", not game.drink() and not bottle.consumed,
		{"health": game.player.health, "consumed": bottle.consumed})

	# Retry restores both the bottle and the starting health.
	await fresh()
	bottle = game.bottles[0]
	game.player.position = Vector2(bottle.position.x, bottle.position.y)
	await steps(3)
	var _ok: bool = await finish_drink()
	var healed: int = game.player.health
	game.restart_attempt()
	await steps(3)
	check("retry-restores-bottle-and-health",
		not bottle.consumed and game.player.health == game.player.START_HEALTH
		and healed > game.player.START_HEALTH,
		{"health": game.player.health, "was": healed, "consumed": bottle.consumed})

	# --- the bottle is a prop too ------------------------------------------
	# Same knock-and-shatter logic as the crate, and smashing it destroys the
	# health it was worth. That is the cost of swinging at everything.
	await fresh()
	bottle = game.bottles[0]
	var bhome: Vector2 = bottle.position
	check("bottle-is-hittable", bottle.get_collision_layer() & 64 != 0,
		{"layer": bottle.get_collision_layer()})

	# Every punch in the game lands between y -55 and -25 measured from the feet,
	# so a hit box matching the 23 px art would sit under all of them. This pins
	# that a plain jab can actually reach it.
	game.player.position = Vector2(bottle.position.x - 40, bottle.position.y)
	game.player.facing = 1.0
	await steps(2)
	game.player.test_attack_pressed = true
	var blift: float = bottle.position.y
	for i in range(40):
		await steps(1)
		blift = minf(blift, bottle.position.y)
	check("jab-reaches-the-bottle", bottle.health < bottle.max_health,
		{"health": bottle.health, "max": bottle.max_health})
	check("jab-knocks-the-bottle", blift < bhome.y - 6.0 and not bottle.broken,
		{"peak_lift_px": bhome.y - blift, "broken": bottle.broken})
	check("bottle-survives-its-first-blow", not bottle.broken,
		{"health": bottle.health})

	var bsettle := 0
	while not bottle.at_rest and bsettle < 180:
		await steps(1)
		bsettle += 1
	check("bottle-settles-on-the-floor",
		bottle.at_rest and is_equal_approx(bottle.position.y, bhome.y),
		{"y": bottle.position.y, "home_y": bhome.y})

	# A second blow smashes it, and the drink goes with it.
	bottle.take_hit(20, bottle.position - Vector2(40, 0))
	await steps(2)
	check("second-blow-smashes-the-bottle", bottle.broken, {"health": bottle.health})
	check("smashed-bottle-cannot-be-drunk",
		not bottle.available() and not bottle.in_reach(game.player),
		{"available": bottle.available()})
	game.player.position = bottle.position
	await steps(3)
	check("no-prompt-over-a-smashed-bottle",
		game.bottle_in_reach == null and not game.drink(),
		{"in_reach": game.bottle_in_reach != null})

	# Retry brings it back, whole and drinkable.
	game.restart_attempt()
	await steps(3)
	check("retry-restores-a-smashed-bottle",
		not bottle.broken and bottle.available()
		and bottle.position == bhome and bottle.health == bottle.max_health,
		{"broken": bottle.broken, "position": str(bottle.position)})

	# A bottle already drunk is gone, so a punch must not find one to hit.
	await fresh()
	bottle = game.bottles[0]
	game.player.position = bottle.position
	await steps(3)
	var _drank2: bool = await finish_drink()
	check("drunk-bottle-cannot-be-hit",
		not bottle.take_hit(20, bottle.position - Vector2(40, 0)),
		{"consumed": bottle.consumed, "broken": bottle.broken})

	# The bottle must not obstruct the route any more than a crate does.
	await fresh()
	bottle = game.bottles[0]
	game.player.position = Vector2(bottle.position.x - 90, bottle.position.y)
	game.player.test_axis = 1
	await steps(45)
	check("walks-through-bottle", game.player.position.x > bottle.position.x + 20,
		{"player_x": game.player.position.x, "bottle_x": bottle.position.x})

	# Health is not a second death rule: the spikes still kill outright.
	await fresh()
	game.player.health = game.player.MAX_HEALTH
	game.player.position = Vector2(660, 620)
	var death_ticks := 0
	while game.state == Game.State.PLAYING and death_ticks < 60:
		await steps(1)
		death_ticks += 1
	check("full-health-does-not-survive-spikes", game.state == Game.State.DYING,
		{"state": game.state})

	var report := {
		"scope": "Anti-Davis moveset: hit geometry, move selection, projectile lifetime, health pickup",
		"engine": Engine.get_version_info().string,
		"created_at": Time.get_datetime_string_from_system(true),
		"results": results, "failures": failures}
	var out := ProjectSettings.globalize_path("res://../evidence")
	DirAccess.make_dir_recursive_absolute(out)
	var file := FileAccess.open(out + "/combat-" + str(Time.get_unix_time_from_system()) + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("COMBAT TESTS: %d checks / %d failures" % [results.size(), failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
