extends RefCounted
## The animation table, loaded once from the file the extractor writes.
##
## Gameplay and appearance both need this and must not disagree: the frame a
## punch lands on is the frame the hitbox opens. Keeping one parsed copy is what
## guarantees that. Nothing here knows about input, physics or drawing.
##
## Regenerate with scripts/extract_anti_davis.py; never hand-edit moves.json.

const PATH := "res://features/player/art/anti_davis/moves.json"

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var text := FileAccess.get_file_as_string(PATH)
		if text.is_empty():
			push_error("moveset: %s is missing. Run scripts/extract_anti_davis.py." % PATH)
			_data = {"animations": {}, "ball": {}, "cell": [1, 1], "origin": [0, 0]}
		else:
			_data = JSON.parse_string(text)
	return _data

static func animations() -> Dictionary:
	return data().get("animations", {})

static func has(key: String) -> bool:
	return animations().has(key)

static func animation(key: String) -> Dictionary:
	return animations().get(key, {})

static func frame_count(key: String) -> int:
	return animation(key).get("durations", []).size()

static func cell() -> Vector2i:
	var c: Array = data().get("cell", [1, 1])
	return Vector2i(int(c[0]), int(c[1]))

static func pivot() -> Vector2:
	## Where the texture must sit so the character's origin — feet, mid-body —
	## lands on the node origin, which is where the collider's feet are. An
	## AnimatedSprite2D with centered = true draws its centre at the node, so the
	## offset is simply centre minus origin. Scaling the node then pivots on the
	## feet, which is why squash and the turn cannot lift him off the ground.
	var c := cell()
	var o: Array = data().get("origin", [0, 0])
	return Vector2(float(c.x) / 2.0 - float(o[0]), float(c.y) / 2.0 - float(o[1]))

static func ball() -> Dictionary:
	return data().get("ball", {})

## Total run time of an animation, in seconds.
static func length(key: String) -> float:
	var total := 0.0
	for d in animation(key).get("durations", []):
		total += float(d)
	return total

## Which frame is showing `time` seconds into the animation. Returns the last
## frame once the clock runs past the end, so a non-looping move holds its
## recovery pose instead of snapping back to frame zero.
static func frame_at(key: String, time: float) -> int:
	var durations: Array = animation(key).get("durations", [])
	if durations.is_empty():
		return 0
	var clock := time
	for i in durations.size():
		clock -= float(durations[i])
		if clock < 0.0:
			return i
	return durations.size() - 1

## Where a held object sits on the given frame, in the character's own space
## with the origin at (0, 0) and +x forward, or null if the frame holds nothing.
##
## LF2 never draws a held object into a character frame — it draws the body and
## then stamps the object at this point. That is why the drink animation is
## empty-handed in the sheet, and why the bottle has to be put back here.
static func wpoint(key: String, frame: int):
	var all: Array = animation(key).get("wpoints", [])
	if frame < 0 or frame >= all.size():
		return null
	var p: Array = all[frame]
	if p.size() < 2:
		return null
	return Vector2(float(p[0]), float(p[1]))

## Hit boxes the given frame opens, as Rect2 in the character's own space with
## the origin at (0, 0) and +x forward. Empty for every locomotion frame.
static func hits(key: String, frame: int) -> Array:
	var all: Array = animation(key).get("hits", [])
	if frame < 0 or frame >= all.size():
		return []
	var out: Array = []
	for entry in all[frame]:
		var r: Array = entry["rect"]
		out.append({"rect": Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])),
					"damage": int(entry["damage"])})
	return out
