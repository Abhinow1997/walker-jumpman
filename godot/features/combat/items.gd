extends RefCounted
## Sprite geometry for the items cut out of the Little Fighter 2 items sheet.
##
## Loaded once from the file scripts/extract_lf2_items.py writes. Every item is
## originned at the point that should touch the ground — bottom centre — so
## placing one is just a world position, with no per-item fudge offsets.
##
## Regenerate with scripts/extract_lf2_items.py; never hand-edit items.json.

const PATH := "res://features/combat/art/items.json"
const ART := "res://features/combat/art/"

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var text := FileAccess.get_file_as_string(PATH)
		if text.is_empty():
			push_error("items: %s is missing. Run scripts/extract_lf2_items.py." % PATH)
			_data = {"items": {}}
		else:
			_data = JSON.parse_string(text)
	return _data

static func item(name: String) -> Dictionary:
	return data().get("items", {}).get(name, {})

static func cell(name: String) -> Vector2i:
	var c: Array = item(name).get("cell", [1, 1])
	return Vector2i(int(c[0]), int(c[1]))

static func pivot(name: String) -> Vector2:
	## Offset for a centred sprite that puts the item's ground point on the node
	## origin: half the cell, minus where the origin sits inside it.
	var c := cell(name)
	var o: Array = item(name).get("origin", [0, 0])
	return Vector2(float(c.x) / 2.0 - float(o[0]), float(c.y) / 2.0 - float(o[1]))

static func frames(name: String) -> int:
	return int(item(name).get("frames", 0))

## The whole strip, for callers that draw regions themselves rather than
## assigning a texture to a node. Null if the art is missing.
static func sheet(name: String) -> Texture2D:
	var spec := item(name)
	if spec.is_empty():
		return null
	var path: String = ART + str(spec.file)
	if not ResourceLoader.exists(path):
		push_warning("items: no art at %s (run scripts/extract_lf2_items.py, then --import)" % path)
		return null
	return load(path)

## Source rectangle of one frame inside that strip.
static func region(name: String, index: int) -> Rect2:
	var c := cell(name)
	return Rect2(clampi(index, 0, frames(name) - 1) * c.x, 0, c.x, c.y)

## One frame of an item strip as an AtlasTexture, or null if the art is missing.
static func frame(name: String, index: int) -> Texture2D:
	var spec := item(name)
	if spec.is_empty():
		return null
	var path: String = ART + str(spec.file)
	if not ResourceLoader.exists(path):
		push_warning("items: no art at %s (run scripts/extract_lf2_items.py, then --import)" % path)
		return null
	var c := cell(name)
	var atlas := AtlasTexture.new()
	atlas.atlas = load(path)
	atlas.region = Rect2(clampi(index, 0, frames(name) - 1) * c.x, 0, c.x, c.y)
	return atlas
