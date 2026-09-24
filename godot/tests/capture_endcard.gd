extends SceneTree
## The last card in the game, shot at full and on its way in. Needs a renderer —
## run WITHOUT --headless.
##
## Deliberately NOT in test_mode, for the same reason capture_cutscene.gd is
## not: that flag collapses a card to its effect and this is a capture of how
## the card LOOKS, which is the whole of what it is for.
##
## The four cards before it are marked seen and the fifth is begun directly,
## rather than fighting both bosses to reach it. What is under test here is the
## layout, and the route to it is covered by test_levels.gd.
const Game = preload("res://game/session.gd")

const LEVEL := "dragons_roost"
## The card is the fifth entry in this level's cutscene block.
const CARD := 4

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
	print("shot %-26s card %.2f  level_dim %.2f  panel_scrim %.2f" % [
		label, game.story_alpha(), game.story_dim.color.a,
		game.end_scrim.modulate.a if is_instance_valid(game.end_scrim) else -1.0])

func check(id: String, passed: bool, observed: Dictionary) -> void:
	if not passed:
		failures += 1
	print(JSON.stringify({"id": id, "status": "PASS" if passed else "FAIL",
						  "observed": observed}))

func until(done: Callable, ticks: int) -> bool:
	for i in range(ticks):
		await step()
		if done.call():
			return true
	return false

func run() -> void:
	output = ProjectSettings.globalize_path("res://../evidence/endcard")
	DirAccess.make_dir_recursive_absolute(output)
	game = Game.new()
	game.level_id = LEVEL
	root.add_child(game)
	game.start_session()
	await step()
	for i in CARD:
		game.story_cards[i]["seen"] = true
	game._begin_story(CARD)
	await step()

	# 01 — coming up. The scrim rides the same dissolve as the panel, so the
	# picture must not be bright behind the text at any point on the way in.
	await shoot("endcard-01-arriving")

	# 02 — full. This is the frame worth looking at.
	var up := await until(func(): return game.story_alpha() >= 0.99, 240)
	check("the-card-comes-all-the-way-up", up, {"alpha": game.story_alpha()})
	await shoot("endcard-02-full")

	# The subtitle band is OFF and the set stack is on. These are the two
	# layouts and a card is one or the other, never both.
	check("it-is-set-and-not-subtitled",
		not game.story_line.visible
		and game.end_card.visible
		and game.end_scrim.visible
		and game.end_title.text != ""
		and game.end_thanks.text != "",
		{"subtitle": game.story_line.visible, "set": game.end_card.visible,
		 "title": game.end_title.text, "thanks": game.end_thanks.text,
		 "credit": game.end_credit.text})

	# The stack is centred as a unit — the gaps between the three lines are
	# per-gap decisions, so this checks the block's own centre and not any one
	# label's. See END_GAPS.
	var top: float = game.end_title.position.y
	var bottom: float = game.end_credit.position.y + game.end_credit.size.y
	var middle: float = (top + bottom) * 0.5
	check("and-the-stack-sits-on-the-middle",
		absf(middle - game.VIEW_HALF.y) <= 12.0,
		{"middle": snappedf(middle, 0.1), "want": game.VIEW_HALF.y,
		 "top": snappedf(top, 0.1), "bottom": snappedf(bottom, 0.1)})

	print("ENDCARD CAPTURE: %d failures — shots in %s" % [failures, output])
	quit(1 if failures else 0)
