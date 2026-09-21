extends SceneTree
## Diagnostic: climbs The Climb on the controls and reports how far it got.
##
## Not a test; makes no assertions. scripts/check_levels.py proves every hop is
## inside the jump envelope on paper, and tests/test_levels.gd proves the view
## and the fatal line behave. Neither of them presses a key. This does: it holds
## a direction, jumps near each takeoff edge and nothing else, so what it
## measures is whether eighteen jumps in a row are actually makeable with the
## movement the game has - including the switchbacks, where he lands running one
## way on a 48 px ledge and has to leave it going the other.
##
##     <godot> --path godot --headless --script tests/diag_climb.gd
##
## It does not fight and it does not dodge. A run that dies to a bandit or to a
## stone is not a broken level; a run that cannot make a JUMP is.
const Game = preload("res://game/session.gd")

## How close to the takeoff edge it lets him get before jumping. Small, because
## the gaps were authored against a takeoff from the lip: every 1 px he jumps
## early is 1 px more air to cross.
const LAUNCH := 14.0

var game: Node2D
var chain: Array = []
var at: int = 0
var reached: int = 0
var stalled: int = 0
## Set from the command line to print every tick spent on one ledge.
var verbose: bool = false
var watch: int = -1

func _initialize() -> void:
	call_deferred("run")

func step() -> void:
	await physics_frame
	await process_frame

## The ledges in climbing order, bottom first, as [x0, x1, top].
##
## Solids that share a top edge and touch are merged into one, because they are
## one surface to stand on: the rest shelves are two or three pieces laid
## abreast, and reading them raw turns each shelf into two or three "ledges" a
## hop apart with no rise and no gap between them. The driver then tries to jump
## from a shelf to the other half of itself and gets nowhere — 6 of 57 with
## thirteen deaths, against 47 of 47 once they are merged.
func build_chain() -> void:
	chain.clear()
	var raw: Array = []
	for entry in game.level.solids:
		raw.append([float(entry[0]), float(entry[0]) + float(entry[2]),
					float(entry[1])])
	raw.sort_custom(func(a, b): return a[2] > b[2] if a[2] != b[2] else a[0] < b[0])
	for rung in raw:
		if not chain.is_empty() and absf(chain[-1][2] - rung[2]) < 0.5 \
				and rung[0] <= chain[-1][1] + 0.5:
			chain[-1][1] = maxf(chain[-1][1], rung[1])
		else:
			chain.append(rung)

## Which ledge he is standing on, or -1 while he is in the air. MEASURED every
## tick rather than counted, and that is the difference between a driver that
## climbs this level and one that gets four ledges up and hangs there.
##
## A fall shorter than CLIMB_DROP is survivable here on purpose, so a missed
## jump usually means landing two ledges lower rather than dying. A counter that
## only ever goes up believes he is still where he was, aims the next jump from
## a ledge he is not standing on, and repeats that until the clock runs out.
func footing(player) -> int:
	if not player.is_on_floor():
		return -1
	for i in chain.size():
		var c: Array = chain[i]
		if absf(player.position.y - c[2]) < 8.0 and player.position.x > c[0] - 6.0 and player.position.x < c[1] + 6.0:
			return i
	return -1

## Is there a live stone over the ground he is about to cross? Only ones above
## him and inside the height of a jump count: a stone already past him is not
## his problem, and one three ledges up will have broken long before he is in
## the air.
func _rock_over(player, lo: float, hi: float) -> bool:
	for stone in game.stones:
		if not is_instance_valid(stone) or stone.broken:
			continue
		if stone.position.x < lo - 26.0 or stone.position.x > hi + 26.0:
			continue
		var above: float = player.position.y - stone.position.y
		if above > -40.0 and above < 300.0:
			return true
	return false

func drive() -> void:
	var player = game.player
	player.test_control = true
	player.test_jump_pressed = false
	var standing := footing(player)
	if standing >= 0 and standing != at:
		at = standing
		reached = maxi(reached, at)
		stalled = 0
		return
	if at + 1 >= chain.size():
		player.test_axis = 0.0
		return
	var here: Array = chain[at]
	var next: Array = chain[at + 1]
	var dir: float = 1.0 if next[0] + next[1] > here[0] + here[1] else -1.0
	# Run at the lip, then AIM. A jump held all the way through travels 164 px
	# at the rise this tower steps by, and its ledges are 36 to 72 wide, so
	# holding the key down sails over most of them and lands in the sea - which
	# is what the first version of this did, eighteen times out of eighteen.
	# Letting go once he is over the ledge is what a person does and what the
	# level is asking for; the player keeps full control of his motion in the
	# air, so it is the aiming and not the reaching that this climb is about.
	var middle: float = (next[0] + next[1]) * 0.5
	if player.is_on_floor() or dir * (middle - player.position.x) > 0.0:
		player.test_axis = dir
	else:
		player.test_axis = 0.0
	# Wait for the rock. Without this the run dies on the same ledge on every
	# single attempt — the shafts are deterministic, so a driver that climbs at
	# a constant rate meets the same stone at the same jump forever — and that
	# says nothing about the level, only that this thing never looks up. It is
	# also the one thing a person obviously does, and the skill the shafts are
	# there to ask for.
	if player.is_on_floor() and _rock_over(player, minf(player.position.x, next[0]),
										   maxf(player.position.x, next[1])):
		player.test_axis = 0.0
		return
	# Jump once he is within LAUNCH of the lip he is leaving, and only while he
	# is standing on it. The gate matters: the condition stays true for the
	# whole flight once he is past the lip, and the player buffers a press for
	# six ticks, so leaving the key down meant a press still queued when he
	# touched down - he landed on a ledge and bounced straight off it, in the
	# direction of the NEXT hop, without ever running at it. That reads in the
	# trace as a run that gets three ledges up and then stops dead.
	var edge: float = here[1] if dir > 0.0 else here[0]
	if player.is_on_floor() and dir * (player.position.x - edge) >= -LAUNCH:
		player.test_jump_pressed = true

func run() -> void:
	game = Game.new()
	game.test_mode = true
	game.level_id = "the_climb"
	root.add_child(game)
	await step()
	build_chain()
	print("The Climb: %d ledges to climb" % (chain.size() - 1))
	# Twice, and the first pass is the one that answers the question. With the
	# punks down, anything that stops the run is the LEVEL - a gap too wide, a
	# ledge too narrow, a turn there is no room to make. With them up it is a
	# report on what a player who refuses to fight gets away with, and a run
	# pinned on a bandit's island says nothing about the eighteen jumps.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("watch="):
			watch = int(arg.trim_prefix("watch="))
			verbose = true
	await attempt("the climb alone, no punks", true)
	if not verbose:
		await attempt("as it ships", false)
	quit()

func attempt(label: String, clear_the_way: bool) -> void:
	at = 0
	reached = 0
	stalled = 0
	game.load_level("the_climb")
	await step()
	game.start_session()
	await step()
	if clear_the_way:
		# Taken out of the level rather than hit for a large number: a punk
		# survives his first blow whatever its size, and a dead one is put back
		# on his feet by the next retry, so both of those quietly left all three
		# of them standing and made this pass identical to the one below it.
		for foe in game.enemies:
			foe.queue_free()
		game.enemies.clear()
	await step()
	print("")
	print("--- %s ---" % label)

	var last_at := -1
	var ticks := 0
	var deaths := 0
	var stuck_on := -1
	while ticks < 16200 and game.state != Game.State.COMPLETE:
		if game.state == Game.State.PLAYING:
			drive()
		elif game.state == Game.State.DYING:
			# Back to the bottom, and the chain starts again with him. Counted
			# on the way IN to the state, which lasts half a second: counting
			# every tick of it turned thirty deaths into a thousand.
			if at != 0:
				deaths += 1
			at = 0
		if verbose and at == watch and game.state == Game.State.PLAYING:
			var pl = game.player
			print("      x %7.1f y %7.1f vx %7.1f floor %s axis %4.1f jump %s hurt %s"
					% [pl.position.x, pl.position.y, pl.velocity.x,
					   pl.is_on_floor(), pl.test_axis, pl.test_jump_pressed,
					   pl.is_hurt()])
		await physics_frame
		ticks += 1
		if at != last_at:
			var here: Array = chain[at]
			print("  ledge %2d  y %-7.0f  after %5.2f s  health %3d  stones %d"
					% [at, here[2], float(ticks) / 60.0, game.player.health,
					   game.stones.size()])
			last_at = at
			stalled = 0
		else:
			stalled += 1
			if stalled == 420:
				stuck_on = at
				print("  ... seven seconds on ledge %d (y %.0f) with no progress"
						% [at, chain[at][2]])

	print("  highest ledge reached: %d of %d" % [reached, chain.size() - 1])
	print("  finished: %s   deaths: %d   time: %.1f s"
			% [game.state == Game.State.COMPLETE, deaths, float(ticks) / 60.0])
	if stuck_on >= 0:
		print("  first stall was on ledge %d, y %.0f" % [stuck_on, chain[stuck_on][2]])
