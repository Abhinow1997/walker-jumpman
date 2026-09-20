extends SceneTree
## What the game's two streams are, and whether the opening's cuts still fit
## inside the one they are written against.
##
## The panel times in storyboard.gd are the recording's: 0:30 is where the
## screech lands and 0:45 is where he runs. Re-render that mp3 a few seconds
## shorter — a retake, a tighter mix — and the last cut falls off the end, which
## on screen is a panel that never appears and a title card that arrives early.
## Nothing else in the project can catch that, because the times are correct
## GDScript either way.
##
## Run from walker-jumpman/:
##     <godot> --path godot --headless --script tests/diag_audio.gd

const Storyboard = preload("res://ui/storyboard.gd")

func _initialize() -> void:
	var vo: AudioStream = load(Storyboard.VOICE)
	assert(vo != null, "no voice-over at " + Storyboard.VOICE)
	var length := vo.get_length()
	print("voice-over %s" % Storyboard.VOICE)
	print("  length %.3f s" % length)
	var previous := -1.0
	for cue in Storyboard.PANELS:
		var at := float(cue["at"])
		assert(at > previous, "panel cues are out of order at %.2fs" % at)
		assert(at < length,
			   "panel '%s' cues at %.2fs but the track is only %.2fs"
			   % [cue["name"], at, length])
		# A panel that is up for under a second is a flash, not a shot: almost
		# always a typo in the cue rather than a deliberate cut.
		if previous >= 0.0:
			assert(at - previous >= 1.0,
				   "panel '%s' is only up for %.2fs" % [cue["name"], at - previous])
		print("  %6.2f s  %s" % [at, cue["name"]])
		previous = at
	print("  %6.2f s  title card, and the music starts" % length)
	print("  %6.2f s  the level, faded up out of black"
		  % (length + Storyboard.CARD_IN + Storyboard.CARD_HOLD + Storyboard.CARD_OUT))

	var track := "res://audio/" + Storyboard.TRACK + ".ogg"
	var music: AudioStream = load(track)
	assert(music != null,
		   "the opening cues '%s' on its title card and there is no %s"
		   % [Storyboard.TRACK, track])
	print("music %s" % track)
	print("  length %.3f s" % music.get_length())
	quit()
