extends SceneTree
## The opening, taken the way a player takes it: NEW JOURNEY on the title, up
## out of black, four panels against the voice-over, the title card, then the
## level.
##
## Two things are checked here that nothing else can check. The cut times are
## asserted as maths — panel_at() is pure, so both sides of every boundary can
## be read without waiting half a minute for them. And one of those boundaries
## is then crossed for real off the playing stream, because the whole design is
## that the stream drives the cuts and a pure function agreeing with itself
## would not prove that.
##
## Needs a renderer for the screenshots, so run it WITHOUT --headless, from
## walker-jumpman/:
##     <godot> --path godot --script tests/capture_storyboard.gd

const Game = preload("res://game/session.gd")
const Storyboard = preload("res://ui/storyboard.gd")

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

## Runs frames until `test` passes. Returns false on timeout rather than
## asserting, so a check that depends on an audio device can be skipped on a
## machine that has none instead of failing there.
func settle(test: Callable, limit: int) -> bool:
	for i in range(limit):
		if test.call():
			return true
		await step()
	return test.call()

func music_node() -> AudioStreamPlayer:
	return root.get_node_or_null("Music")

func run() -> void:
	output = ProjectSettings.globalize_path("res://../evidence/screens")
	DirAccess.make_dir_recursive_absolute(output)

	# --- the cut times, as maths -------------------------------------------
	# Read either side of every boundary, derived from the table rather than
	# written out: a hand-written list of times goes stale the moment a panel is
	# added, which is what happened when panel 0 arrived and pushed the ledge
	# from 0:00 to 0:18.
	var board := Storyboard.new()
	var times := PackedStringArray()
	assert(board.panel_at(0.0) == 0, "the opening does not start on the first panel")
	for i in range(Storyboard.PANELS.size()):
		var cue := float(Storyboard.PANELS[i]["at"])
		var shot := str(Storyboard.PANELS[i]["name"])
		assert(board.panel_at(cue) == i,
			   "'%s' is not up at %.2fs exactly" % [shot, cue])
		if i > 0:
			assert(board.panel_at(cue - 0.01) == i - 1,
				   "'%s' is already up before %.2fs" % [shot, cue])
		times.append("%d:%02d %s" % [int(cue) / 60, int(cue) % 60, shot])
	board.free()
	print("cut times: " + String(", ").join(times))

	# --- reached the way the player reaches it ------------------------------
	change_scene_to_file("res://ui/title.tscn")
	for i in range(4): await step()
	var title: Control = current_scene
	assert(title != null, "title scene did not become current_scene")
	title.index = 0
	title._choose(0)
	for i in range(4): await step()
	var opening = current_scene
	assert(opening.has_method("skip"),
		   "NEW JOURNEY booted a level directly; the opening did not open")
	assert(opening.level_id == Game.catalogue()[0],
		   "the opening is carrying %s, not the first course level %s"
		   % [opening.level_id, Game.catalogue()[0]])
	# The menu's loop has to be out of the way: the voice-over carries its own
	# bed and two playing at once is the bug this line exists to catch.
	var music := music_node()
	assert(music == null or not music.playing,
		   "the menu music is still playing under the voice-over")
	print("opening installed, carrying level '%s'" % opening.level_id)

	# --- up out of black ----------------------------------------------------
	# NEW JOURNEY leaves a lit menu, so the first panel arrives rather than
	# replacing it in one frame. Caught early, while the rect is still most of
	# the way up, and then waited out so the panels below are photographed at
	# full brightness rather than part-faded.
	assert(opening.black_alpha() > 0.0, "the opening did not start from black")
	await capture("storyboard-00-fading-in")
	var opened := await settle(func(): return opening.black_alpha() <= 0.0, 180)
	assert(opened, "the opening fade never finished")
	print("opened out of black over %.2fs" % Storyboard.OPEN_IN)

	# --- the panels ---------------------------------------------------------
	# The playhead is moved to each cue rather than `index` being set to it.
	# _process takes the panel from the stream on every frame of the VOICE
	# phase, so one poked in directly is overwritten before it can be
	# photographed — which is how the first version of this capture wrote the
	# same picture three times under three names. Seeking is also the honest
	# shot: it is the path the player's machine takes to reach that panel.
	for i in range(Storyboard.PANELS.size()):
		var at := float(Storyboard.PANELS[i]["at"])
		opening.voice.seek(at + 0.25)
		var up := await settle(func(): return opening.index == i, 60)
		if not up:
			# Nothing is advancing playback, so the seek never reaches
			# _process. Stop the driver and set the panel directly: the art is
			# still photographed, and the cut times are covered by the pure
			# check above and the live crossing below.
			print("panel %d: forced, playback is not advancing" % (i + 1))
			opening.set_process(false)
			opening.index = i
			opening.queue_redraw()
			for j in range(2): await step()
		await capture("storyboard-%02d-%s"
					  % [i + 1, str(Storyboard.PANELS[i]["name"]).replace(" ", "-")])
		opening.set_process(true)

	# --- one cut taken off the playing stream -------------------------------
	# The screech, because it is the cut the opening is built around. Dropped in
	# just short of the mark and allowed to cross it on its own: the checks above
	# only prove panel_at() agrees with itself, and the whole design is that the
	# stream is what drives it. If the machine has no audio device the position
	# never advances, and that is reported rather than failed.
	var cross := 2
	var mark := float(Storyboard.PANELS[cross]["at"])
	opening.voice.seek(mark - 0.6)
	for i in range(2): await step()
	var moving := await settle(func(): return opening.voice_time() > mark - 0.55, 30)
	if moving:
		assert(opening.index == cross - 1,
			   "'%s' was already up at %.2fs"
			   % [Storyboard.PANELS[cross]["name"], opening.voice_time()])
		var crossed := await settle(func(): return opening.index == cross, 120)
		assert(crossed, "the stream passed %.2fs and the panel did not change" % mark)
		print("live cut: '%s' came up at %.2fs off the stream"
			  % [Storyboard.PANELS[cross]["name"], opening.voice_time()])
	else:
		print("live cut: SKIPPED, no audio device is advancing playback")

	# --- the voice-over runs out and the title card comes up ----------------
	opening.voice.seek(opening.voice.stream.get_length() - 0.25)
	var carded := await settle(func(): return opening.phase == Storyboard.Phase.CARD, 180)
	if not carded:
		# No audio device, so `finished` never fires. Take the same path the
		# signal would have, so the rest of the capture still runs.
		print("title card: forced, no audio device to end the recording")
		opening._begin_card()
		for i in range(2): await step()
	assert(opening.phase == Storyboard.Phase.CARD,
		   "the recording ended and the title card did not come up")
	# The game's own loop starts here, and this is the seam the whole opening is
	# built around: the first level names this same track, so session.gd's cue
	# will find it already playing and the music runs unbroken into the level.
	music = music_node()
	assert(music != null and music.playing,
		   "the title card is up and the game's music has not started")
	assert(music.track == Storyboard.TRACK,
		   "the title card started '%s', not '%s'" % [music.track, Storyboard.TRACK])
	print("title card up, music '%s' playing" % music.track)
	var music_position := music.get_playback_position()

	# Numbered after the panels rather than at fixed digits: with three panels
	# the card was 04, and adding panel 0 would have quietly overwritten it.
	var n := Storyboard.PANELS.size()
	await settle(func(): return opening.card_alpha() > 0.35, 60)
	await capture("storyboard-%02d-card-dissolving" % (n + 1))
	await settle(func(): return opening.card_alpha() >= 1.0, 120)
	await capture("storyboard-%02d-card" % (n + 2))

	# --- down to black, and up again on the level ---------------------------
	var darkening := await settle(func(): return opening.black_alpha() > 0.4, 400)
	assert(darkening, "the title card never started fading out")
	await capture("storyboard-%02d-fading-out" % (n + 3))

	var handed := await settle(func(): return current_scene is Node2D, 200)
	assert(handed, "the opening never handed off to a level")
	var game := current_scene
	assert(game.level_id == Game.catalogue()[0],
		   "handed off to %s, not %s" % [game.level_id, Game.catalogue()[0]])
	assert(game.state == Game.State.PLAYING,
		   "the level is in state %d, not PLAYING" % game.state)
	assert(is_instance_valid(game.player), "the level booted without a player")
	# Up out of the same black the card went down to, rather than a cut to a
	# fully lit level.
	assert(game.fade_phase == Game.Fade.IN,
		   "the level did not come up out of black (fade phase %d)" % game.fade_phase)
	await capture("storyboard-%02d-level-fading-in" % (n + 4))

	# The seam. Nothing restarted the track across the handoff: the same node is
	# still playing and it is further through the loop than it was on the card.
	music = music_node()
	assert(music != null and music.playing,
		   "the music stopped somewhere between the title card and the level")
	assert(music.track == Storyboard.TRACK,
		   "the level changed the track to '%s'" % music.track)
	assert(music.get_playback_position() > music_position,
		   "the music restarted at the handoff instead of carrying on")
	print("music carried across the handoff: %.2fs -> %.2fs"
		  % [music_position, music.get_playback_position()])

	var lit := await settle(func(): return game.fade_alpha() <= 0.0, 200)
	assert(lit, "the level never finished fading up")
	await capture("storyboard-%02d-playing" % (n + 5))
	print("opening complete: %s is playing" % game.level_id)
	quit()
