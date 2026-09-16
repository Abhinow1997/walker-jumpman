extends SceneTree
const Game = preload("res://game/session.gd")
var output: String

func _initialize() -> void:
	call_deferred("run")

func step() -> void:
	await physics_frame
	await process_frame

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(output + "/" + label + ".png")
	assert(error == OK)
	print("Captured: " + label)

func run() -> void:
	output = ProjectSettings.globalize_path("res://../evidence/screens")
	DirAccess.make_dir_recursive_absolute(output)
	# Loaded the way the game loads it, so current_scene is set and the handoff
	# in _boot is exercised for real rather than around.
	change_scene_to_file("res://ui/title.tscn")
	for i in range(4): await step()
	var title: Control = current_scene
	assert(title != null, "title scene did not become current_scene")
	await capture("title-01-new-journey")
	for row in [1, 2, 3]:
		title.index = row
		title.queue_redraw()
		for i in range(2): await step()
		await capture("title-0%d-row%d" % [row + 1, row])
	# Every row that hands off is taken for real, so a broken boot fails here
	# rather than in front of the player. Each one replaces current_scene, so
	# the title is reloaded between them.
	# Each boot replaces current_scene and frees the one before it, so only the
	# level id is carried across — the session node itself does not survive.
	var journey := await boot(0, Game.State.PLAYING)
	assert(journey == Game.catalogue()[0],
		   "NEW JOURNEY should open the course, got %s" % journey)
	await capture("title-05-new-journey-booted")

	var practice := await boot(2, Game.State.PLAYING)
	assert(practice != journey, "PRACTICE duplicates NEW JOURNEY at %s" % practice)
	await capture("title-06-practice-booted")

	# LOAD GAME boots without starting, which leaves the session on its own
	# level list rather than in play.
	await boot(1, Game.State.MENU)
	await capture("title-07-load-game-booted")
	quit()

## Takes a row's handoff and returns the level the session landed on.
func boot(row: int, expect: Game.State) -> String:
	change_scene_to_file("res://ui/title.tscn")
	for i in range(4): await step()
	var title: Control = current_scene
	title.index = row
	title._choose(row)
	for i in range(6): await step()
	var game := current_scene
	assert(game is Node2D, "row %d did not install a session" % row)
	assert(game.state == expect,
		   "row %d state %d, expected %d" % [row, game.state, expect])
	assert(is_instance_valid(game.player), "row %d booted without a player" % row)
	print("BOOT row %d: level=%s state=%d" % [row, game.level_id, game.state])
	return game.level_id
