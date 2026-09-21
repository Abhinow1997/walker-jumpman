extends SceneTree
## The defeat screen: the MISSION FAILED banner with the cause line under it,
## shot for a combat death and a fall. Needs a renderer — run WITHOUT --headless.
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
	print("shot %-26s state=%d reason=%s" % [label, game.state, game.death_reason])

func to_dying() -> bool:
	for i in range(40):
		await step()
		if game.state == Game.State.DYING:
			return true
	return false

func run() -> void:
	output = ProjectSettings.globalize_path("res://../evidence/death")
	DirAccess.make_dir_recursive_absolute(output)
	game = Game.new()
	game.level_id = "dragons_roost"
	root.add_child(game)
	game.start_session()
	game.player.test_control = true
	await step()
	game.story_cards.clear()   # no walk-in cutscene in the way

	# 1) Beaten in battle — an emptied bar.
	game.player.position = Vector2(1000.0, 648.0)
	await step()
	await step()
	var _b: bool = game.player.take_damage(999, game.player.global_position + Vector2(40.0, 0.0))
	var down1: bool = await to_dying()
	await step()
	await shoot("death-01-beaten")

	# Back on our feet, then 2) a fall.
	game.restart_attempt()
	game.story_cards.clear()
	await step()
	game.player.position = Vector2(1000.0, 1200.0)   # below the sea line
	var down2: bool = await to_dying()
	await step()
	await shoot("death-02-fell")
	print("RESULT beaten=%s fell=%s" % [down1, down2])
	quit()
