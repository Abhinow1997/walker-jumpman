extends SceneTree
## Development tool: what the music node is actually doing through a boss fight.
##
## Written when the battle track was reported inaudible on The Fractured Isles.
## The file itself was not the problem — decisive_battle.wav peaks at -2 dBFS
## and averages -14.9 — so this asks the engine instead: which stream the one
## music node is holding, whether it is playing, where its playhead is, and
## what volume it is being played at, through the whole beat from walking up to
## the boss to putting it down.
##
## Either boss level, because they are different questions. The isles fights
## one and the track ends with it; The Dragon's Roost fights two and the track
## has to last as long as the LAST of them — so on a level with two this goes
## on to beat the first one and keep listening while the other fights.
##
##     <godot> --path godot --script tests/diag_battle_music.gd
##     <godot> --path godot --script tests/diag_battle_music.gd -- dragons_roost
##
## Run WITHOUT --headless. The headless build loads a dummy audio driver and a
## dummy driver's playhead is not evidence about anything.
const Game = preload("res://game/session.gd")
const Music = preload("res://game/music.gd")

## Which level to walk, when none is named on the command line.
const LEVEL := "fractured_isles"
## The deck each level's fight happens on. Not derived: the spawn deck and the
## arena deck are the same height on the Roost and are not on the isles, and a
## player dropped at the wrong one falls out of the shot the card is over.
const DECK := {"fractured_isles": 600.0, "dragons_roost": 648.0}

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

## Where the level cues its fight: the first cutscene panel with an `at`. The
## first run of this put the player at 6900 against a cue of 6960 and watched
## nothing happen for twelve seconds — _story_due fires on x >= at.
func card_x() -> float:
	for card in game.level.get("cutscene", []):
		if card.has("at"):
			return float(card["at"])
	return 0.0

func run() -> void:
	var want := LEVEL
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		want = str(args[0])
	game = Game.new()
	# NOT test_mode: the card is the thing that ducks the loop, and a run that
	# skips the card cannot show a duck that was never lifted.
	game.level_id = want
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
	var deck: float = float(DECK.get(want, 648.0))
	game.player.position = Vector2(card_x() + 40.0, deck)
	game.player.velocity = Vector2.ZERO
	for _i in 30:
		await physics_frame
	say("at the card")

	# Through the card, sampling twice a second, until the story is actually
	# over rather than for a fixed count. The isles holds one panel for about
	# four seconds; The Dragon's Roost runs two, 5.8 and 11.0 plus the fades,
	# and a twelve-second window ended in the middle of them — which looks
	# exactly like a fight playing the wrong track, and is not one.
	for beat in 80:
		for _i in 30:
			await physics_frame
		say("card+%.1fs" % (float(beat + 1) * 0.5))
		if not game.story_running():
			break

	# The fight itself: every boss the card woke is up and swinging.
	for beat in 8:
		for _i in 30:
			await physics_frame
		game.player.health = game.player.MAX_HEALTH
		say("fight+%.1fs" % (float(beat + 1) * 0.5))

	# On a level that fights two, the half the isles cannot show: the first one
	# goes down and the track has to stay on the fight the other one is still
	# having. It used to drop to the coast loop here and come back when the
	# body finally left — see boss_fighting() in game/session.gd.
	if bosses.size() > 1:
		print("-- putting %s down, %s still up" % [bosses[0].kind, bosses[1].kind])
		var _out: bool = bosses[0].take_hit(bosses[0].health,
				game.player.global_position)
		for beat in 16:
			for _i in 30:
				await physics_frame
			game.player.health = game.player.MAX_HEALTH
			say("down+%.1fs %s" % [float(beat + 1) * 0.5,
					"(body gone)" if not bosses[0].visible else ""])

	# And the aftermath, which is the level's own loop on both of them.
	print("-- putting the rest down")
	for foe in bosses:
		if foe.alive():
			var _last: bool = foe.take_hit(foe.health, game.player.global_position)
	for beat in 6:
		for _i in 30:
			await physics_frame
		game.player.health = game.player.MAX_HEALTH
		say("clear+%.1fs" % (float(beat + 1) * 0.5))
	quit()
