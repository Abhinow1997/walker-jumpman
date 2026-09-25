extends SceneTree
## The Climb's opening card, shot across its one dissolve. Needs a renderer —
## run WITHOUT --headless.
##
## Deliberately NOT in test_mode, for the same reason capture_cutscene.gd is
## not: that flag collapses a card to its effect, so a capture that set it
## would shoot the level with no picture on it.
##
## What the shots are for. This card is the odd one out in the game — every
## other story card is a walk-in with a positive `at`, and this one fires at
## `at: 0`, on the first frame he is on his feet. So the thing worth proving is
## that the picture is already arriving before the player has done anything,
## and that the level is untouched underneath it when it goes. 01 is the frame
## the level starts, 02 is the card at full, 03 is the level back with him
## still on his mark.
const Game = preload("res://game/session.gd")

const LEVEL := "the_climb"

var game: Node2D
var output: String
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func step() -> void:
	await physics_frame
	await process_frame

func shoot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png("%s/%s.png" % [output, label])
	assert(err == OK)
	print("shot %-28s card %.2f  player (%.0f, %.0f)  cam %.0f" % [
		label, game.story_alpha(),
		game.player.position.x, game.player.position.y, game.camera.position.y])

func check(id: String, passed: bool, observed: Dictionary) -> void:
	if not passed:
		failures += 1
	print(JSON.stringify({"id": id, "status": "PASS" if passed else "FAIL",
						  "observed": observed}))

func until(done: Callable, ticks: int) -> bool:
	## Stepped against the condition rather than a tick count — the hold is a
	## number in the level file and a capture that guessed would drift the
	## moment it was retuned.
	for i in range(ticks):
		await step()
		if done.call():
			return true
	return false

func run() -> void:
	output = ProjectSettings.globalize_path("res://../evidence/climb-card")
	DirAccess.make_dir_recursive_absolute(output)
	game = Game.new()
	game.level_id = LEVEL
	root.add_child(game)
	game.start_session()
	await step()
	check("the-card-is-imported",
		game.story_cards.size() == 1 and game.story_cards[0]["tex"] != null,
		{"cards": game.story_cards.size()})

	# 01 — the first frame. The card is already on its way up: there is no
	# walk-in to wait through, which is the whole point of `at: 0`.
	await shoot("climb-01-first-frame")

	# 02 — full. The picture covers the level and the world is frozen behind
	# it; he is still standing on spawn because nothing has been given a tick.
	var up := await until(func(): return game.story_alpha() >= 0.99, 240)
	check("the-card-comes-all-the-way-up", up, {"alpha": game.story_alpha()})
	await shoot("climb-02-card-full")
	var held_x: float = game.player.position.x

	# 03 — back to the level, with him exactly where the picture found him.
	var gone := await until(func(): return not game.story_running(), 600)
	await step()
	await shoot("climb-03-level-back")
	check("and-it-hands-the-level-back-untouched",
		gone and is_equal_approx(game.player.position.x, held_x)
		and is_equal_approx(held_x, float(game.level.spawn[0])),
		{"gone": gone, "x": game.player.position.x, "spawn_x": game.level.spawn[0]})

	print("CLIMB CARD CAPTURE: %d failures — shots in %s" % [failures, output])
	quit(1 if failures else 0)
