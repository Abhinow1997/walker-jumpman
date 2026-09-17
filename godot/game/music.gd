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
## The name it is found by. Anything already called this under the root is it.
const NODE := "Music"

## Which track is loaded, as the bare name a level or the title asked for.
var track: String = ""


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
	var path := DIR + name + ".ogg"
	if not ResourceLoader.exists(path):
		push_warning("music: no track at %s (run scripts/extract_magic_cliffs.py)" % path)
		node.track = ""
		return
	var stream := load(path)
	# The pack's loop is 96 seconds and meant to run continuously. Set here
	# rather than in the .import, so a reimport cannot quietly drop it.
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	node.stream = stream
	node.play()


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
	node.volume_db = LEVEL_DB
	# Keeps playing while the session is paused: the pause screen is a breath,
	# not a scene change, and silence there reads as the game having crashed.
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(node)
	return node
