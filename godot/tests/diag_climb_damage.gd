extends SceneTree
## Diagnostic: what every enemy on a level actually hits the player for.
##
## No simulation and no assertions, the same as diag_boss_health.gd. A level's
## `enemy_damage` block is a key in a JSON file until something reads it off a
## spawned body, and this is the before-and-after for any change to one. The
## Climb and The Fractured Isles are read side by side because the point of the
## override is that the same kind is two different blows on the two of them.
##
##     <godot> --path godot --headless --script tests/diag_climb_damage.gd
##     <godot> --path godot --headless --script tests/diag_climb_damage.gd -- greybox
const Game = preload("res://game/session.gd")

## Levels to read, when none is named on the command line.
const LEVELS := ["the_climb", "fractured_isles"]
## What the player has to spend, so a blow can be read as a share of the bar
## rather than as a bare number. features/player/player.gd.
const PLAYER_HEALTH := 100

var game: Node2D

func _initialize() -> void:
	call_deferred("run")

func steps(n: int) -> void:
	for i in range(n):
		await physics_frame
		await process_frame

func read(id: String) -> void:
	game = Game.new()
	game.test_mode = true
	game.level_id = id
	root.add_child(game)
	await steps(3)
	game.start_session()
	await steps(2)
	var hits: Dictionary = game.level.get("enemy_damage", {})
	print("=== %s" % id)
	var counted := {}
	for foe in game.enemies:
		if not is_instance_valid(foe) or counted.has(foe.kind):
			continue
		counted[foe.kind] = true
		var source := "the level" if hits.has(foe.kind) else "the profile"
		var damage: int = foe.attack_damage()
		print("  %-12s hits for %3d  -> %4.1f blows to empty the bar  (%s)" % [
			foe.kind, damage, float(PLAYER_HEALTH) / maxf(float(damage), 1.0), source])
	game.queue_free()
	await steps(2)

func run() -> void:
	var wanted: Array = LEVELS
	var argv := OS.get_cmdline_user_args()
	if argv.size() > 0:
		wanted = argv
	for id in wanted:
		await read(id)
	quit()
