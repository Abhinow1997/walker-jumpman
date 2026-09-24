extends SceneTree
## Where the voice actually speaks, in seconds. This is how the caption times in
## storyboard.gd were arrived at, and re-running it is how they get fixed when
## the recording is re-rendered — the alternative is timing eighteen lines by
## ear with a stopwatch.
##
## It plays a stream through a capture bus, sums its energy into 20 ms windows,
## and prints every run of sound with the gaps between them. A gap of 0.32 s or
## more counts as one line ending and the next beginning; anything shorter is a
## breath inside a line.
##
## USE THE VOICE-ONLY STEM, NOT THE MERGED MIX. The mix has a continuous bed
## under the voice and there is no silence in it to find — every window is above
## any threshold worth setting, and it reports one segment as long as the track.
## The stem and the mix are the same render (56.529 s against 56.568 s, which is
## encoder padding), so a boundary measured on one lands in the same place on
## the other.
##
## Copy the stem in first — it is not kept in the repository, being a working
## file rather than something the game loads:
##     cp "Assests/Storyboard/Scene-1.mp3" godot/audio/_stem_probe.mp3
##     <godot> --path godot --headless --import
##
## Then run it WITHOUT --headless, because the dummy mixer never fills a capture
## buffer, and expect it to take as long as the recording:
##     <godot> --path godot --script tests/diag_speech.gd
##
## Delete the stem afterwards. godot/audio/*.mp3 is tracked on purpose — see
## .gitignore — so one left behind would be committed.

const STEM := "res://audio/_stem_probe.mp3"
## Energy is summed into windows this long, and every time printed is a multiple
## of it. Short enough to place a word, long enough not to chop one in half.
const WINDOW := 0.02
## A gap shorter than this is a breath inside a line, not a line ending.
const GAP := 0.16
## Speech has to hold for at least this long to count, so a click or a lip
## noise does not open a segment of its own.
const MIN_RUN := 0.08

var player: AudioStreamPlayer
var capture: AudioEffectCapture
var rms: Array[float] = []
var carry: float = 0.0
var carried: int = 0
var per_window: int = 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var stream: AudioStream = load(STEM)
	if stream == null:
		print("no stem at %s" % STEM)
		quit()
		return
	per_window = int(AudioServer.get_mix_rate() * WINDOW)

	var bus := AudioServer.bus_count
	AudioServer.add_bus(bus)
	AudioServer.set_bus_name(bus, "Probe")
	capture = AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(bus, capture)
	AudioServer.set_bus_mute(bus, true)

	player = AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "Probe"
	root.add_child(player)
	player.play()
	print("measuring %.3f s at %d Hz, %d samples per window"
		  % [stream.get_length(), AudioServer.get_mix_rate(), per_window])

	while player.playing:
		await process_frame
		_drain()
	_drain()
	_report(stream.get_length())
	quit()

func _drain() -> void:
	var available := capture.get_frames_available()
	if available <= 0:
		return
	var frames := capture.get_buffer(available)
	for frame in frames:
		# Mono sum: the stem is a single voice and the two channels carry the
		# same thing, so either one alone would only halve the numbers.
		var level := (absf(frame.x) + absf(frame.y)) * 0.5
		carry += level * level
		carried += 1
		if carried >= per_window:
			rms.append(sqrt(carry / float(carried)))
			carry = 0.0
			carried = 0

func _report(length: float) -> void:
	if rms.is_empty():
		print("NOTHING CAPTURED — run without --headless")
		return
	var loudest := 0.0
	for value in rms:
		loudest = maxf(loudest, value)
	# Forty decibels under the loudest moment. Well above the stem's own floor
	# and well under any spoken syllable.
	var floor_level := loudest * 0.01
	print("windows %d, peak %.5f, threshold %.5f" % [rms.size(), loudest, floor_level])

	var gap_windows := int(GAP / WINDOW)
	var min_windows := int(MIN_RUN / WINDOW)
	var segments := []
	var start := -1
	var quiet := 0
	for i in range(rms.size()):
		if rms[i] >= floor_level:
			if start < 0:
				start = i
			quiet = 0
		elif start >= 0:
			quiet += 1
			if quiet >= gap_windows:
				var stop := i - quiet
				if stop - start >= min_windows:
					segments.append([start, stop])
				start = -1
				quiet = 0
	if start >= 0 and rms.size() - start >= min_windows:
		segments.append([start, rms.size() - 1])

	print("--- %d segments ---" % segments.size())
	var previous := 0.0
	for s in segments:
		var from: float = s[0] * WINDOW
		var to: float = s[1] * WINDOW
		var peak := 0.0
		for i in range(s[0], s[1] + 1):
			peak = maxf(peak, rms[i])
		print("%6.2f -> %6.2f  (%4.2fs, gap %4.2fs before, peak %.4f)"
			  % [from, to, to - from, from - previous, peak])
		if to - from > 3.5:
			# Long enough to hold more than one line. Print its shape so the
			# dips that did not open a gap of their own can still be seen.
			var shape := ""
			var step := int(0.25 / WINDOW)
			var at_window: int = s[0]
			while at_window < int(s[1]):
				var loud := 0.0
				for j in range(at_window, mini(at_window + step, int(s[1]) + 1)):
					loud = maxf(loud, rms[j])
				shape += "%d" % clampi(int(loud / loudest * 9.0), 0, 9)
				at_window += step
			print("        shape @0.25s: %s" % shape)
		previous = to
	print("--- tail %.2f s ---" % (length - previous))
