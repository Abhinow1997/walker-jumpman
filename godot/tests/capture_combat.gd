extends SceneTree
## Development tool: drives each attack next to a crate and saves a cropped
## render, with the live hit rectangle drawn over the frame that opens it.
##
## The overlay is the point. moves.json's hit geometry is transcribed from the
## LF2 pack, and the only way to be sure a box still sits on the fist after the
## art was re-cut is to look at it. Not a test; makes no assertions.
## Run without --headless; it needs a real renderer.
const Game = preload("res://game/session.gd")
const Moveset = preload("res://features/player/moveset.gd")

var game: Node2D
var overlay: Node2D
var output: String

func _initialize() -> void:
	call_deferred("run")

func steps(n: int) -> void:
	for i in range(n):
		await physics_frame
		await process_frame

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	var origin: Vector2 = game.camera.position - Vector2(320, 180)
	var at: Vector2 = (game.player.position - origin) * 2.0
	var box := Rect2i(int(at.x) - 150, int(at.y) - 210, 320, 250)
	box = box.intersection(Rect2i(Vector2i.ZERO, frame.get_size()))
	if box.size.x <= 0 or box.size.y <= 0:
		print("skipped " + label + ": player off screen")
		return
	frame.get_region(box).save_png(output + "/fight-" + label + ".png")
	print("shot: " + label)

func wide_shot(label: String) -> void:
	## Whole viewport. The health bar and the drink prompt live in the HUD, which
	## a crop centred on the player would cut off entirely.
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + "/fight-" + label + ".png")
	print("shot: " + label)

func fresh() -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	game = Game.new()
	game.test_mode = true
	root.add_child(game)
	game.start_session()
	game.player.test_control = true
	overlay = HitboxOverlay.new()
	overlay.game = game
	overlay.z_index = 50
	game.add_child(overlay)
	await steps(3)

func stand_near(crate: Area2D, offset: float) -> void:
	game.player.position = Vector2(crate.position.x + offset, crate.position.y)
	game.player.velocity = Vector2.ZERO
	game.player.facing = -1.0 if offset > 0.0 else 1.0
	await steps(2)

## Capture the frame a move opens its hitbox on.
##
## Stepping to that frame and then calling shot() is not enough: a contact frame
## lasts ~50 ms and the await on frame_post_draw costs more than that, so the
## render lands on the recovery pose with the box already shut. The player is
## frozen on the contact frame instead — his physics step is what advances the
## attack clock — held for the render, then let go.
func shot_at_contact(label: String, cap: int = 40) -> void:
	for i in range(cap):
		await steps(1)
		if game.player.attack != "" and not Moveset.hits(game.player.attack, game.player.attack_frame).is_empty():
			break
	var was_enabled: bool = game.player.enabled
	game.player.enabled = false
	await shot(label)
	game.player.enabled = was_enabled

## Capture a specific frame of a move. Same freeze trick as shot_at_contact:
## the player's physics step is what advances the attack clock, so holding him
## still holds the frame through the render.
func shot_at_frame(label: String, key: String, frame: int, cap: int = 60) -> void:
	# Step before checking. begin_drink() sets attack_frame on the spot, but the
	# visual only catches up on the player's next physics step, so testing first
	# captures the pose from before the move started.
	for i in range(cap):
		await steps(1)
		if game.player.attack == key and game.player.attack_frame == frame:
			break
	game.player.enabled = false
	await shot(label)
	game.player.enabled = true

func run() -> void:
	output = ProjectSettings.globalize_path("res://../evidence/fight")
	DirAccess.make_dir_recursive_absolute(output)

	await fresh()
	var crate: Area2D = game.crates[0]
	await stand_near(crate, -40.0)
	game.player.test_attack_pressed = true
	await steps(2)
	await shot("01-jab-windup")
	await shot_at_contact("02-jab-contact")
	await steps(6)
	await shot("03-crate-damaged")

	game.player.test_attack_pressed = true
	await shot_at_contact("04-cross-contact")
	await steps(5)
	await shot("05-crate-broken")

	await fresh()
	game.player.test_jump_pressed = true
	await steps(8)
	game.player.test_attack_pressed = true
	await shot_at_contact("06-air-kick")

	await fresh()
	crate = game.crates[0]
	game.player.position = Vector2(crate.position.x - 230, crate.position.y)
	game.player.test_axis = 1
	await steps(22)
	game.player.test_attack_pressed = true
	await shot_at_contact("07-shoulder-charge")
	# The charge carries more than the crate's health, but an untouched crate
	# survives its first blow, so this is a launch and not a deletion.
	for gap in [4, 5, 7, 10]:
		await steps(gap)
		await shot("07b-crate-launched-%d" % gap)

	await fresh()
	crate = game.crates[0]
	await stand_near(crate, -300.0)
	game.player.test_blast_pressed = true
	await steps(6)
	await shot("08-blast-throw")
	while game.blasts.is_empty():
		await steps(1)
	await steps(8)
	await shot("09-blast-flight")
	var ticks := 0
	while not crate.broken and ticks < 120:
		await steps(1)
		ticks += 1
	await shot("10-blast-impact")

	# The crate art and the tumble it breaks into, both LF2's own frames.
	await fresh()
	crate = game.crates[0]
	await stand_near(crate, -46.0)
	await shot("11-crate-intact")
	# Knocked, not destroyed: a jab sends the box up and away, it tumbles through
	# LF2's six box angles, lands, skids and settles square.
	crate.take_hit(20, game.player.global_position)
	for gap in [2, 3, 4, 5, 8]:
		await steps(gap)
		await shot("11b-crate-knocked-%d" % gap)
	while not crate.at_rest:
		await steps(1)
	await shot("11c-crate-settled")
	crate.take_hit(60, game.player.global_position)
	# Uneven spacing on purpose: the burst is over in a few frames but the pieces
	# take most of a second to bounce and settle, and both halves matter.
	for gap in [3, 6, 12, 20, 24]:
		await steps(gap)
		await shot("12-crate-break-%d" % gap)

	# The bottle needs the whole viewport: the prompt and the health bar are HUD,
	# and a crop around the player would cut both off.
	await fresh()
	var bottle: Area2D = game.bottles[0]
	game.player.position = Vector2(bottle.position.x - 120, bottle.position.y)
	await steps(3)
	await wide_shot("13-health-low")
	# Beside it, not on top of it: standing exactly on the bottle hides the art
	# behind the character, and the reach area is wide enough to prompt from here.
	game.player.position = Vector2(bottle.position.x - 34, bottle.position.y)
	await steps(4)
	await wide_shot("14-drink-prompt")
	var _lift1: bool = game.pick_up()
	await steps(26)
	var _drank: bool = game.drink()
	# A drink is six seconds of standing still, so the interesting shots are the
	# countdown partway through and the bar afterwards, not the moment of asking.
	await steps(120)
	await wide_shot("15-drinking-2s")
	await steps(180)
	await wide_shot("16-drinking-5s")
	while game.player.is_drinking():
		await steps(1)
	await steps(6)
	await wide_shot("17-after-drinking")

	# Interrupting it. One second in, he takes a step, and that is the drink
	# gone: nothing restored, and the bottle back on the floor to try again.
	await fresh()
	bottle = game.bottles[0]
	game.player.position = Vector2(bottle.position.x - 34, bottle.position.y)
	await steps(4)
	var _lift2: bool = game.pick_up()
	await steps(26)
	var _tried: bool = game.drink()
	await steps(60)
	await wide_shot("18-drink-interrupted-before")
	game.player.test_axis = 1
	await steps(2)
	game.player.test_axis = 0
	await steps(8)
	await wide_shot("19-drink-interrupted-after")

	# The drink, frame by frame. The bottle is not in the character art: LF2
	# stamps it on the frame's weapon point, and so does this.
	await fresh()
	bottle = game.bottles[0]
	game.player.position = Vector2(bottle.position.x - 34, bottle.position.y)
	await steps(3)
	await shot("20-before-drinking")
	var _lift3: bool = game.pick_up()
	await steps(26)
	var _started: bool = game.drink()
	for f in range(4):
		await shot_at_frame("21-drink-f%d" % f, "drink", f)
	# The four frames loop for the whole six seconds; let it finish rather than
	# leaving a drink running into the next section.
	while game.player.is_drinking():
		await steps(1)
	await steps(6)
	await shot("22-drink-frames-done")

	# The bottle is a prop as well as a pickup: knock it about, smash it, and the
	# drink goes with it.
	await fresh()
	bottle = game.bottles[0]
	game.player.position = Vector2(bottle.position.x - 40, bottle.position.y)
	game.player.facing = 1.0
	await steps(2)
	await shot("23-bottle-intact")
	game.player.test_attack_pressed = true
	# Indexed, not gap-named: two equal gaps would write the same file twice.
	var gaps := [4, 3, 4]
	for i in gaps.size():
		await steps(gaps[i])
		await shot("24-bottle-knocked-%d" % i)
	while not bottle.at_rest:
		await steps(1)
	await shot("25-bottle-settled")
	bottle.take_hit(20, bottle.global_position - Vector2(40, 0))
	for gap in [3, 6, 12]:
		await steps(gap)
		await shot("26-bottle-smashed-%d" % gap)

	# Struck mid-drink: the bottle leaves his hand instead of being set down and
	# falls under the same physics a punched one uses. Same frame gaps as the
	# crate and bottle knock sequences above, so the three can be compared.
	await fresh()
	bottle = game.bottles[0]
	game.player.position = bottle.position
	await steps(4)
	var _lift4: bool = game.pick_up()
	await steps(26)
	var _hd: bool = game.drink()
	await steps(60)
	game.player.interrupt_drink(game.player.DRINK_HIT)
	for i in range(4):
		await shot("27-bottle-dropped-%d" % i)
		await steps(4)
	var dropped_settle := 0
	while not bottle.at_rest and dropped_settle < 240:
		await steps(1)
		dropped_settle += 1
	await shot("28-bottle-dropped-settled")

	# --- the enemy bandit -----------------------------------------------------
	# The whole loop in one pass: he closes, he swings, it costs a bar, and the
	# player answers. Whole viewport, because the health bar is HUD.
	await fresh()
	var bandit: Area2D = game.enemies[0]
	game.player.position = Vector2(bandit.position.x - 190, bandit.position.y)
	game.player.health = game.player.MAX_HEALTH
	await steps(4)
	await wide_shot("29-bandit-spots-him")
	await steps(40)
	await wide_shot("30-bandit-closing")
	# Run on until the blow actually lands, so the shot is the hit and not a
	# guess at which frame it happens on.
	var hp: int = game.player.health
	var waited := 0
	while game.player.health == hp and waited < 300:
		await steps(1)
		waited += 1
	await wide_shot("31-bandit-lands-one")
	await steps(20)
	await wide_shot("32-a-bar-gone")

	# The player answers. Five jabs put him down; this catches the last one.
	game.player.facing = 1.0
	while bandit.health > 20 and waited < 600:
		bandit.take_hit(20, game.player.global_position)
		await steps(12)
		waited += 1
	await shot("33-bandit-on-his-last-bar")
	bandit.take_hit(20, game.player.global_position)
	for gap in [2, 8, 20]:
		await steps(gap)
		await shot("34-bandit-down-%d" % gap)

	# --- hit reactions, both sides -------------------------------------------
	# Both packs draw a recoil; these are the frames of each, side by side.
	await fresh()
	game.player.position = Vector2(400, 640)
	game.player.health = game.player.MAX_HEALTH
	await steps(4)
	await shot("35-player-before-the-blow")
	var _b: bool = game.player.take_damage(20, game.player.global_position + Vector2(40, 0))
	for i in range(3):
		await shot("36-player-hurt-%d" % i)
		await steps(6)
	await steps(30)
	await shot("37-player-recovered")

	await fresh()
	var foe: Area2D = game.enemies[0]
	game.player.position = Vector2(foe.position.x - 60, foe.position.y)
	await steps(4)
	await shot("38-bandit-before-the-blow")
	var _fb: bool = foe.take_hit(20, game.player.global_position)
	for i in range(3):
		await shot("39-bandit-hurt-%d" % i)
		await steps(6)
	await steps(30)
	await shot("40-bandit-recovered")

	# --- lifting and throwing ------------------------------------------------
	await fresh()
	var box: Area2D = game.crates[0]
	var mark: Area2D = game.enemies[0]
	box.position = Vector2(520, 640); box.home = box.position
	mark.position = Vector2(640, 640); mark.home = mark.position; mark.target = null
	game.player.position = Vector2(500, 640)
	await steps(6)
	await wide_shot("41-crate-at-his-feet")
	var _lift5: bool = game.pick_up()
	await steps(8)
	await wide_shot("42-lifting")
	await steps(24)
	await wide_shot("43-carrying-it")
	game.player.test_axis = 1
	await steps(22)
	game.player.test_axis = 0
	await wide_shot("44-hauling-it")
	game.player.facing = 1.0
	game.player.test_attack_pressed = true
	await steps(6)
	await wide_shot("45-throwing")
	var flight := 0
	while not box.broken and flight < 200:
		await steps(1)
		flight += 1
		if flight == 6:
			await wide_shot("46-in-the-air")
	await steps(3)
	await wide_shot("47-it-connects")

	# The bottle, lifted before it can be drunk.
	await fresh()
	var flask: Area2D = game.bottles[0]
	game.player.position = flask.position
	await steps(6)
	await wide_shot("48-bottle-at-his-feet")
	var _take: bool = game.pick_up()
	await steps(26)
	await wide_shot("49-holding-the-bottle")
	var _sip2: bool = game.drink()
	await steps(40)
	await wide_shot("50-drinking-what-he-holds")

	print("FIGHT SHEET: written to " + output)
	game.queue_free()
	await process_frame
	quit()

## Draws whatever hit rectangles are live this frame, in world space.
class HitboxOverlay extends Node2D:
	var game: Node2D

	func _physics_process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if not is_instance_valid(game) or not is_instance_valid(game.player):
			return
		var player = game.player
		if player.attack == "":
			return
		for hit in Moveset.hits(player.attack, player.attack_frame):
			var box: Rect2 = hit.rect
			if player.facing < 0.0:
				box.position.x = -(box.position.x + box.size.x)
			box.position += player.global_position
			draw_rect(box, Color(0.85, 0.25, 0.2, 0.25))
			draw_rect(box, Color(0.85, 0.25, 0.2, 0.95), false, 2.0)
		for blast in game.blasts:
			if is_instance_valid(blast):
				draw_rect(blast._world_rect(), Color(0.95, 0.5, 0.15, 0.9), false, 2.0)
