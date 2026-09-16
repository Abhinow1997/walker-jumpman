extends SceneTree
## Development tool: drives the knight into each animation state and saves a
## cropped render of the rendered viewport. Not a test; makes no assertions about
## play feel. Pass an output directory with --outdir, otherwise writes beside the
## other evidence. Run without --headless; it needs a real renderer.
const Game = preload("res://game/session.gd")
var game: Node2D
var output: String

func _initialize() -> void:
	call_deferred("run")

func step() -> void:
	await physics_frame
	await process_frame

func steps(n: int) -> void:
	for i in range(n):
		await step()

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	# The camera tracks the player, so locate him in window space before cropping.
	## World point to screen pixel: back off to the camera's top-left corner, then
	## apply the canvas magnification the 960x540 viewport gets in a 1280x720 window.
	var origin: Vector2 = game.camera.position - Game.VIEW_HALF
	var at: Vector2 = (game.player.position - origin) * (1280.0 / 960.0)
	## Two thirds of the old 120/192/240/240: same framing, smaller cast.
	var box := Rect2i(int(at.x) - 80, int(at.y) - 128, 160, 160)
	box = box.intersection(Rect2i(Vector2i.ZERO, frame.get_size()))
	var error := frame.get_region(box).save_png(output + "/pose-" + label + ".png")
	assert(error == OK, "could not save pose " + label)
	print("pose: " + label)

func fresh() -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	game = Game.new()
	game.test_mode = true
	root.add_child(game)
	game.start_session()
	game.player.test_control = true
	await steps(3)

func run() -> void:
	output = ProjectSettings.globalize_path("res://../evidence/poses")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--outdir="):
			output = argument.substr(9)
	DirAccess.make_dir_recursive_absolute(output)

	await fresh()
	await shot("01-idle-wound")
	# Let the spring run down; he should visibly slump.
	await steps(200)
	await shot("02-idle-unwound")

	game.player.test_axis = 1.0
	await steps(24)
	await shot("03-run-a")
	await steps(7)
	await shot("04-run-b")

	game.player.test_jump_pressed = true
	await steps(6)
	await shot("05-rise")
	while game.player.velocity.y < 120.0:
		await step()
	await shot("06-fall")
	while not game.player.is_on_floor():
		await step()
	await shot("07-land")
	await steps(4)
	await shot("08-land-recover")

	# Skid: still travelling right, but intent has already flipped left.
	game.player.test_axis = -1.0
	await steps(3)
	await shot("09-skid")

	await fresh()
	game.player.position = Vector2(660, 620)
	while game.state != Game.State.DYING:
		await step()
	await steps(6)
	await shot("10-death-a")
	await steps(8)
	await shot("11-death-b")

	print("POSE SHEET: written to " + output)
	game.queue_free()
	await process_frame
	quit()
