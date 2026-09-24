extends SceneTree
## Development tool: how far a player can walk out of a boss fight.
##
## Both boss levels fence their bosses into an arena, and both used to leave
## the way out of it open — so a player could walk back to ground neither boss
## could follow him onto, and the fight stopped happening. A level names the
## line it seals behind (`boss_arena`); this drives him at it and reports the
## furthest he gets, with the fight on and again once it is over.
##
##     <godot> --path godot --headless --script tests/diag_arena_seal.gd
##     <godot> --path godot --headless --script tests/diag_arena_seal.gd -- dragons_roost
const Game = preload("res://game/session.gd")

## Levels to walk, when none is named on the command line.
const LEVELS := ["fractured_isles", "dragons_roost"]

var game: Node2D

func _initialize() -> void:
	call_deferred("run")

func steps(n: int) -> void:
	for i in range(n):
		await physics_frame
		await process_frame

## Where the level cues the fight: the first cutscene panel with an `at`.
func card_x() -> float:
	for card in game.level.get("cutscene", []):
		if card.has("at"):
			return float(card["at"])
	return game.arena_line() + 96.0

func bosses() -> Array:
	var out: Array = []
	for foe in game.enemies:
		if is_instance_valid(foe) and foe.is_boss():
			out.append(foe)
	return out

## The one with no floor under it, which is the only one fly_bounds means
## anything for. The Roost fights two and lists the walker second, so taking
## the last boss reported a Dragon Lord's fence: (-inf, inf), unset and
## correctly so.
func flyer_boss() -> Node2D:
	for foe in bosses():
		if foe.is_flyer():
			return foe
	return null

## Holds left for `ticks` and reports the furthest west he got, stopping at
## the first death: walking west off a deck is a fall, and a respawn at the
## level spawn is not an escape from the arena.
func run_west(ticks: int) -> float:
	game.player.test_control = true
	game.player.test_axis = -1.0
	var least := INF
	for i in ticks:
		await physics_frame
		if game.state != Game.State.PLAYING:
			break
		least = minf(least, game.player.position.x)
	game.player.test_axis = 0.0
	return least

## A running jump west, which is how he would clear a gap on the way back.
func jump_west(from: float, on: float) -> float:
	game.player.position = Vector2(from, on)
	game.player.velocity = Vector2.ZERO
	for _i in 20:
		await physics_frame
	# The axis as well as the velocity: the player recomputes velocity.x from
	# his input every frame, so a jump set by velocity alone goes straight up.
	game.player.test_control = true
	game.player.test_axis = -1.0
	game.player.velocity = Vector2(-320.0, -330.0)
	var least := INF
	for i in 90:
		await physics_frame
		if game.state != Game.State.PLAYING:
			break
		least = minf(least, game.player.position.x)
	game.player.test_axis = 0.0
	return least

## Puts him inside the arena with the fight on, standing him back up first if
## the last measurement ended in the water.
func arm(at: float, on: float) -> void:
	if game.state != Game.State.PLAYING:
		game.restart_attempt()
		await steps(2)
	game.player.position = Vector2(at, on)
	game.player.velocity = Vector2.ZERO
	for _i in 30:
		await physics_frame
	# test_mode takes the card's effect without its seconds of picture.
	game._wake_boss()
	await steps(2)

func walk(id: String) -> void:
	game = Game.new()
	game.test_mode = true
	game.level_id = id
	root.add_child(game)
	await steps(3)
	game.start_session()
	await steps(2)
	var deck: float = game.player.position.y
	# Everything but the bosses put down, which is what a player who reached
	# the arena would have done. Their own gate is left to them.
	for foe in game.enemies:
		if is_instance_valid(foe) and not foe.is_boss():
			foe.health = 0
	await steps(4)

	var line: float = game.arena_line()
	print("=== %s: arena line %.0f, fight cued at %.0f" % [id, line, card_x()])
	if line == -INF:
		print("    names no boss_arena - nothing is sealed")
		game.queue_free()
		await steps(2)
		return

	await arm(card_x(), deck)
	var boss: Node2D = bosses()[0]
	var flyer: Node2D = flyer_boss()
	print("    sealed=%s  wall layer=%d  arena %s  flyer fence %s" % [
		game.sealed, game.seal_wall.collision_layer, game.arena_of(boss),
		flyer.fly_bounds])
	print("    camera left edge %.0f, wall %.0f inside the screen" % [
		game.camera.position.x - 480.0,
		line - (game.camera.position.x - 480.0)])

	var west: float = await run_west(720)
	print("    held left 12s:   furthest west %6.0f   %s" % [
		west, "HELD" if west > line else "ESCAPED past the line"])
	await arm(line + 60.0, deck)
	var leapt: float = await jump_west(line + 60.0, deck)
	print("    jumped west:     furthest west %6.0f   %s" % [
		leapt, "HELD" if leapt > line else "ESCAPED past the line"])

	# And the boss cannot leave either, which is the other half of one room.
	await arm(line + 60.0, deck)
	var flew := INF
	for i in 900:
		await physics_frame
		if game.state != Game.State.PLAYING:
			break
		flew = minf(flew, flyer.position.x)
	print("    flyer over 15s:  furthest west %6.0f   %s" % [
		flew, "stayed in" if flew >= line - 1.0 else "drifted out"])

	# It opens when every boss is gone.
	if game.state != Game.State.PLAYING:
		await arm(line + 60.0, deck)
	for foe in bosses():
		foe.take_hit(foe.health, game.player.global_position)
	for _i in 1200:
		await physics_frame
		if game.boss() == null:
			break
	# The seal is lifted by _sync_gates on the NEXT tick, not on the frame the
	# last body goes.
	await steps(4)
	var after: float = await jump_west(line + 60.0, deck)
	print("    fight over:      sealed=%s, furthest west %6.0f   %s" % [
		game.sealed, after,
		"still held" if after > line else "free to go back"])
	game.queue_free()
	await steps(2)

func run() -> void:
	var want: Array = LEVELS
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		want = [args[0]]
	for id in want:
		await walk(str(id))
	quit()
