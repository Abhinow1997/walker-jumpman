extends SceneTree
## Development tool: why the dragon's battle track cannot be heard.
##
## Reported as inaudible on The Fractured Isles. The file itself is not the
## problem — decisive_battle.wav peaks at -2 dBFS and averages -14.9 — so this
## asks the engine instead: which stream the one music node is holding, whether
## it is playing, where its playhead is, and what volume it is being played at,
## through the whole beat from walking up to the dragon to putting it down.
##
##     <godot> --path godot --script tests/diag_battle_music.gd
##
## Run WITHOUT --headless. The headless build loads a dummy audio driver and a
## dummy driver's playhead is not evidence about anything.
const Game = preload("res://game/session.gd")
const Music = preload("res://game/music.gd")

## The Fractured Isles: the dragon's card fires at 6960 and the fight is past
## the gate at 6110.
const CARD_AT := 6960.0

var game: Node2D

func _initialize() -> void:
	call_deferred("run")

func steps(n: int) -> void:
	for i in range(n):
		await physics_frame
		await process_frame

func node() -> AudioStreamPlayer:
	return root.get_node_or_null("Music")

func say(label: String) -> void:
	var music := node()
	if music == null:
		print("%-22s  NO MUSIC NODE" % label)
		return
	var stream: AudioStream = music.stream
	print(("%-22s  track=%-16s stream=%-22s playing=%s pos=%6.2f len=%7.2f "
			+ "vol=%6.1f paused=%s ducked=%s muted=%s bus=%.1f/%s  want=%s") % [
		label, music.track,
		stream.resource_path.get_file() if stream != null else "<none>",
		music.playing, music.get_playback_position(),
		stream.get_length() if stream != null else -1.0,
		music.volume_db, music.stream_paused, Music.ducked, Music.muted,
		AudioServer.get_bus_volume_db(0), AudioServer.is_bus_mute(0),
		game.current_track() if is_instance_valid(game) else "-"])

func wyrm() -> Node2D:
	for foe in game.enemies:
		if is_instance_valid(foe) and foe.is_boss():
			return foe
	return null

func run() -> void:
	game = Game.new()
	# NOT test_mode: the card is the thing that ducks the loop, and a run that
	# skips the card cannot show a duck that was never lifted.
	game.level_id = "fractured_isles"
	root.add_child(game)
	await steps(3)
	game.start_session()
	await steps(2)
	say("on the level")

	# Up to the dragon. The gate at 6110 is shut behind the fight before it, so
	# the enemies in front of him are lifted out rather than fought.
	var bosses: Array = []
	for foe in game.enemies:
		if is_instance_valid(foe) and foe.is_boss():
			bosses.append(foe)
		elif is_instance_valid(foe):
			foe.queue_free()
	game.enemies.clear()
	for foe in bosses:
		game.enemies.append(foe)
	await steps(2)
	for wall in game.gate_walls:
		wall.collision_layer = 0
	game.gates.clear()
	game.gate_walls.clear()
	say("arena clear")

	# PAST the cue, not short of it: _story_due fires on x >= at, and the first
	# run of this put him at 6900 and watched nothing happen for twelve seconds.
	game.player.position = Vector2(CARD_AT + 40.0, 600.0)
	game.player.velocity = Vector2.ZERO
	for _i in 30:
		await physics_frame
	say("at the card")

	# Through the card, sampling twice a second. STORY_IN + HOLD + OUT is about
	# four seconds; twelve is enough to see the far side of it.
	for beat in 24:
		for _i in 30:
			await physics_frame
		say("card+%.1fs" % (float(beat + 1) * 0.5))
		if beat == 11:
			var boss := wyrm()
			print("   boss: %s engaged=%s visible=%s alive=%s hp=%d" % [
				boss != null,
				boss.engaged if boss != null else false,
				boss.visible if boss != null else false,
				boss.alive() if boss != null else false,
				boss.health if boss != null else -1])
	quit()
