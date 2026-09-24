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
	# The session wires both signals when it spawns a level's enemies; mirror that
	# here so a spawned archer's arrows actually reach the player. Harmless for the
	# kinds that never loose one — only the hunter emits it.
	foe.fired_arrow.connect(game._on_arrow_fired)
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

## Wait until the engine agrees his feet are down AND nothing is mid-swing.
##
## Teleporting does not put him on the floor — move_and_slide has to run first,
## and until it has, last_floor_tick is stale and a jump press is refused. The
## attack half matters just as much: a committed move cannot be jumped out of,
## so an animation still running from the previous check eats the next jump.
func settled() -> bool:
	for i in range(60):
		await physics_frame
		game.player.test_axis = 0.0
		if game.player.is_on_floor() and game.player.attack == "":
			return true
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

	# --- the perch hunters: hold the shelf, then come down ------------------
	# They sit on the Isles' high shelves, 144 px up and more, out of reach of the
	# player's flat blast and 107 px jump. The contract is no longer "ignore them":
	# while the ground below them still has holders they hold their shelf and snipe
	# down into it, and once it is clear they come off the shelf to be finished —
	# see perched/descend in enemy.gd and _sync_descent in session.gd.
	await fresh()
	game.load_level("fractured_isles")     # the only level that has any
	game.start_session()
	game.player.test_control = true
	await steps(3)
	# Section 1 (2240..4460): perches at y492 over a deck at y648-660.
	game.player.position = Vector2(3950, 660)
	game.player.velocity = Vector2.ZERO
	var roosts := {}
	for foe in game.enemies:
		# Arm the perches so they engage; leave the deck holders unarmed — a deck
		# enemy killing the player would end the attempt — but ALIVE, because while
		# they live the perch has no cue to come down, which is what this first
		# check tests.
		foe.target = game.player if foe.perched else null
		if foe.perched and 2240.0 <= foe.home.x and foe.home.x < 4460.0:
			roosts[foe] = foe.position.y
	await steps(150)
	# Held its height while the deck lived — an archer shuffling along its own
	# shelf to hold range is fine; coming DOWN is the thing gated on the deck.
	var drifted := 0.0
	for foe in roosts:
		drifted = maxf(drifted, absf(foe.position.y - float(roosts[foe])))
	check("a-perch-holds-while-the-deck-lives", drifted < 8.0 and roosts.size() > 0,
		{"perches": roosts.size(), "drifted": drifted,
		 "apex": Enemy.JUMP_VELOCITY * Enemy.JUMP_VELOCITY / (2.0 * Enemy.GRAVITY),
		 "drop_limit": Enemy.DROP_LIMIT})

	# Clear the ground under them, and the cue lands: the snipers come down.
	for foe in game.enemies:
		if is_instance_valid(foe) and foe.holds_gate and not foe.perched \
				and 2240.0 <= foe.home.x and foe.home.x < 4460.0:
			foe.take_hit(1000, game.player.global_position)
	game.player.position = Vector2(3950, 660)
	game.player.velocity = Vector2.ZERO
	# The behaviour under test is the descent, NOT whether the player survives it.
	# The two snipers come down right on top of him, and left alone they shoot the
	# stationary test player to death — the retry that follows stands every perch
	# back on its shelf, which is exactly what this measured as "never came down".
	# So keep him topped up, and latch each perch the first time it is down: a
	# perch that comes off its shelf counts even if something later moves it.
	var came_down_set := {}
	for i in range(320):
		await steps(1)
		game.player.health = game.player.MAX_HEALTH
		for foe in roosts:
			if foe.position.y > float(roosts[foe]) + 100.0:
				came_down_set[foe] = true
	var came_down := came_down_set.size()
	check("a-perch-comes-down-when-the-deck-clears", came_down == roosts.size(),
		{"came_down": came_down, "of": roosts.size()})

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

	# --- the dragon: the one enemy with no feet on the ground ----------------
	# Flown in its own arena rather than on the fixture, because every number
	# in the flyer style is measured against the roost_deck it took off from and the
	# arena is built to those numbers. scripts/../tests/diag_dragon.gd prints
	# the whole fight; this pins the five things it must not stop doing.
	await fresh()
	game.load_level("dragons_roost")
	game.start_session()
	game.player.test_control = true
	# Drop the walk-in cutscene: it would wake the bosses the first time the
	# player is placed past its cue at x900, and these checks drive `engaged` by
	# hand. The cutscene has its own coverage in tests/test_levels.gd.
	game.story_cards.clear()
	# And the battle track: current_track() would switch to it the moment a boss
	# is engaged and load a 21 MB WAV in the middle of this long phase simulation.
	# This block is about the flyer's mechanics, not its music — its own coverage
	# is in test_levels. Kept on the level's own loop so nothing loads mid-run.
	game.level["boss_music"] = ""
	await steps(3)
	var roost_deck := 648.0
	# The roost now holds two bosses side by side — the flying dragon and the
	# Dragon Lord on its feet. Find each by kind rather than by slot; the level is
	# still being authored and a hard-coded index goes stale silently. The
	# two-boss integration has its own block further down; the flyer checks here
	# want the arena to themselves, every altitude in them measured against the
	# dragon alone, so the Lord is lifted out for their duration.
	var wyrm: Area2D = null
	var overlord: Area2D = null
	for foe in game.enemies:
		if foe.kind == "dragon":
			wyrm = foe
		elif foe.kind == "dragon_lord":
			overlord = foe
	check("the-roost-holds-a-dragon-and-a-dragon-lord",
		game.enemies.size() == 2 and wyrm != null and wyrm.style == "flyer"
			and overlord != null and overlord.style == "bruiser" and overlord.is_boss(),
		{"enemies": game.enemies.size(),
		 "dragon": wyrm.style if wyrm != null else "<none>",
		 "lord": overlord.style if overlord != null else "<none>"})
	if overlord != null:
		game.enemies.erase(overlord)
		overlord.queue_free()
		await steps(1)

	# Its own art, not the other boss's. Two kinds a tab apart in PROFILES read
	# the same folder if anything ever crosses them over, and the animations
	# are named rather than counted for the reason mark's manifest check is.
	# Its own art, not the other boss's, and ALL of it. The zip ships one
	# animation; the other thirteen are decoded out of the preview gifs by
	# scripts/extract_dragon.py, and a decoder that quietly stopped working
	# would show up first as animations going missing from this list.
	var roost_anims: Dictionary = wyrm.data().get("animations", {}) if wyrm != null else {}
	var roost_wanted := ["idle", "idle_air", "walk", "walk_air", "claw", "swoop",
			"fire", "fire_air", "hurt", "hurt_air", "takeoff", "land", "death"]
	var roost_absent: Array = roost_wanted.filter(func(k): return not roost_anims.has(k))
	check("the-dragon-loads-its-own-manifest",
		roost_absent.is_empty()
		and str(wyrm.data().get("_source", "")).contains("demo_lugia")
		and float(wyrm.data().get("faces", 1)) == -1.0,
		{"missing": roost_absent, "faces": wyrm.data().get("faces", 0) if wyrm != null else 0,
		 "source": wyrm.data().get("_source", "") if wyrm != null else "<none>"})

	# Four attacks across two phases, each with the box it hits with measured
	# off its own art. The phase tag is what keeps a standing fire breath from
	# being thrown a hundred px up.
	var wyrm_moves: Dictionary = wyrm.data().get("moves", {}) if wyrm != null else {}
	var air_moves: Array = wyrm_moves.keys().filter(
		func(k): return str(wyrm_moves[k].get("phase", "")) == "air")
	var ground_moves: Array = wyrm_moves.keys().filter(
		func(k): return str(wyrm_moves[k].get("phase", "")) == "ground")
	check("it-has-an-attack-for-each-phase",
		air_moves.size() == 2 and ground_moves.size() == 2
		and wyrm_moves.has("swoop") and wyrm_moves.has("claw")
		and wyrm_moves.has("fire") and wyrm_moves.has("fire_air"),
		{"air": air_moves, "ground": ground_moves})

	# Perched until the fight starts. This is the one thing that lets a flyer
	# be placed and validated like anything else — see check_levels.py, which
	# fails any enemy that is not standing on a solid.
	game.player.position = Vector2(wyrm.home.x - wyrm.aggro - 80.0, roost_deck)
	game.player.velocity = Vector2.ZERO
	await steps(6)
	check("the-dragon-waits-on-its-perch",
		not wyrm.aloft and wyrm.grounded and absf(wyrm.position.y - roost_deck) < 1.0,
		{"aloft": wyrm.aloft, "grounded": wyrm.grounded, "y": wyrm.position.y})

	# And takes off when walked up to, and holds its altitude.
	#
	# Physics ticks rather than steps(): one step() is a PROCESS frame and
	# covers up to eight of them, which is long enough for the dragon to
	# launch, reach cruise AND start its first pass — so a sample taken on the
	# step boundary read 46, the bottom of a swoop, and called it the cruise.
	# The pass has its own check below; this one wants the height before it.
	game.player.position = Vector2(wyrm.home.x - 420.0, roost_deck)
	game.player.velocity = Vector2.ZERO
	var cruise: float = float(wyrm.prof.get("cruise", 0.0))
	var roost_settled := 0.0
	for i in range(240):
		await physics_frame
		game.player.position.y = roost_deck
		roost_settled = roost_deck - wyrm.position.y
		if wyrm.aloft and wyrm.swoop < 0.0 and absf(roost_settled - cruise) < 8.0:
			break
	check("it-takes-off-and-holds-its-cruise",
		wyrm.aloft and absf(roost_settled - cruise) < 8.0,
		{"aloft": wyrm.aloft, "held": roost_settled, "cruise": cruise})

	# The two measurements the arena is built around, asserted so a tuning
	# change to either side shows up here rather than in a playtest:
	#   * out of reach from the floor. The player apexes at 106.7 and his
	#     highest hit box is 36 above his feet; the dragon's body box starts
	#     at its soles, so cruise has to clear the sum.
	#   * inside the shot. The camera shows 270 above his feet and the raised
	#     wingtip is 104 above the dragon's own soles.
	var roost_apex: float = 106.7
	var punch_top: float = 36.0
	var wingtip: float = 104.0
	check("cruising-it-is-over-a-jumped-punch",
		cruise > roost_apex + punch_top,
		{"cruise": cruise, "jumped_punch_reaches": roost_apex + punch_top})
	check("and-still-inside-the-shot",
		cruise + wingtip < 270.0,
		{"top_of_the_dragon": cruise + wingtip, "camera_shows": 270.0})

	# A pass has to come low enough for two boxes to meet it: the player's
	# standing punch (22 to 36 above his feet) and the blast (25 to 43). Both
	# are measured against the dragon's soles, so this is the one number that
	# decides whether the fight can be won at all.
	var roost_lowest := 1e9
	var swooped := false
	for i in range(420):
		await steps(1)
		game.player.position.x = wyrm.home.x - 380.0
		game.player.position.y = roost_deck
		if wyrm.swoop >= 0.0:
			swooped = true
			roost_lowest = minf(roost_lowest, roost_deck - wyrm.position.y)
	check("a-pass-brings-it-into-reach",
		swooped and roost_lowest < 36.0,
		{"bottomed_out_at": roost_lowest, "standing_punch_tops_at": punch_top,
		 "blast_flies_at": 43.5})

	# And it does not stay up. The whole reason the pack's ground set is worth
	# decoding is that the dragon uses it: after `air_time` it lands, fights on
	# its feet for `ground_time` with a different attack and a different walk,
	# and takes off again. Driven here for one full turn of that.
	#
	# Put at the TOP of the air phase first. Joining the cycle wherever the
	# block above happened to leave it means possibly joining a ground phase
	# with a second left in it, and a dragon that lands 300 px from the player
	# needs longer than that to walk in and swing — the loop then breaks on the
	# take-off having seen no ground attack at all, which says nothing about
	# whether it has one.
	# A clean slate before forcing the air phase. reset() clears the swoop, shift
	# and phase clocks and the state the block above left the dragon in — without
	# it, a landing already committed a tick earlier reads as "grounded" on the
	# very first recorded frame and the loop clocks a ground phase it never saw
	# fly (the intermittent landed_after_s ~0.03 failure). reset() also drops
	# `engaged` and stands it back on its perch, so re-arm and re-lift it here.
	wyrm.reset()
	wyrm.target = game.player
	wyrm.engaged = true
	wyrm.aloft = true
	wyrm.grounded = false
	wyrm.shift = -1.0
	wyrm.deck_y = roost_deck
	wyrm.mark_y = roost_deck
	wyrm.air_left = float(wyrm.prof.get("air_time", 9.0))
	wyrm.position.y = roost_deck - float(wyrm.prof.get("cruise", 156.0))
	await physics_frame
	var saw_ground := false
	var saw_air_again := false
	var ground_attack := ""
	var air_attack := ""
	var landed_at := -1
	# And WAIT for a clean air phase before judging anything. Forcing the
	# fields above is not enough on its own: the block before this one leaves
	# the dragon wherever its own 420 steps ended, which can be one tick from
	# the deck with a landing already committed, and the loop then clocked a
	# ground phase it had arrived at the end of and broke out of it having
	# seen no swing. Nothing is recorded until it is properly up.
	var settled := false
	for i in range(3600):
		await physics_frame
		game.player.position.x = wyrm.home.x - 300.0
		game.player.position.y = roost_deck
		game.player.health = game.player.MAX_HEALTH
		if not settled:
			settled = wyrm.aloft and wyrm.shift < 0.0 					and wyrm.air_left > float(wyrm.prof.get("air_time", 9.0)) * 0.5
			continue
		if wyrm.state == wyrm.State.PUNCH:
			if wyrm.aloft:
				if air_attack == "":
					air_attack = wyrm.move
			elif ground_attack == "":
				ground_attack = wyrm.move
		if not wyrm.aloft and wyrm.grounded and wyrm.engaged and wyrm.shift < 0.0:
			if not saw_ground:
				landed_at = i
			saw_ground = true
		elif saw_ground and wyrm.aloft and landed_at >= 0 and i > landed_at + 60:
			saw_air_again = true
			break
	check("it-comes-down-and-fights-on-its-feet",
		saw_ground and ground_attack != "" and ground_attack != air_attack,
		{"landed_after_s": landed_at / 60.0, "in_the_air": air_attack,
		 "settled": settled, "saw_air_again": saw_air_again,
		 "on-its-feet": ground_attack})
	check("and-then-takes-off-again",
		saw_air_again,
		{"air_time": wyrm.prof.get("air_time"), "ground_time": wyrm.prof.get("ground_time")})

	# --- the boss plate ------------------------------------------------------
	# Its health gets the plate across the bottom of the screen: the winged
	# heart and two tracks, cut from the asset sheet by
	# scripts/extract_boss_bar.py. Which enemies get one is a profile flag, so
	# the HUD never has to know which kinds exist.
	check("a-boss-is-flagged-as-one-and-a-punk-is-not",
		wyrm.is_boss()
		and bool(Enemy.PROFILES["dragon_lord"].get("boss", false))
		and not bool(Enemy.PROFILES["bandit"].get("boss", false))
		and not bool(Enemy.PROFILES["mark"].get("boss", false)),
		{"dragon": wyrm.is_boss(),
		 "dragon_lord": Enemy.PROFILES["dragon_lord"].get("boss", false),
		 "bandit": Enemy.PROFILES["bandit"].get("boss", false)})
	var plate_hud = game.hud
	check("the-plate-art-is-imported",
		plate_hud.boss_plate != null and plate_hud.boss_bars.size() == 2,
		{"plate": plate_hud.boss_plate != null, "tracks": plate_hud.boss_bars.keys()})

	# Nothing on screen until the fight starts: a boss bar for a boss you have
	# not met is a spoiler, and `engaged` is already the line between the two.
	wyrm.reset()
	wyrm.target = game.player
	game.player.position = Vector2(wyrm.home.x - wyrm.aggro - 100.0, roost_deck)
	game.player.velocity = Vector2.ZERO
	await steps(4)
	check("no-plate-until-the-boss-notices-you",
		not wyrm.engaged and plate_hud.boss() == null,
		{"engaged": wyrm.engaged})

	# Up, full, and following the dragon rather than the player.
	game.player.position = Vector2(wyrm.home.x - 400.0, roost_deck)
	game.player.velocity = Vector2.ZERO
	for i in range(90):
		await physics_frame
		game.player.position.y = roost_deck
		game.player.health = game.player.MAX_HEALTH
		if plate_hud.boss() == wyrm:
			break
	await steps(6)
	check("the-plate-comes-up-full",
		plate_hud.boss() == wyrm and float(plate_hud.boss_shown["health"]) > 0.95,
		{"green": plate_hud.boss_shown["health"]})

	# A blow opens a gap between the two tracks, and the gap closes. Same
	# number at two speeds — that gap IS the damage, and it is the only reason
	# the plate is drawn with a second bar.
	# A quarter of the bar. It was a flat 90, which was 37% of the old 240 and
	# is 6% of the health a boss has now — the gap between the two tracks is a
	# fraction of the plate, so what opens a readable one is a fraction too.
	var _plate_hit: bool = wyrm.take_hit(wyrm.max_health / 4,
			game.player.global_position)
	for i in range(9):
		await physics_frame
		game.player.health = game.player.MAX_HEALTH
	var plate_green: float = float(plate_hud.boss_shown["health"])
	var plate_magma: float = float(plate_hud.boss_shown["magma"])
	check("a-blow-opens-a-gap-between-the-two-tracks",
		plate_magma - plate_green > 0.05,
		{"green": plate_green, "magma": plate_magma, "gap": plate_magma - plate_green})
	for i in range(150):
		await physics_frame
		game.player.health = game.player.MAX_HEALTH
	check("and-the-gap-closes-on-its-own",
		absf(float(plate_hud.boss_shown["magma"])
			 - float(plate_hud.boss_shown["health"])) < 0.02,
		{"green": plate_hud.boss_shown["health"],
		 "magma": plate_hud.boss_shown["magma"]})
	# Back up where the checks below expect it. They are about what it does in
	# the air, and the plate work above finished with it on its perch.
	wyrm.reset()
	wyrm.target = game.player
	wyrm.engaged = true
	wyrm.aloft = true
	wyrm.grounded = false
	wyrm.deck_y = roost_deck
	wyrm.position.y = roost_deck - float(wyrm.prof.get("cruise", 156.0))
	wyrm.air_left = 30.0
	wyrm.mark_y = roost_deck
	await steps(2)

	# Its answer to a thrown blast is height, not a guard: it has no defend
	# frame either, and this is the same anti-spam rule the other three enemies
	# get, reached by the one axis a flyer owns.
	check("the-dragon-does-not-guard",
		wyrm.max_guard == 0.0 and wyrm.climbs,
		{"pool": wyrm.max_guard, "climbs": wyrm.climbs})
	var cold_range: float = wyrm.guard_reaction * 560.0
	wyrm.dodge = 0.0
	wyrm.braced = 0.0
	var was_high := roost_deck - wyrm.position.y
	wyrm.warn_of_blast(Vector2(wyrm.position.x - (cold_range + 140.0),
			wyrm.position.y), 1.0, 560.0)
	var roost_climbed: bool = wyrm.dodge > 0.0
	for i in range(40):
		await steps(1)
		game.player.position.y = roost_deck
	check("it-climbs-over-one-it-saw-coming",
		roost_climbed and roost_deck - wyrm.position.y > was_high,
		{"dodged": roost_climbed, "was": was_high, "now": roost_deck - wyrm.position.y,
		 "reads_one_from": cold_range})
	wyrm.dodge = 0.0
	wyrm.braced = 0.0
	await steps(2)
	wyrm.warn_of_blast(Vector2(wyrm.position.x - (cold_range - 60.0),
			wyrm.position.y), 1.0, 560.0)
	check("but-not-over-one-thrown-from-inside-its-reaction",
		wyrm.dodge <= 0.0,
		{"thrown_from": cold_range - 60.0, "reads_one_from": cold_range})

	# --- it cannot be pushed out of its own arena ----------------------------
	# A flyer has no floor to run out from under it and it BACKS AWAY from a
	# player who comes closer than its standoff, while a shut gate pins the
	# camera to the wall. Put those together and a player standing in the
	# right-hand corner of a gated arena pushes the boss out through the side
	# of the screen — tests/diag_arena.gd measured 272 frames of 900, up to 284
	# px past the edge, before this existed. So it is fenced into the section
	# it was placed in, which for a boss is its arena.
	var pen: Vector2 = game.section_bounds(game.section_of(wyrm.home.x))
	check("a-flyer-is-fenced-into-its-own-section",
		wyrm.is_flyer() and wyrm.fly_bounds.y == pen.y and wyrm.fly_bounds.y < INF
		and str(Enemy.PROFILES["bandit"].get("style", "")) != "flyer",
		{"bounds": wyrm.fly_bounds, "section": pen, "gates": game.gates})
	wyrm.reset()
	wyrm.target = game.player
	wyrm.engaged = true
	wyrm.aloft = true
	wyrm.grounded = false
	wyrm.deck_y = roost_deck
	wyrm.air_left = 30.0
	wyrm.mark_y = roost_deck
	# Backed into the corner with the player crowding it: 200 px is well inside
	# the 340 it wants, so every frame of this is it trying to get out.
	wyrm.position = Vector2(wyrm.fly_bounds.y - 60.0, roost_deck - 156.0)
	game.player.position = Vector2(wyrm.fly_bounds.y - 260.0, roost_deck)
	var pen_worst: float = -INF
	for i in range(120):
		await physics_frame
		game.player.position = Vector2(wyrm.fly_bounds.y - 260.0, roost_deck)
		game.player.health = game.player.MAX_HEALTH
		pen_worst = maxf(pen_worst, wyrm.position.x)
	check("and-crowding-it-cannot-push-it-through-the-wall",
		pen_worst <= wyrm.fly_bounds.y + 0.5,
		{"furthest": pen_worst, "fence": wyrm.fly_bounds.y,
		 "over_by": pen_worst - wyrm.fly_bounds.y})
	# Back where the fly-away below expects it: that measures from where it is
	# struck, and a dragon left pinned against its own fence would measure the
	# fence.
	wyrm.reset()
	wyrm.target = game.player
	wyrm.engaged = true
	wyrm.aloft = true
	wyrm.grounded = false
	wyrm.deck_y = roost_deck
	wyrm.position = Vector2(wyrm.home.x, roost_deck - float(wyrm.prof.get("cruise", 156.0)))
	wyrm.air_left = 30.0
	wyrm.mark_y = roost_deck
	game.player.position = Vector2(wyrm.home.x - 400.0, roost_deck)
	await steps(2)

	# --- it is a boss now ----------------------------------------------------
	# Six things were wrong with this fight and every one of them is a number
	# or a missing branch. tests/diag_dragonfight.gd measures the lot and is
	# the before-and-after; these are the parts that can be asserted.

	# TWENTY-FIVE HITS, AND NINETEEN HERE. The hardest single blow the player
	# owns is the jumped kick, and the dragon's own number — the one The
	# Fractured Isles fights it at, where it is the whole boss — has to survive
	# twenty-one of them. This level cuts it to sixteen in its own file
	# (`enemy_health`), because here it fights over a Dragon Lord who is 1275
	# himself and two of those back to back is a longer last level rather than
	# a harder one. So both are asserted, and apart: the kind stays a
	# twenty-one-hit boss, and the level is allowed to spend some of that
	# without being allowed to make it cheap. Read off the moveset rather than
	# typed here — retune the kick and both move with it.
	#
	# The floors are one hit under each, not the figure itself: both bosses
	# came down 15% together (1500 to 1275, 1140 to 969) and 969 is 16.1 kicks
	# rather than a round number. Asserting >= 21 and >= 15 leaves the tuning
	# room the old >= 25 and >= 18 had, and still fails the 240 this started
	# at — four kicks, a fight over before either phase played.
	var hardest := 0
	for key in ["punch_a", "punch_b", "kick", "charge"]:
		for kframe in range(12):
			for hit in Moveset.hits(key, kframe):
				hardest = maxi(hardest, int(hit["damage"]))
	var wyrm_own: int = int(Enemy.PROFILES["dragon"]["health"])
	check("it-takes-twenty-one-of-the-players-best-and-sixteen-on-the-roost",
		hardest > 0 and wyrm_own >= 21 * hardest
		and wyrm.max_health >= 15 * hardest and wyrm.max_health < wyrm_own,
		{"profile": wyrm_own, "on_this_level": wyrm.max_health,
		 "hardest_blow": hardest,
		 "hits_here": float(wyrm.max_health) / float(maxi(hardest, 1)),
		 "hits_on_the_isles": float(wyrm_own) / float(maxi(hardest, 1))})

	# IT HITS THROUGH YOU. Struck mid-swing from behind it keeps its facing,
	# its swing and its ground: the counter is footwork, not trading. Same
	# rule the Dragon Lord has and for the same reason.
	wyrm.reset()
	wyrm.target = game.player
	wyrm.engaged = true
	await steps(2)
	game.player.position = Vector2(wyrm.position.x - 70.0, roost_deck)
	wyrm.facing = -1.0
	wyrm._start_punch()
	await physics_frame
	var swing_facing: float = wyrm.facing
	var swing_state: int = wyrm.state
	var _behind: bool = wyrm.take_hit(40, Vector2(wyrm.position.x + 300.0, roost_deck))
	await physics_frame
	check("nothing-staggers-it-or-turns-it-out-of-a-swing",
		bool(Enemy.PROFILES["dragon"].get("unflinching", false))
		and wyrm.facing == swing_facing and wyrm.state == swing_state
		and wyrm.stagger <= 0.0 and is_zero_approx(wyrm.velocity.x)
		and wyrm.hurt_flash > 0.0,
		{"facing": wyrm.facing, "was": swing_facing, "state": wyrm.state,
		 "stagger": wyrm.stagger, "shoved": wyrm.velocity.x,
		 "flash": wyrm.hurt_flash})

	# THE BREATH REACHES FURTHER THAN IT IS DRAWN, by a number in the profile
	# rather than by editing the manifest — that file says how long the flame
	# is painted, which is a fact about the sheet. And it is CHOSEN from much
	# further out than that: the band is 121..240 and a flyer holds a standoff
	# of 340 to 470, so for as long as the band was the only test the breath
	# was never once thrown.
	var drawn: Array = wyrm.move_data("fire_air").get("range", [])
	check("the-breath-reaches-past-the-flame-and-is-picked-from-further-still",
		wyrm.reach_bonus("fire_air") > 0.0
		and wyrm.band_top("fire_air") == float(drawn[1]) + wyrm.reach_bonus("fire_air")
		and wyrm.reach_bonus("claw") == 0.0
		and float(Enemy.PROFILES["dragon"].get("fire_from", 0.0))
			> wyrm.band_top("fire_air") + Enemy.STANDOFF_NEAR * 0.5,
		{"drawn_to": drawn[1], "reaches": wyrm.band_top("fire_air"),
		 "decides_from": Enemy.PROFILES["dragon"].get("fire_from", 0.0),
		 "standoff_near": Enemy.STANDOFF_NEAR,
		 "claw_bonus": wyrm.reach_bonus("claw")})
	# In the air, off cooldown, and well outside the flame: it lines one up
	# anyway and closes, which is the branch that was missing.
	wyrm.reset()
	wyrm.target = game.player
	wyrm.engaged = true
	wyrm.aloft = true
	wyrm.grounded = false
	wyrm.deck_y = roost_deck
	wyrm.mark_y = roost_deck
	wyrm.air_left = 60.0
	wyrm.position = Vector2(wyrm.home.x, roost_deck - 156.0)
	game.player.position = Vector2(wyrm.home.x - 400.0, roost_deck)
	game.player.velocity = Vector2.ZERO
	wyrm.cooldown = 0.0
	wyrm.special_ready = 0.0
	await physics_frame
	var lining: bool = wyrm._lining_up(400.0)
	var breathed := false
	for i in range(240):
		await physics_frame
		game.player.position = Vector2(wyrm.home.x - 400.0, roost_deck)
		game.player.health = game.player.MAX_HEALTH
		if wyrm.move == "fire_air" and wyrm.state == wyrm.State.PUNCH:
			breathed = true
			break
	check("and-it-closes-from-out-there-and-breathes",
		lining and breathed
		and absf(wyrm.position.x - game.player.position.x) <= wyrm.band_top("fire_air") + 8.0,
		{"lined_up_at_400": lining, "breathed": breathed,
		 "threw_it_from": absf(wyrm.position.x - game.player.position.x)})

	# AND THE BREATH PUTS HIM DOWN. Every blow flings; the fire flings hardest,
	# and a flung blow is a knockdown rather than a flinch — LF2's falling
	# frames, and no control until he is up. See DOWN_TIME in player.gd.
	wyrm.move = "claw"
	var claw_fling: float = wyrm.fling_for()
	wyrm.move = "fire_air"
	var fire_fling: float = wyrm.fling_for()
	check("its-blows-throw-him-and-the-breath-throws-hardest",
		claw_fling > 0.0 and fire_fling > claw_fling * 1.5,
		{"claw": claw_fling, "breath": fire_fling})
	game.player.position = Vector2(wyrm.home.x - 60.0, roost_deck)
	game.player.velocity = Vector2.ZERO
	game.player.health = game.player.MAX_HEALTH
	var _flung: bool = game.player.take_damage(20, Vector2(wyrm.home.x, roost_deck),
			fire_fling)
	await physics_frame
	check("a-flung-blow-knocks-him-off-his-feet",
		game.player.is_downed() and game.player.is_hurt()
		and game.player.velocity.y < 0.0
		and signf(game.player.velocity.x) < 0.0,
		{"downed": game.player.is_downed(), "up": game.player.velocity.y,
		 "away": game.player.velocity.x})
	var down_for := 0
	while game.player.is_downed() and down_for < 240:
		await physics_frame
		down_for += 1
	check("and-he-is-down-for-longer-than-a-flinch",
		down_for / 60.0 > game.player.HURT_STUN * 2.0
		and absf(down_for / 60.0 - game.player.DOWN_TIME) < 0.1,
		{"down_for": down_for / 60.0, "flinch": game.player.HURT_STUN,
		 "want": game.player.DOWN_TIME})

	# SPAMMING THE BLAST DOES NOT HOLD IT OFF. Each one it reads stacks; the
	# stack sends it higher, and past SPAM_ANGRY a further blast buys no more
	# evasion — it rides them out and comes down instead. Without that last
	# rule a shot every 0.3 s refreshed the dodge for ever and the dragon
	# climbed out of its own fight.
	wyrm.reset()
	wyrm.target = game.player
	wyrm.engaged = true
	wyrm.aloft = true
	wyrm.grounded = false
	wyrm.deck_y = roost_deck
	wyrm.mark_y = roost_deck
	wyrm.air_left = 60.0
	wyrm.position = Vector2(wyrm.home.x, roost_deck - 156.0)
	game.player.position = Vector2(wyrm.home.x - 400.0, roost_deck)
	await physics_frame
	check("the-stack-starts-empty", is_zero_approx(wyrm.spam), {"spam": wyrm.spam})
	for i in range(int(Enemy.SPAM_MAX) + 2):
		wyrm.warn_of_blast(game.player.global_position, 1.0, 560.0)
	check("a-stream-of-blasts-stacks-and-stops-buying-evasion",
		wyrm.spam >= Enemy.SPAM_ANGRY and wyrm.spam <= Enemy.SPAM_MAX
		and wyrm.dodge <= 0.0 and wyrm.swoop_ready <= 0.0,
		{"spam": wyrm.spam, "cap": Enemy.SPAM_MAX, "dodge": wyrm.dodge,
		 "swoop_ready": wyrm.swoop_ready})
	# And one on its own still buys the climb it always did — thrown at a
	# height it could actually be hit at. Cruising 156 up it is above the line
	# the blast flies along and there is nothing to dodge, which is why the
	# stack above is counted before that test and the dodge after it.
	wyrm.spam = 0.0
	wyrm.dodge = 0.0
	wyrm.braced = 0.0
	wyrm.position.y = roost_deck - 20.0
	await physics_frame
	wyrm.warn_of_blast(Vector2(wyrm.position.x - 400.0, wyrm.position.y),
			1.0, 560.0)
	check("but-a-single-one-is-still-dodged",
		wyrm.dodge > 0.0 and wyrm.spam < Enemy.SPAM_ANGRY,
		{"dodge": wyrm.dodge, "spam": wyrm.spam})
	# The stack forgets a player who stops.
	var quiet: float = wyrm.spam
	await steps(60)
	check("and-the-stack-forgets-a-player-who-stops",
		wyrm.spam < quiet,
		{"was": quiet, "now": wyrm.spam})

	# Back where the fly-away below expects it.
	wyrm.reset()
	wyrm.target = game.player
	wyrm.engaged = true
	wyrm.aloft = true
	wyrm.grounded = false
	wyrm.deck_y = roost_deck
	wyrm.position = Vector2(wyrm.home.x, roost_deck - float(wyrm.prof.get("cruise", 156.0)))
	wyrm.air_left = 30.0
	wyrm.mark_y = roost_deck
	game.player.position = Vector2(wyrm.home.x - 400.0, roost_deck)
	game.player.health = game.player.MAX_HEALTH
	await steps(2)

	# And the ending the whole level exists for. Beaten, it does not fall over
	# — there is no collapse in six frames of wing-flap and none is roost_wanted. It
	# turns away, climbs, and is gone, and the flag opens while you watch it go.
	var shut_before: float = game.gate_shut_at()
	var died_at: Vector2 = wyrm.position
	var struck_from := Vector2(wyrm.position.x - 200.0, roost_deck)
	var _down: bool = wyrm.take_hit(wyrm.health, struck_from)
	# Beaten, it goes DOWN first. The pack draws a collapse and that is what
	# plays; the fly-away is the second half of it, below.
	check("the-dragon-goes-down-before-it-leaves",
		not wyrm.alive() and wyrm.facing > 0.0 and not wyrm.aloft,
		{"alive": wyrm.alive(), "facing": wyrm.facing, "aloft": wyrm.aloft,
		 "struck_from_the": "left"})
	# The wall does NOT open on the killing blow. A boss holds it until its
	# body is off the screen, because the death is seconds long and the flag
	# is a short run past the wall — see section_clear in game/session.gd.
	check("and-the-gate-still-holds-while-the-body-is-there",
		shut_before < INF and game.gate_shut_at() == shut_before
		and not wyrm.alive() and wyrm.visible,
		{"was": shut_before, "now": game.gate_shut_at(),
		 "body": wyrm.visible})
	# And then it gets up and goes. Measured from the DECK it roost_collapsed on
	# rather than from where it was struck, because it falls out of the air
	# first and the climb starts from the bottom of that.
	#
	# Physics ticks, not steps(): the whole thing runs about four seconds and a
	# step() covering up to eight ticks makes the budget for that unknowable.
	var roost_flew := 0.0
	var roost_rose := 0.0
	var roost_ticks := 0
	var roost_floor := died_at.y
	var roost_collapsed := false
	while wyrm.visible and roost_ticks < 420:
		await physics_frame
		roost_ticks += 1
		if not wyrm.aloft:
			roost_floor = maxf(roost_floor, wyrm.position.y)
			roost_collapsed = roost_collapsed or wyrm.sprite.animation == "death"
		roost_flew = maxf(roost_flew, absf(wyrm.position.x - died_at.x))
		roost_rose = maxf(roost_rose, roost_floor - wyrm.position.y)
	# It used to fly out here too, and that assertion read `roost_flew > 400`
	# and `roost_rose > 240`. The departure is The Fractured Isles' ending and
	# now belongs to that level alone — this one sets `boss_departs: false`, so
	# the body stays on the deck through the victory cards and is cleared where
	# it fell. See the note in levels/dragons_roost.json. What still has to be
	# true is the first half of the beat: it comes down on the deck and plays
	# the collapse the pack ships, rather than vanishing where it was hit.
	check("it-collapses-on-the-deck-and-stays-there",
		not wyrm.visible and roost_collapsed and roost_rose < 60.0,
		{"gone": not wyrm.visible, "played_the_collapse": roost_collapsed,
		 "flew": roost_flew, "rose": roost_rose, "after_s": roost_ticks / 60.0})

	# --- The Dragon's Roost: two bosses, and the Lord turned up -------------
	# The roost holds the flying dragon AND the Dragon Lord, standing a body apart
	# at the centre of the deck. The plate carries one on each track, the Lord
	# hits through your blows, his hits fling you off your feet, and his close
	# special is a leap-slam that shocks the ground where he lands.
	await fresh()
	game.load_level("dragons_roost")
	game.start_session()
	game.player.test_control = true
	# Same as the flyer block above: drop the walk-in cutscene so placing the
	# player does not wake the bosses out from under the manual `engaged` control,
	# and the battle track so no 21 MB WAV loads mid-run. Both have their own
	# coverage in test_levels.
	game.story_cards.clear()
	game.level["boss_music"] = ""
	await steps(3)
	var arena_deck := 648.0
	var lord: Area2D = null
	var flyer: Area2D = null
	for foe in game.enemies:
		if foe.kind == "dragon_lord":
			lord = foe
		elif foe.kind == "dragon":
			flyer = foe

	# Both wake and both hold the gate, and the plate reads one boss on each
	# track: the Lord on the main green, the flyer on the red beneath it.
	lord.engaged = true
	flyer.engaged = true
	await steps(2)
	check("the-roost-runs-a-bar-for-each-boss",
		game.boss_main() == lord and game.boss_second() == flyer
		and lord.holds_gate and flyer.holds_gate,
		{"main": game.boss_main().kind if game.boss_main() != null else "<none>",
		 "second": game.boss_second().kind if game.boss_second() != null else "<none>"})

	# And each track KEEPS its boss for the length of the fight. Beating one of
	# the two does not re-deal them: the bar of whoever went down empties and
	# stays empty, and the one still fighting goes on draining where it was.
	#
	# They used to be worked out every frame from whoever was still standing, so
	# the moment either of them fell the plate came back as ONE full green bar —
	# the survivor's health, moved onto the green and shadowed in red — which
	# reads as a fight starting rather than as one half won, and the bar you had
	# been watching drain was gone.
	#
	# The bodies are put out of sight by hand rather than by waiting the deaths
	# out: the flyer's is DOWN_TIME and then a flight out of the level, and it is
	# the body being GONE rather than the killing blow that used to free a track.
	var roost_hud = game.hud
	var _flyer_down: bool = flyer.take_hit(flyer.health, game.player.global_position)
	flyer.visible = false
	for i in range(60):
		await physics_frame
		game.player.health = game.player.MAX_HEALTH
	check("and-beating-one-empties-that-bar-and-only-that-bar",
		game.boss_main() == lord and game.boss_second() == flyer
		and float(roost_hud.boss_shown["magma"]) < 0.02
		and float(roost_hud.boss_shown["health"]) > 0.98,
		{"main": game.boss_main().kind if game.boss_main() != null else "<none>",
		 "second": game.boss_second().kind if game.boss_second() != null else "<none>",
		 "green": roost_hud.boss_shown["health"],
		 "magma": roost_hud.boss_shown["magma"]})

	# The other way round, which is the one that gave it away: the Lord holds the
	# green, and when HE goes down the flying dragon must not inherit it.
	flyer.reset()
	flyer.target = game.player
	flyer.engaged = true
	var _lord_down: bool = lord.take_hit(lord.health, game.player.global_position)
	lord.visible = false
	for i in range(60):
		await physics_frame
		game.player.health = game.player.MAX_HEALTH
	check("and-the-survivor-does-not-move-onto-the-other-track",
		game.boss_main() == lord and game.boss_second() == flyer
		and float(roost_hud.boss_shown["health"]) < 0.02
		and float(roost_hud.boss_shown["magma"]) > 0.98,
		{"main": game.boss_main().kind if game.boss_main() != null else "<none>",
		 "second": game.boss_second().kind if game.boss_second() != null else "<none>",
		 "green": roost_hud.boss_shown["health"],
		 "magma": roost_hud.boss_shown["magma"]})

	# Both gone and the plate goes with them, tracks and all, so the next fight
	# starts from full rather than inheriting these two empty bars.
	var _flyer_again: bool = flyer.take_hit(flyer.health, game.player.global_position)
	flyer.visible = false
	await steps(2)
	check("and-both-tracks-are-given-back-when-the-fight-is-over",
		game.boss() == null and game.boss_main() == null
		and game.boss_second() == null,
		{"boss": game.boss() != null,
		 "green_track": game.boss_main() != null,
		 "magma_track": game.boss_second() != null})
	flyer.reset()
	flyer.target = game.player
	flyer.engaged = true

	# Hits THROUGH your blows. Jabbed over and over on his feet, he never
	# staggers — the counter is footwork, not trading — but he still bleeds.
	lord.reset()
	lord.target = game.player
	lord.engaged = true
	game.player.position = Vector2(lord.home.x - 300.0, arena_deck)   # out of his own reach
	game.player.velocity = Vector2.ZERO
	await steps(2)
	var lord_hp: int = lord.health
	var lord_staggered := false
	for i in range(40):
		var _h: bool = lord.take_hit(6, Vector2(lord.position.x - 40.0, arena_deck))
		await steps(1)
		if lord.state == lord.State.HURT:
			lord_staggered = true
	check("the-lord-hits-through-your-attacks",
		not lord_staggered and lord.health < lord_hp,
		{"ever_staggered": lord_staggered, "lost": lord_hp - lord.health})

	# Only he flings — nothing else in the cast moves the player when it hits.
	check("only-the-dragon-lord-flings",
		float(Enemy.PROFILES["dragon_lord"].get("fling", 0.0)) > 0.0
		and not Enemy.PROFILES["bandit"].has("fling")
		and not Enemy.PROFILES["mark"].has("fling")
		and not Enemy.PROFILES["hunter"].has("fling"),
		{"lord_fling": Enemy.PROFILES["dragon_lord"].get("fling", 0.0)})

	# A flung blow throws the player off his feet, away from the fist, and the
	# fall is the second half of it.
	game.player.reset_at(Vector2(1000.0, arena_deck))
	game.player.enabled = true
	await steps(2)
	var flung_from: float = game.player.position.x
	var _fl: bool = game.player.take_damage(20, Vector2(940.0, arena_deck), 300.0)
	var flung_airborne := false
	for i in range(24):
		await steps(1)
		if not game.player.is_on_floor():
			flung_airborne = true
	check("a-flung-blow-throws-the-player-back-and-down",
		flung_airborne and game.player.position.x > flung_from + 20.0,
		{"thrown": game.player.position.x - flung_from, "left_the_ground": flung_airborne})

	# The leap-slam: his close special LEAVES the ground, and the LANDING shocks
	# the deck around where he comes down — a player caught even to the side of
	# him, not only in front. The shock stays under stone height on purpose (a
	# player 108 up on a floating stone is clear), which the arena depends on.
	check("the-slam-shock-stays-below-a-stone",
		Enemy.SLAM_SHOCK_HEIGHT < 108.0,
		{"shock_rises": Enemy.SLAM_SHOCK_HEIGHT, "stone_is": 108.0})
	lord.reset()
	lord.target = game.player
	lord.engaged = true
	lord.special_ready = 0.0
	lord.cooldown = 0.0
	game.player.reset_at(Vector2(lord.home.x - 80.0, arena_deck))   # inside the 0..126 slam band
	game.player.enabled = true
	await steps(2)
	var slam_hp: int = game.player.health
	var slam_chosen := false
	var slam_airborne := false
	for i in range(200):
		await steps(1)
		# Pin him in the landing zone so the blow is guaranteed to reach him; the
		# fling itself is measured above.
		game.player.position = Vector2(lord.home.x - 80.0, arena_deck)
		game.player.velocity = Vector2.ZERO
		if lord.move == "slam":
			slam_chosen = true
			if not lord.grounded:
				slam_airborne = true
		if game.player.health < slam_hp:
			break
	check("the-lord-leaps-and-slams-the-ground",
		slam_chosen and slam_airborne and game.player.health < slam_hp,
		{"chose_slam": slam_chosen, "left_the_ground": slam_airborne,
		 "player_lost": slam_hp - game.player.health})

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

	# --- breathed on --------------------------------------------------------
	# The Anti-Davis pack draws the player being hit by fire and nothing in the
	# game asked for it until now: four frames, two of him tumbling inside the
	# flame and two of him burning where he landed (LF2 203-206, cut as `burn`
	# by scripts/extract_anti_davis.py). Both bosses breathe, so a blow says
	# whether it was made of fire and the player wears it for exactly as long
	# as the stun that blow cost him — no bar ticks down, which would be a
	# second death he has no answer to.
	#
	# tests/capture_burn.gd is the picture of all of this.
	await fresh()
	game.load_level("dragons_roost")
	game.start_session()
	game.player.test_control = true
	game.story_cards.clear()
	game.level["boss_music"] = ""
	await steps(3)
	check("the-moves-made-of-fire-are-the-three-that-are-drawn-with-it",
		Enemy.FIRE_MOVES.has("fire") and Enemy.FIRE_MOVES.has("fire_air")
		and Enemy.FIRE_MOVES.has("breath")
		and not Enemy.FIRE_MOVES.has("punch")
		and not Enemy.FIRE_MOVES.has("slam")
		and not Enemy.FIRE_MOVES.has("claw")
		and not Enemy.FIRE_MOVES.has("swoop"),
		{"fire": Enemy.FIRE_MOVES})

	# End to end and through the boss's own hit box: nothing below calls
	# take_damage. He stands in the breath's band — 146 to 274, so 200 picks
	# the breath over the leap-slam — with the cooldowns spent every tick so
	# the next thing the Lord decides is the special.
	var burn_lord: Area2D = null
	for foe in game.enemies:
		if foe.kind == "dragon_lord":
			burn_lord = foe
		else:
			# Put down properly rather than health = 0: a body at zero that
			# never went through the death is still standing there fighting.
			var _gone: bool = foe.take_hit(foe.health, Vector2.ZERO)
			foe.visible = false
	burn_lord.target = game.player
	burn_lord.engaged = true
	game.player.reset_at(Vector2(burn_lord.home.x - 200.0, 648.0))
	game.player.enabled = true
	game.player.test_control = true
	var lit := -1
	var lit_by := ""
	for i in range(600):
		game.player.health = game.player.MAX_HEALTH
		burn_lord.cooldown = 0.0
		burn_lord.special_ready = 0.0
		await physics_frame
		if game.player.is_burning():
			lit = i
			lit_by = burn_lord.move
			break
	check("a-breath-sets-the-player-alight",
		lit >= 0 and lit_by == "breath" and game.player.is_downed(),
		{"ticks": lit, "move": lit_by, "downed": game.player.is_downed(),
		 "burning": game.player.is_burning()})
	check("and-the-burn-is-what-is-drawn-rather-than-the-plain-tumble",
		game.player.visual.playing == "burn",
		{"drawing": game.player.visual.playing})

	# And it goes out with the stun. The flame is what that stun looks like,
	# not damage of its own.
	var _lord_out: bool = burn_lord.take_hit(burn_lord.health, Vector2.ZERO)
	var burn_ticks := -1
	for i in range(180):
		game.player.health = game.player.MAX_HEALTH
		await physics_frame
		if not game.player.is_hurt():
			burn_ticks = i
			break
	check("and-it-goes-out-when-he-has-his-feet-back",
		burn_ticks >= 0 and not game.player.is_burning()
		and game.player.visual.playing != "burn",
		{"ticks": burn_ticks, "burning": game.player.is_burning(),
		 "drawing": game.player.visual.playing})

	# A fist does not light him: same knockdown, same falling frames, no fire.
	var _fist: bool = game.player.take_damage(20,
			game.player.global_position + Vector2(60.0, 0.0), 240.0)
	await physics_frame
	check("and-a-blow-that-is-not-fire-leaves-him-unlit",
		game.player.is_downed() and not game.player.is_burning()
		and game.player.visual.playing == "death",
		{"downed": game.player.is_downed(),
		 "burning": game.player.is_burning(),
		 "drawing": game.player.visual.playing})

	# --- the blast goes up with him ----------------------------------------
	# It used to be a ground move: `ground: true` in MOVES, refused in mid-air,
	# so every blast in the game left his hand at the same height and there was
	# nothing to decide. Now the muzzle rides HIM — BLAST_MUZZLE is measured
	# from his feet — so a jumped shot flies a jump higher.
	#
	# Which cuts both ways, and both are asserted below: it is the only way to
	# put an energy strike into something above head height, and it is equally
	# why a jumped shot sails clean over a bandit standing in front of you.
	await fresh()
	var air_deck := -1200.0
	for parked_air in game.enemies:
		parked_air.target = null
	game._add_solid(Rect2(2000, air_deck, 1200, 200))
	await steps(2)

	# Standing.
	game.player.position = Vector2(2100, air_deck)
	game.player.velocity = Vector2.ZERO
	game.player.facing = 1.0
	await settled()
	game.player.mana = game.player.MAX_MANA
	game.player.test_blast_pressed = true
	var flat_at := -1.0
	for i in range(90):
		await steps(1)
		if not game.blasts.is_empty():
			flat_at = air_deck - game.blasts[0].position.y
			break
	check("a-standing-blast-leaves-at-chest-height",
		flat_at > 25.0 and flat_at < 45.0, {"above_his_feet": flat_at})
	for spent in game.blasts:
		spent.queue_free()
	game.blasts.clear()

	# Jumped, thrown at the top. `settled()` matters here: a committed move
	# cannot be jumped out of, so a blast animation still running from the
	# check above would silently eat the jump press.
	game.player.position = Vector2(2100, air_deck)
	game.player.velocity = Vector2.ZERO
	await settled()
	var high_at := -1.0
	var kept_vx := 0.0
	var into_vx := 0.0
	game.player.mana = game.player.MAX_MANA
	game.player.test_jump_pressed = true
	await physics_frame
	var apex_seen := 0.0
	var let_go := false
	for i in range(140):
		# Running while he throws, which is what the momentum check is for.
		game.player.test_axis = 1.0
		apex_seen = maxf(apex_seen, air_deck - game.player.position.y)
		if not let_go and not game.player.is_on_floor() \
				and game.player.velocity.y >= -20.0:
			let_go = true
			into_vx = game.player.velocity.x
			game.player.test_blast_pressed = true
		if let_go and high_at < 0.0 and not game.blasts.is_empty():
			high_at = air_deck - game.blasts[0].position.y
			kept_vx = game.player.velocity.x
		await physics_frame
		if high_at >= 0.0:
			break
	game.player.test_axis = 0.0
	check("a-jumped-blast-leaves-a-jump-higher",
		high_at > flat_at + 60.0 and apex_seen > 90.0,
		{"above_his_feet": high_at, "standing_was": flat_at, "apex": apex_seen})
	# A planted move plants his FEET, and in mid-air there are none to plant.
	# Braking here would drop him short of whatever he jumped over.
	check("and-does-not-brake-the-jump-it-was-thrown-from",
		into_vx > 200.0 and absf(kept_vx - into_vx) < 20.0,
		{"into": into_vx, "out": kept_vx})

	# And the trade, at the heights it actually turns on. Three numbers decide
	# all of it, and none of them is a guess:
	#
	#   a standing shot leaves at 34 above his feet and the blast's box is 9
	#   either side of that; a jumped one leaves at 105; and a dragon cruises
	#   with its body between 156 and 252 above the deck.
	#
	# So from the floor NEITHER shot reaches it — 43 and 114 against a belly at
	# 156 — which is the thing that makes the arena's floating stones the
	# answer rather than decoration. From one of those, 96 up, the flat shot is
	# still short at 139 and the jumped one lands at 228. That is the whole
	# mechanic, and the cost is the check after it.
	var reach_cases := [
		# [player stands at, target, target height, jumped, should land]
		[0.0, "bandit", 0.0, false, true],
		[0.0, "bandit", 0.0, true, false],
		[96.0, "dragon", 156.0, false, false],
		[96.0, "dragon", 156.0, true, true],
	]
	for row in reach_cases:
		var stand_at: float = row[0]
		var foe_kind: String = row[1]
		var foe_up: float = row[2]
		var jumped_shot: bool = row[3]
		var should: bool = row[4]
		await fresh()
		for parked_t in game.enemies:
			parked_t.target = null
		game._add_solid(Rect2(2000, air_deck, 1200, 200))
		if stand_at > 0.0:
			game._add_solid(Rect2(2150, air_deck - stand_at, 140, 24))
		await steps(2)
		var mark_foe: Area2D = await spawn_foe(foe_kind, Vector2(2500, air_deck))
		# Parked: this is about where the shot goes, not about the fight. A
		# flyer with no target holds the height it is given and does not drift.
		mark_foe.target = null
		if foe_up > 0.0:
			mark_foe.aloft = true
			mark_foe.grounded = false
			mark_foe.deck_y = air_deck
			mark_foe.position.y = air_deck - foe_up
			mark_foe.velocity = Vector2.ZERO
		await steps(2)
		var foe_was: int = mark_foe.health
		game.player.position = Vector2(2210, air_deck - stand_at)
		game.player.velocity = Vector2.ZERO
		await settled()
		game.player.facing = 1.0
		game.player.mana = game.player.MAX_MANA
		if jumped_shot:
			game.player.test_jump_pressed = true
			await physics_frame
			var fired := false
			for i in range(160):
				if not fired and not game.player.is_on_floor() \
						and game.player.velocity.y >= -20.0:
					fired = true
					game.player.test_blast_pressed = true
				await physics_frame
				if mark_foe.health < foe_was:
					break
		else:
			game.player.test_blast_pressed = true
			for i in range(160):
				await physics_frame
				if mark_foe.health < foe_was:
					break
		var landed_it: bool = mark_foe.health < foe_was
		check("a-%s-blast-from-%s-%s-a-%s" % [
				"jumped" if jumped_shot else "flat",
				"a-stone" if stand_at > 0.0 else "the-deck",
				"reaches" if should else "misses",
				foe_kind],
			landed_it == should,
			{"hit": landed_it, "expected": should,
			 "stood_at": stand_at, "target_at": air_deck - mark_foe.position.y})
		mark_foe.queue_free()
		await steps(1)

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
	# The cause line is generic now, not "the bandits": the same defeat screen has
	# to read right whoever emptied the bar, the roost's dragon included.
	check("an-empty-bar-says-you-were-beaten", game.death_reason.to_lower().contains("beaten"),
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
	# First Steps carries a mark and a hunter among its enemy entries. This
	# exercises the whole path the roster adds — the session reads the kind off
	# each entry, the enemy loads its own art folder, and everything the bandit
	# does works on them unchanged.
	await fresh()
	game.load_level("first_steps")
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
	check("mark-and-hunter-spawn-from-level-entries",
		mk != null and hn != null,
		{"count": game.enemies.size(), "mark": mk != null, "hunter": hn != null})

	# Everything below fights the two of them one at a time, and needs the thing
	# proving_ground used to give: a long flat patch with clear floor between the
	# combatants and no spikes in it. proving_ground is gone, so lay one over the
	# greybox fixture — a plain solid across its gaps, its spikes cleared — and
	# spawn a fresh mark and hunter onto it. on_roster so fight_one's "park
	# everyone else" loop reaches whichever of the two is not fighting.
	await fresh()
	game.start_session()
	game.player.test_control = true
	for hz in game.hazard_areas:
		hz.queue_free()
	game.hazard_areas.clear()
	game._add_solid(Rect2(-200, 640, 2400, 240))
	await steps(2)
	mk = await spawn_foe("mark", Vector2(1050, 640), true)
	hn = await spawn_foe("hunter", Vector2(1120, 640), true)
	await steps(2)
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
	print("COMBAT TESTS: %d checks / %d failures" % [results.size(), failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
