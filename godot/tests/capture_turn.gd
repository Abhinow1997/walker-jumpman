extends SceneTree
## Development tool: renders every frame of a direction change into
## evidence/turn, so the mirror can be checked frame by frame after touching
## TURN_NARROW, TURN_LIFT or TURN_RATE in player_sprite.gd. The turn is over in
## about a tenth of a second, which is too fast to judge at play speed.
## Not a test; makes no assertions. Run without --headless; it needs a renderer.
const Game = preload("res://game/session.gd")
var game: Node2D
var output: String

func _initialize() -> void:
	call_deferred("run")

func step() -> void:
	await physics_frame
	await process_frame

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	var origin: Vector2 = game.camera.position - Vector2(320, 180)
	var at: Vector2 = (game.player.position - origin) * 2.0
	var box := Rect2i(int(at.x) - 90, int(at.y) - 190, 180, 210)
	box = box.intersection(Rect2i(Vector2i.ZERO, frame.get_size()))
	frame.get_region(box).save_png(output + "/turn-" + label + ".png")

func run() -> void:
	output = ProjectSettings.globalize_path("res://../evidence/turn")
	DirAccess.make_dir_recursive_absolute(output)
	game = Game.new()
	game.test_mode = true
	root.add_child(game)
	game.start_session()
	game.player.test_control = true
	game.player.test_axis = 1.0
	for i in range(30):
		await step()
	game.player.test_axis = -1.0
	for i in range(12):
		await shot("%02d" % i)
		await step()
	print("TURN: written to " + output)
	quit()
