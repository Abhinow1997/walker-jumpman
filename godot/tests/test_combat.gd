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
	# Enemies are parked by default. A bandit who walks over mid-test and lands a
	# punch is correct game behaviour and ruins every check that is not about
	# him — he broke the whole drink section the moment he was added. Tests that
	# want him arm him with arm_enemies().
	for bandit in game.enemies:
		bandit.target = null
	await steps(3)

## Point the bandits at the player. Only for tests that are about the bandits.
func arm_enemies() -> void:
	for bandit in game.enemies:
		bandit.target = game.player
	await steps(1)

## Drive one enemy through the whole loop on a clear patch: it closes and lands a
## punch, it takes one back, and it goes down through its own hurt run. Every
## other enemy is parked first, so on a level with more than one neither steals
## the other's blow. `spot` must be clear ground.
func fight_one(foe: Area2D, label: String, spot: Vector2) -> void:
	for other in game.enemies:
		other.target = null
	foe.position = spot
	foe.home = spot
	foe.target = game.player
	game.player.position = Vector2(spot.x - 40.0, spot.y)
	game.player.health = game.player.MAX_HEALTH
	await steps(3)
	var before: int = game.player.health
	var ticks := 0
	while game.player.health == before and ticks < 300:
		await steps(1)
		ticks += 1
	check(label + "-lands-a-blow",
		game.player.health < before and ticks < 300,
		{"health": game.player.health, "ticks": ticks})
	var full: int = foe.health
	check("a-jab-hurts-" + label,
		foe.take_hit(20, foe.position - Vector2(40.0, 0.0)) and foe.health == full - 20,
		{"health": foe.health})
	var kill := 0
	while foe.alive() and kill < 40:
		foe.take_hit(20, foe.position - Vector2(40.0, 0.0))
		await steps(2)
		kill += 1
	await steps(4)
	check("a-downed-" + label + "-stays-down",
		not foe.alive() and foe.sprite.animation == "hurt",
		{"alive": foe.alive(), "playing": foe.sprite.animation})

## Put him on the ground a given distance from a crate, facing it.
## How far the jab reaches from the player's origin, read from the moveset.
func jab_reach() -> float:
	var reach := 0.0
	for hit in Moveset.hits("punch_a", 1):
		reach = maxf(reach, hit.rect.position.x + hit.rect.size.x)
	return reach

## Stand just close enough to `target` that a jab lands solidly on it, overlapping
## its near edge by half the reach so the knock-back does not immediately carry it
## out of range of the follow-up.
##
## Derived rather than hard-coded: every one of these used to be -40, which had
## plenty of slack at the original art size and went marginal all at once when
## the cast was resampled to 0.75. A number that has to be re-tuned whenever the
## art changes does not belong in a test.
func punching_distance(target: Area2D) -> float:
	return -(target.body.x * 0.5 + jab_reach() * 0.5)

func stand_to_punch(target: Area2D) -> void:
	await stand_near(target, punching_distance(target))

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

## Picks the bottle up and waits for the lift to finish. Drinking is a second
## beat now — he has to be holding it — so every drink test goes through here.
func take_bottle(limit: int = 60) -> bool:
	if not game.pick_up():
		return false
	var waited := 0
	while game.player.attack != "" and waited < limit:
		await steps(1)
		waited += 1
	return game.player.is_carrying()

## Lifts the bottle, drinks it, and stands still for the whole six seconds.
## Nothing is restored and nothing is spent until it finishes, so a test that
## checks straight after game.drink() reads the value from before he raised it.
## The cap is generous: six seconds is 360 physics ticks.
func finish_drink(cap: int = 480) -> bool:
	if not await take_bottle():
		return false
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
	await stand_to_punch(crate)
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
	await stand_to_punch(crate)
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
	await stand_to_punch(crate)
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
	await stand_to_punch(crate)
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
	# Run in until he is a stride short of it rather than for a fixed number of
	# ticks. The charge's reach scales with the art, and a hard-coded run-up left
	# him starting the move an inch too far out the moment it did.
	game.player.test_axis = 1
	var run_in := 0
	while game.player.position.x < crate.position.x - 90.0 and run_in < 120:
		await steps(1)
		run_in += 1
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
	await stand_to_punch(game.crates[0])
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
	await stand_to_punch(crate)
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
	await stand_to_punch(crate)
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
	check("no-prompt-when-away", game.carryable_in_reach() == null,
		{"in_reach": game.carryable_in_reach()})
	var health_before: int = game.player.health
	check("drink-refused-when-away", not game.drink() and game.player.health == health_before,
		{"health": game.player.health})

	# Standing on it: prompt appears, drinking restores and consumes.
	game.player.position = Vector2(bottle.position.x, bottle.position.y)
	await steps(3)
	check("prompt-when-near", game.carryable_in_reach() == bottle,
		{"in_reach": game.carryable_in_reach()})
	# Checked before he raises it: the bottle starts emptying on the first frame
	# of the drink, so a moment later this is legitimately a frame short of six.
	check("full-bottle-quotes-six-seconds",
		absf(bottle.drink_seconds(game.player) - 6.0) < 0.01,
		{"seconds": bottle.drink_seconds(game.player)})
	health_before = game.player.health

	# Drinking is an animation, not an instant effect: he plays LF2's own
	# weapon_drink frames, with the bottle stamped on each frame's weapon point.
	var _lifted1: bool = await take_bottle()
	var drank: bool = game.drink()
	await steps(1)
	check("drink-plays-animation", drank and game.player.attack == "drink",
		{"attack": game.player.attack})
	check("bottle-appears-in-hand",
		game.player.carrying == bottle and bottle.carried
		and Moveset.wpoint("drink", game.player.attack_frame) != null,
		{"carrying": game.player.carrying == bottle,
		 "wpoint": str(Moveset.wpoint("drink", game.player.attack_frame))})
	check("health-not-granted-on-keypress", game.player.health == health_before,
		{"health": game.player.health, "before": health_before})
	check("bottle-not-spent-on-keypress", not bottle.consumed and bottle.carried,
		{"consumed": bottle.consumed, "carried": bottle.carried})
	var two_bars: int = bottle.heal_segments * game.player.segment_health()
	check("a-bottle-is-worth-two-bars", two_bars == 40, {"points": two_bars})

	# Measured in game seconds, not loop iterations. steps() awaits a physics
	# frame and a process frame, and those do not run one-for-one, so counting
	# iterations drifts by several percent and reads as a timing bug that is not
	# there. game.elapsed accumulates the same delta the drink does.
	var drink_started: float = game.elapsed
	var drink_ticks := 0
	while game.player.attack == "drink" and drink_ticks < 480:
		await steps(1)
		drink_ticks += 1
	var drink_took: float = game.elapsed - drink_started
	check("drink-takes-six-seconds", absf(drink_took - 6.0) < 0.2,
		{"seconds": snappedf(drink_took, 0.01), "expected": 6.0})
	check("drink-restores-two-bars",
		game.player.health == health_before + two_bars,
		{"before": health_before, "after": game.player.health, "restored": two_bars})
	check("drink-animation-ends", game.player.attack == "" and drink_ticks < 480,
		{"attack": game.player.attack, "ticks": drink_ticks})
	check("hand-empties-after-drinking", not game.player.is_carrying(),
		{"carrying": game.player.carrying})
	check("drink-consumes-bottle", bottle.consumed and game.carryable_in_reach() == null,
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
	var _lifted2: bool = await take_bottle()
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
	var second_started: float = game.elapsed
	var second_ticks := 0
	var _relift: bool = await take_bottle()
	var _resume: bool = game.drink()
	while game.player.is_drinking() and second_ticks < 480:
		await steps(1)
		second_ticks += 1
	var second_took: float = game.elapsed - second_started
	check("second-sitting-takes-only-what-is-left", absf(second_took - 3.0) < 0.25,
		{"seconds": snappedf(second_took, 0.01), "expected": 3.0})
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
	var half_started: float = game.elapsed
	var half_ticks := 0
	var _lifted3: bool = await take_bottle()
	var _halfdrink: bool = game.drink()
	while game.player.is_drinking() and half_ticks < 480:
		await steps(1)
		half_ticks += 1
	var half_took: float = game.elapsed - half_started
	check("half-bottle-takes-half-the-time", absf(half_took - 3.0) < 0.2,
		{"seconds": snappedf(half_took, 0.01), "expected": 3.0})
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
	# Walking out of reach is not in this list any more: he carries the bottle,
	# so there is no reach to leave. Losing hold of it is covered by the hit
	# tests below.
	for case in [
		{"id": "moving", "act": "axis"},
		{"id": "jumping", "act": "jump"},
		{"id": "attacking", "act": "attack"},
	]:
		await fresh()
		bottle = game.bottles[0]
		game.player.position = bottle.position
		await steps(3)
		health_before = game.player.health
		var _lift: bool = await take_bottle()
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
		await steps(3)
		check("%s-stops-the-drink" % case.id,
			started and not game.player.is_drinking(),
			{"started": started, "attack": game.player.attack})
		check("%s-keeps-the-mouthful" % case.id,
			game.player.health > health_before
			and game.player.health < health_before + two_bars,
			{"health": game.player.health, "before": health_before})
		check("%s-leaves-the-rest-in-the-bottle" % case.id,
			not bottle.consumed and bottle.available() and bottle.contents < 1.0,
			{"consumed": bottle.consumed, "contents": bottle.contents})
		# He lowers it from his mouth rather than dropping it, so the next drink
		# does not start with bending down for it again.
		check("%s-still-holds-the-bottle" % case.id,
			game.player.carrying == bottle,
			{"carrying": game.player.carrying == bottle})

	# --- a hit knocks it out of his hand -------------------------------------
	# Every other interruption leaves him holding it; a blow throws it clear, on
	# the same launch a thrown crate uses.
	await fresh()
	bottle = game.bottles[0]
	var floor_y: float = bottle.position.y
	game.player.position = bottle.position
	await steps(3)
	health_before = game.player.health
	var _lifted4: bool = await take_bottle()
	var _hitdrink: bool = game.drink()
	await steps(60)
	var _struck: bool = game.player.take_damage(20, game.player.global_position + Vector2(40, 0))
	await steps(1)
	check("a-hit-stops-the-drink", not game.player.is_drinking(), {"attack": game.player.attack})
	check("a-hit-empties-his-hands", not game.player.is_carrying(),
		{"carrying": game.player.carrying})
	check("a-hit-throws-the-bottle-clear",
		bottle.thrown and not bottle.carried and not bottle.at_rest,
		{"thrown": bottle.thrown, "at_rest": bottle.at_rest})
	check("a-dropped-bottle-starts-above-the-floor", bottle.position.y < floor_y - 8.0,
		{"y": bottle.position.y, "floor": floor_y})
	var fall_ticks := 0
	while not bottle.broken and fall_ticks < 300:
		await steps(1)
		fall_ticks += 1
	check("a-dropped-bottle-falls-and-comes-apart",
		bottle.broken and fall_ticks > 2,
		{"broken": bottle.broken, "ticks": fall_ticks, "y": bottle.position.y,
		 "floor": floor_y})
	# The blow costs a whole bar, which is more than a second of drinking was
	# worth — so the mouthful shows up as him being better off than a bar down,
	# not as a net gain.
	check("what-he-drank-before-the-blow-still-counted",
		game.player.health > health_before - 20,
		{"health": game.player.health, "before": health_before,
		 "bar_down_would_be": health_before - 20})

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

	# Every punch in the game lands well above the bottle's drawn height, so a hit
	# box matching the art would sit under all of them. This pins that a plain jab
	# can actually reach it.
	await stand_to_punch(bottle)
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
		not bottle.available() and game.carryable_in_reach() != bottle,
		{"available": bottle.available()})
	game.player.position = bottle.position
	await steps(3)
	check("no-prompt-over-a-smashed-bottle",
		game.carryable_in_reach() == null and not game.drink(),
		{"in_reach": game.carryable_in_reach()})

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

	# --- the enemy bandit -----------------------------------------------------
	# He is the first thing in the level that can take health off the player, so
	# these pin the whole loop: he closes, he swings, the swing costs exactly one
	# bar, and an empty bar kills on the same terms a pit does.
	await fresh()
	check("level-has-a-bandit", game.enemies.size() > 0, {"enemies": game.enemies.size()})
	var bandit: Area2D = game.enemies[0]
	await arm_enemies()
	check("bandit-has-the-players-energy", bandit.MAX_HEALTH == game.player.MAX_HEALTH,
		{"bandit": bandit.MAX_HEALTH, "player": game.player.MAX_HEALTH})
	# Even his charge — the fastest he ever moves — stays under the player's run,
	# so leaving is always an answer to a fight he does not want.
	check("bandit-is-outrunnable",
		float(bandit.prof.get("charge_speed", bandit.speed)) < game.player.tuning.speed,
		{"charge": bandit.prof.get("charge_speed", bandit.speed),
		 "player": game.player.tuning.speed})
	check("bandit-is-on-the-hittable-layer", bandit.get_collision_layer() & 64 != 0,
		{"layer": bandit.get_collision_layer()})

	# Closes the distance rather than waiting to be walked into.
	game.player.position = Vector2(bandit.position.x - 200, bandit.position.y)
	game.player.health = game.player.MAX_HEALTH
	await steps(3)
	var bandit_start: float = bandit.position.x
	await steps(45)
	check("bandit-walks-toward-the-player", bandit.position.x < bandit_start - 20.0,
		{"from": bandit_start, "to": bandit.position.x})

	# Closes, swings, and the swing costs exactly one bar of five.
	var before_hit: int = game.player.health
	var swung := 0
	while game.player.health == before_hit and swung < 300:
		await steps(1)
		swung += 1
	check("bandit-lands-a-punch", game.player.health < before_hit and swung < 300,
		{"health": game.player.health, "ticks": swung})
	check("bandit-hit-costs-exactly-one-bar",
		before_hit - game.player.health == game.player.segment_health(),
		{"lost": before_hit - game.player.health, "bar": game.player.segment_health()})

	# He may not empty the bar in a burst: a second blow inside the invulnerable
	# window is refused, which is what stops a bandit stood inside the player from
	# draining five bars in a third of a second.
	var after_one: int = game.player.health
	check("a-second-blow-is-refused-at-once",
		not game.player.take_damage(20, bandit.global_position)
		and game.player.health == after_one,
		{"health": game.player.health})
	await steps(int(game.player.HURT_INVULNERABLE * 60.0) + 6)
	check("a-blow-lands-again-once-the-window-passes",
		game.player.take_damage(20, bandit.global_position)
		and game.player.health == after_one - 20,
		{"health": game.player.health})

	# --- a punch breaks a drink and drops the bottle -------------------------
	await fresh()
	var drink_bottle: Area2D = game.bottles[0]
	game.player.position = drink_bottle.position
	game.player.health = game.player.MAX_HEALTH - 20
	await steps(3)
	var pre_drink: int = game.player.health
	var _lifted5: bool = await take_bottle()
	var _started2: bool = game.drink()
	await steps(60)
	check("drinking-before-the-punch", game.player.is_drinking(), {"attack": game.player.attack})
	var _hurt: bool = game.player.take_damage(20, game.player.global_position + Vector2(40, 0))
	await steps(3)
	check("a-punch-breaks-the-drink", not game.player.is_drinking(),
		{"attack": game.player.attack})
	check("a-punch-knocks-the-bottle-out-of-his-hands",
		not game.player.is_carrying() and drink_bottle.thrown
		and not drink_bottle.consumed,
		{"carrying": game.player.is_carrying(), "thrown": drink_bottle.thrown})
	check("the-mouthful-still-counted", game.player.health > pre_drink - 20,
		{"health": game.player.health, "before": pre_drink})

	# --- an empty bar is fatal ----------------------------------------------
	await fresh()
	game.player.health = 20
	await steps(2)
	var _fatal: bool = game.player.take_damage(20, game.player.global_position + Vector2(40, 0))
	await steps(4)
	check("an-empty-bar-kills", game.state == Game.State.DYING and game.player.health == 0,
		{"state": game.state, "health": game.player.health})
	check("death-names-the-bandits", game.death_reason.to_lower().contains("bandit"),
		{"reason": game.death_reason})

	# --- the bandit takes what the player throws ------------------------------
	await fresh()
	bandit = game.enemies[0]
	await arm_enemies()
	var bandit_home: Vector2 = bandit.position
	var bandit_full: int = bandit.health
	check("jab-hurts-the-bandit", bandit.take_hit(20, bandit.position - Vector2(40, 0))
		and bandit.health == bandit_full - 20,
		{"health": bandit.health})
	var jabs := 1
	while bandit.alive() and jabs < 12:
		bandit.take_hit(20, bandit.position - Vector2(40, 0))
		jabs += 1
	check("five-jabs-put-him-down", not bandit.alive() and jabs == 5,
		{"jabs": jabs, "health": bandit.health})
	check("a-downed-bandit-cannot-be-hit",
		not bandit.take_hit(20, bandit.position - Vector2(40, 0)),
		{"health": bandit.health})
	await steps(3)
	check("a-downed-bandit-stops-attacking", bandit.state == bandit.State.DEAD,
		{"state": bandit.state})

	# Retry brings him back, whole and where he started.
	game.restart_attempt()
	await steps(3)
	check("retry-restores-the-bandit",
		bandit.alive() and bandit.health == bandit.MAX_HEALTH and bandit.position == bandit_home,
		{"health": bandit.health, "position": str(bandit.position)})

	# He is a target, not a wall: the level is too narrow to be pinned in.
	await fresh()
	bandit = game.enemies[0]
	game.player.position = Vector2(bandit.position.x - 90, bandit.position.y)
	game.player.health = game.player.MAX_HEALTH
	game.player.test_axis = 1
	await steps(60)
	game.player.test_axis = 0
	check("walks-through-the-bandit", game.player.position.x > bandit.position.x + 10,
		{"player_x": game.player.position.x, "bandit_x": bandit.position.x})

	# --- lifting and throwing ------------------------------------------------
	# LF2's own two-beat handling: you pick a thing up before you use it, and
	# what you can do with it depends on its weight. A bottle rides in one hand
	# and gets drunk; a crate goes overhead and the only thing to do with it is
	# throw it at someone.
	await fresh()
	var box: Area2D = game.crates[0]
	var flask: Area2D = game.bottles[0]
	check("a-crate-is-heavy", bool(box.heavy), {"heavy": box.heavy})
	check("a-bottle-is-light", not bool(flask.heavy), {"heavy": flask.heavy})

	# Out of reach, nothing is lifted.
	game.player.position = Vector2(box.position.x - 300, box.position.y)
	await steps(3)
	check("nothing-to-lift-from-across-the-room",
		game.carryable_in_reach() == null and not game.pick_up(),
		{"in_reach": game.carryable_in_reach()})

	# At its feet, he bends and takes it.
	game.player.position = Vector2(box.position.x - 20, box.position.y)
	await steps(3)
	check("the-crate-is-in-reach", game.carryable_in_reach() == box, {})
	var lifted_it: bool = game.pick_up()
	check("lifting-plays-the-heavy-pick-up",
		lifted_it and game.player.attack == "pick_heavy",
		{"attack": game.player.attack})
	check("it-is-in-his-hands-from-the-first-frame",
		game.player.carrying == box and box.carried and game.player.carry_heavy,
		{"carrying": game.player.carrying == box, "carried": box.carried})

	var lift_wait := 0
	while game.player.attack != "" and lift_wait < 60:
		await steps(1)
		lift_wait += 1
	# Carried, not dropped: it rides the weapon point above his head rather than
	# falling back to the floor when the pick-up animation ends.
	check("a-carried-crate-rides-above-him",
		box.carried and box.position.y < game.player.position.y - 20.0,
		{"crate_y": box.position.y, "player_y": game.player.position.y})
	check("a-carried-crate-cannot-be-hit",
		not box.take_hit(20, game.player.global_position),
		{"health": box.health})
	check("hands-full-means-nothing-else-to-lift",
		not game.pick_up(), {"carrying": game.player.carrying})

	# It slows him, and it follows him.
	var carry_from: float = game.player.position.x
	game.player.test_axis = 1
	await steps(30)
	game.player.test_axis = 0
	check("carrying-something-heavy-slows-him",
		absf(game.player.velocity.x) <= game.player.tuning.speed * game.player.CARRY_SPEED + 1.0,
		{"speed": absf(game.player.velocity.x),
		 "cap": game.player.tuning.speed * game.player.CARRY_SPEED})
	check("the-crate-comes-with-him",
		game.player.position.x > carry_from + 20.0
		and absf(box.position.x - game.player.position.x) < 30.0,
		{"crate_x": box.position.x, "player_x": game.player.position.x})

	# Thrown, it flies, and it hurts what it lands on.
	await fresh()
	box = game.crates[0]
	var mark: Area2D = game.enemies[0]
	# Clear flat ground: the opening run is solid from 0 to 896 except a
	# platform at x 320..416, and a crate dropped on that lands on top of it.
	box.position = Vector2(520, 640)
	box.home = box.position
	mark.position = Vector2(615, 640)
	mark.home = mark.position
	mark.target = null
	game.player.position = Vector2(500, 640)
	await steps(6)
	var _got: bool = game.pick_up()
	await steps(30)
	game.player.facing = 1.0
	var mark_full: int = mark.health
	game.player.test_attack_pressed = true
	await steps(4)
	check("a-full-handed-attack-throws-instead-of-punching",
		game.player.attack == "throw_heavy", {"attack": game.player.attack})
	var flight := 0
	while not box.broken and flight < 200:
		await steps(1)
		flight += 1
	check("the-throw-leaves-his-hands",
		not game.player.is_carrying(), {"carrying": game.player.carrying})
	check("a-thrown-crate-hits-what-it-reaches",
		mark.health == mark_full - box.throw_damage,
		{"health": mark.health, "was": mark_full, "damage": box.throw_damage})
	check("a-thrown-crate-comes-apart-on-impact",
		box.broken and flight > 2, {"broken": box.broken, "ticks": flight})

	# A throw that reaches nobody still lands and breaks, rather than sliding on
	# for ever as a live hazard.
	await fresh()
	box = game.crates[0]
	box.position = Vector2(520, 640)
	box.home = box.position
	game.enemies[0].position = Vector2(2000, 640)
	game.player.position = Vector2(500, 640)
	await steps(6)
	var _got2: bool = game.pick_up()
	await steps(30)
	game.player.facing = 1.0
	game.player.test_attack_pressed = true
	var empty_flight := 0
	while not box.broken and empty_flight < 200:
		await steps(1)
		empty_flight += 1
	check("a-throw-that-hits-nothing-still-lands-and-breaks",
		box.broken and box.position.x > 560.0,
		{"x": box.position.x, "ticks": empty_flight})

	# The bottle is the other half of the rule: lifted first, drunk second.
	await fresh()
	flask = game.bottles[0]
	game.player.position = flask.position
	await steps(3)
	check("drinking-is-refused-with-empty-hands",
		not game.drink() and not game.player.is_drinking(),
		{"carrying": game.player.carrying})
	var took: bool = game.pick_up()
	check("lifting-a-bottle-plays-the-light-pick-up",
		took and game.player.attack == "pick_light" and not game.player.carry_heavy,
		{"attack": game.player.attack, "heavy": game.player.carry_heavy})
	var bwait := 0
	while game.player.attack != "" and bwait < 60:
		await steps(1)
		bwait += 1
	check("a-light-carry-does-not-slow-him", not game.player.carry_heavy, {})
	check("now-it-can-be-drunk", game.drink() and game.player.is_drinking(),
		{"attack": game.player.attack})

	# --- hit reactions, both sides -------------------------------------------
	# Both packs draw a recoil and both use it. A blow that only moved a number
	# on the HUD would not read as a blow at all.
	await fresh()
	check("the-player-has-a-hurt-animation", Moveset.has("hurt"),
		{"animations": Moveset.animations().keys()})
	check("the-stun-is-shorter-than-the-invulnerable-window",
		game.player.HURT_STUN < game.player.HURT_INVULNERABLE,
		{"stun": game.player.HURT_STUN, "window": game.player.HURT_INVULNERABLE})

	game.player.position = Vector2(400, 640)
	game.player.health = game.player.MAX_HEALTH
	await steps(3)
	var _blow: bool = game.player.take_damage(20, game.player.global_position + Vector2(40, 0))
	await steps(2)
	check("a-blow-stuns-him", game.player.is_hurt(), {"stun": game.player.hurt_stun})
	check("a-blow-plays-the-hurt-animation",
		game.player.visual.sprite.animation == "hurt",
		{"playing": game.player.visual.sprite.animation})

	# Stunned, the controls do nothing.
	var held_x: float = game.player.position.x
	game.player.test_axis = 1
	game.player.test_jump_pressed = true
	await steps(6)
	check("the-stun-takes-the-controls",
		absf(game.player.position.x - held_x) < 2.0 and game.player.jumps == 0,
		{"moved": game.player.position.x - held_x, "jumps": game.player.jumps})

	# And gives them back. A stun that outlasted its welcome would be a sentence.
	var waited := 0
	while game.player.is_hurt() and waited < 120:
		await steps(1)
		waited += 1
	await steps(8)
	check("the-stun-wears-off",
		not game.player.is_hurt() and game.player.position.x > held_x + 10.0,
		{"moved": game.player.position.x - held_x, "ticks": waited})
	game.player.test_axis = 0
	check("the-hurt-pose-is-dropped-afterwards",
		game.player.visual.sprite.animation != "hurt",
		{"playing": game.player.visual.sprite.animation})

	# Being hit cancels whatever he was throwing.
	await fresh()
	await stand_to_punch(game.crates[0])
	game.player.test_attack_pressed = true
	await steps(2)
	check("swinging-before-the-blow", game.player.attack != "", {"attack": game.player.attack})
	var _blow2: bool = game.player.take_damage(20, game.player.global_position + Vector2(40, 0))
	await steps(1)
	check("a-blow-cancels-his-attack", game.player.attack == "" and game.player.is_hurt(),
		{"attack": game.player.attack})

	# Falling is not part of the stun: freezing him in mid-air over a pit would
	# turn one punch into a death.
	await fresh()
	game.player.position = Vector2(950, 400)
	await steps(2)
	var fell_from: float = game.player.position.y
	var _blow3: bool = game.player.take_damage(20, game.player.global_position + Vector2(40, 0))
	await steps(6)
	check("gravity-survives-the-stun",
		game.player.is_hurt() and game.player.position.y > fell_from + 8.0,
		{"fell": game.player.position.y - fell_from})

	# The bandit's recoil is his own pack's, on the same terms.
	await fresh()
	bandit = game.enemies[0]
	await arm_enemies()
	var _bhit: bool = bandit.take_hit(20, bandit.global_position - Vector2(40, 0))
	await steps(2)
	check("a-struck-bandit-recoils",
		bandit.state == bandit.State.HURT and bandit.sprite.animation == "hurt",
		{"state": bandit.state, "playing": bandit.sprite.animation})
	check("a-struck-bandit-uses-the-recoil-frames-only", bandit.sprite.frame <= 1,
		{"frame": bandit.sprite.frame})
	var recovering := 0
	while bandit.state == bandit.State.HURT and recovering < 120:
		await steps(1)
		recovering += 1
	check("the-bandit-recovers", bandit.alive() and bandit.state != bandit.State.HURT,
		{"state": bandit.state, "ticks": recovering})

	# Down, the same strip runs on into the collapse and stays there.
	while bandit.alive():
		bandit.take_hit(20, bandit.global_position - Vector2(40, 0))
		await steps(2)
	await steps(40)
	var hurt_frames: int = Moveset.frame_count("hurt")
	check("a-downed-bandit-holds-the-collapse",
		bandit.sprite.animation == "hurt"
		and bandit.sprite.frame == bandit.sprite.sprite_frames.get_frame_count("hurt") - 1,
		{"playing": bandit.sprite.animation, "frame": bandit.sprite.frame,
		 "player_hurt_frames": hurt_frames})

	# --- the bandit is a charger ---------------------------------------------
	# He no longer ambles up like the walker he was: from mid-range he commits a
	# dash, moving far faster than his walk, which is what punishes standing still.
	await fresh()
	var chg: Area2D = game.enemies[0]
	check("bandit-is-the-charger", chg.style == "charger", {"style": chg.style})
	for other in game.enemies:
		other.target = null
	chg.position = Vector2(820, 640); chg.home = chg.position
	chg.target = game.player
	game.player.position = Vector2(740, 640)
	game.player.health = game.player.MAX_HEALTH
	await steps(2)
	var charged := false
	for i in range(120):
		await steps(1)
		if chg.state == chg.State.CHARGE or absf(chg.velocity.x) > chg.speed + 8.0:
			charged = true
			break
	check("a-bandit-charges-from-mid-range", charged,
		{"state": chg.state, "vx": chg.velocity.x, "walk": chg.speed})

	# --- two more kinds: Mark and Hunter, spawned from level entries ----------
	# proving_ground carries [1000, 640, "mark"] and [430, 640, "hunter"]. This
	# exercises the whole path the roster adds — the session reads the kind off
	# each entry, the enemy loads its own art folder, and everything the bandit
	# does works on them unchanged.
	await fresh()
	game.load_level("proving_ground")
	game.start_session()
	game.player.test_control = true
	await steps(3)
	var mk: Area2D = null
	var hn: Area2D = null
	for foe in game.enemies:
		if foe.kind == "mark":
			mk = foe
		elif foe.kind == "hunter":
			hn = foe
	check("proving-ground-spawns-mark-and-hunter",
		mk != null and hn != null and game.enemies.size() == 2,
		{"count": game.enemies.size(),
		 "first_kind": game.enemies[0].kind if game.enemies.size() > 0 else "<none>"})
	check("mark-loads-his-own-manifest",
		mk != null and mk.data().get("animations", {}).size() == 4
		and str(mk.data().get("_source", "")).contains("Mark"),
		{"source": mk.data().get("_source", "") if mk != null else "<none>"})
	check("hunter-loads-his-own-manifest",
		hn != null and hn.data().get("animations", {}).size() >= 4
		and hn.data().get("animations", {}).has("shoot")
		and str(hn.data().get("_source", "")).contains("Hunter"),
		{"anims": hn.data().get("animations", {}).keys() if hn != null else [],
		 "source": hn.data().get("_source", "") if hn != null else "<none>"})
	# Each carries its own geometry: Mark's jab reaches further than Hunter's.
	check("the-two-kinds-have-their-own-reach",
		mk != null and hn != null and mk.reach() > 0.0 and hn.reach() > 0.0
		and mk.reach() != hn.reach(),
		{"mark": mk.reach() if mk != null else -1.0,
		 "hunter": hn.reach() if hn != null else -1.0})

	# --- personality: they fight to type ------------------------------------
	# Mark is the tank — more health than the standard bar and a heavier blow than
	# the archer's melee; Hunter is the glass one who fights at range.
	check("mark-is-the-bruiser",
		mk != null and hn != null and mk.style == "bruiser"
		and mk.max_health > mk.MAX_HEALTH and mk.attack_damage() > hn.attack_damage(),
		{"style": mk.style if mk != null else "<none>",
		 "health": mk.max_health if mk != null else -1,
		 "damage": mk.attack_damage() if mk != null else -1,
		 "hunter_damage": hn.attack_damage() if hn != null else -1})
	check("hunter-is-the-archer",
		hn != null and hn.style == "archer" and hn.max_health < hn.MAX_HEALTH,
		{"style": hn.style if hn != null else "<none>",
		 "health": hn.max_health if hn != null else -1})

	# Mark swings through a blow: caught mid-punch, he keeps the swing and only
	# takes the damage — you cannot trade jabs with him and win the exchange.
	if mk != null:
		for other in game.enemies:
			other.target = null
		mk.position = Vector2(1050, 640); mk.home = mk.position
		mk.target = game.player
		game.player.position = Vector2(1050 - mk.attack_range() * 0.7, 640)
		game.player.health = game.player.MAX_HEALTH
		var to_punch := 0
		while mk.state != mk.State.PUNCH and to_punch < 120:
			await steps(1)
			to_punch += 1
		check("mark-throws-his-punch", mk.state == mk.State.PUNCH,
			{"state": mk.state, "ticks": to_punch})
		var armor_hp: int = mk.health
		var _sa: bool = mk.take_hit(20, mk.global_position - Vector2(40.0, 0.0))
		check("mark-swings-through-a-blow",
			mk.state == mk.State.PUNCH and mk.health == armor_hp - 20,
			{"state": mk.state, "health": mk.health, "was": armor_hp})
		mk.reset()

	# Hunter fights at range: from across the gap he draws the bow and looses an
	# arrow — a real travelling object — that crosses to the player and hurts.
	if hn != null:
		for other in game.enemies:
			other.target = null
		# Both east of the spikes (800..848): hunter far, the player 180 back — out
		# of melee, inside fire range, on clear floor.
		hn.position = Vector2(1120, 640); hn.home = hn.position
		hn.target = game.player
		game.player.position = Vector2(940, 640)
		game.player.health = game.player.MAX_HEALTH
		var before_arrow: int = game.player.health
		var saw_arrow := false
		var arrow_hit := false
		var at := 0
		while not arrow_hit and at < 400:
			await steps(1)
			at += 1
			if game.arrows.size() > 0:
				saw_arrow = true
			if game.player.health < before_arrow:
				arrow_hit = true
		check("hunter-looses-an-arrow", saw_arrow,
			{"saw_arrow": saw_arrow, "state": hn.state})
		check("the-arrow-crosses-and-connects", arrow_hit,
			{"health": game.player.health, "was": before_arrow, "ticks": at})
		hn.reset()

	# Each closes, lands a punch, and goes down through its own hurt run — on its
	# own clear patch, with the other parked, so neither steals the other's blow.
	if mk != null:
		await fight_one(mk, "mark", Vector2(1120, 640))
	if hn != null:
		await fight_one(hn, "hunter", Vector2(200, 640))

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
