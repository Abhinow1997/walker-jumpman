extends SceneTree
## Development tool: renders each non-bandit enemy kind inside the real game, on
## first_steps where they are spawned from level entries. Not a test; makes no
## assertions. Run without --headless; it needs a real renderer.
##
## The point is in-engine proof: that the folder each extract_<kind>.py wrote
## loads, scales and animates the same way the bandit does, rather than a Pillow
## preview of the source sheet. Saves cropped shots to evidence/<kind>/.
const Game = preload("res://game/session.gd")

# One clear patch of the first_steps coast, near the opening ledge. Each kind is
# captured here in turn with every other enemy banished off screen, so nothing
# but the enemy in hand is ever in frame.
const SPOT := Vector2(600, 648)

var game: Node2D
var output: String

func _initialize() -> void:
	call_deferred("run")

func steps(n: int) -> void:
	for i in range(n):
		await physics_frame
		await process_frame

## Crop centred on a world point — the enemy, here, not the player.
func shot(label: String, center: Vector2, w: int = 300, h: int = 190) -> void:
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	var origin: Vector2 = game.camera.position - Game.VIEW_HALF
	var at: Vector2 = (center - origin) * (1280.0 / 960.0)
	var box := Rect2i(int(at.x) - w / 2, int(at.y) - h / 2, w, h)
	box = box.intersection(Rect2i(Vector2i.ZERO, frame.get_size()))
	if box.size.x <= 0 or box.size.y <= 0:
		print("skipped " + label + ": off screen")
		return
	frame.get_region(box).save_png(output + "/" + label + ".png")
	print("shot: " + label)

## Get every other enemy out of the shot — parked and hidden where it stands, so
## a corpse from an earlier capture cannot share the frame. NOT moved off the
## floor: an enemy dropped into empty space falls past its fall line and dies,
## and a kind captured later would already be a hidden corpse by its turn.
func banish_others(active: Area2D) -> void:
	for foe in game.enemies:
		if foe != active:
			foe.target = null
			foe.visible = false

func capture(kind: String, foe: Area2D) -> void:
	output = ProjectSettings.globalize_path("res://../evidence/" + kind)
	DirAccess.make_dir_recursive_absolute(output)
	var spot: Vector2 = SPOT
	banish_others(foe)
	# He may have been banished (and hidden) during an earlier kind's capture.
	foe.visible = true
	foe.position = spot
	foe.home = spot

	# Idle: parked, the player stood back out of frame.
	foe.target = null
	game.player.position = Vector2(spot.x - 150.0, spot.y)
	game.player.facing = 1.0
	await steps(6)
	await shot(kind + "-01-idle", spot)

	# Walk: armed, he closes the gap. Caught a few steps into the chase.
	game.player.position = Vector2(spot.x - 90.0, spot.y)
	foe.target = game.player
	await steps(16)
	await shot(kind + "-02-closing", (foe.position + game.player.position) * 0.5)

	# Punch: put the player in range and wait for the swing, then hold him on the
	# extension frame — his physics step advances the attack clock, so freezing
	# him holds the pose through the render. If the swing is not caught in time
	# (a shorter reach steps in closer and can knock the player out of frame
	# first), the pose is set directly — it is the same extension frame either way.
	foe.position = spot
	game.player.position = Vector2(spot.x - 30.0, spot.y)
	game.player.health = game.player.MAX_HEALTH
	foe.facing = -1.0
	await steps(3)
	var caught := false
	for i in range(180):
		await steps(1)
		if foe.sprite.animation == "punch":
			foe.set_physics_process(false)
			foe._show("punch", 1)
			await shot(kind + "-03-punch", (foe.position + game.player.position) * 0.5)
			foe.set_physics_process(true)
			caught = true
			break
	if not caught:
		foe.position = spot
		foe.facing = -1.0
		foe.set_physics_process(false)
		foe.sprite.scale = Vector2(foe.facing * foe.art_faces, 1.0) * foe.art_scale
		foe._show("punch", 1)
		await shot(kind + "-03-punch", (foe.position + game.player.position) * 0.5)
		foe.set_physics_process(true)

	# Signature move: the archer draws his bow and looses an arrow. Catch the arrow
	# in flight, crossing the gap to the player. Staged east of the spikes.
	if foe.style == "archer":
		var apos := Vector2(1120, 640)
		foe.reset()
		foe.position = apos
		foe.home = apos
		foe.visible = true
		game.player.position = Vector2(apos.x - 180.0, apos.y)
		foe.target = game.player
		var shot_seen := false
		for i in range(240):
			await steps(1)
			if game.arrows.size() > 0 \
					and absf(game.arrows[0].global_position.x - foe.position.x) > 55.0:
				for a in game.arrows:
					a.set_physics_process(false)
				foe.set_physics_process(false)
				var mid: float = (foe.position.x + game.player.position.x) * 0.5
				await shot(kind + "-06-shoot", Vector2(mid, apos.y - 18.0), 330)
				foe.set_physics_process(true)
				for a in game.arrows:
					a.set_physics_process(true)
				shot_seen = true
				break
		if not shot_seen:
			print(kind + ": arrow not caught")
		foe.reset()
		foe.position = spot
		foe.home = spot

	# Jump: the player takes the platform at x320..416, 64 px up — over the 60 px
	# band every attack in this game is stuck inside, his own included. Caught in
	# the air on the way up after him.
	#
	# Melee kinds only. The archer's answer to height is to back off and shoot,
	# and he never leaps at the player; he jumps to keep his footing and nothing
	# else, which there is nowhere on this level to show.
	if foe.style != "archer":
		var under := Vector2(420, 640)
		foe.reset()
		foe.position = under
		foe.home = under
		foe.visible = true
		game.player.position = Vector2(370, 576)
		game.player.velocity = Vector2.ZERO
		game.player.facing = 1.0
		foe.target = game.player
		foe.engaged = true
		var flew := false
		for i in range(240):
			await steps(1)
			if not foe.grounded and foe.position.y < 620.0:
				foe.set_physics_process(false)
				await shot(kind + "-07-jump", Vector2(395, 588), 330)
				foe.set_physics_process(true)
				flew = true
				break
		if not flew:
			print(kind + ": jump not caught")
		foe.reset()
		foe.position = spot
		foe.home = spot
	else:
		print(kind + ": no jump shot — an archer never leaps at you")

	# Guard: a real blast, really thrown from outside his own reaction — the
	# distance is read off the enemy rather than written down, because Mark needs
	# 280 px of warning where the hunter needs 146, and a number that suits one
	# catches nothing on the other. Clamped to stay on this floor and west of the
	# spikes at 800.
	var stand := Vector2(1050, 640)
	foe.reset()
	foe.position = stand
	foe.home = stand
	foe.visible = true
	foe.target = null
	var throw_from: float = maxf(680.0, stand.x - (foe.guard_reaction * 560.0 + 120.0))
	# Clear the lane. Any crate or bottle between the player and the enemy is under
	# the muzzle from here — a blast thrown from far enough back for Mark to read
	# it smashes the prop on frame one and never leaves. Props are parked rather
	# than broken so the earlier crate and bottle shots are untouched.
	for prop in game.crates + game.bottles:
		if is_instance_valid(prop) and prop.position.x > throw_from - 60.0 \
				and prop.position.x < stand.x:
			prop.position = Vector2(prop.position.x, stand.y - 2000.0)
	game.player.position = Vector2(throw_from, stand.y)
	game.player.velocity = Vector2.ZERO
	game.player.facing = 1.0
	game.player.mana = game.player.MAX_MANA
	await steps(3)
	game.player.test_blast_pressed = true
	var guarded := false
	for i in range(180):
		await steps(1)
		if foe.guarding() and not game.blasts.is_empty():
			foe.set_physics_process(false)
			for b in game.blasts:
				b.set_physics_process(false)
			var mid: float = (foe.position.x + game.blasts[0].global_position.x) * 0.5
			await shot(kind + "-08-guard", Vector2(mid, stand.y - 20.0), 330)
			foe.set_physics_process(true)
			for b in game.blasts:
				b.set_physics_process(true)
			guarded = true
			break
	if not guarded:
		print(kind + ": guard not caught")

	# And the frame it gives way on. Its pool is emptied by hand rather than by
	# standing here throwing blasts at him until it runs out.
	foe.reset()
	foe.position = stand
	foe.home = stand
	foe.target = null
	await steps(2)
	foe.warn_of_blast(Vector2(stand.x - 400.0, stand.y), 1.0, 560.0)
	var braced_up := false
	for i in range(90):
		await steps(1)
		if foe.guarding():
			braced_up = true
			break
	if braced_up:
		foe.guard = 1.0     # one blow from empty
		var _broke: bool = foe.take_hit(45, Vector2(stand.x - 40.0, stand.y))
		await steps(2)
		foe.set_physics_process(false)
		await shot(kind + "-09-guard-break", stand)
		foe.set_physics_process(true)
	else:
		print(kind + ": guard break not caught")
	foe.reset()
	foe.position = spot
	foe.home = spot

	# Hurt: the player strikes back; catch the recoil.
	foe.target = null
	foe.position = spot
	game.player.position = Vector2(spot.x - 44.0, spot.y)
	var _h: bool = foe.take_hit(20, game.player.global_position)
	await steps(2)
	await shot(kind + "-04-hurt", spot)

	# Down: run him out to the collapse and hold it.
	while foe.alive():
		foe.take_hit(20, game.player.global_position)
		await steps(2)
	await steps(30)
	await shot(kind + "-05-down", spot)

func run() -> void:
	game = Game.new()
	game.test_mode = true
	game.level_id = "first_steps"
	root.add_child(game)
	game.start_session()
	game.player.test_control = true
	await steps(3)

	for kind in ["mark", "hunter"]:
		var foe: Area2D = null
		for e in game.enemies:
			if e.kind == kind:
				foe = e
		if foe == null:
			print("no " + kind + " in the level")
			continue
		print("capturing " + kind)
		await capture(kind, foe)

	print("ENEMY CAPTURE: done")
	game.queue_free()
	await process_frame
	quit(0)
