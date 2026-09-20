extends SceneTree
## Retimes ui/captions.json by ear, which is the only thing that actually works.
##
## tests/diag_speech.gd can measure where sound starts and stops in the stem,
## and that is genuinely useful — but it cannot tell which words are inside a
## run of sound, and pairing a line list against a gap list by eye produces
## captions that are individually plausible and collectively wrong. This asks
## the one question a measurement cannot answer, of the one person who can hear
## the recording.
##
## Run it WITHOUT --headless, from walker-jumpman/:
##     <godot> --path godot --script tests/time_captions.gd
##
## The recording plays once, from the top. The line you are waiting for is on
## screen; press SPACE the moment you hear it begin. BACKSPACE undoes the last
## mark and rewinds a little so you can take it again, ENTER writes the file
## early, and ESCAPE quits without saving. It writes ui/captions.json in place,
## keeping the words and replacing only the numbers, so nothing else has to
## change afterwards — the game reads that file directly.
##
## Marks are taken on the same clock the game cuts panels on, latency included,
## so a line marked here lands where it was marked.

const Storyboard = preload("res://ui/storyboard.gd")
const FILE := "res://ui/captions.json"

## A press is taken this much earlier than it happened. Nobody presses a key on
## the syllable; the hand is reacting to something already begun, and a caption
## that arrives a fifth of a second early reads as on time while one that
## arrives late reads as broken.
const REACTION := 0.20
## How far BACKSPACE rewinds past the mark it just took, so the line can be
## heard coming again rather than being already underway.
const REWIND := 2.5
## Counted down before the recording starts. The first line is four hundredths
## of a second in, so without this there is nothing to react to it with.
const LEAD_IN := 3.0
## The shortest believable gap between two spoken lines. A press closer than
## this to the last one is refused: nobody delivers two lines a fifth of a
## second apart, so it is somebody trying to catch up by pressing faster, and
## accepting it buries eight good lines under a second of noise. It happened.
const MIN_GAP := 0.45

var player: AudioStreamPlayer
var lines: Array = []
var marks: Array = []
var index: int = 0
var held := {}
## Frames left to keep the refusal notice on screen.
var refused := 0
var layer: CanvasLayer
var clock_label: Label
var now_label: Label
var next_label: Label
var foot_label: Label


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	lines = Storyboard.captions()
	if lines.is_empty():
		print("no captions in %s" % FILE)
		quit()
		return

	_build_screen()
	player = AudioStreamPlayer.new()
	player.stream = load(Storyboard.VOICE)
	root.add_child(player)

	# Nothing plays until a key press has actually been seen. The commonest way
	# to lose a take is the window not holding focus — this script polls the
	# keyboard, so an unfocused window silently records nothing — and starting
	# the recording before focus is proven spends the whole fifty-seven seconds
	# finding that out.
	DisplayServer.window_move_to_foreground()
	clock_label.text = "%.1f s of recording, %d lines" % [
		player.stream.get_length(), lines.size()]
	now_label.text = "Click this window, then press SPACE to begin."
	next_label.text = "first line:   " + _text(0)
	foot_label.text = "ESC quits"
	while true:
		await process_frame
		if _pressed(KEY_ESCAPE):
			print("quit before starting")
			quit()
			return
		if _pressed(KEY_SPACE):
			break
	# A countdown, because the first line starts four hundredths of a second in.
	# Without it the recording begins on the same key press that proves focus,
	# there is no time at all to catch line one, and a take that misses the
	# first line is a take where every later press is against the wrong line —
	# accurate marks, all of them one or two lines out. That is exactly how the
	# first real session went.
	var began := Time.get_ticks_msec()
	while true:
		await process_frame
		var left := LEAD_IN - float(Time.get_ticks_msec() - began) / 1000.0
		if left <= 0.0:
			break
		now_label.text = "%d" % int(ceil(left))
		next_label.text = "first line:   " + _text(0)
		foot_label.text = "mark it the moment you hear it"
	player.play()
	print("%d lines to mark. SPACE on each one as it begins." % lines.size())

	while player.playing and index < lines.size():
		await process_frame
		if _pressed(KEY_ESCAPE):
			print("quit without saving")
			quit()
			return
		if _pressed(KEY_ENTER) or _pressed(KEY_KP_ENTER):
			break
		if _pressed(KEY_BACKSPACE):
			_undo()
		if _pressed(KEY_SPACE):
			_mark()
		_refresh()

	_write()
	quit()


func at() -> float:
	## The same clock storyboard.gd cuts on, so a mark taken here means the same
	## thing there. Without the two AudioServer terms a mark drifts by whatever
	## the output buffer happens to be.
	if not player.playing:
		return player.stream.get_length()
	return maxf(0.0, player.get_playback_position()
			+ AudioServer.get_time_since_last_mix()
			- AudioServer.get_output_latency())


func _pressed(key: int) -> bool:
	## Edge, not state: a SceneTree script has no _input, so the keyboard is
	## polled and the press has to be de-repeated here.
	var down := Input.is_physical_key_pressed(key)
	var was: bool = held.get(key, false)
	held[key] = down
	return down and not was


func _mark() -> void:
	var when := maxf(0.0, at() - REACTION)
	if not marks.is_empty() and when - float(marks[-1]) < MIN_GAP:
		# Refused rather than dropped quietly: the screen says so, because a
		# press that does nothing and does not explain itself is why somebody
		# presses again harder.
		refused = 12
		return
	marks.append(when)
	index += 1


func _undo() -> void:
	if marks.is_empty():
		return
	var back: float = marks[-1]
	marks.remove_at(marks.size() - 1)
	index -= 1
	player.seek(maxf(0.0, back - REWIND))


func _text(i: int) -> String:
	if i < 0 or i >= lines.size():
		return ""
	return str(lines[i].get("text", ""))


func _build_screen() -> void:
	layer = CanvasLayer.new()
	root.add_child(layer)
	var back := ColorRect.new()
	back.color = Color(0.06, 0.07, 0.09)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(back)
	clock_label = _label(30.0, 22, Color(0.55, 0.60, 0.66))
	now_label = _label(150.0, 30, Color(0.98, 0.99, 1.0))
	next_label = _label(300.0, 20, Color(0.45, 0.50, 0.56))
	foot_label = _label(470.0, 17, Color(0.31, 0.85, 0.91))


func _label(y: float, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.position = Vector2(60.0, y)
	label.size = Vector2(840.0, 120.0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	layer.add_child(label)
	return label


func _refresh() -> void:
	var was := ""
	if not marks.is_empty():
		was = "   last mark %.2f s" % marks[-1]
	clock_label.text = "%.2f s        line %d of %d%s" % [at(), index + 1, lines.size(), was]
	now_label.text = _text(index)
	var upcoming := _text(index + 1)
	next_label.text = ("next:  " + upcoming) if upcoming != "" else "last line"
	if refused > 0:
		refused -= 1
		foot_label.text = "TOO SOON after the last mark — that press was not taken"
	else:
		foot_label.text = "SPACE mark    BACKSPACE undo and rewind    ENTER save now    ESC quit"


func _write() -> void:
	## Keeps the words and the note, replaces the numbers. `until` is the next
	## line's mark, so one caption is always on screen and there is no second
	## key press to get wrong — hand-edit a gap in afterwards if a line should
	## clear before the next one starts.
	if marks.is_empty():
		print("nothing marked; %s left alone" % FILE)
		return
	var length: float = player.stream.get_length()
	var out: Array = []
	for i in range(lines.size()):
		var line: Dictionary = (lines[i] as Dictionary).duplicate()
		if i < marks.size():
			line["at"] = snappedf(marks[i], 0.01)
			# Clamped, not just snapped: the last line's `until` is the end of
			# the recording, and snapping 56.568 to hundredths rounds it UP to
			# 56.57 — two thousandths past a track that is only 56.568 long.
			# Small enough to look like nothing and enough to fail the check in
			# diag_audio, which in a debug build hangs the headless run.
			var ends: float = marks[i + 1] if i + 1 < marks.size() else length
			line["until"] = minf(snappedf(ends, 0.01), length)
		out.append(line)
	var existing := FileAccess.open(FILE, FileAccess.READ)
	var note := ""
	if existing != null:
		var was = JSON.parse_string(existing.get_as_text())
		existing.close()
		if typeof(was) == TYPE_DICTIONARY:
			note = str(was.get("_note", ""))
	var file := FileAccess.open(FILE, FileAccess.WRITE)
	if file == null:
		print("could not write %s" % FILE)
		return
	file.store_string(JSON.stringify({"_note": note, "lines": out}, " ") + "\n")
	file.close()
	# A take that runs to the very end is the signature of falling behind: the
	# last line was marked against the second to last line's audio, and so on
	# back to wherever the slip began. Cheap to spot, expensive to miss.
	var last: float = marks[-1]
	if last > length - 2.0:
		print("WARNING: the last mark is at %.2f s of %.2f s. A take usually ends"
			  % [last, length])
		print("         well before the recording does — this one probably fell")
		print("         a line behind somewhere. Worth running again.")
	print("wrote %d of %d marks to %s" % [marks.size(), lines.size(), FILE])
	for i in range(mini(marks.size(), lines.size())):
		print("  %6.2f  %s" % [marks[i], _text(i)])
	if marks.size() < lines.size():
		print("  (%d lines past the last mark kept their old times)"
			  % (lines.size() - marks.size()))
