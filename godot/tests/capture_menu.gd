extends SceneTree
## The level-select menu: proof of exactly which levels the game offers. Needs a
## renderer — run WITHOUT --headless.
const Game = preload("res://game/session.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var out := ProjectSettings.globalize_path("res://../evidence/menu")
	DirAccess.make_dir_recursive_absolute(out)
	var game := Game.new()
	game.level_id = "first_steps"
	root.add_child(game)
	game.state = Game.State.MENU
	game.menu_index = 0
	for i in range(6):
		await physics_frame
		await process_frame
	if is_instance_valid(game.hud):
		game.hud.queue_redraw()
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png(out + "/level_select.png")
	assert(err == OK)
	print("shot level_select   listing: %s" % str(Game.listing()))
	quit()
