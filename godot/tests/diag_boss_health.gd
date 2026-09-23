extends SceneTree
## Diagnostic: how many hits each boss is, as the level that places it sets it.
##
## No simulation and no assertions. "Too easy in five hits" is arithmetic, and
## this is the arithmetic — every attack the player owns against every boss on
## the board, counted in CLEAN hits of that one attack. It is the before-and-
## after for any change to a boss's health, and the one place the two levels
## that share the dragon can be read side by side: the isles' is the profile's
## number and the Roost's is the level's own, so the same kind is two different
## fights on purpose.
##
##     <godot> --path godot --headless --script tests/diag_boss_health.gd
##     <godot> --path godot --headless --script tests/diag_boss_health.gd -- dragons_roost
const Game = preload("res://game/session.gd")
const Moveset = preload("res://features/player/moveset.gd")

## Levels to read, when none is named on the command line.
const LEVELS := ["fractured_isles", "dragons_roost"]
## What the player can put into a boss. The four swings are measured off the
## art the same way the game measures them; the blast carries its damage in
## its own scene rather than in a hit frame, so it is named here.
const SWINGS := ["punch_a", "punch_b", "kick", "charge"]
const BLAST := 45

var game: Node2D

func _initialize() -> void:
	call_deferred("run")

func steps(n: int) -> void:
	for i in range(n):
		await physics_frame
		await process_frame

## The hardest damage any frame of this move opens, which is what a clean hit
## with it is worth.
func best(key: String) -> int:
	var worst := 0
	for frame in range(12):
		for hit in Moveset.hits(key, frame):
			worst = maxi(worst, int(hit["damage"]))
	return worst

func read(id: String) -> void:
	game = Game.new()
	game.test_mode = true
	game.level_id = id
	root.add_child(game)
	await steps(3)
	game.start_session()
	await steps(2)
	var tuned: Dictionary = game.level.get("enemy_health", {})
	print("=== %s" % id)
	for foe in game.enemies:
		if not (is_instance_valid(foe) and foe.is_boss()):
			continue
		var source := "the level" if tuned.has(foe.kind) else "the profile"
		print("  %-12s health %4d  (%s)" % [foe.kind, foe.max_health, source])
		var line := ""
		for key in SWINGS:
			var damage := best(key)
			if damage <= 0:
				continue
			line = "    %-8s %3d damage -> %5.1f clean hits" % [
				key, damage, float(foe.max_health) / float(damage)]
			print(line)
		print("    %-8s %3d damage -> %5.1f clean hits" % [
			"blast", BLAST, float(foe.max_health) / float(BLAST)])
	game.queue_free()
	await steps(2)

func run() -> void:
	var want: Array = LEVELS
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		want = [args[0]]
	for id in want:
		await read(str(id))
	quit()
