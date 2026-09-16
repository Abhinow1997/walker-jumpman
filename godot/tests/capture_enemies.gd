extends SceneTree
## Development tool: renders each non-bandit enemy kind inside the real game, on
## proving_ground where they are spawned from level entries. Not a test; makes no
## assertions. Run without --headless; it needs a real renderer.
##
## The point is in-engine proof: that the folder each extract_<kind>.py wrote
## loads, scales and animates the same way the bandit does, rather than a Pillow
## preview of the source sheet. Saves cropped shots to evidence/<kind>/.
const Game = preload("res://game/session.gd")

# One clear patch of proving_ground: east of the spikes (800..848), west of the
# flag (1192). Each kind is captured here in turn with every other enemy banished
# off screen, so nothing but the enemy in hand is ever in frame.
const SPOT := Vector2(1050, 640)

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
	game.level_id = "proving_ground"
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
