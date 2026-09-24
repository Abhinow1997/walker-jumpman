extends SceneTree
## Diagnostic: how long the dragon fight lasts and how hard it pushes back.
## Not a test; makes no assertions. It is the before-and-after for any change
## to the boss's numbers.
##
## Two halves.
##
## THE ARITHMETIC needs no simulation: how many clean hits of each of the
## player's attacks it takes to empty the bar. "Too easy in five hits" is this
## number, and it is the one a health change moves.
##
## THE FIGHT is thirty seconds of the dragon actually fighting a player who
## stands his ground on the deck, healed every tick so the run is not cut
## short. It counts what the boss threw, what landed, and what it did about
## blasts — the things aggression means. The player is deliberately crude: a
## dummy that jumps and swings on a fixed cadence measures the BOSS, and a
## clever one would measure me.
##
##     <godot> --path godot --headless --script tests/diag_dragonfight.gd
const Game = preload("res://game/session.gd")
const Enemy = preload("res://features/combat/enemy.gd")
const Moveset = preload("res://features/player/moveset.gd")

const LEVEL := "fractured_isles"
const DECK := 660.0
## Thirty seconds at 60 Hz.
const WATCH := 1800

var game: Node2D
var wyrm: Area2D

func _initialize() -> void:
	call_deferred("run")

func step() -> void:
	await physics_frame
	await process_frame

func best_hits() -> void:
	## Every attack the player owns, and the clean hits each needs.
	var rows: Array = []
	for key in ["punch_a", "punch_b", "kick", "charge"]:
		var worst := 0
		for frame in range(12):
			for hit in Moveset.hits(key, frame):
				worst = maxi(worst, int(hit["damage"]))
		if worst > 0:
			rows.append([key, worst])
	rows.append(["blast", 45])
	print("  health %d" % wyrm.max_health)
	for row in rows:
		print("    %-8s %3d damage -> %5.1f clean hits"
				% [row[0], row[1], float(wyrm.max_health) / float(row[1])])

func fight() -> void:
	## Thirty seconds of it, against a dummy that will not die.
	var swoops := 0
	var breaths := 0
	var claws := 0
	var landed := 0
	var dealt := 0
	var dodges := 0
	var aloft_ticks := 0
	var in_reach := 0
	var last_move := ""
	var last_state: int = -1
	var blasts := 0
	var hp: int = game.player.health
	game.player.test_control = true
	for i in range(WATCH):
		await physics_frame
		# A dummy that stands, jumps every second and swings, and throws a
		# blast every two. Crude on purpose — see the header.
		game.player.position.y = minf(game.player.position.y, DECK)
		if i % 60 == 0:
			game.player.test_jump_pressed = true
		if i % 45 == 20:
			game.player.test_attack_pressed = true
		if i % 120 == 60:
			game.player.test_blast_pressed = true
			blasts += 1
		if game.player.health < hp:
			landed += 1
		hp = game.player.health
		game.player.health = game.player.MAX_HEALTH
		if wyrm.aloft:
			aloft_ticks += 1
		if absf(wyrm.position.x - game.player.position.x) <= 200.0:
			in_reach += 1
		if wyrm.dodge > 0.0 and last_state != 99:
			dodges += 1
			last_state = 99
		elif wyrm.dodge <= 0.0:
			last_state = 0
		if wyrm.state == wyrm.State.PUNCH and wyrm.move != last_move:
			match wyrm.move:
				"swoop": swoops += 1
				"claw": claws += 1
				"fire", "fire_air": breaths += 1
			last_move = wyrm.move
		elif wyrm.state != wyrm.State.PUNCH:
			last_move = ""
		if not wyrm.alive():
			break
		dealt = wyrm.max_health - wyrm.health
	print("  30 s of fight, player pinned on the deck:")
	print("    dragon threw   %2d swoop(s), %2d claw(s), %2d breath(s)"
			% [swoops, claws, breaths])
	print("    it landed      %2d blow(s) on the player" % landed)
	print("    it dodged      %2d of %d blast(s) thrown at it" % [dodges, blasts])
	print("    it was aloft   %.0f%% of the time, within 200 px %.0f%%"
			% [100.0 * aloft_ticks / WATCH, 100.0 * in_reach / WATCH])
	print("    player took it to %d/%d" % [wyrm.health, wyrm.max_health])

func spammed() -> void:
	## Ten seconds of nothing but K, which is the thing the player does when a
	## boss is out of reach. It should cost him: the dragon reads the pattern
	## rather than each shot, climbs out of the flat line the blast flies on,
	## and stops waiting out its swoop cooldown. See SPAM_MAX in enemy.gd.
	var peak_spam := 0.0
	var peak_lift := 0.0
	var swoops := 0
	var landed := 0
	var last_move := ""
	var hp: int = game.player.health
	game.player.position = Vector2(wyrm.home.x - 420.0, DECK)
	game.player.velocity = Vector2.ZERO
	wyrm.reset()
	wyrm.target = game.player
	wyrm.engaged = true
	wyrm.aloft = true
	wyrm.grounded = false
	wyrm.deck_y = DECK
	wyrm.mark_y = DECK
	wyrm.air_left = 60.0
	wyrm.position = Vector2(wyrm.home.x, DECK - 156.0)
	await step()
	for i in range(600):
		await physics_frame
		game.player.position.y = DECK
		if i % 18 == 0:
			game.player.test_blast_pressed = true
		if game.player.health < hp:
			landed += 1
		hp = game.player.health
		game.player.health = game.player.MAX_HEALTH
		peak_spam = maxf(peak_spam, wyrm.spam)
		peak_lift = maxf(peak_lift, DECK - 156.0 - wyrm.position.y)
		if wyrm.state == wyrm.State.PUNCH and wyrm.move != last_move:
			# Any attack: a breath is coming down at him too.
			swoops += 1
			last_move = wyrm.move
		elif wyrm.state != wyrm.State.PUNCH:
			last_move = ""
	print("  10 s of nothing but the blast, thrown every 0.3 s:")
	print("    stack peaked at %.1f of %.0f, and it climbed %.0f px over cruise"
			% [peak_spam, Enemy.SPAM_MAX, peak_lift])
	print("    it attacked %d time(s) anyway and landed %d blow(s)"
			% [swoops, landed])

func run() -> void:
	game = Game.new()
	game.test_mode = true
	game.level_id = LEVEL
	root.add_child(game)
	game.start_session()
	await step()
	for foe in game.enemies:
		if foe.is_boss():
			wyrm = foe
		else:
			foe.target = null
	print("%s dragon: fling %.0f, unflinching %s, swoop_cooldown %.2f, special %.2f"
			% [LEVEL, wyrm.fling_for(),
			   str(bool(Enemy.PROFILES["dragon"].get("unflinching", false))),
			   float(Enemy.PROFILES["dragon"].get("swoop_cooldown", 0.0)),
			   float(Enemy.PROFILES["dragon"].get("special_cooldown", 0.0))])
	best_hits()
	var moves: Dictionary = wyrm.data().get("moves", {})
	for name in moves:
		var r: Array = moves[name].get("hit_rect", [0, 0, 0, 0])
		var band: Array = moves[name].get("range", [])
		print("    %-9s reach %5.1f  damage %2d  band %s"
				% [name, float(r[0]) + float(r[2]), int(moves[name].get("damage", 0)),
				   str(band)])
	# In the arena, fight on.
	game.player.position = Vector2(wyrm.home.x - 380.0, DECK)
	game.player.velocity = Vector2.ZERO
	wyrm.engaged = true
	await step()
	await fight()
	await spammed()
	quit()
