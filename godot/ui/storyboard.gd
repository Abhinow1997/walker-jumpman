extends Control

## The cold open. NEW JOURNEY plays this before the first level: four panels
## faded up out of black and played against the merged voice-over, then the
## title card, then the game.
##
## THE CUTS ARE THE RECORDING'S, NOT A TIMER'S. Every panel change is taken from
## the voice-over's own playback position — the isles hold until 0:18, he is
## asleep on the ledge until 0:30, the screech lands there, and he runs at 0:45.
## Which of those changes dissolve and which cut hard is a per-cue decision in
## PANELS below. The captions run off the same clock and their own table, so a
## line arrives with the words rather than with the picture.
## A Timer counts process frames, so one hitch while a level streams in would
## slide the wake-up off the line it was written for and never catch up. Reading
## the stream instead means a late frame shows the right panel late rather than
## the wrong panel on time.
##
## THE MUSIC IS THE TRANSITION. The menu loop is hushed on the way in, because
## the voice-over carries its own bed and two would collide. It is cued again on
## the title card — and the first level names that same track, so the cue in
## session.gd's _build_world finds it already playing and does nothing. The loop
## runs unbroken from the logo into play: there is no second track to cross-fade
## and no silence to cover. See music.gd on why that node outlives this scene.

const Session = preload("res://game/session.gd")
const Music = preload("res://game/music.gd")

## Voice-over and bed, already mixed down together — see the storyboard section
## of ui/art/PROVENANCE.md. Loaded rather than preloaded: it is a minute of
## audio and nothing outside the opening needs it resident.
const VOICE := "res://audio/storyboard_scene_1.mp3"

## The logo drop. Deliberately the title screen's own backdrop rather than a
## fifth panel: the player has just come from it, so the game's name arriving at
## the end of the opening lands as a title card and not as new art.
const TITLE_CARD := preload("res://ui/art/title_bg.png")

## Where each panel takes over, in seconds into the voice-over. Held here and
## nowhere else; tests/diag_audio.gd checks they still fall inside the track,
## which is what catches a re-recorded mp3 that ends before the last cue.
##
## `fade` is optional and is how long the panel takes to dissolve in over the
## one before it, starting AT its cue — so the cue is still the moment the
## change begins, not the moment it finishes. A cue without one is a hard cut.
##
## Only the ledge has it. The isles and the ledge are two held shots of a quiet
## morning and the eye should be carried between them; the screech and the run
## are the opposite, a noise that wakes him and a decision to move, and a
## dissolve would soften the exact thing those cuts are for. Hard cuts are also
## what keeps 0:30 and 0:45 landing on the mark rather than around it.
const PANELS := [
	{"at": 0.0, "name": "the isles", "tex": preload("res://ui/art/storyboard/panel_0.png")},
	{"at": 18.0, "fade": 1.2, "name": "the ledge", "tex": preload("res://ui/art/storyboard/panel_1.png")},
	{"at": 30.0, "name": "the screech", "tex": preload("res://ui/art/storyboard/panel_2.png")},
	{"at": 45.0, "name": "the run", "tex": preload("res://ui/art/storyboard/panel_3.png")},
]

## What he says, and when — read from ui/captions.json rather than written here.
##
## It is data because it is retimed, not edited: the words are fixed by the
## recording and only the numbers move, and they move every time the mp3 is
## re-rendered. tests/time_captions.gd plays the recording and writes that file
## back from one key press per line, which is the only way these have ever been
## right — they were first derived by measuring where speech starts in the stem,
## and a measurement can say WHEN a sound happens but not WHICH words are in it.
##
## The delivery tags are not in the file. [exhales], [sighs], [curious],
## [whispers], [excited] and [laughs] are instructions to the voice, not words
## he says, and a subtitle that prints them is captioning the score rather than
## the film. The one bracket that stays is [EXPLOSION], which is the convention
## the other way round: a sound with no words in it still has to be captioned.
const CAPTION_FILE := "res://ui/captions.json"
static var _captions: Array = []


static func captions() -> Array:
	## The cue list, read once. Static and lazy like session.gd's catalogue(),
	## because the diagnostics want it before any opening has been built.
	if _captions.is_empty():
		_read_captions()
	return _captions


static func _read_captions() -> void:
	if not ResourceLoader.exists(CAPTION_FILE) and not FileAccess.file_exists(CAPTION_FILE):
		push_warning("captions: nothing at %s; the opening will play silent-titled"
					 % CAPTION_FILE)
		return
	var file := FileAccess.open(CAPTION_FILE, FileAccess.READ)
	if file == null:
		push_warning("captions: could not open %s" % CAPTION_FILE)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("lines"):
		push_warning("captions: %s has no `lines` array" % CAPTION_FILE)
		return
	_captions = parsed["lines"]


## The column the captions wrap in, the baseline the last line sits on, and how
## long each takes to arrive and leave. The bottom is above the skip hint rather
## than on it: both are bottom-centred text and for the first six seconds they
## are both on screen.
const CAPTION_WIDTH := 760.0
const CAPTION_BOTTOM := 486.0
const CAPTION_SIZE := 17
const CAPTION_FADE := 0.18

## The screen the opening starts on. NEW JOURNEY cuts from a lit menu straight
## into somebody else's picture, so the first panel is brought up out of black
## rather than replacing the menu in one frame. Panel 0 is the establishing shot
## and has no character in it, which is what makes it the one to fade onto:
## there is nothing to miss while it arrives.
const OPEN_IN := 1.0

## The title card, once the voice-over is out: up, held, then down to black.
const CARD_IN := 0.9
const CARD_HOLD := 2.4
const CARD_OUT := 0.8

## The loop the menu plays and the first level names. One string, three screens.
const TRACK := "magic_cliffs"

## The panels are authored at the viewport, so this is both the design space and
## the size they are drawn at: one texel per pixel under nearest filtering,
## exactly as title_bg.png is. The same constant as title.gd's.
const DESIGN := Vector2(960, 540)

## How long the skip line stays up, and how long it takes to go. Long enough to
## be read, short enough not to sit over the whole opening.
const HINT_SHOWN := 5.0
const HINT_FADE := 1.5

## Which part of the opening is running. CARD and OUT are timed off `clock`;
## VOICE is timed off the stream.
enum Phase { VOICE, CARD, OUT }
var phase: Phase = Phase.VOICE
## Seconds inside the current phase. Only CARD and OUT use it.
var clock: float = 0.0
## Seconds since the opening started, for the skip hint alone.
var shown: float = 0.0
## Which panel is up.
var index: int = 0
## How far that panel has dissolved in over the one before it, 0 to 1. Always 1
## for a cue with no `fade`, which is every cue but the ledge.
var blend: float = 1.0
## Which caption is up, -1 between lines, and how far it has faded in or out.
## Resolved here rather than in _draw so the draw stays a blit and two alphas.
var said: int = -1
var said_alpha: float = 0.0
## Whether the title card has been reached. A skipped opening goes straight to
## black from whatever panel was up, so the card must not draw over it.
var card_up: bool = false
## The level to hand off to. Set before add_child — see open().
var level_id: String = ""
var voice: AudioStreamPlayer

## Set before this is added to the tree to take every wait out of it: skip()
## then boots on the spot rather than through the fade. The same flag session.gd
## carries, for the same reason — a suite must not sit through fifty-seven
## seconds of voice-over to reach the level behind it.
var test_mode: bool = false


static func open(tree: SceneTree, id: String) -> Control:
	## Installs the opening as the current scene and frees the screen it
	## replaces, the way Session.boot does for a level. It hands off to that
	## level itself when it ends or is skipped, so the caller names the level
	## and then has nothing left to do.
	if tree == null:
		return null
	var scene = new()
	scene.level_id = id
	var outgoing := tree.current_scene
	tree.root.add_child(scene)
	tree.current_scene = scene
	if outgoing != null:
		outgoing.queue_free()
	return scene


func _ready() -> void:
	# Built in code rather than from a .tscn, as the session is, so there is no
	# scene file holding a second copy of the anchors.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The panels are opaque and cover the frame, so the clear colour never shows.
	mouse_filter = Control.MOUSE_FILTER_STOP
	# The title registers these too and both sides skip what already exists, so
	# reaching the opening by any route leaves skip bound.
	Session.setup_input()
	Music.hush(get_tree())
	voice = AudioStreamPlayer.new()
	voice.stream = load(VOICE)
	# The end of the recording is the cue for the title card. Taken from the
	# signal rather than by comparing against get_length(), so a stream that
	# stops early still moves the opening on instead of holding panel 3 forever.
	voice.finished.connect(_begin_card)
	add_child(voice)
	voice.play()


func _process(delta: float) -> void:
	shown += delta
	match phase:
		Phase.VOICE:
			var at := voice_time()
			index = panel_at(at)
			blend = blend_at(at)
			said = caption_at(at)
			said_alpha = caption_alpha(at)
		Phase.CARD:
			clock += delta
			if clock >= CARD_IN + CARD_HOLD:
				phase = Phase.OUT
				clock = 0.0
		Phase.OUT:
			clock += delta
			if clock >= CARD_OUT:
				_hand_off()
				return
	# Every frame: the hint is fading, the card is dissolving or the screen is
	# going down. There is one full-screen blit behind all of it and nothing
	# else running, so there is nothing here worth the bookkeeping to skip.
	queue_redraw()


func voice_time() -> float:
	## Where the recording actually is, in seconds. get_playback_position only
	## moves when the mixer fills a buffer, so on its own it steps in chunks and
	## a cut written for 30.00 can land a frame or two out; the two AudioServer
	## terms are the standard correction for that. Clamped at zero because the
	## latency term can exceed the position on the first frames of playback.
	if voice == null or not voice.playing:
		return 0.0
	return maxf(0.0, voice.get_playback_position()
			+ AudioServer.get_time_since_last_mix()
			- AudioServer.get_output_latency())


func panel_at(seconds: float) -> int:
	## The last panel whose cue has passed. Pure, so a test can check the cut
	## times without an audio device: the suites run headless on a dummy mixer
	## that never advances a playback position.
	var found := 0
	for i in PANELS.size():
		if seconds >= float(PANELS[i]["at"]):
			found = i
	return found


func blend_at(seconds: float) -> float:
	## How far the panel at `seconds` has dissolved in over the one before it.
	## Pure, like panel_at, and 1.0 for a hard cut — so a panel with no `fade`
	## costs nothing and draws exactly as it did before any of this existed.
	var i := panel_at(seconds)
	if i == 0:
		return 1.0
	var span := float(PANELS[i].get("fade", 0.0))
	if span <= 0.0:
		return 1.0
	return clampf((seconds - float(PANELS[i]["at"])) / span, 0.0, 1.0)


func caption_at(seconds: float) -> int:
	## Which caption is being spoken at `seconds`, or -1 in the gaps between
	## them. Pure, like panel_at and blend_at, so the cue table can be checked
	## without an audio device. Linear over eighteen entries once a frame, which
	## is nothing next to the two full-screen blits underneath it.
	for i in range(captions().size()):
		if seconds >= float(captions()[i]["at"]) and seconds < float(captions()[i]["until"]):
			return i
	return -1


func caption_alpha(seconds: float) -> float:
	## How far the caption at `seconds` has faded in, or back out. Derived from
	## the time rather than accumulated, so seeking the recording — which every
	## capture does — lands on the right opacity instead of the one left over
	## from wherever the playhead used to be.
	var i := caption_at(seconds)
	if i < 0:
		return 0.0
	var since := seconds - float(captions()[i]["at"])
	var left := float(captions()[i]["until"]) - seconds
	return clampf(minf(since, left) / CAPTION_FADE, 0.0, 1.0)


func _begin_card() -> void:
	## The voice-over is out; the logo comes up and the game's music with it.
	if phase != Phase.VOICE:
		return  # skip() got here first, or the signal fired twice
	phase = Phase.CARD
	clock = 0.0
	card_up = true
	index = PANELS.size() - 1
	# Whatever was dissolving is finished with: the card draws over the last
	# panel, and half of the one before it showing through would be a smear.
	blend = 1.0
	# He has stopped talking, so nothing is being said over the logo.
	said = -1
	Music.cue(get_tree(), TRACK)
	queue_redraw()


func skip() -> void:
	## Straight to black and into the level. The music is cued here as well, so
	## a skipped opening leaves the game in exactly the state a watched one does
	## — the alternative is a level that starts silent because the cue lived in
	## a phase the player jumped over.
	if phase == Phase.OUT:
		return
	if is_instance_valid(voice):
		voice.stop()
	Music.cue(get_tree(), TRACK)
	blend = 1.0
	said = -1
	phase = Phase.OUT
	clock = 0.0
	queue_redraw()
	if test_mode:
		_hand_off()


func _hand_off() -> void:
	var game := Session.boot(get_tree(), level_id, true)
	if game == null:
		return
	# The level comes up out of the same black this went down to, using the
	# session's own level-swap fade rather than a second one layered here. The
	# rect is darkened directly as well: _advance_fade does not run until the
	# session's first physics tick, and without this the first drawn frame would
	# be the level at full brightness — a flash between two blacks.
	game.fade_phase = Session.Fade.IN
	game.fade_clock = 0.0
	if is_instance_valid(game.fade_rect):
		game.fade_rect.color.a = 1.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	# Three actions rather than one: `jump` is the space bar, which is what a
	# player presses at a cutscene, `confirm` is enter and `pause` is escape.
	if event.is_action_pressed("jump") or event.is_action_pressed("confirm") or event.is_action_pressed("pause"):
		skip()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		skip()


func card_alpha() -> float:
	## How far the title card has dissolved in over the last panel, 0 to 1.
	if not card_up:
		return 0.0
	if phase == Phase.CARD:
		return clampf(clock / CARD_IN, 0.0, 1.0)
	return 1.0


func black_alpha() -> float:
	## How black the screen is, 0 to 1. Public for the same reason session.gd's
	## fade_alpha is: a capture has to be able to assert the dip.
	##
	## Both ends come through here rather than one of them being a separate
	## layer, which is why _draw puts this last: whatever is under it — a panel,
	## the title card, the skip hint — is covered by the same rect on the way in
	## and on the way out, and a skip during the opening fade cannot leave the
	## hint burning on a black screen.
	if phase == Phase.OUT:
		return clampf(clock / CARD_OUT, 0.0, 1.0)
	# The way in. `shown` is wall time rather than stream position on purpose:
	# the fade is the screen arriving, and it should not stall on a machine
	# where the audio device takes a moment to start.
	return clampf(1.0 - shown / OPEN_IN, 0.0, 1.0)


func hint_alpha() -> float:
	if phase != Phase.VOICE:
		return 0.0
	return clampf(1.0 - (shown - HINT_SHOWN) / HINT_FADE, 0.0, 1.0)


func _draw() -> void:
	var frame := Rect2(Vector2.ZERO, DESIGN)
	# One stack, drawn the same way in every phase: the panel, the card over it
	# while it dissolves in, then the black over both. Which of them are visible
	# is left to the three alphas, so a skip from any point draws correctly
	# without a branch per phase.
	# The panel under this one is still on screen while a cue with a `fade`
	# crosses. Drawn as two full-frame blits rather than a shader or a second
	# Control: both are opaque and viewport-sized, so the top one at `blend`
	# over the bottom one is the whole dissolve.
	if blend < 1.0 and index > 0:
		draw_texture_rect(PANELS[index - 1]["tex"], frame, false)
		draw_texture_rect(PANELS[index]["tex"], frame, false,
						  Color(1.0, 1.0, 1.0, blend))
	else:
		draw_texture_rect(PANELS[index]["tex"], frame, false)
	var card := card_alpha()
	if card > 0.0:
		draw_texture_rect(TITLE_CARD, frame, false, Color(1.0, 1.0, 1.0, card))
	var hint := hint_alpha()
	if hint > 0.0:
		var font := ThemeDB.fallback_font
		var text := "SPACE: Skip"
		# Shadowed, like the title's hint: this sits over sky in one panel and
		# cliff in the next, and flat text is lost on the second.
		draw_string(font, Vector2(1.0, 523.0), text, HORIZONTAL_ALIGNMENT_CENTER,
					DESIGN.x, 15, Color(0.0, 0.0, 0.0, 0.7 * hint))
		draw_string(font, Vector2(0.0, 522.0), text, HORIZONTAL_ALIGNMENT_CENTER,
					DESIGN.x, 15, Color(0.95, 0.97, 0.98, hint))
	if said >= 0 and said_alpha > 0.0:
		_draw_caption(str(captions()[said]["text"]), said_alpha)
	var black := black_alpha()
	if black > 0.0:
		draw_rect(frame, Color(0.0, 0.0, 0.0, black))


func _draw_caption(text: String, alpha: float) -> void:
	## Bottom-centred, wrapped, on a scrim. The scrim is not decoration: these
	## sit over bright cloud in one panel and dark cliff in the next, and a
	## shadowed outline alone loses the thin strokes against the clouds.
	var font := ThemeDB.fallback_font
	var block := font.get_multiline_string_size(
		text, HORIZONTAL_ALIGNMENT_CENTER, CAPTION_WIDTH, CAPTION_SIZE)
	var left := (DESIGN.x - CAPTION_WIDTH) * 0.5
	var top := CAPTION_BOTTOM - block.y
	# draw_multiline_string takes the baseline of the FIRST line, not its top.
	var baseline := top + font.get_ascent(CAPTION_SIZE)
	draw_rect(Rect2(Vector2(0.0, top - 9.0), Vector2(DESIGN.x, block.y + 17.0)),
			  Color(0.0, 0.0, 0.0, 0.44 * alpha))
	draw_multiline_string(font, Vector2(left + 1.0, baseline + 1.0), text,
						  HORIZONTAL_ALIGNMENT_CENTER, CAPTION_WIDTH,
						  CAPTION_SIZE, -1, Color(0.0, 0.0, 0.0, 0.75 * alpha))
	draw_multiline_string(font, Vector2(left, baseline), text,
						  HORIZONTAL_ALIGNMENT_CENTER, CAPTION_WIDTH,
						  CAPTION_SIZE, -1, Color(0.96, 0.97, 0.98, alpha))
