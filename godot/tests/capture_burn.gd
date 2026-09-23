extends SceneTree
## Development tool: what being breathed on looks like.
##
## The Anti-Davis pack draws the player being hit by fire and nothing in the
## game used to ask for it: four frames, two of him tumbling inside the flame
## and two of him burning where he landed (LF2 frames 203-206, cut as `burn`
## by scripts/extract_anti_davis.py). Both bosses breathe — the dragon's
## `fire` and `fire_air`, the Dragon Lord's `breath` — so this drives each of
## them into throwing one and shoots the player while he is alight.
##
## The blows are real: the boss is put in range with its cooldowns spent, it
## picks its own special, and the hit arrives through its own hit box. Nothing
## here calls take_damage.
##
##     <godot> --path godot --script tests/capture_burn.gd
##
## Run WITHOUT --headless; it needs a real renderer.
const Game = preload("res://game/session.gd")

const DECK := 648.0

var game: Node2D
var output: String
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func step() -> void:
	await physics_frame
	await process_frame

func shoot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png("%s/%s.png" % [output, label])
	assert(err == OK)
	print("shot %-30s drawing %-6s burning %s  downed %s  feet %s" % [
		label, game.player.visual.playing, game.player.is_burning(),
		game.player.is_downed(), game.player.is_on_floor()])

func check(id: String, passed: bool, observed: Dictionary) -> void:
	if not passed:
		failures += 1
	print(JSON.stringify({"id": id, "status": "PASS" if passed else "FAIL",
						  "observed": observed}))

func fresh() -> void:
	if is_instance_valid(game):
		game.queue_free()
		await step()
	game = Game.new()
	game.test_mode = true
	game.level_id = "dragons_roost"
	root.add_child(game)
	await step()
	game.start_session()
	game.player.test_control = true
	game.story_cards.clear()
	game.level["boss_music"] = ""
	await step()

## Stands the player `gap` px in front of `foe` with everything else off the
## deck, spends the boss's cooldowns so its next decision is its special, and
## runs until the player is alight. Returns the ticks it took, or -1.
func breathe_on(foe: Area2D, gap: float, ticks: int, pinned: bool) -> int:
	for other in game.enemies:
		if other != foe:
			other.health = 0
			other.visible = false
	foe.reset()
	foe.target = game.player
	foe.engaged = true
	# `pinned` keeps the dragon on its feet: its standing fire belongs to the
	# ground phase, and a dragon left to its own clock takes off long before
	# nine hundred ticks are up and is never offered that move again.
	if pinned:
		foe.aloft = false
		foe.ground_left = 9999.0
	game.player.position = Vector2(foe.home.x - gap, DECK)
	game.player.velocity = Vector2.ZERO
	await step()
	for i in range(ticks):
		# Topped up, because the picture wanted is a man on fire and not the
		# failure card. The i-frames mean this cannot loop the burn either.
		game.player.health = game.player.MAX_HEALTH
		foe.cooldown = 0.0
		foe.special_ready = 0.0
		if pinned:
			foe.ground_left = 9999.0
		await step()
		if game.player.is_burning():
			return i
	return -1

## One boss: the moment the fire lands, and again once he is on the deck.
func burn(label: String, foe: Area2D, gap: float, n: int, pinned: bool) -> void:
	var lit: int = await breathe_on(foe, gap, 900, pinned)
	check("%s-sets-him-alight" % label, lit >= 0,
		{"ticks": lit, "move": foe.move, "burning": game.player.is_burning()})
	if lit < 0:
		return
	var move: String = foe.move
	await shoot("%02d-%s-alight" % [n, label])
	check("and-the-flame-is-what-is-drawn-in-the-air",
		game.player.visual.playing == "burn" and not game.player.is_on_floor(),
		{"drawing": game.player.visual.playing,
		 "feet_down": game.player.is_on_floor()})
	# Down he comes. The second half of the strip is him burning on the deck,
	# and it is picked off his feet rather than off the clock.
	var landed := -1
	for i in range(120):
		game.player.health = game.player.MAX_HEALTH
		await step()
		if game.player.is_on_floor() and game.player.is_downed():
			landed = i
			break
	await shoot("%02d-%s-down" % [n + 1, label])
	check("and-he-goes-on-burning-where-he-lands",
		landed >= 0 and game.player.visual.playing == "burn"
		and game.player.is_burning(),
		{"ticks_to_land": landed, "drawing": game.player.visual.playing,
		 "burning": game.player.is_burning(), "by": move})

func run() -> void:
	output = ProjectSettings.globalize_path("res://../evidence/burn")
	DirAccess.make_dir_recursive_absolute(output)
	await fresh()
	var lord: Area2D = null
	var wyrm: Area2D = null
	for foe in game.enemies:
		if foe.kind == "dragon_lord":
			lord = foe
		elif foe.kind == "dragon":
			wyrm = foe

	# The Dragon Lord, whose breath reaches 146 to 274: stood at 200 he throws
	# it rather than the leap-slam, which wants to be inside 126.
	await burn("dragon-lord-breath", lord, 200.0, 1, false)

	# And the dragon. Its standing fire reaches 125 to 180 and belongs to the
	# phase it is on its feet for, so the phase clock is pinned down first —
	# otherwise it takes off and the ground breath is never offered.
	await fresh()
	for foe in game.enemies:
		if foe.kind == "dragon":
			wyrm = foe
	await burn("dragon-fire", wyrm, 150.0, 3, true)

	# For contrast: an ordinary knockdown, which is the same pose without the
	# fire. The Lord's leap-slam, from inside its band.
	await fresh()
	for foe in game.enemies:
		if foe.kind == "dragon_lord":
			lord = foe
	for other in game.enemies:
		if other != lord:
			other.health = 0
			other.visible = false
	lord.target = game.player
	lord.engaged = true
	game.player.position = Vector2(lord.home.x - 100.0, DECK)
	game.player.velocity = Vector2.ZERO
	var slammed := -1
	for i in range(900):
		game.player.health = game.player.MAX_HEALTH
		lord.cooldown = 0.0
		lord.special_ready = 0.0
		await step()
		if game.player.is_downed():
			slammed = i
			break
	await shoot("05-no-fire-just-a-knockdown")
	check("a-blow-that-is-not-fire-is-the-plain-tumble",
		slammed >= 0 and not game.player.is_burning()
		and game.player.visual.playing == "death",
		{"ticks": slammed, "drawing": game.player.visual.playing,
		 "burning": game.player.is_burning(), "by": lord.move})

	print("BURN CAPTURE: %d failures -> %s" % [failures, output])
	quit(1 if failures else 0)
