extends SceneTree
## Diagnostic: the final boss fight, flown in the real arena. Not a test; makes
## no assertions. Prints a timeline of the dragon's altitude and state, then a
## ledger of the three things the fight is made of.
##
## What to look at:
##
##   TAKE-OFF   the tick it leaves the perch, and the height it settles at.
##              That number is `cruise` in its profile and everything else in
##              the arena is measured against it.
##   THE PASS   how often it comes down, how low, and whether the strike
##              connects. A dragon that swoops and never lands a blow has its
##              hit_lead out of step with its dive speed; one that connects
##              every time is a dragon the player cannot dodge.
##   THE CLIMB  what a thrown blast does to a pass in progress. Beaten from
##              far off it should read CLIMBED; from inside its reaction it
##              should read HIT.
##   DEPARTURE  where it is when its death animation runs out. Off the top
##              corner of the shot, or the fly-away is only half a fly-away.
const Game = preload("res://game/session.gd")
const Blast = preload("res://features/combat/blast.gd")

const LEVEL := "dragons_roost"
## The deck the whole arena sits on, and therefore the line every altitude in
## this file is printed against.
const DECK := 648.0

var game: Node2D

func _initialize() -> void:
	call_deferred("run")

func step() -> void:
	await physics_frame
	await process_frame

func boot() -> void:
	game = Game.new()
	game.test_mode = true
	game.level_id = LEVEL
	root.add_child(game)
	game.start_session()
	game.player.test_control = true
	await step()

func foe() -> Area2D:
	return game.enemies[0]

## Where the dragon is, in the terms the profile is written in.
func height() -> float:
	return DECK - foe().position.y

func state_name(s: int) -> String:
	return ["IDLE", "WALK", "PUNCH", "HURT", "DEAD", "CHARGE", "SHOOT",
			"JUMP", "BLOCK"][s]

func park(at: float) -> void:
	game.player.position = Vector2(at, DECK)
	game.player.velocity = Vector2.ZERO
	game.player.facing = 1.0
	await step()

func throw_one() -> void:
	game.player.mana = game.player.MAX_MANA
	game.player.test_blast_pressed = true
	var waited := 0
	while game.player.attack == "blast" and waited < 120:
		await physics_frame
		waited += 1

func run() -> void:
	await boot()
	var dragon := foe()
	print("arena      %s, deck y %.0f, perch x %.0f" % [
		game.level.title, DECK, dragon.home.x])
	print("profile    cruise %.0f  dive %.0f  aggro %.0f  health %d  reach %.0f" % [
		float(dragon.prof.get("cruise", 0.0)), float(dragon.prof.get("dive", 0.0)),
		dragon.aggro, dragon.max_health, dragon.reach()])
	print("           swoop wind-up %.2f s, which is %.0f px of dive" % [
		dragon.hit_lead("swoop"),
		dragon.hit_lead("swoop") * float(dragon.prof.get("dive", 0.0))])
	print("           air %.0f s / ground %.0f s; attacks %s" % [
		float(dragon.prof.get("air_time", 0.0)),
		float(dragon.prof.get("ground_time", 0.0)),
		dragon.data().get("moves", {}).keys()])
	print("")

	# --- the cycle ------------------------------------------------------------
	# The thing the whole two-phase split is for: it does not stay up. Logged
	# as it happens, with every attack it actually throws, so a phase that
	# never comes round or a move that never gets used shows up here.
	print("--- THE CYCLE: 30 s of it, with the player standing his ground")
	await park(dragon.home.x - 300.0)
	var was_aloft := false
	var was_shift := false
	var was_move := ""
	var used := {}
	for i in range(1800):
		await physics_frame
		game.player.position.x = dragon.home.x - 300.0
		game.player.position.y = DECK
		game.player.health = game.player.MAX_HEALTH
		if (dragon.shift >= 0.0) != was_shift:
			was_shift = dragon.shift >= 0.0
			if was_shift:
				print("  %5.1f s  %s" % [i / 60.0,
					"TAKING OFF" if dragon.shift_up else "LANDING"])
		if dragon.aloft != was_aloft:
			was_aloft = dragon.aloft
			print("  %5.1f s    -> %s, %.0f above the deck"
					% [i / 60.0, "in the air" if was_aloft else "on its feet",
					   height()])
		var m: String = dragon.move if dragon.state == dragon.State.PUNCH else ""
		if m != "" and m != was_move:
			used[m] = int(used.get(m, 0)) + 1
			print("  %5.1f s      %s (%s, %.0f out)"
					% [i / 60.0, m, "air" if dragon.aloft else "ground",
					   absf(dragon.position.x - game.player.position.x)])
		was_move = m
	print("  attacks thrown: %s" % used)
	print("")

	# --- take-off -------------------------------------------------------------
	# Back on its perch first: the cycle above left it mid-fight.
	dragon.reset()
	dragon.target = game.player
	await step()
	print("--- TAKE-OFF: the player walks in from outside its aggro")
	await park(dragon.home.x - dragon.aggro - 80.0)
	print("  parked at %.0f, gap %.0f: aloft %s" % [
		game.player.position.x, dragon.home.x - game.player.position.x, dragon.aloft])
	await park(dragon.home.x - 420.0)
	var launched := -1
	for i in range(240):
		await physics_frame
		if dragon.aloft and launched < 0:
			launched = i
		if launched >= 0 and i - launched > 100:
			break
	print("  gap 420: launched on tick %d, settled at %.0f above the deck (%s)"
			% [launched, height(), state_name(dragon.state)])
	print("")

	# --- the pass -------------------------------------------------------------
	print("--- THE PASS: 8 seconds of it, held at arm's length")
	var passes := 0
	var strikes := 0
	var landed := 0
	var struck_at := 0.0
	var struck_gap := 0.0
	var connected := false
	var was_swooping := false
	var was_punching := false
	var before: int = game.player.health
	for i in range(600):
		await physics_frame
		# Held still in the middle of the arena: this is about what the dragon
		# does, not about whether the player can dodge it.
		game.player.position.x = dragon.home.x - 380.0
		game.player.position.y = DECK
		var punching: bool = dragon.state == dragon.State.PUNCH
		if dragon.swoop > 0.0 and not was_swooping:
			passes += 1
			print("  pass %d begun from %.0f out, %.0f above the deck" % [
				passes, absf(dragon.position.x - game.player.position.x), height()])
		was_swooping = dragon.swoop > 0.0
		if punching and not was_punching:
			strikes += 1
			struck_at = height()
			struck_gap = absf(dragon.position.x - game.player.position.x)
			connected = false
		if game.player.health < before:
			landed += 1
			connected = true
			# Topped straight back up, so a long run is not decided by the
			# player dying half way through it — and `before` goes back with
			# it, or every blow after the first reads as no change.
			game.player.health = game.player.MAX_HEALTH
			before = game.player.health
		if was_punching and not punching:
			print("  strike %d thrown from %.0f above the deck, %.0f out: %s"
					% [strikes, struck_at, struck_gap,
					   "LANDED" if connected else "missed"])
		was_punching = punching
	print("  %d passes, %d strikes thrown, %d blows landed in 10 s" % [
		passes, strikes, landed])
	print("")

	# --- the climb ------------------------------------------------------------
	print("--- THE CLIMB: a blast thrown at one, from two ranges")
	print("      it reads one from %.0f px cold, %.0f once braced" % [
		dragon.guard_reaction * Blast.SPEED,
		dragon.guard_reaction * dragon.BRACED_REACTION * Blast.SPEED])
	for gap in [320.0, 120.0]:
		dragon.reset()
		dragon.target = game.player
		dragon.braced = 0.0
		await park(dragon.home.x - 300.0)
		# Wait for it to be up and in the middle of a pass, which is the only
		# time a blast can reach it at all.
		var ready := false
		for i in range(400):
			await physics_frame
			game.player.position.y = DECK
			if dragon.aloft and dragon.swoop >= 0.0 and height() < 90.0:
				ready = true
				break
		if not ready:
			print("  %-4.0f px: never came low enough to throw at" % gap)
			continue
		var was: int = dragon.health
		var at := height()
		await park(dragon.position.x - gap)
		await throw_one()
		var top := at
		var thrown := false
		var dodged := false
		for i in range(120):
			await physics_frame
			top = maxf(top, height())
			thrown = thrown or not game.blasts.is_empty()
			dodged = dodged or dragon.dodge > 0.0
			if thrown and game.blasts.is_empty():
				break
		var verdict := "HIT" if dragon.health < was else (
				"CLIMBED" if dodged else ("MISSED" if thrown else "NOT THROWN"))
		print("  %-4.0f px: was at %.0f, went to %.0f, health %d -> %d   %s" % [
			gap, at, top, was, dragon.health, verdict])
	print("")

	# --- the answer -----------------------------------------------------
	# The other half of the fight: what the player gets back. Three standing
	# positions, 20 s of passes each, and the crudest possible input — hold J
	# whenever the dragon is within 90 px and never move.
	#
	# That is a FLOOR, not a forecast. It cannot jump (the jab wins the frame
	# every time it tries) and it never steps out of a swoop, so the damage it
	# takes is the worst case and the damage it deals is the least a player can
	# manage. The real balance of this fight wants a human on the controls, the
	# same way check_levels.py warns on a gap it can only measure.
	print("--- THE ANSWER: the crudest input there is, 20 s from each position")
	print("      (holds J in range, never moves, never jumps - a floor, not a forecast)")
	for how in ["deck", "far stone", "near stone"]:
		dragon.reset()
		dragon.target = game.player
		var stand: float = DECK if how == "deck" else 552.0
		var post: float = dragon.home.x - 380.0
		if how == "far stone":
			post = 1141.0
		elif how == "near stone":
			post = 1717.0
		game.player.position = Vector2(post, stand)
		game.player.velocity = Vector2.ZERO
		game.player.health = game.player.MAX_HEALTH
		await step()
		var full: int = dragon.health
		var swings := 0
		var taken := 0
		for i in range(1200):
			await physics_frame
			# Pinned, so the run measures reach rather than whether he wandered
			# off a 74 px stone.
			game.player.position.x = post
			taken += game.player.MAX_HEALTH - game.player.health
			game.player.health = game.player.MAX_HEALTH
			game.player.facing = signf(dragon.position.x - game.player.position.x)
			if absf(dragon.position.x - game.player.position.x) < 90.0:
				game.player.test_attack_pressed = true
				swings += 1
		var quiet: String = ""
		if full == dragon.health and taken == 0:
			# Not a bug: the far stone is 959 from the perch and the dragon has
			# 560 of aggro, so standing there never starts the fight at all.
			quiet = "   (never engaged - %.0f out, aggro %.0f)" % [
				absf(dragon.home.x - post), dragon.aggro]
		print("  %-11s dealt %3d of the dragon's %d, took %3d of his own 100%s"
				% [how, full - dragon.health, full, taken, quiet])
	print("")

	# --- the departure --------------------------------------------------------
	print("--- DEPARTURE: put down at the near end of the arena")
	dragon.reset()
	dragon.target = game.player
	await park(dragon.home.x - 300.0)
	for i in range(200):
		await physics_frame
		game.player.position.y = DECK
		if dragon.aloft:
			break
	var from: Vector2 = game.player.position
	var at_death: Vector2 = dragon.position
	dragon.take_hit(dragon.health, from)
	print("  struck from x %.0f; it turns to face %+.0f, gate shut_at %s" % [
		from.x, dragon.facing,
		"open" if game.gate_shut_at() == INF else str(game.gate_shut_at())])
	var ticks := 0
	while dragon.visible and ticks < 400:
		await physics_frame
		ticks += 1
		if ticks % 30 == 0:
			print("    %.1f s: x %+.0f, %.0f above the deck, playing %s"
					% [ticks / 60.0, dragon.position.x - at_death.x, height(),
					   dragon.sprite.animation])
	print("  gone after %.2f s, %.0f px away and %.0f up" % [
		ticks / 60.0, dragon.position.x - at_death.x, height()])
	print("  the flag is %s" % ("open" if game.gate_shut_at() == INF else "still shut"))
	quit()
