extends SceneTree
## Diagnostic: what it actually costs to kill an enemy by mashing K, at a range
## he can read the blast from, against one he cannot. Not a test; makes no
## assertions. Prints a blast-by-blast ledger.
##
## The three numbers to look at are the count, the mana, and whether the ledger
## ever reads GUARD BREAK. A guard that never breaks is a wall; a guard that
## breaks on the second blast is decoration.
##
## The Dragon Lord has no guard — his pack ships no defend frame — so his
## column reads BURNT OUT instead: he throws his attack early enough that the
## fire is out when the blast arrives, and it dies in the fire.
const Game = preload("res://game/session.gd")
const Enemy = preload("res://features/combat/enemy.gd")
const Blast = preload("res://features/combat/blast.gd")

var game: Node2D

func _initialize() -> void:
	call_deferred("run")

func step() -> void:
	await physics_frame
	await process_frame

## Throw one and wait until it has either landed or expired.
func throw_one() -> void:
	game.player.test_blast_pressed = true
	var waited := 0
	while game.player.attack == "blast" and waited < 120:
		await physics_frame
		waited += 1
	while not game.blasts.is_empty() and waited < 300:
		await physics_frame
		waited += 1

func ledger(kind: String, gap: float, pause_ticks: int, shots: int) -> void:
	var deck := -600.0
	var foe := Enemy.new()
	foe.kind = kind
	foe.position = Vector2(2600, deck)
	foe.fall_limit = 1000.0
	foe.struck_player.connect(game._on_player_struck)
	# On the roster, not just in the scene: warn_of_blast is delivered by the
	# session walking `enemies`, so an enemy that is only a child never hears a
	# thing and never guards.
	game.enemies.append(foe)
	game.add_child(foe)
	await step()
	# Parked: this is about what the blast does to him, not about the chase.
	foe.target = null
	game.player.position = Vector2(2600 - gap, deck)
	game.player.velocity = Vector2.ZERO
	game.player.facing = 1.0
	game.player.mana = game.player.MAX_MANA
	await step()
	print("--- %s at %.0f px, %.2f s between shots  (reads one from %.0f px cold, %.0f braced)" % [
		kind, gap, float(pause_ticks) / 60.0,
		foe.guard_reaction * Blast.SPEED,
		foe.guard_reaction * foe.BRACED_REACTION * Blast.SPEED])
	var spent := 0
	for i in range(shots):
		var before_hp: int = foe.health
		var before_guard: float = foe.guard
		var mana_before: int = 0
		var blocked := false
		var broke := false
		var burnt := false
		# He has to be free to throw, or the press is swallowed by the swing he
		# is still in and the ledger reports a shot that never happened.
		var settle := 0
		while game.player.attack != "" and settle < 120:
			await physics_frame
			settle += 1
		game.player.mana = game.player.MAX_MANA
		mana_before = game.player.mana
		# Watch for the guard going up and for the frame it gives.
		game.player.test_blast_pressed = true
		var waited := 0
		while waited < 300:
			await physics_frame
			waited += 1
			if foe.guarding():
				blocked = true
			if foe.guard_broke > 0.0:
				broke = true
			if foe.burns_projectiles() and not game.blasts.is_empty():
				burnt = true
			if foe.health != before_hp:
				break
			if game.blasts.is_empty() and waited > 30:
				break
		spent += mana_before - game.player.mana
		var verdict := "clean"
		if broke:
			verdict = "GUARD BREAK"
		elif blocked and before_hp - foe.health < 20:
			verdict = "blocked"
		elif burnt and before_hp == foe.health:
			verdict = "BURNT OUT"
		print("  %2d  %-11s  hp %4d -> %-4d  guard %6.1f -> %-6.1f  braced %.2f" % [
			i + 1, verdict, before_hp, foe.health, before_guard, foe.guard, foe.braced])
		if not foe.alive():
			print("  down after %d blast(s), %d mana" % [i + 1, spent])
			break
		for w in range(pause_ticks):
			await physics_frame
	if foe.alive():
		print("  still up after %d blast(s), %d mana, hp %d/%d" % [
			shots, spent, foe.health, foe.max_health])
	game.enemies.erase(foe)
	foe.queue_free()
	await step()

func run() -> void:
	game = Game.new()
	game.test_mode = true
	game.level_id = "fractured_isles"
	root.add_child(game)
	game.start_session()
	game.player.test_control = true
	await step()
	for parked in game.enemies:
		parked.target = null
	game._add_solid(Rect2(2000, -600.0, 900, 200))
	await step()

	# Mashing it from across the room: the case this was built for.
	await ledger("bandit", 280.0, 2, 12)
	# The same mashing from inside the range a BRACED enemy can read: still
	# melee distance, but the blast lands.
	await ledger("bandit", 60.0, 2, 4)
	# And the middle ground that is the actual lesson: closer than his cold
	# reaction, and not mashed, so he is never braced when it arrives.
	await ledger("bandit", 150.0, 150, 4)
	# Spaced out but still across the room: he reads every one of them cold, and
	# his guard refills faster than a patient player can spend it.
	await ledger("bandit", 280.0, 150, 6)
	# The bruiser reads one slowest; the archer fastest.
	await ledger("mark", 280.0, 2, 8)
	await ledger("hunter", 280.0, 2, 8)
	# And the boss, who has no guard at all and answers with fire instead. Far
	# enough back that he has time to wind up, then from inside it.
	await ledger("dragon_lord", 340.0, 2, 14)
	await ledger("dragon_lord", 120.0, 2, 6)
	quit()
