extends AudioStreamPlayer
## The game's music, and the one node in the project that outlives a scene.
##
## The title screen hands off by building a session, adding it to the root and
## freeing itself (see title.gd's _boot), so anything parented to either scene
## dies at the handoff. A track that restarted every time you pressed NEW
## JOURNEY would be obvious, because the title and The Fractured Isles play the
## same loop: the pack ships one. So this parents itself to the tree root and is
## found again by name, and asking for the track that is already playing does
## nothing at all — the music simply carries on across the transition.
##
## Everything goes through cue() and hush(). Neither is called `play`: this
## extends AudioStreamPlayer, which already has one, and GDScript will not let a
## static function shadow an inherited method. Nothing else in the game holds a
## reference to this node, which is what keeps a level from having to know
## whether the title screen ran first.
##
## Not an autoload on purpose: the test suites are SceneTree scripts that build
## a session directly, and the game must not depend on project.godot having
## registered something for them to work.

const DIR := "res://audio/"
## Under the sound effects rather than over them. The loop is a background wash
## and it is the only thing playing continuously, so it sits well back.
const LEVEL_DB := -12.0
## Per-track trim, on top of LEVEL_DB. Two different things are called "music"
## here and one fader cannot serve both.
##
## The coast loop is a bed. It is also mastered hot: at LEVEL_DB it comes out
## of the bus at -20.5 dBFS average. The battle track is a quieter master —
## -26.2 dBFS under exactly the same settings, measured by
## tests/diag_music_levels.gd — and it is the one piece of music in this game
## that is NOT a bed. It plays over a fight that is already loud with roars,
## fire, blasts and hits, and at the same fader it disappeared underneath it:
## six decibels down on a loop that is itself deliberately well back.
##
## +8 puts it at about -18 dBFS out, a shade forward of the coast loop, which
## is where a boss theme belongs. Its own peak is -2.0 dBFS, so even at this
## trim the loudest sample out of the bus is -6 and there is nothing to clip.
## Keyed by track rather than by level: two levels play this one, and the
## reason for the trim is a property of the recording.
const TRIM := {"decisive_battle": 8.0}
## The name it is found by. Anything already called this under the root is it.
const NODE := "Music"
## Silence. Godot treats anything at or below -80 dB as off.
const SILENT_DB := -80.0
## How far the loop drops while something else is speaking over it — a level's
## story card, which has a voice of its own and no bed. Pushed down rather than
## stopped: cue("") clears the stream, so bringing the level's music back after
## a four-second picture would restart the loop from the top and put an audible
## seam either side of the card. Ducked, it is simply still running underneath.
const DUCK_DB := -18.0

## Which track is loaded, as the bare name a level or the title asked for.
var track: String = ""

## Whether something is currently talking over the loop. Static for the same
## reasons `muted` is, and separate from it because they are different people's
## decisions: `muted` is the player's switch and is never ours to touch.
static var ducked: bool = false

## Whether the player has silenced the music from the pause screen.
##
## Static rather than a field on the node, for two reasons: the HUD can read it
## to label the toggle without holding a reference to anything, and it outlives
## the node if the node is ever rebuilt.
##
## Silenced by VOLUME and not by stop(). A level change cues its own track, so
## with a stop() every one of those calls would have to consult this first and a
## missed one would start the music up again behind a player who had turned it
## off. Turning the volume down is a thing cue() cannot undo by accident — and
## coming back on lands in time with the loop rather than restarting it.
static var muted: bool = false


static func cue(tree: SceneTree, name: String) -> void:
	## Cues `name` — a file in res://audio/ without its extension — or stops
	## the music when it is empty. Asking for what is already playing is a no-op,
	## which is the whole reason this node survives scene changes.
	if tree == null:
		return
	var node: AudioStreamPlayer = _node(tree, name != "")
	if node == null:
		return
	if node.track == name and (name == "" or node.playing):
		return
	node.track = name
	if name == "":
		node.stop()
		node.stream = null
		return
	# Ogg first, wav second. Every track here wants to be an ogg — the Magic
	# Cliffs loop is 96 s in 2.3 MB — and the boss track is a wav only because
	# there is no Vorbis encoder on the machine it was added on. Encode it and
	# this finds the ogg without another line changing. See
	# scripts/extract_boss_music.py.
	# Asked for every tick by current_track() in session.gd, so a track that
	# cannot load must not be retried every tick: before this, one boss fight
	# put three engine errors a frame into the log for as long as it lasted.
	# Remembered per name rather than per path, and never cleared — a file that
	# appears mid-session is a reimport in the editor, and that restarts play.
	if _missing.has(name):
		node.track = ""
		return
	var path := ""
	for suffix in [".ogg", ".wav"]:
		if ResourceLoader.exists(DIR + name + suffix):
			path = DIR + name + suffix
			break
	if path == "":
		_warn_missing(name)
		node.track = ""
		return
	var stream := load(path)
	# ResourceLoader.exists() is satisfied by the .import file on its own, so a
	# track whose SOURCE is missing gets all the way here and comes back null.
	# decisive_battle.wav was exactly that for a while — ignored by `*.wav`
	# with no exception for godot/audio/, so only its .import was committed —
	# and the boss fights name it on both levels that have one.
	#
	# Leave whatever is playing where it is rather than assigning the null.
	# `node.stream = null` is SILENCE, and that is how the last two fights in
	# the game ran with nothing under them at all: not the coast loop, nothing.
	# tests/diag_battle_music.gd printed `stream=<none> playing=false` for the
	# whole fight. A missing battle track should cost you the battle track and
	# leave the level's own loop running under the fight, which is what every
	# other path through this function already does.
	if stream == null:
		_warn_missing(name)
		node.track = ""
		return
	# The pack's loop is 96 seconds and meant to run continuously. Set here
	# rather than in the .import, so a reimport cannot quietly drop it.
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamWAV:
		# Same decision, different property. loop_end has to be a real sample
		# count: left at zero the loop is empty and the track plays once.
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(_loop_seconds(name, stream) * float(stream.mix_rate))
	node.stream = stream
	# Set per track, not once at creation: the trim above is part of the level
	# this track plays at, and the mute and the duck have to survive the swap.
	node.volume_db = _level_db(name)
	node.play()


## Where a track's loop turns back, in seconds, for the tracks that do not loop
## at their own end. Keyed by track, like TRIM, and for the same reason: it is
## a property of the recording.
##
## xDeviruchi's pack is built as Intro / Loop / End and ships a table of the
## loop points ("READ THIS FIRST.pdf", Tables 1 and 2). Decisive Battle is
## "Loop, End": it starts at 0, but the loop turns at 116.033 s and the last
## four seconds of the 120.18 s file are an ENDING — a closing tag written to
## finish the piece, not to run into the top of it again. Looping the whole
## file plays that tag mid-fight and then jumps to the start, which is the one
## audible seam in a track the pack says is otherwise seamless. A boss fight
## can outlast two minutes, so this is reachable.
##
## Anything not named here loops at its own end, which is right for the Magic
## Cliffs loop — Ansimuz's is a continuous 96 s bed with no ending.
const LOOP_END := {"decisive_battle": 116.033}


## The loop point for `name`, falling back to the whole file. Clamped, so a
## table entry that outruns a replaced recording cannot produce a loop_end past
## the last sample.
static func _loop_seconds(name: String, stream: AudioStream) -> float:
	var whole := float(stream.get_length())
	if not LOOP_END.has(name):
		return whole
	return minf(float(LOOP_END[name]), whole)


## Track names that could not be loaded, so cue() says so once and then stops
## trying. See the guard in cue().
static var _missing: Dictionary = {}


static func _warn_missing(name: String) -> void:
	if _missing.has(name):
		return
	_missing[name] = true
	push_warning(("music: no track called %s in %s — the level's own loop is "
				  + "carrying on under it. Run the extractor that owns it; for "
				  + "decisive_battle see godot/audio/PROVENANCE.md.") % [name, DIR])


## What the player hears: this track's mix level, ducked under a voice, or
## silence. The track matters — see TRIM.
static func _level_db(name: String = "") -> float:
	if muted:
		return SILENT_DB
	var level: float = LEVEL_DB + float(TRIM.get(name, 0.0))
	return level + DUCK_DB if ducked else level


static func duck(tree: SceneTree, under: bool) -> void:
	## Pushes the loop down under something else that is speaking, and brings
	## it back up. The track keeps playing throughout, which is the point — see
	## DUCK_DB.
	ducked = under
	var node := _node(tree, false)
	if node != null:
		node.volume_db = _level_db(node.track)


static func silence(tree: SceneTree, value: bool) -> void:
	## Sets the mute and applies it to whatever is playing. Safe before any music
	## exists: the flag is remembered and the node picks it up when it is made.
	muted = value
	var node := _node(tree, false)
	if node != null:
		node.volume_db = _level_db(node.track)


static func toggle(tree: SceneTree) -> bool:
	## Flips the mute and reports the new state, which is what the caller wants
	## for a button that has to relabel itself.
	silence(tree, not muted)
	return muted


static func hush(tree: SceneTree) -> void:
	## Stops whatever is playing. Used by the levels that have no music of their
	## own, so walking out of a themed level into a greybox one goes quiet
	## instead of carrying the wrong track with it.
	cue(tree, "")


static func _node(tree: SceneTree, create: bool) -> AudioStreamPlayer:
	## The one music node under the tree root, made on first use. Deferred adds
	## are avoided: the caller wants it playing now, and add_child from _ready is
	## safe on the root.
	var root := tree.root
	if root == null:
		return null
	var found := root.get_node_or_null(NODE)
	if found != null:
		return found
	if not create:
		return null
	var node = new()
	node.name = NODE
	# Not LEVEL_DB: a node made while the player has the music off must come
	# up silent, or muting then changing level turns it back on.
	node.volume_db = _level_db()
	# Keeps playing while the session is paused: the pause screen is a breath,
	# not a scene change, and silence there reads as the game having crashed.
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(node)
	return node
