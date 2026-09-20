extends SceneTree
## The two story cards the dragon fight is bracketed by, shot across both
## dissolves. Needs a renderer — run WITHOUT --headless.
##
## Deliberately NOT in test_mode. That flag is what collapses a card to its
## effect — the fight starts and the picture never comes up — so a capture that
## set it would shoot seven frames of an ordinary level.
##
## What the shots are for: each card holds for as long as its own clip, which
## is about ten seconds, and the only things worth looking at are the two ends
## of it. 02 and 04 are the standoff arriving and leaving, 06 is the departure,
## and 05 and 07 are there to prove the level is exactly where it was when each
## picture went.
const Game = preload("res://game/session.gd")

const LEVEL := "fractured_isles"
## The Archway deck. The first card's line sits 48 px onto it.
const DECK := 660.0

var game: Node2D
var wyrm: Area2D
var at: float = 0.0
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
	print("shot %-34s card %.2f  dragon %-7s (%.0f, %.0f)  player (%.0f, %.0f)  cam %.0f" % [
		label, game.story_alpha(),
		("gone" if not wyrm.visible else ("up" if wyrm.engaged else "asleep")),
		wyrm.position.x, wyrm.position.y,
		game.player.position.x, game.player.position.y, game.camera.position.x])

func check(id: String, passed: bool, observed: Dictionary) -> void:
	if not passed:
		failures += 1
	print(JSON.stringify({"id": id, "status": "PASS" if passed else "FAIL",
						  "observed": observed}))

func until(done: Callable, ticks: int) -> bool:
	## Steps until the condition holds, rather than for a fixed count: a card
	## is as long as its own clip and a capture that guessed at tick counts
	## would drift the moment one was re-rendered.
	for i in range(ticks):
		await step()
		if done.call():
			return true
	return false

func run() -> void:
	output = ProjectSettings.globalize_path("res://../evidence/cutscene")
	DirAccess.make_dir_recursive_absolute(output)
	game = Game.new()
	game.level_id = LEVEL
	root.add_child(game)
	game.start_session()
	game.player.test_control = true
	await step()
	for foe in game.enemies:
		if foe.is_boss():
			wyrm = foe
	at = float(game.level.cutscene[0].at)
	check("both-cards-are-imported",
		game.story_cards.size() == 2
		and game.story_cards[0]["tex"] != null
		and game.story_cards[1]["tex"] != null,
		{"cards": game.story_cards.size()})

	# 01 — short of the line. The deck, the two floating stones, the dragon on
	# its perch at the right of the frame, and no card. 6900 is the first solid
	# footing on this side of the last hop.
	game.player.position = Vector2(at - 60.0, DECK)
	game.player.velocity = Vector2.ZERO
	await step()
	await step()
	await step()
	await shoot("cutscene-01-walking-in")
	check("nothing-up-before-the-line",
		not game.story_running() and not wyrm.engaged,
		{"alpha": game.story_alpha(), "engaged": wyrm.engaged})

	# 02 — the standoff arriving. Caught at about half, which is the frame that
	# says what this looks like: the level still legible underneath, the
	# picture coming over it.
	game.player.test_axis = 1.0
	var came_up: bool = await until(func(): return game.story_running(), 60)
	game.player.test_axis = 0.0
	await until(func(): return game.story_alpha() > 0.45, 30)
	await shoot("cutscene-02-standoff-coming-up")
	check("the-line-brings-it-up", came_up and game.story_running(),
		{"x": game.player.position.x, "at": at, "alpha": game.story_alpha()})

	# 03 — held, full screen. The world is stopped under it: he is still where
	# he crossed the line and the dragon is still sitting down.
	var stood_at: float = game.player.position.x
	await until(func(): return game.story_alpha() >= 1.0, 90)
	await step()
	await step()
	await shoot("cutscene-03-standoff-held")
	# The one thing a headless suite cannot check: that the clip is actually
	# coming out of the speakers. There is an audio device here.
	check("the-card-is-speaking",
		game.story_voice.playing
		and game.story_voice.stream == game.story_cards[0]["voice"],
		{"playing": game.story_voice.playing,
		 "at": game.story_voice.get_playback_position()})
	# The boss loop has not started yet — the card ducks the level's own track
	# and the fight track comes in as the picture hands the level back.
	check("the-fight-track-waits-for-the-fight",
		game.current_track() == str(game.level.music),
		{"want": game.current_track(), "boss_track": str(game.level.boss_music)})
	check("the-level-is-stopped-under-it",
		is_equal_approx(game.player.position.x, stood_at)
		and not game.player.enabled,
		{"drifted": game.player.position.x - stood_at,
		 "enabled": game.player.enabled})

	# 04 — going, and the fight already on behind it. The dragon is woken as
	# the picture starts to leave rather than after it has gone, so this is the
	# frame that has both.
	await until(func(): return wyrm.engaged, 1500)
	await until(func(): return game.story_alpha() < 0.55, 40)
	await shoot("cutscene-04-standoff-going-dragon-up")
	check("and-it-goes-out-on-the-roar",
		game.story_voice.stream == game.story_cards[0]["tail"]
		and game.story_voice.playing,
		{"playing": game.story_voice.playing,
		 "roar": game.story_cards[0]["tail"] != null})
	check("the-fight-starts-under-the-dissolve",
		wyrm.engaged and game.story_running(),
		{"engaged": wyrm.engaged, "alpha": game.story_alpha()})

	# 05 — the card gone. The same level it dimmed, the boss plate up because
	# the dragon is now fighting, and the dragon walking in from the right.
	await until(func(): return not game.story_running(), 200)
	await step()
	await step()
	await shoot("cutscene-05-the-fight")
	check("he-has-his-legs-back",
		game.player.enabled and not game.story_layer.visible
		and game.hud.boss() == wyrm
		and game.current_track() == str(game.level.boss_music),
		{"enabled": game.player.enabled,
		 "visible": game.story_layer.visible,
		 "plate": game.hud.boss() == wyrm})

	# 07 — the card, once the whole down beat is out. It waits for the fall to
	# finish rather than for the body to leave: the picture is of the dragon in
	# the air on its way out, so it belongs between the fall and the leaving.
	# Stood where a player who beat it would be standing. It matters for the
	# shot and not for the code: the camera follows the PLAYER, so a dragon
	# put down with a blast from the far end of the arena collapses off the
	# right edge of the screen, and 06 to 08 would be three pictures of an
	# empty deck. Killing it in reach is also how it is actually beaten.
	game.player.position = Vector2(wyrm.position.x - 150.0, DECK)
	game.player.velocity = Vector2.ZERO
	await step()
	await step()
	var _beaten: bool = wyrm.take_hit(wyrm.health, Vector2(game.player.position.x, DECK))
	# 06 — down, and staying down. The collapse the pack draws is 0.86 s and
	# the departure used to start the frame it ended, so the whole death read
	# as a stumble; it now lies there for DOWN_TIME and this is shot in the
	# middle of that, in gameplay, before any picture.
	await until(func(): return wyrm.fallen() or wyrm.position.y >= DECK - 4.0, 300)
	await step()
	await step()
	await step()
	await shoot("cutscene-06-beaten-and-down")
	check("it-lies-there-before-anything-else",
		not wyrm.alive() and wyrm.visible and not wyrm.fallen()
		and not game.story_running() and absf(wyrm.position.y - DECK) < 12.0,
		{"down": not wyrm.fallen(), "card": game.story_running(),
		 "off_the_deck": DECK - wyrm.position.y})
	var fell: bool = false
	for i in range(600):
		await step()
		if wyrm.fallen():
			fell = true
			break
	var came: bool = await until(func(): return game.story_running(), 120)
	await until(func(): return game.story_alpha() >= 1.0, 90)
	await step()
	await shoot("cutscene-07-departure-held")
	check("the-end-card-comes-up-after-the-fall",
		fell and came and wyrm.visible
		and game.story_art.texture == game.story_cards[1]["tex"],
		{"fell": fell, "came_up": came, "body_still_there": wyrm.visible})
	# Its own clip, over the level's own loop — the battle track ended with
	# the killing blow, two seconds ago.
	check("the-end-card-has-its-own-voice",
		game.story_voice.playing
		and game.story_voice.stream == game.story_cards[1]["voice"]
		and game.current_track() == str(game.level.music),
		{"playing": game.story_voice.playing,
		 "at": game.story_voice.get_playback_position(),
		 "track": game.current_track()})

	# 08 — and the level back, with the body still on the deck: the fly-away
	# is held by the freeze and runs after the picture, not under it.
	var lay_at: Vector2 = wyrm.position
	await until(func(): return not game.story_running(), 1500)
	await step()
	await step()
	await shoot("cutscene-08-and-then-it-leaves")
	# It waited: the body was still on the deck while the picture was up — see
	# `and-the-body-stays-down-while-it-plays` in test_levels, which measures
	# that — and it is climbing now that the picture has gone.
	check("the-body-waited-and-is-leaving-now",
		not game.story_running() and game.player.enabled
		and wyrm.visible and wyrm.position.y < lay_at.y - 40.0,
		{"enabled": game.player.enabled, "still_there": wyrm.visible,
		 "climbed": lay_at.y - wyrm.position.y})

	# 09 — gone, the way to the flag open, and the level's own loop back.
	var left: bool = await until(func(): return not wyrm.visible, 900)
	await step()
	await shoot("cutscene-09-the-way-on")
	check("and-the-fight-is-over-track-and-all",
		left and game.gate_shut_at() == INF
		and game.current_track() == str(game.level.music),
		{"gone": left, "shut_at": game.gate_shut_at(),
		 "track": game.current_track()})

	print("CUTSCENE CAPTURE: %s -> %d failures" % [output, failures])
	quit(1 if failures > 0 else 0)
