extends SceneTree
## Development tool: how loud each track actually comes out of the mixer.
##
## diag_battle_music.gd already showed that the battle track is cued, is
## playing, is not ducked and is at the same -12 dB the coast loop is at — so
## "not audible" is not a routing fault, and the next question is whether the
## samples reaching the bus are as loud as the other track's. This taps the
## Master bus and measures them under identical conditions.
##
##     <godot> --path godot --script tests/diag_music_levels.gd
##
## Run WITHOUT --headless: a dummy audio driver pushes no frames and every
## reading comes back as silence.
const Music = preload("res://game/music.gd")

## Tracks to weigh, in the order the fight uses them.
const TRACKS := ["magic_cliffs", "decisive_battle"]
## Seconds to let a track settle before measuring, and seconds to measure over.
const SETTLE := 1.2
const WINDOW := 2.0

var capture: AudioEffectCapture

func _initialize() -> void:
	call_deferred("run")

func wait(seconds: float) -> void:
	## Wall clock rather than a frame count, and NOT `left -= await
	## process_frame`: process_frame yields nothing, so that subtracts null and
	## the window closes on whatever frame the error happened to land on. The
	## two tracks came back with 512 and 2048 frames in them.
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame

func weigh(name: String) -> void:
	Music.cue(root.get_tree(), name)
	await wait(SETTLE)
	capture.clear_buffer()
	await wait(WINDOW)
	var frames: PackedVector2Array = capture.get_buffer(capture.get_frames_available())
	if frames.is_empty():
		print("%-18s  NO FRAMES CAPTURED" % name)
		return
	var peak := 0.0
	var sum := 0.0
	for frame in frames:
		var value: float = maxf(absf(frame.x), absf(frame.y))
		peak = maxf(peak, value)
		sum += value * value
	var rms: float = sqrt(sum / float(frames.size()))
	print("%-18s  %6d frames   peak %7.2f dBFS   rms %7.2f dBFS" % [
		name, frames.size(),
		linear_to_db(peak) if peak > 0.0 else -200.0,
		linear_to_db(rms) if rms > 0.0 else -200.0])

func run() -> void:
	# Tapped rather than inferred. get_bus_peak_volume_left_db reports what the
	# bus decided; this is the samples themselves.
	capture = AudioEffectCapture.new()
	capture.buffer_length = 4.0
	AudioServer.add_bus_effect(0, capture)
	await wait(0.3)
	for name in TRACKS:
		await weigh(str(name))
	print("both measured at Music.LEVEL_DB (%.1f dB), master at %.1f dB" % [
		Music.LEVEL_DB, AudioServer.get_bus_volume_db(0)])
	quit()
