extends SceneTree
## Development tool: the dip to black between two levels, frame by frame.
## Runs without test_mode, which is what skips the fade. Not a test.
const Game = preload("res://game/session.gd")
var game: Node2D
var output: String

func _initialize() -> void:
	call_deferred("run")

func step() -> void:
	await physics_frame
	await process_frame

func shoot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png("%s/%s.png" % [output, label])
	assert(err == OK)
	print("shot %-26s alpha %.2f  level %s" % [label, game.fade_alpha(), game.level_id])

func run() -> void:
	output = ProjectSettings.globalize_path("res://../evidence/transition")
	DirAccess.make_dir_recursive_absolute(output)
	var shipped: Array = Game.catalogue().duplicate()
	Game._catalogue = ["first_steps", "proving_ground"]

	game = Game.new()
	game.level_id = "first_steps"
	root.add_child(game)
	game.start_session()
	# Stand him at the flag, which is where this is always seen from.
	game.player.position = Vector2(float(game.level.finish[0]) - 40.0, 640.0)
	for i in range(6): await step()
	await shoot("00-at-the-flag")

	game.state = Game.State.COMPLETE
	game.confirm()
	for i in range(40):
		await step()
		if i in [3, 7, 11, 16, 22, 30]:
			await shoot("%02d-tick" % i)
	Game._catalogue = shipped
	quit()
