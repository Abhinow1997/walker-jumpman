extends SceneTree
## Diagnostic: which loop is playing at each beat of a boss fight.
##
## The battle track belongs to the FIGHT and the level's own quiet loop is the
## bed for everything after it. That is one question on a level with one boss
## and a different one on The Dragon's Roost, which fights two: the track has
## to last as long as the LAST of them, not the first one in the level's list.
##
##     <godot> --path godot --headless --script tests/diag_boss_track.gd
const Game = preload("res://game/session.gd")

const LEVELS := ["fractured_isles", "dragons_roost"]

var game: Node2D
## Whether the level just walked fights more than one, which is the only case
## the order of the deaths can matter in. Read after walk() returns, because
## by then its world has been torn down and there is nothing left to count.
var many: bool = false

func _initialize() -> void:
	call_deferred("run")

func steps(n: int) -> void:
	for i in range(n):
		await physics_frame
		await process_frame

func bosses() -> Array:
	var out: Array = []
	for foe in game.enemies:
		if is_instance_valid(foe) and foe.is_boss():
			out.append(foe)
	return out

func say(label: String) -> void:
	var who: Array = []
	for foe in bosses():
		who.append("%s %s%s" % [foe.kind, "alive" if foe.alive() else "DOWN",
				"" if foe.visible else "/gone"])
	print("    %-28s track %-16s | %s" % [label, game.current_track(),
			", ".join(who)])

## Waits out a death: the collapse, the time on the deck, and for the flyer the
## flight out of the level. Reports the ticks, or -1.
func wait_gone(foe: Area2D) -> int:
	for i in range(900):
		await physics_frame
		if not foe.visible:
			return i
	return -1

func walk(id: String, last_first: bool) -> void:
	game = Game.new()
	game.test_mode = true
	game.level_id = id
	root.add_child(game)
	await steps(3)
	game.start_session()
	game.story_cards.clear()
	await steps(2)
	print("=== %s: level loop %s, battle loop %s%s" % [
		id, game.level.get("music", ""), game.level.get("boss_music", ""),
		"  (last listed beaten first)" if last_first else ""])
	# The order the level lists them in, which is what boss() picks from.
	var listed: Array = []
	for foe in bosses():
		listed.append(foe.kind)
	print("    bosses in list order: %s" % str(listed))
	many = listed.size() > 1
	say("before the fight")
	game._wake_boss()
	await steps(2)
	say("fight on")

	# Put them down one at a time and watch the loop through each death: the
	# killing blow, the body on the deck, the body gone. Both orders, because
	# which of the two dies first is the player's choice and the old rule was
	# only wrong one way round.
	var order: Array = bosses()
	if last_first:
		order.reverse()
	for foe in order:
		if not foe.alive():
			continue
		var _down: bool = foe.take_hit(foe.health, game.player.global_position)
		await steps(2)
		say("%s beaten" % foe.kind)
		var gone: int = await wait_gone(foe)
		await steps(2)
		say("%s gone (%.1fs)" % [foe.kind, gone / 60.0])
	game.queue_free()
	await steps(2)

func run() -> void:
	var want: Array = LEVELS
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		want = [args[0]]
	for id in want:
		await walk(str(id), false)
		if many:
			await walk(str(id), true)
	quit()
