extends SceneTree
## The Dragon's Roost walk-in cutscene: the two Dragon Lord panels in sequence,
## then the fight with both bosses awake. Needs a renderer — run WITHOUT
## --headless. Deliberately NOT test_mode, which would collapse the cards.
const Game = preload("res://game/session.gd")
const LEVEL := "dragons_roost"
const DECK := 648.0

var game: Node2D
var lord: Area2D
var flyer: Area2D
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
	print("shot %-34s card %.2f  voice %s" % [label, game.story_alpha(),
		game.story_voice.playing])

func until(done: Callable, ticks: int) -> bool:
	for i in range(ticks):
		await step()
		if done.call():
			return true
	return false

func run() -> void:
	output = ProjectSettings.globalize_path("res://../evidence/roost")
	DirAccess.make_dir_recursive_absolute(output)
	game = Game.new()
	game.level_id = LEVEL
	root.add_child(game)
	game.start_session()
	game.player.test_control = true
	await step()
	for foe in game.enemies:
		if foe.kind == "dragon_lord":
			lord = foe
		elif foe.kind == "dragon":
			flyer = foe
	var at := float(game.level.cutscene[0].at)

	# Walk over the cue.
	game.player.position = Vector2(at - 60.0, DECK)
	game.player.velocity = Vector2.ZERO
	game.player.test_axis = 1.0
	var up: bool = await until(func(): return game.story_running(), 90)
	game.player.test_axis = 0.0

	# Panel 1 held, full screen, with the dialogue clip playing under it.
	await until(func(): return game.story_alpha() >= 1.0, 120)
	await step()
	await shoot("cutscene-01-panel-one")
	print("panel 1 tex==card0: %s  voice==dragon_lord_fight: %s  clip_at %.1fs" % [
		game.story_art.texture == game.story_cards[0]["tex"],
		game.story_voice.stream == game.story_cards[0]["voice"],
		game.story_voice.get_playback_position()])

	# The cut to panel 2: it dissolves in over panel 1 with the level kept COVERED
	# the whole time, rather than dropping back to gameplay between them. Sample
	# the dim right through the swap — it must stay near full — and confirm the
	# world stays frozen. Shoot the crossfade mid-way to show both at once.
	var second := false
	var covered := true
	var frozen := true
	var mid_shot := false
	var clip_at := 0.0
	var same_clip := false
	# Where in the dialogue the cut happens, and with it the subtitle: the line
	# changes hands on the first frame of the swap, not when the dissolve ends.
	# tests/diag_speech.gd puts the last sound of the first line at 6.70 s and
	# the shout that opens the second at 7.40, so this wants to land between
	# them. Move the first card's `hold` to move it.
	var swap_at := -1.0
	var said: String = game.story_line.text
	for i in range(1800):
		await step()
		if game.story_phase == Game.Story.SWAP:
			if swap_at < 0.0:
				swap_at = game.story_voice.get_playback_position()
				said = game.story_line.text
			if game.story_dim.color.a < Game.STORY_DIM * 0.9:
				covered = false
			if game.player.enabled:
				frozen = false
			if not mid_shot and game.story_art.modulate.a > 0.35 \
					and game.story_art.modulate.a < 0.85:
				mid_shot = true
				await shoot("cutscene-02-crossfade")
		if game.story_art.texture == game.story_cards[1]["tex"] \
				and game.story_phase == Game.Story.HOLD \
				and game.story_art.modulate.a > 0.99:
			second = true
			same_clip = game.story_voice.playing \
				and game.story_voice.stream == game.story_cards[0]["voice"]
			clip_at = game.story_voice.get_playback_position()
			break
	await shoot("cutscene-03-panel-two")
	print("panel 2: same continuous clip=%s  clip_at %.1fs  covered_through_swap=%s  frozen=%s" % [
		same_clip, clip_at, covered, frozen])
	print("the line changes hands at %.2fs of the clip (speech runs 0.48-6.70 and 7.40-18.10)" % swap_at)
	print("  panel 1: \"%s\"" % game.story_cards[0]["line"])
	print("  panel 2: \"%s\"" % said)

	# Out the other side: the fight, both bosses awake, plate up, and the BATTLE
	# track now playing where the level's calm loop was.
	await until(func(): return not game.story_running(), 900)
	for i in range(30):
		await step()
		game.player.health = game.player.MAX_HEALTH
	await shoot("cutscene-04-fight-on")
	print("RESULT up=%s second=%s same_clip=%s clip_at=%.1fs covered=%s frozen=%s lord=%s dragon=%s plate=%s track=%s" % [
		up, second, same_clip, clip_at, covered, frozen, lord.engaged, flyer.engaged,
		game.boss_main() != null, game.current_track()])
	quit()
