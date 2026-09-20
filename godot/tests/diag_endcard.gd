extends SceneTree
## Diagnostic: from where can the dragon be beaten and still leave a body for
## the departure card to be cued off? Not a test; makes no assertions.
##
## The card waits on fallen() — beaten, down, and still on the screen. Every
## way the body can fail to be any of those is a way the level ends with no
## ending, and none of them looks like a crash.
##
##     <godot> --path godot --headless --script tests/diag_endcard.gd
const Game = preload("res://game/session.gd")

const LEVEL := "fractured_isles"
const DECK := 660.0
## Long enough for the whole death: any glide down, the fall, DOWN_TIME and a
## margin. In physics ticks.
const PATIENCE := 900

var game: Node2D
var wyrm: Area2D
var at: float = 0.0

func _initialize() -> void:
	call_deferred("run")

func step() -> void:
	await physics_frame
	await process_frame

func arm() -> void:
	## Both cards unplayed and the dragon back on its feet, without rebuilding
	## the level: the card is once per visit and this wants several goes.
	game.story_cards[0]["seen"] = true   # the standoff is not what is under test
	game.story_cards[1]["seen"] = false
	wyrm.reset()
	wyrm.target = game.player
	wyrm.engaged = true
	await step()

func kill_at(label: String, x: float, y: float, in_the_air: bool) -> void:
	await arm()
	game.player.position = Vector2(clampf(x - 150.0, 6950.0, 7780.0), DECK)
	game.player.velocity = Vector2.ZERO
	if in_the_air:
		wyrm.aloft = true
		wyrm.grounded = false
		wyrm.deck_y = DECK
		wyrm.mark_y = DECK
		wyrm.air_left = 30.0
	wyrm.position = Vector2(x, y)
	await step()
	var _down: bool = wyrm.take_hit(wyrm.health, game.player.global_position)
	var ticks := 0
	var card := false
	var lowest := -INF
	while ticks < PATIENCE:
		await physics_frame
		ticks += 1
		lowest = maxf(lowest, wyrm.position.y)
		if game.story_running():
			card = true
			break
		if not wyrm.visible:
			break
	print("  %-34s killed at (%5.0f,%4.0f)  -> %-12s after %5.2f s   body %s, fell to y %.0f"
			% [label, x, y, ("CARD" if card else "NOTHING"), ticks / 60.0,
			   ("there" if wyrm.visible else "GONE"), lowest])
	# Out from under whatever came up, so the next case starts clean.
	if game.story_running():
		game.story_cards[1]["skip"] = true
		var _s: bool = game.skip_story()
		for i in range(200):
			await step()
			if not game.story_running():
				break
		game.story_cards[1]["skip"] = false

func run() -> void:
	game = Game.new()
	game.test_mode = false
	game.level_id = LEVEL
	root.add_child(game)
	game.start_session()
	game.player.test_control = true
	await step()
	for foe in game.enemies:
		if foe.is_boss():
			wyrm = foe
		else:
			foe.target = null
	at = float(game.level.cutscene[0].at)
	print("%s: deck 6912..8160, arena mouth %.0f, wall %.0f, dragon home %.0f"
			% [LEVEL, at - 48.0, float(game.gates.back()), wyrm.home.x])

	# On its feet, where the level put it. The case every test has used.
	await kill_at("on its feet on the deck", 7650.0, DECK, false)
	# In the air over the deck — most of the fight.
	await kill_at("in the air over the deck", 7400.0, DECK - 156.0, true)
	# In the air over the MOUTH of the arena, which is still deck.
	await kill_at("in the air over the mouth", 6950.0, DECK - 156.0, true)
	# In the air past the mouth: the standoff pushes it out here whenever the
	# player is at the left end of the arena, and there is open sea under it.
	await kill_at("in the air over the gap", 6700.0, DECK - 156.0, true)
	await kill_at("in the air out over the sea", 6300.0, DECK - 156.0, true)

	# And the other way to miss it: the wall opens the frame the dragon dies,
	# and the flag is 132 px past it. A player who beats the boss against the
	# wall and keeps running may reach the goal before the card is due.
	await arm()
	game.player.position = Vector2(7700.0, DECK)
	game.player.velocity = Vector2.ZERO
	wyrm.position = Vector2(7650.0, DECK)
	await step()
	var _down: bool = wyrm.take_hit(wyrm.health, game.player.global_position)
	game.player.test_axis = 1.0
	var run_ticks := 0
	var got := "nothing"
	while run_ticks < PATIENCE:
		await physics_frame
		run_ticks += 1
		if game.state == Game.State.COMPLETE:
			got = "THE FLAG"
			break
		if game.story_running():
			got = "the card"
			break
	game.player.test_axis = 0.0
	print("  %-34s ran for the flag from the wall -> %s after %.2f s"
			% ["beaten against the wall", got, run_ticks / 60.0])
	quit()
