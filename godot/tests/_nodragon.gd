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
const Enemy = preload("res://features/combat/enemy.gd")
const Crate = preload("res://features/combat/crate.gd")
const PlayerSprite = preload("res://features/player/player_sprite.gd")

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

## An enemy of the test's own, wired the way the session wires the level's ones.
## The signal matters: an enemy whose struck_player goes nowhere can swing all it
## likes and the player's health never moves, so a jump attack would look like a
## miss.
## `on_roster` puts him in game.enemies as well as in the scene. Off by default
## because a test enemy on the roster also becomes a gate holder and a camera
## consideration; on for anything that needs the session to talk to him, which
## right now means warn_of_blast — that is delivered by the session walking
## `enemies`, so an enemy who is only a child never hears a blast coming.
func spawn_foe(kind: String, at: Vector2, on_roster: bool = false) -> Area2D:
	var foe := Enemy.new()
	foe.kind = kind
	foe.position = at
	foe.fall_limit = float(game.level.fall_y)
	foe.struck_player.connect(game._on_player_struck)
	if on_roster:
		game.enemies.append(foe)
	game.add_child(foe)
	await steps(2)
	foe.target = game.player
	return foe

## Tell an enemy a blast is on its way from `gap` px in front of him, and wait
## for him to decide. Returns true if his arms came up. The warning is delivered
## by hand rather than by throwing a real one, so the geometry under test is the
## gap and nothing else — no animation timing, no mana, no travel.
func incoming(foe: Area2D, gap: float) -> bool:
	var from := Vector2(foe.position.x - gap, foe.position.y)
	foe.warn_of_blast(from, 1.0, 560.0)
	var waited := 0
	while waited < 90:
		await steps(1)
		waited += 1
		if foe.guarding():
			return true
		if foe.guard_due < 0.0 and foe.guard_hold <= 0.0:
			return false
	return false

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
## Takes a bar off him, so a milk bottle has somewhere to go. He spawns on the
## whole bar now and drink() refuses one at full health — which is the game's
## rule and is checked on its own — so every test that is ABOUT the drink has to
## give him a reason to want one first. Exactly one bottle's worth, so a full
## bottle still lands in full and the six seconds stay six.
func thirsty() -> void:
	game.player.health = game.player.MAX_HEALTH - 40

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
	# The LAST crate, not the first. A blast is stopped by level geometry, and
	# the first crate is knocked back onto the raised step at x 320 — where the
	# step's own face eats the second blast before it arrives. This one sits on
	# the long flat run at the end with nothing raised within the knockback, so
	# the check measures the projectile rather than the scenery. It passed on the
	# first crate for years by 2.45 px: the old wooden box was wide enough to
	# overhang the step's edge into the same query, and the narrower rock is not.
	crate = game.crates[game.crates.size() - 1]
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

	# --- a fight, once started, is not walked away from ---------------------
	# Two rules pulling against each other. An enemy must not set off across the
	# level the moment it loads — that is what `aggro` is for. But one that lets
	# you take three steps back and then forgets you, turns round and stands
	# there, reads as broken rather than as an escape. So aggro decides when the
	# fight STARTS, and after that he follows.
	await fresh()
	var slow: Area2D = game.enemies[0]
	for other in game.enemies:
		if other != slow:
			other.target = null
	slow.armor = true            # stand in for the bruiser on a greybox level
	slow.position = Vector2(700, 640)
	slow.home = slow.position
	slow.target = game.player
	# Well outside his aggro, on the same floor.
	game.player.position = Vector2(700 - slow.aggro - 120.0, 640)
	game.player.velocity = Vector2.ZERO
	await steps(40)
	check("he-stays-put-until-the-fight-starts",
		not slow.engaged and absf(slow.position.x - 700.0) < 2.0,
		{"engaged": slow.engaged, "x": slow.position.x, "aggro": slow.aggro})

	# Walk into his range: that is the fight starting.
	game.player.position = Vector2(700 - slow.aggro + 80.0, 640)
	await steps(20)
	check("walking-into-his-range-starts-it", slow.engaged,
		{"engaged": slow.engaged, "gap": absf(slow.position.x - game.player.position.x)})

	# Back off well past aggro. He has to keep coming.
	var stood_at: float = slow.position.x
	game.player.position = Vector2(700 - slow.aggro - 200.0, 640)
	await steps(180)
	check("and-then-he-follows-you-out-of-range",
		slow.engaged and stood_at - slow.position.x > 40.0,
		{"closed": stood_at - slow.position.x,
		 "gap": absf(slow.position.x - game.player.position.x),
		 "aggro": slow.aggro})

	# A blast from outside aggro must start it too, or the ranged option would be
	# a way to poke a statue that never answers.
	await fresh()
	var sniped: Area2D = game.enemies[0]
	for other in game.enemies:
		if other != sniped:
			other.target = null
	sniped.target = game.player
	sniped.position = Vector2(900, 640)
	sniped.home = sniped.position
	game.player.position = Vector2(900 - sniped.aggro - 150.0, 640)
	await steps(20)
	check("still-idle-before-the-shot", not sniped.engaged, {"engaged": sniped.engaged})
	var _sniped_hit: bool = sniped.take_hit(10, game.player.position)
	await steps(4)
	check("a-hit-from-out-of-range-starts-it", sniped.engaged,
		{"engaged": sniped.engaged})

	# And a retry puts him back on his mark, forgetting the fight.
	game.restart_attempt()
	await steps(6)
	check("a-retry-un-engages-him",
		not sniped.engaged and absf(sniped.position.x - sniped.home.x) < 2.0,
		{"engaged": sniped.engaged, "x": sniped.position.x, "home": sniped.home.x})

	# --- jumping: the terrain stops being a free win ------------------------
	# Three things the ground used to do for the player. A gap ended a chase, or
	# ate the enemy — and an enemy who fell in his own section's pit opened that
	# section's gate for free. A ledge 60 px up made him harmless, because every
	# attack in this game is thrown dead flat. And jumping clean over his head
	# was a way past him with no answer at all.
	#
	# Staged on a private patch of ground 600 px above the level, where there is
	# nothing else, so the widths below are exactly the widths under test and
	# stay that way the next time the course is re-authored.
	await fresh()
	var deck := -600.0
	for parked in game.enemies:
		parked.target = null
	game._add_solid(Rect2(0, deck, 400, 200))          # near floor
	game._add_solid(Rect2(484, deck, 400, 200))        # an 84 px gap, same height
	game._add_solid(Rect2(1000, deck, 400, 200))       # and a 220 px one
	game._add_solid(Rect2(1620, deck, 400, 200))
	game._add_solid(Rect2(2200, deck, 500, 200))       # flat, with a shelf over it
	game._add_solid(Rect2(2400, deck - 64.0, 120, 24))
	await steps(2)

	# Flat ground first, because the failure mode of a jump planner is jumping.
	# An enemy who hops his way along level floor reads as a broken animation,
	# not as intelligence.
	var hopper: Area2D = await spawn_foe("bandit", Vector2(2240, deck))
	game.player.position = Vector2(2560, deck)
	game.player.velocity = Vector2.ZERO
	var pogo := false
	for i in range(90):
		await steps(1)
		if hopper.state == hopper.State.JUMP:
			pogo = true
			break
	check("flat-ground-is-walked-not-hopped",
		not pogo and hopper.position.x > 2250.0,
		{"jumped": pogo, "x": hopper.position.x})

	# A player 90 px over his head — the height his own jump reaches, and half
	# again the 60 px band every ground attack is stuck inside. He goes up after
	# him, and the swing he throws on the way is the same swing with the same
	# box: it is simply higher, because he is.
	#
	# The player stands on a ledge rather than being held in mid-air: steps() is
	# a PROCESS frame and Godot runs up to eight physics ticks inside one, so a
	# player pinned once per step falls most of a jump's height between pins and
	# the two arcs never meet. See tests/diag_jump.gd.
	#
	# The enemy starts 50 px to one side, not underneath, and is reset() first.
	# A fist reaches FORWARD, 12 to 30 px ahead of him, so an enemy directly
	# below the player swings past him on both sides and connects with nothing —
	# which is exactly where a bandit ends up if he carries a charge in from the
	# walk above, because he overruns.
	game._add_solid(Rect2(2600, deck - 90.0, 200, 20))
	await steps(2)
	hopper.reset()
	hopper.position = Vector2(2570, deck)
	hopper.home = hopper.position
	hopper.engaged = true
	game.player.position = Vector2(2620, deck - 90.0)
	game.player.velocity = Vector2.ZERO
	await steps(2)
	var before_hop: int = game.player.health
	var went_up := false
	var caught_airborne := false
	for i in range(150):
		await steps(1)
		if hopper.position.y < deck - 20.0:
			went_up = true
		if game.player.health < before_hop:
			caught_airborne = not hopper.grounded
			break
	check("a-player-above-him-is-followed-up", went_up,
		{"state": hopper.state, "y": hopper.position.y, "deck": deck,
		 "apex": hopper.jump_apex()})
	check("and-caught-by-a-punch-thrown-out-of-the-jump", caught_airborne,
		{"health": game.player.health, "before": before_hop,
		 "y": hopper.position.y, "grounded": hopper.grounded})

	# The shelf: 64 px up, which is over the 60 px band every ground attack is
	# limited to. Standing on it used to be immunity.
	hopper.position = Vector2(2560, deck)
	hopper.velocity = Vector2.ZERO
	hopper.hop_cooldown = 0.0
	game.player.position = Vector2(2460, deck - 64.0)
	game.player.velocity = Vector2.ZERO
	var climbed := false
	for i in range(180):
		await steps(1)
		if hopper.grounded and absf(hopper.position.y - (deck - 64.0)) < 4.0:
			climbed = true
			break
	check("a-ledge-is-climbed-not-stared-at", climbed,
		{"x": hopper.position.x, "y": hopper.position.y, "shelf": deck - 64.0})

	# The 84 px gap. From the lip that is (84 + 20 + 18) / 0.75 = 163 px/s of the
	# bandit's 215 — inside his reach with room to spare. Which of the course's
	# own gaps that works out to is tests/diag_gaps.gd's question, not this one's:
	# it crosses 24, 60, 72, 96 and 120 px on the Isles and holds the lip at 132
	# and up.
	var leaper: Area2D = await spawn_foe("bandit", Vector2(340, deck))
	game.player.position = Vector2(560, deck)
	game.player.velocity = Vector2.ZERO
	var across := false
	for i in range(180):
		await steps(1)
		if leaper.grounded and leaper.position.x > 484.0:
			across = true
			break
	check("a-gap-he-can-clear-is-leapt", across and leaper.alive(),
		{"x": leaper.position.x, "y": leaper.position.y, "alive": leaper.alive(),
		 "reach": leaper.leap_speed * leaper.air_time()})

	# And the other half, which matters more: a gap too wide for him stops him at
	# the lip. He does not walk in. Falling in used to be how an enemy opened his
	# own gate, and it is the difference between reckless and broken.
	var stopper: Area2D = await spawn_foe("bandit", Vector2(1340, deck))
	game.player.position = Vector2(1660, deck)
	game.player.velocity = Vector2.ZERO
	await steps(150)
	check("a-gap-he-cannot-clear-stops-him-at-the-lip",
		stopper.alive() and absf(stopper.position.y - deck) < 4.0
			and stopper.position.x > 1340.0 and stopper.position.x < 1404.0,
		{"x": stopper.position.x, "y": stopper.position.y, "lip": 1400.0,
		 "alive": stopper.alive(),
		 "reach": stopper.leap_speed * stopper.air_time()})

	# The archer is the exception, and on purpose: one who leaps at you has given
	# up the only thing he is for. He jumps to keep his footing, never at you.
	var archer: Area2D = await spawn_foe("hunter", Vector2(2300, deck))
	game.player.position = Vector2(2460, deck - 64.0)
	game.player.velocity = Vector2.ZERO
	archer.engaged = true
	var archer_hopped := false
	for i in range(120):
		await steps(1)
		if archer.state == archer.State.JUMP:
			archer_hopped = true
			break
	check("an-archer-never-leaps-at-you", not archer_hopped,
		{"state": archer.state, "style": archer.style})

	# --- and the jump must not reach the perches ----------------------------
	# The hunters on the Isles' high shelves sit 144 px up and more. The whole
	# section-gate design rests on them being out of the fight — see holds_gate
	# in enemy.gd — so a jump that could carry one down into it, or carry a deck
	# enemy up onto it, would be a level design change wearing an AI change's
	# clothes. 101 px of jump and a 120 px drop limit keep them where they are.
	await fresh()
	game.load_level("fractured_isles")     # the only level that has any
	game.start_session()
	game.player.test_control = true
	await steps(3)
	game.player.position = Vector2(3950, 660)
	game.player.velocity = Vector2.ZERO
	var roosts := {}
	for foe in game.enemies:
		# Only the perches are armed: a deck enemy killing the player would end
		# the attempt, and a retry puts everybody back on their mark, which would
		# pass this check without ever testing it.
		foe.target = null if foe.holds_gate else game.player
		if not foe.holds_gate:
			roosts[foe] = foe.position
	await steps(180)
	# Height, not position: an archer shuffling along his own shelf to hold his
	# range is doing his job. Coming DOWN off it is the thing that would be a
	# level redesign, and it is the only thing this asserts.
	var worst := 0.0
	for foe in roosts:
		worst = maxf(worst, absf(foe.position.y - float(roosts[foe].y)))
	check("a-perch-is-still-out-of-reach", worst < 8.0 and roosts.size() > 0,
		{"perches": roosts.size(), "drifted": worst,
		 "apex": Enemy.JUMP_VELOCITY * Enemy.JUMP_VELOCITY / (2.0 * Enemy.GRAVITY),
		 "drop_limit": Enemy.DROP_LIMIT})

	# --- the guard: mashing K stops being the answer ------------------------
	# Three blasts killed a bandit, and nothing about throwing them from across
	# the room was worse than throwing them from arm's length. So the answer to
	# every fight in the game was the same key, held down.
	#
	# Now anyone with time to SEE one coming gets his arms up. What "time" means
	# is the whole design: a fixed reaction per kind, cut to a fraction of itself
	# while he is braced — and he braces on every blast that goes past him, hit
	# or miss. Mash it and he reads them from almost on top of him; throw one and
	# wait, or throw it from close, and it lands.
	await fresh()
	var deck2 := -600.0
	for parked2 in game.enemies:
		parked2.target = null
	game._add_solid(Rect2(2000, deck2, 900, 200))
	await steps(2)
	game.player.position = Vector2(2100, deck2)
	game.player.velocity = Vector2.ZERO

	var blocker: Area2D = await spawn_foe("bandit", Vector2(2600, deck2))
	blocker.target = null      # this is about the blast, not about the chase
	var cold: float = blocker.guard_reaction * 560.0
	check("a-blast-from-across-the-room-is-seen-coming",
		await incoming(blocker, cold + 110.0),
		{"reaction_px": cold, "thrown_from": cold + 110.0})

	# What a block is worth. Not immunity — a fifth still gets through — and no
	# stagger, so he is not held still by being shot at.
	var unhurt: int = blocker.health
	var pool: float = blocker.guard
	var stopped: bool = blocker.take_hit(45, Vector2(blocker.position.x - 40.0, blocker.position.y))
	check("a-guarded-blast-is-soaked-not-ignored",
		stopped and blocker.health < unhurt and unhurt - blocker.health <= 12
			and blocker.guard < pool and blocker.state != blocker.State.HURT,
		{"lost": unhurt - blocker.health, "of": 45, "guard": blocker.guard,
		 "was": pool, "state": blocker.state})

	# Cold, from inside his reaction, there is no guard at all. This is the
	# counter: close the distance.
	blocker.reset()
	blocker.target = null
	await steps(2)
	check("a-blast-from-close-up-cannot-be",
		not await incoming(blocker, cold - 50.0),
		{"reaction_px": cold, "thrown_from": cold - 50.0})

	# And the anti-spam rule, which is the whole point. The same throw, from the
	# same place, read this time because one went past a moment ago.
	blocker.reset()
	blocker.target = null
	await steps(2)
	var cold_throw: bool = await incoming(blocker, cold - 50.0)
	var braced_throw: bool = await incoming(blocker, cold - 50.0)
	check("but-mashing-it-gets-that-same-throw-read",
		not cold_throw and braced_throw,
		{"cold": cold_throw, "braced": braced_throw, "braced_px": blocker.guard_reaction
			* blocker.BRACED_REACTION * 560.0})

	# Guards break. Spend the pool and the blow that empties it is the one that
	# gets through — full damage, full stagger, and no guard for a while after.
	blocker.reset()
	blocker.target = null
	await steps(2)
	var blocks := 0
	var broke := false
	for i in range(8):
		if not await incoming(blocker, cold + 110.0):
			break
		var hp: int = blocker.health
		var _b: bool = blocker.take_hit(45, Vector2(blocker.position.x - 40.0, blocker.position.y))
		if hp - blocker.health >= 45:
			broke = true
			break
		blocks += 1
	check("a-guard-can-be-broken-by-spending-it",
		broke and blocks >= 2,
		{"blocked": blocks, "broke": broke, "guard": blocker.guard,
		 "pool": blocker.max_guard})
	check("and-a-broken-guard-staggers-him",
		blocker.state == blocker.State.HURT and blocker.guard < 1.0,
		{"state": blocker.state, "guard": blocker.guard})

	# A guard faces one way. Walking round him is not a thing the player can do
	# — there is no depth — but the blast he did not see is still the blast that
	# works, and a thrown rock from behind counts.
	blocker.reset()
	blocker.target = null
	await steps(2)
	var _seen: bool = await incoming(blocker, cold + 110.0)
	blocker.facing = 1.0        # looking away from where the blow lands
	var behind: int = blocker.health
	var _hit2: bool = blocker.take_hit(45, Vector2(blocker.position.x - 40.0, blocker.position.y))
	check("a-blow-from-behind-is-not-guarded",
		behind - blocker.health >= 45,
		{"lost": behind - blocker.health, "guarding": blocker.guarding()})

	# The boss has no guard, and on purpose: his pack ships no defend frame, so
	# a block of his would be invisible. Pinned here so that stays a decision.
	var boss: Area2D = await spawn_foe("dragon_lord", Vector2(2300, deck2))
	boss.target = null
	await steps(2)
	var boss_guarded: bool = await incoming(boss, 400.0)
	check("the-boss-does-not-guard",
		not boss_guarded and boss.max_guard == 0.0,
		{"pool": boss.max_guard, "guarded": boss_guarded})

	# What he does instead: breathes on it. The range he can do it from is his
	# own wind-up rather than a number — the fire is 0.36 s into his swing, so he
	# needs that much of the blast's flight to meet it.
	var wind_up: float = boss.hit_lead("punch") * 560.0
	boss.reset()
	boss.target = null
	await steps(2)
	boss.warn_of_blast(Vector2(boss.position.x - (wind_up + 140.0), boss.position.y),
			1.0, 560.0)
	var swung_at_it := false
	var fire_out := false
	for i in range(90):
		await steps(1)
		if boss.state == boss.State.PUNCH:
			swung_at_it = true
		if boss.burns_projectiles():
			fire_out = true
	check("the-boss-answers-one-with-his-own-fire",
		swung_at_it and fire_out,
		{"swung": swung_at_it, "fire_out": fire_out, "wind_up_px": wind_up})

	# And cannot from inside it — the same lesson the guard teaches, arrived at
	# from the other direction. blast.gd asks burns_projectiles() before it
	# resolves a hit; capture_boss.gd drives that end to end with real blasts.
	boss.reset()
	boss.target = null
	await steps(2)
	boss.warn_of_blast(Vector2(boss.position.x - (wind_up - 60.0), boss.position.y),
			1.0, 560.0)
	var swung_close := false
	for i in range(60):
		await steps(1)
		if boss.state == boss.State.PUNCH:
			swung_close = true
			break
	check("but-not-one-thrown-from-inside-that-wind-up", not swung_close,
		{"thrown_from": wind_up - 60.0, "wind_up_px": wind_up})

	# End to end, through the session: a real blast, really thrown, really seen.
	# Everything above hands the enemy the warning directly; this is the wiring.
	await fresh()
	for parked3 in game.enemies:
		parked3.target = null
	game._add_solid(Rect2(2000, deck2, 900, 200))
	await steps(2)
	var shot_at: Area2D = await spawn_foe("bandit", Vector2(2600, deck2), true)
	shot_at.target = null
	game.player.position = Vector2(2600 - 280.0, deck2)
	game.player.velocity = Vector2.ZERO
	game.player.facing = 1.0
	game.player.mana = game.player.MAX_MANA
	await steps(3)
	var guarded_a_real_one := false
	var before_shot: int = shot_at.health
	game.player.test_blast_pressed = true
	for i in range(140):
		await steps(1)
		if shot_at.guarding():
			guarded_a_real_one = true
		if shot_at.health < before_shot:
			break
	check("a-thrown-blast-reaches-him-as-a-warning",
		guarded_a_real_one and shot_at.health < before_shot
			and before_shot - shot_at.health <= 12,
		{"guarded": guarded_a_real_one, "lost": before_shot - shot_at.health,
		 "blasts": game.blasts.size()})
	game.enemies.erase(shot_at)

	# --- the two paths the rock needs ---------------------------------------
	# Neither is used by the crate or the bottle: both break straight into flying
	# debris and both have drawn tumble angles. The rock sheet has five break
	# frames and no angles at all, so prop.gd grew a drawn-shatter path and a
	# rotate-the-sprite path for it. Exercised here against the crate's own art
	# as a stand-in, so they are not first run in front of a player.
	await fresh()
	var mock: Area2D = Crate.new()
	# Any multi-frame strip proves the stepping; crate_spin has six.
	mock.art_break = "crate_spin"
	mock.break_step = 0.05
	mock.position = Vector2(700, 640)
	game.add_child(mock)
	await steps(2)
	# Twice: SURVIVES_FIRST_BLOW leaves anything at full health on one point, so
	# a single hit of any size only dents it.
	var _dent: bool = mock.take_hit(999, mock.position - Vector2(40, 0))
	await steps(1)
	var _killed: bool = mock.take_hit(999, mock.position - Vector2(40, 0))
	await steps(1)
	check("a-drawn-break-plays-where-it-stood",
		mock.broken and mock.breaking and mock.sprite.visible
		and mock.debris.is_empty(),
		{"breaking": mock.breaking, "visible": mock.sprite.visible,
		 "pieces": mock.debris.size()})
	var stepped := false
	var strip_ticks := 0
	while mock.breaking and strip_ticks < 90:
		if mock.sprite.texture != mock.break_frames[0]:
			stepped = true
		await steps(1)
		strip_ticks += 1
	check("the-drawn-break-steps-through-its-frames", stepped,
		{"frames": mock.break_frames.size(), "ticks": strip_ticks})
	check("the-pieces-fly-once-the-strip-is-done",
		not mock.breaking and not mock.sprite.visible
		and mock.debris.size() == mock.debris_types.size(),
		{"pieces": mock.debris.size(), "expected": mock.debris_types.size(),
		 "visible": mock.sprite.visible})

	# And a prop with no drawn angles turns its own sprite instead of flying rigid.
	await fresh()
	var roller: Area2D = Crate.new()
	roller.spins_sprite = true
	roller.position = Vector2(700, 640)
	game.add_child(roller)
	await steps(2)
	# Standing in for art with no tumble drawn for it, which is the rock's case.
	roller.spin_frames.clear()
	var _knocked: bool = roller.take_hit(20, roller.position - Vector2(40, 0))
	await steps(2)
	var turned_to: float = roller.sprite.rotation
	await steps(4)
	check("no-drawn-angles-means-the-sprite-turns",
		not roller.at_rest and absf(roller.sprite.rotation - turned_to) > 0.01,
		{"rotation": roller.sprite.rotation, "was": turned_to,
		 "at_rest": roller.at_rest})
	# Back on the ground it has to be upright again, not left lying at an angle.
	var settle := 0
	while not roller.at_rest and settle < 240:
		await steps(1)
		settle += 1
	check("it-lands-upright",
		roller.at_rest and is_zero_approx(roller.sprite.rotation),
		{"rotation": roller.sprite.rotation, "ticks": settle})

	# The breakable prop is the rock now, and uses both: five drawn shatter
	# frames and no tumble angles to step through.
	await fresh()
	var rock: Area2D = game.crates[0]
	check("the-breakable-prop-uses-the-rock-art",
		rock.art_rest == "rock" and rock.art_break == "rock_break"
		and rock.art_debris == "rock_debris" and rock.spins_sprite
		and rock.break_frames.size() == 5 and rock.rest_frames.size() == 6,
		{"rest": rock.art_rest, "break_frames": rock.break_frames.size(),
		 "rest_frames": rock.rest_frames.size(), "spins": rock.spins_sprite})
	# The bottle is untouched by either: it has drawn angles and no shatter art.
	var milk: Area2D = game.bottles[0]
	check("the-bottle-breaks-as-it-always-did",
		milk.art_break == "" and not milk.spins_sprite
		and milk.break_frames.is_empty() and milk.debris_spins == 4,
		{"art_break": milk.art_break, "spins": milk.spins_sprite,
		 "debris_spins": milk.debris_spins})
	# Its resting art animates, which nothing in the game did before.
	var was: Texture2D = rock._resting_frame()
	var changed := false
	for i in range(40):
		await steps(1)
		if rock._resting_frame() != was:
			changed = true
			break
	check("the-rock-glow-pulses-where-it-stands", changed,
		{"rest_fps": rock.rest_fps, "frames": rock.rest_frames.size()})

	# --- a landed blow flashes the same red on anybody ----------------------
	# The player's hurt flash and the enemies' are the same colour for the same
	# length, so the feedback is one thing to learn rather than two. Asserted
	# rather than commented, because two constants in two files drift.
	check("enemies-flash-the-player's-red",
		Enemy.HURT_TINT == PlayerSprite.HURT_TINT
		and is_equal_approx(Enemy.HURT_FLASH, PlayerSprite.HURT_FLASH),
		{"enemy": str(Enemy.HURT_TINT), "player": str(PlayerSprite.HURT_TINT),
		 "enemy_s": Enemy.HURT_FLASH, "player_s": PlayerSprite.HURT_FLASH})

	await fresh()
	var struck: Area2D = game.enemies[0]
	check("an-unhit-enemy-is-not-tinted",
		struck.sprite.modulate.is_equal_approx(Color.WHITE),
		{"modulate": str(struck.sprite.modulate)})
	var _landed: bool = struck.take_hit(20, struck.position - Vector2(40, 0))
	await steps(1)
	check("a-hit-enemy-flashes-red",
		struck.sprite.modulate.r > struck.sprite.modulate.g + 0.3
		and struck.sprite.modulate.is_equal_approx(
			Color.WHITE.lerp(Enemy.HURT_TINT, struck.hurt_flash / Enemy.HURT_FLASH)),
		{"modulate": str(struck.sprite.modulate), "left": struck.hurt_flash})
	# And it fades out rather than sticking.
	var fade_ticks := 0
	while struck.hurt_flash > 0.0 and fade_ticks < 60:
		await steps(1)
		fade_ticks += 1
	check("the-flash-fades-back-to-white",
		struck.sprite.modulate.is_equal_approx(Color.WHITE) and fade_ticks < 60,
		{"modulate": str(struck.sprite.modulate), "ticks": fade_ticks})

	# The bruiser eats a blow mid-swing through his super-armour and never plays
	# a recoil frame, so before this the one enemy you most needed feedback from
	# was the one that gave you none.
	await fresh()
	var bruiser: Area2D = null
	for one in game.enemies:
		if one.armor:
			bruiser = one
	if bruiser == null:
		# First Steps has no bruiser; make the same point on an armoured stand-in
		# rather than skipping the check entirely.
		bruiser = game.enemies[0]
		bruiser.armor = true
	bruiser.state = bruiser.State.PUNCH
	var _hit: bool = bruiser.take_hit(20, bruiser.position - Vector2(40, 0))
	await steps(1)
	check("super-armour-still-flashes",
		bruiser.state == bruiser.State.PUNCH and bruiser.hurt_flash > 0.0
		and bruiser.sprite.modulate.r > bruiser.sprite.modulate.g + 0.3,
		{"state": bruiser.state, "flash": bruiser.hurt_flash,
		 "modulate": str(bruiser.sprite.modulate)})

	# --- the blast costs mana ----------------------------------------------
	# The one thing that spends the bar, and the one thing that refuses to run
	# when it is empty. Punches stay free, which is what keeps a bar of mana from
	# being a bar of "may I play".
	await fresh()
	var mana_before: int = game.player.mana
	check("starts-with-twelve-blasts",
		mana_before == game.player.START_MANA
		and mana_before / game.player.BLAST_COST == 12,
		{"mana": mana_before, "cost": game.player.BLAST_COST,
		 "blasts": mana_before / game.player.BLAST_COST})
	game.player.test_blast_pressed = true
	await steps(1)
	check("mana-not-spent-on-keypress",
		game.player.attack == "blast" and game.player.mana == mana_before,
		{"attack": game.player.attack, "mana": game.player.mana})
	var released := 0
	while not game.player.blast_released and released < 60:
		await steps(1)
		released += 1
	check("blast-costs-mana-on-release",
		game.player.mana == mana_before - game.player.BLAST_COST,
		{"mana": game.player.mana, "before": mana_before})
	await finish_attack()

	# A punch is not a blast and must not touch the bar.
	mana_before = game.player.mana
	await stand_to_punch(game.crates[0])
	game.player.test_attack_pressed = true
	await finish_attack()
	# Not equality: the bar trickles back the whole time, and a punch takes long
	# enough that a point can land during it. What must not happen is a punch
	# taking any off.
	check("punching-is-free", game.player.mana >= mana_before,
		{"mana": game.player.mana, "before": mana_before})

	# Empty: the key does nothing at all. Not a shorter blast, not a punch
	# instead — nothing, so the bar is the whole explanation.
	game.player.mana = game.player.BLAST_COST - 1
	# Counted rather than asserted empty: a projectile from the blast above is
	# still crossing the level on its own range, and it is not evidence of this.
	var live_before: int = game.blasts.size()
	game.player.test_blast_pressed = true
	await steps(3)
	check("no-blast-on-empty-mana",
		game.player.attack == "" and game.blasts.size() <= live_before
		and game.player.mana == game.player.BLAST_COST - 1,
		{"attack": game.player.attack, "mana": game.player.mana,
		 "blasts": game.blasts.size(), "before": live_before})
	# And one point more is enough again, so the refusal is the cost and not a
	# separate rule that could drift away from it.
	game.player.mana = game.player.BLAST_COST
	game.player.test_blast_pressed = true
	await steps(2)
	check("one-blast-left-still-fires", game.player.attack == "blast",
		{"attack": game.player.attack, "mana": game.player.mana})
	await finish_attack()

	# --- the bar refills itself ---------------------------------------------
	# Slowly, and on its own. Without this the blast was something to hoard: run
	# the bar down and only a brown bottle brought it back.
	await fresh()
	check("a-blast-is-ten-seconds-of-trickle",
		is_equal_approx(float(game.player.BLAST_COST) / game.player.MANA_REGEN, 10.0),
		{"cost": game.player.BLAST_COST, "per_second": game.player.MANA_REGEN})
	game.player.mana = 0
	game.player.mana_pool = 0.0
	await steps(2)
	var from_fraction: float = game.player.mana_fraction()
	var from_clock: float = game.elapsed
	await steps(60)
	var gained: float = game.player.mana_fraction() - from_fraction
	var over: float = game.elapsed - from_clock
	var wanted: float = game.player.MANA_REGEN * over / float(game.player.MAX_MANA)
	check("mana-trickles-back-at-the-stated-rate",
		gained > 0.0 and absf(gained - wanted) < wanted * 0.3,
		{"gained": gained, "wanted": wanted, "seconds": over})
	# And it moves BETWEEN whole points: the bar would tick once every two
	# seconds rather than flow if the fraction only counted banked points.
	check("the-bar-moves-between-whole-points",
		game.player.mana == 0 and game.player.mana_fraction() > 0.0,
		{"mana": game.player.mana, "fraction": game.player.mana_fraction()})
	game.player.mana = game.player.MAX_MANA
	await steps(20)
	check("the-trickle-stops-at-full",
		game.player.mana == game.player.MAX_MANA
		and is_equal_approx(game.player.mana_fraction(), 1.0),
		{"mana": game.player.mana, "fraction": game.player.mana_fraction()})

	# --- the bars slide rather than snapping ---------------------------------
	# The HUD draws an eased fill, so a drop is something you watch happen. The
	# number beside it is the real value and changes at once.
	await fresh()
	game.player.mana = game.player.MAX_MANA
	await steps(10)
	var before_shown: float = float(game.hud.shown["mana"])
	game.player.mana -= 40
	await steps(1)
	var lagging: float = float(game.hud.shown["mana"])
	check("the-bar-lags-the-number-it-is-chasing",
		lagging > game.player.mana_fraction() + 0.05 and lagging <= before_shown,
		{"shown": lagging, "real": game.player.mana_fraction(),
		 "before": before_shown})
	var ease_ticks := 0
	while absf(float(game.hud.shown["mana"]) - game.player.mana_fraction()) > 0.01 			and ease_ticks < 120:
		await steps(1)
		ease_ticks += 1
	check("and-catches-up-within-the-second", ease_ticks < 60,
		{"ticks": ease_ticks, "shown": float(game.hud.shown["mana"]),
		 "real": game.player.mana_fraction()})

	# --- the brown bottle is mana ------------------------------------------
	await fresh()
	thirsty()
	var brew: Node2D = null
	for item in game.bottles:
		if item.refills == "mana":
			brew = item
	check("level-has-a-brown-bottle", brew != null,
		{"bottles": game.bottles.size()})
	if brew != null:
		game.player.mana = 0
		game.player.health = game.player.MAX_HEALTH
		await stand_near(brew, -4.0)
		var two_bars_mana: int = brew.refill_segments * game.player.segment_mana()
		var drank_it: bool = await finish_drink()
		# At least the bottle's worth, and not a point of health. Not an exact
		# figure: the drink takes six seconds and the bar trickles back through
		# all of them, so the total is the bottle plus about three.
		check("brown-bottle-fills-mana-not-health",
			drank_it and game.player.mana >= two_bars_mana
			and game.player.mana <= two_bars_mana + 6
			and game.player.health == game.player.MAX_HEALTH,
			{"mana": game.player.mana, "bottle_worth": two_bars_mana,
			 "health": game.player.health})
		# Full mana refuses the drink for the same reason full health refuses
		# milk: the bottle is worth keeping.
		await fresh()
		thirsty()
		for item in game.bottles:
			if item.refills == "mana":
				brew = item
		game.player.mana = game.player.MAX_MANA
		await stand_near(brew, -4.0)
		var _held: bool = await take_bottle()
		check("full-mana-refuses-the-brown-bottle",
			not game.drink() and not brew.consumed,
			{"mana": game.player.mana, "consumed": brew.consumed})

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
	# He starts on the whole bar now. Which means drink() will refuse a bottle
	# until something has taken a piece out of him — that is the deal START_HEALTH
	# documents, and it is why every bottle on the course sits after a fight.
	#
	# Both of these have to be asked BEFORE thirsty(), which is the helper every
	# other drink block opens with: it is what makes room for a bottle, and it
	# would answer the question this block is asking.
	check("starts-on-a-full-bar",
		game.player.health == game.player.MAX_HEALTH,
		{"health": game.player.health, "max": game.player.MAX_HEALTH})
	check("a-bottle-is-refused-at-full-health",
		game.player.refill_full("health"),
		{"health": game.player.health})
	# And now there is room for one. Everything below is about the drink.
	thirsty()

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
	var two_bars: int = bottle.refill_segments * game.player.segment_health()
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
	thirsty()
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
	thirsty()
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
		thirsty()
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
	thirsty()
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

	# At full health the bottle is refused rather than wasted — which is where he
	# starts, so nothing has to be set up for this one any more.
	await fresh()
	bottle = game.bottles[0]
	game.player.position = Vector2(bottle.position.x, bottle.position.y)
	await steps(3)
	check("drink-refused-at-full",
		game.player.health == game.player.MAX_HEALTH
		and not game.drink() and not bottle.consumed,
		{"health": game.player.health, "consumed": bottle.consumed})

	# Retry restores both the bottle and the starting health.
	await fresh()
	thirsty()
	bottle = game.bottles[0]
	game.player.position = Vector2(bottle.position.x, bottle.position.y)
	await steps(3)
	var _ok: bool = await finish_drink()
	var healed: int = game.player.health
	game.restart_attempt()
	await steps(3)
	# Healed above where the drink started him, and the retry puts him back on the
	# whole bar. Measured against what thirsty() left him on rather than against
	# START_HEALTH, which is now the ceiling and cannot be exceeded.
	check("retry-restores-bottle-and-health",
		not bottle.consumed and game.player.health == game.player.START_HEALTH
		and healed > game.player.MAX_HEALTH - 40,
		{"health": game.player.health, "was": healed, "consumed": bottle.consumed})

	# --- the bottle is a prop too ------------------------------------------
	# Same knock-and-shatter logic as the crate, and smashing it destroys the
	# health it was worth. That is the cost of swinging at everything.
	await fresh()
	thirsty()
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
	thirsty()
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
	thirsty()
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

	# The bottle is the other half of the rule: lifted first, drunk second. Thirsty
	# first of all, or the refusal under test would be "you are full" rather than
	# "your hands are empty".
	await fresh()
	thirsty()
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
	# Named animations rather than a count: the count moved the day he learned to
	# jump, and a manifest that has grown a frame is not a manifest that is wrong.
	check("mark-loads-his-own-manifest",
		mk != null and mk.data().get("animations", {}).has("idle")
		and mk.data().get("animations", {}).has("walk")
		and mk.data().get("animations", {}).has("punch")
		and mk.data().get("animations", {}).has("hurt")
		and str(mk.data().get("_source", "")).contains("Mark"),
		{"source": mk.data().get("_source", "") if mk != null else "<none>",
		 "anims": mk.data().get("animations", {}).keys() if mk != null else []})
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
	print("NODRAGON TESTS: %d checks / %d failures" % [results.size(), failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
