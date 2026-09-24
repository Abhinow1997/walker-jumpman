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
	for i in range(Storyboard.PANELS.size()):
		var cue: Dictionary = Storyboard.PANELS[i]
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
		# A dissolve that outlasts the shot it is dissolving into would still be
		# running when the next cue arrives, and the panel it is fading up would
		# never be seen on its own at all.
		var span := float(cue.get("fade", 0.0))
		var next := length
		if i + 1 < Storyboard.PANELS.size():
			next = float(Storyboard.PANELS[i + 1]["at"])
		assert(span < next - at,
			   "panel '%s' dissolves for %.2fs but is only up for %.2fs"
			   % [cue["name"], span, next - at])
		if span > 0.0:
			print("  %6.2f s  %s, dissolving in over %.2fs" % [at, cue["name"], span])
		else:
			print("  %6.2f s  %s" % [at, cue["name"]])
		previous = at
	print("  %6.2f s  title card, and the music starts" % length)
	print("  %6.2f s  the level, faded up out of black"
		  % (length + Storyboard.CARD_IN + Storyboard.CARD_HOLD + Storyboard.CARD_OUT))

	# --- the captions ------------------------------------------------------
	# Structure only. Whether a line is the RIGHT line for that moment is not
	# something this can know — it would have to understand the recording — so
	# what is checked is that no caption runs past the end of the track, that
	# they do not overlap, and that none is on screen too briefly to read.
	print("captions: %d lines" % Storyboard.captions().size())
	var ends_at := 0.0
	var reading := 0.0
	for i in range(Storyboard.captions().size()):
		var line: Dictionary = Storyboard.captions()[i]
		var from := float(line["at"])
		var to := float(line["until"])
		var words := str(line["text"])
		assert(to > from, "caption %d ends before it starts" % i)
		assert(from >= ends_at,
			   "caption %d overlaps the one before it at %.2fs" % [i, from])
		# One snap step of slack: the cue file holds hundredths and the track
		# length does not land on one, so an exact comparison fails on rounding
		# alone. Anything further out than that is a real overrun.
		assert(to <= length + 0.01,
			   "caption %d runs to %.2fs, past the end of the %.2fs track"
			   % [i, to, length])
		# Under four tenths of a second is a flash, not a line: below the fade
		# either side of it, so it would never even reach full opacity.
		assert(to - from >= Storyboard.CAPTION_FADE * 2.0,
			   "caption %d is up for only %.2fs" % [i, to - from])
		reading += to - from
		ends_at = to
	print("  %.1f s of the %.1f s recording carries a caption (%.0f%%)"
		  % [reading, length, reading / length * 100.0])
	print("  first at %.2f s, last leaves at %.2f s"
		  % [float(Storyboard.captions()[0]["at"]), ends_at])

	var track := "res://audio/" + Storyboard.TRACK + ".ogg"
	var music: AudioStream = load(track)
	assert(music != null,
		   "the opening cues '%s' on its title card and there is no %s"
		   % [Storyboard.TRACK, track])
	print("music %s" % track)
	print("  length %.3f s" % music.get_length())
	quit()
