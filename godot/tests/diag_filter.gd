extends SceneTree
## Diagnostic: how the cast holds up at window sizes other than the 1280x720 the
## project pins. Shoots the player close up at several sizes, with the filter the
## game ships and with linear, so the two can be compared side by side.
## Not a test; makes no assertions.
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
	var img := root.get_texture().get_image()
	var err := img.save_png("%s/%s.png" % [output, label])
	assert(err == OK)
	print("shot %-28s %dx%d" % [label, img.get_width(), img.get_height()])

func run() -> void:
	output = ProjectSettings.globalize_path("res://../evidence/filter")
	DirAccess.make_dir_recursive_absolute(output)
	game = Game.new()
	game.test_mode = true
	root.add_child(game)
	game.start_session()
	game.player.test_control = true
	for i in range(6): await step()

	var art: float = game.player.visual.art_scale if "visual" in game.player else -1.0
	print("art_scale=%s  viewport=%s" % [art, str(root.size)])

	for size in [Vector2i(1280, 720), Vector2i(1876, 1040), Vector2i(2560, 1440)]:
		DisplayServer.window_set_size(size)
		for i in range(4): await step()
		var mag := float(size.x) / 960.0
		print("window %s -> magnification %.3f, sprite lands at %.3f" % [str(size), mag, mag * 0.75])
		# Whatever the game itself sets, before this script overrides anything.
		var shipped: int = game.player.visual.sprite.texture_filter
		print("  shipped filter = %s" % ("NEAREST" if shipped == CanvasItem.TEXTURE_FILTER_NEAREST else "LINEAR"))
		await shoot("%dx%d-shipped" % [size.x, size.y])
		for filter in [CanvasItem.TEXTURE_FILTER_NEAREST, CanvasItem.TEXTURE_FILTER_LINEAR]:
			_apply(game.player, filter)
			for i in range(2): await step()
			var name := "nearest" if filter == CanvasItem.TEXTURE_FILTER_NEAREST else "linear"
			await shoot("%dx%d-%s" % [size.x, size.y, name])
	quit()

## The player draws through a child Sprite2D, so the filter has to be set on the
## node that actually holds the texture rather than on the body.
func _apply(node: Node, filter: int) -> void:
	if node is CanvasItem:
		node.texture_filter = filter
	for child in node.get_children():
		_apply(child, filter)
