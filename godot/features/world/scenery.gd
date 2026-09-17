extends Node2D
## Draws a themed world: parallax background, terrain, and set dressing.
##
## The terrain is NOT authored. It is generated from the level's own `solids`,
## the same rectangles the player collides with and the validator measures, so
## the art and the collision cannot drift apart — a cliff is never drawn where
## you cannot stand, and never missing where you can. Levels place set dressing
## explicitly, because a tree or an archway is a decision rather than a
## consequence of the geometry.
##
## A level without a `theme` is not drawn here at all; session.gd keeps its own
## procedural greybox for those. First Steps still looks exactly as it did.
##
## Regenerate the art with scripts/extract_magic_cliffs.py, then --import.

const ART := "res://features/world/art/"

var game: Node2D
var theme: String = ""

var data: Dictionary = {}
var pieces: Dictionary = {}      ## name -> Texture2D
var scale_art: float = 1.0
var fill: Color = Color("193133")
var backdrop: Color = Color("6dd6d6")
## The water below the surface band, taken from the sea art's own bottom row.
var deep_water: Color = Color("4e9e96")

## The horizon travels with the camera one for one, so the waterline keeps the
## screen position it has at the spawn wherever you are in the level.
##
## Nailing it to a world y works only while a level is flat: a course that
## descends 700 units spends its whole lower half under a horizon set at the
## height of its first cliff, and the player reads as walking on the seabed. At
## less than 1.0 the sea still creeps up on him; at 1.0 it stays put.
const SEA_DRIFT := 1.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	## Lets a cliff body be tiled in one draw rather than a loop per row.
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	z_index = -10
	_load(theme)
	_load_backdrop()
	if is_instance_valid(game):
		var ground: Dictionary = game.level.get("ground", {})
		lean = float(ground.get("lean", TAPER_RATE))
		lean_min_width = float(ground.get("lean_min_width", TAPER_MIN_WIDTH))
		brk_step = maxf(float(ground.get("break_step", EDGE_STEP)), 4.0)
		brk_jitter = float(ground.get("break_jitter", EDGE_JITTER))
		body_alpha = float(ground.get("texture", BODY_TEXTURE))
		edge_dx_left = float(ground.get("edge_left_x", 0.0))
		edge_dx_right = float(ground.get("edge_right_x", 0.0))
		profiles = ground.get("profiles", {})

func _load(name: String) -> void:
	if name == "":
		return
	var path := "%s%s/%s.json" % [ART, name, name]
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_warning("scenery: %s is missing. Run its extractor, then --import." % path)
		return
	data = JSON.parse_string(text)
	if data == null:
		data = {}
		return
	scale_art = float(data.get("render_scale", 1.0))
	fill = Color(str(data.get("fill", "#193133")))
	for key in data.get("pieces", {}):
		var file: String = "%s%s/%s" % [ART, name, data.pieces[key].file]
		if not ResourceLoader.exists(file):
			push_warning("scenery: no art at %s (run the extractor, then --import)" % file)
			continue
		pieces[key] = load(file)
	for layer in data.get("background", []):
		var file: String = "%s%s/%s" % [ART, name, layer.file]
		if ResourceLoader.exists(file):
			pieces[str(layer.file)] = load(file)
	# The sky's own top pixel, so the band above the artwork is never a guess.
	if pieces.has("sky.png"):
		var img: Image = pieces["sky.png"].get_image()
		backdrop = img.get_pixel(0, 0)
	if pieces.has("sea.png"):
		var sea: Image = pieces["sea.png"].get_image()
		deep_water = sea.get_pixel(0, sea.get_height() - 1)

func size_of(key: String) -> Vector2:
	var spec: Dictionary = data.get("pieces", {}).get(key, {})
	var s: Array = spec.get("size", [1, 1])
	return Vector2(float(s[0]), float(s[1])) * scale_art

## Transparent margin on the left and right of a piece, in world units. An edge
## column aligned by its rect rather than its art leaves that much flat fill
## showing along the face it is supposed to be the edge of.
func bleed_of(key: String) -> Vector2:
	var b: Array = data.get("pieces", {}).get(key, {}).get("bleed", [0, 0])
	return Vector2(float(b[0]), float(b[1])) * scale_art

## How far below a piece's top edge the surface you stand on is.
func surface_of(key: String) -> float:
	return float(data.get("pieces", {}).get(key, {}).get("surface", 0)) * scale_art

func _blit(key: String, at: Vector2) -> void:
	if pieces.has(key):
		draw_texture_rect(pieces[key], Rect2(at, size_of(key)), false)

## A horizontal run of one piece, clipped to `width` so the last one does not
## overhang. Every terrain edge in the game is one of these.
func _run(key: String, at: Vector2, width: float) -> void:
	if not pieces.has(key) or width <= 0.0:
		return
	var tex: Texture2D = pieces[key]
	var cell := size_of(key)
	var source := Vector2(tex.get_width(), tex.get_height())
	var x := 0.0
	while x < width:
		var span: float = minf(cell.x, width - x)
		var part: float = span / cell.x
		draw_texture_rect_region(tex, Rect2(at + Vector2(x, 0.0), Vector2(span, cell.y)),
								 Rect2(Vector2.ZERO, Vector2(source.x * part, source.y)))
		x += cell.x

## The x range a demo image covers. Terrain and set dressing inside it are the
## image's job and are skipped; outside it the level is procedural as ever.
var backdrop_span := Vector2(1.0, -1.0)

func _draw() -> void:
	if data.is_empty() or not is_instance_valid(game) or game.level.is_empty():
		return
	_background()
	_scene_backdrop()
	_terrain()          # cliffs, named pieces and bridges, generated from the solids
	_decor()            # trees, islands and set dressing placed by the level

func _load_backdrop() -> void:
	if not is_instance_valid(game):
		return
	var key: String = str(game.level.get("backdrop", {}).get("file", ""))
	if key == "" or pieces.has(key):
		return
	var f: String = "%s%s/%s" % [ART, theme, key]
	if ResourceLoader.exists(f):
		pieces[key] = load(f)

## A scene photographed straight from the art pack, laid into the world so its
## ground lines up with the collision under it: exact by construction, where
## rebuilding it tile by tile drifts. The price is a background baked into the
## picture rather than parallaxed, so a level uses this only for a stretch and
## goes procedural either side. Below the image the rock runs on in the fill
## colour to the level's depth; the sky above already matches.
func _scene_backdrop() -> void:
	var bd: Dictionary = game.level.get("backdrop", {})
	var key: String = str(bd.get("file", ""))
	if not pieces.has(key):
		return
	var tex: Texture2D = pieces[key]
	var s: float = float(bd.get("scale", scale_art))
	var at := Vector2(float(bd.get("x", 0.0)), float(bd.get("y", 0.0)))
	var full := Vector2(tex.get_width(), tex.get_height()) * s
	var right: float = float(bd.get("clip_right", at.x + full.x))
	var wide: float = clampf(right - at.x, 0.0, full.x)
	# The deep rock below the image, in the flat fill the pack's own ground
	# interiors are: a photographed cliff body is one colour, so running on in
	# that same colour is what makes the join invisible. This used to tile
	# body_stone over it, which put a visible grid under the picture instead.
	var below := PackedVector2Array([
		Vector2(at.x, at.y + full.y), Vector2(at.x + wide, at.y + full.y),
		Vector2(at.x + wide, at.y + full.y + 2200.0), Vector2(at.x, at.y + full.y + 2200.0)])
	draw_colored_polygon(below, fill)
	draw_texture_rect_region(tex, Rect2(at, Vector2(wide, full.y)),
							 Rect2(Vector2.ZERO, Vector2(wide / s, tex.get_height())))
	backdrop_span = Vector2(at.x, right)

# --- background --------------------------------------------------------------

func _background() -> void:
	## Straight off the viewport rather than the session's own constant: the
	## camera has zoom 1, so the visible world is exactly one viewport across.
	var half: Vector2 = get_viewport_rect().size * 0.5
	var view := Rect2(game.camera.position - half, half * 2.0)
	# Generous, because the camera clamps but this must never show its own edge.
	draw_rect(Rect2(view.position - half, view.size + half * 2.0), backdrop)
	var anchor: float = float(game.level.get("horizon", _floor_y()))
	var home: float = clampf(float(game.level.spawn[1]), game.view_top, game.view_bottom)
	var horizon: float = anchor + (game.camera.position.y - home) * SEA_DRIFT
	for layer in data.get("background", []):
		var key: String = str(layer.file)
		if not pieces.has(key):
			continue
		var tex: Texture2D = pieces[key]
		var cell := Vector2(float(layer.size[0]), float(layer.size[1])) * scale_art
		# Parallax: a layer at factor f slides f as fast as the camera, so in
		# world space its origin creeps along at (1 - f) of the camera's own
		# travel. At f = 0 it is nailed to the view; at 1 it would be scenery.
		var factor := float(layer.get("factor", 0.0))
		var origin := view.position.x * (1.0 - factor)
		var start: float = origin - fposmod(origin - view.position.x, cell.x) - cell.x
		var top := horizon - cell.y
		if key == "sea.png":
			# One tiled row at the waterline, then flat water below it. Repeating
			# the art downward put a seam every 72 units: it is a surface band
			# with a gradient, and was never meant to tile vertically.
			var x1 := start
			while x1 < view.end.x + cell.x:
				draw_texture_rect(tex, Rect2(Vector2(x1, horizon), cell), false)
				x1 += cell.x
			var deep := horizon + cell.y
			if deep < view.end.y + half.y:
				draw_rect(Rect2(view.position.x - half.x, deep,
								view.size.x + half.x * 2.0,
								view.end.y + half.y - deep), deep_water)
			continue
		var x2 := start
		while x2 < view.end.x + cell.x:
			draw_texture_rect(tex, Rect2(Vector2(x2, top), cell), false)
			x2 += cell.x

func _floor_y() -> float:
	var solids: Array = game.level.get("solids", [])
	if solids.is_empty():
		return 0.0
	var lowest: float = float(solids[0][1])
	for s in solids:
		lowest = maxf(lowest, float(s[1]))
	return lowest

# --- terrain -----------------------------------------------------------------

## A cap is only drawn when the platform is wider than one: on anything smaller
## the two ends would overlap into mush, and a small ledge reads better as a
## plain grassed block anyway.
const CAP_MIN_TILES := 6.0

## How strongly the cave rock shows through a placed rock mass - an archway leg
## or a hanging stalactite, which are small enough that one tile reads as rock.
## Cliff bodies are NOT textured: at that size the same tile read as wallpaper.
const BODY_TEXTURE := 0.5

func _terrain() -> void:
	## A solid may name the art to wear as an optional fifth value:
	##   [x, y, w, h]                 cliff: grass over a filled body
	##   [x, y, w, h, "island_small"] that piece, centred, sitting on the top edge
	##   [x, y, w, h, "bridge"]       planking, with an anchor post at each end
	## Whatever it wears, the rectangle is still the collision and still what the
	## validator measures, so the art cannot end up somewhere you cannot stand.
	for entry in game.level.solids:
		var r := Rect2(float(entry[0]), float(entry[1]), float(entry[2]), float(entry[3]))
		if r.position.x >= backdrop_span.x and r.position.x < backdrop_span.y:
			continue  # a demo image draws this stretch; the rect is collision only
		var wears: String = str(entry[4]) if entry.size() > 4 else ""
		if wears == "bridge":
			_bridge(r)
		elif pieces.has(wears):
			_blit(wears, Vector2(r.position.x + (r.size.x - size_of(wears).x) / 2.0,
								 r.position.y - surface_of(wears)))
		else:
			_cliff(r)

## Cliff faces lean inward from the moment the grass ends, the way the pack draws
## them. A straight vertical wall reads as a cut; land that tore off leaves a
## slope. The lean runs this deep and takes this much off each side, then the
## face drops straight so a cliff 1600 units deep does not taper away to nothing.
##
## There is deliberately no vertical section first. One was added to stop the
## square rock caps notching where they met the leaning column, and it put a hard
## 74-unit box edge at the top of every face - the caps went instead.
## Horizontal travel per unit of depth. The lean does NOT stop: it ran for a
## fixed 132 units before and then dropped straight, which put a dead vertical
## line down the lower half of every face - the same box, lower down.
const TAPER_RATE := 0.55
## The lean never stops. A cliff is a wedge that closes to a point and simply
## ends there - torn land, which is what this level is about - and that point is
## always below what the camera can see. Leaving a vertical stem instead was the
## last box: the face slanted, then dropped dead straight for the rest of its
## depth. Nothing is drawn below the point; the sea shows through.
##
## Only cliffs wide enough to stay open through the 270 the camera shows below
## his feet may lean; anything narrower stays square rather than closing in view.
const TAPER_MIN_WIDTH := 336.0
## How tall each break in the face is, and how far in or out it may wander. Two
## tiles of each: enough that the edge reads as broken rock rather than a ruled
## line, small enough that the face still obviously leans.
const EDGE_STEP := 24.0
const EDGE_JITTER := 24.0

## Every number above is a DEFAULT. A level may override any of them under a
## `ground` block, which is what lets tools/level-editor.html tune the shape of
## the rock with sliders instead of someone editing this file and rebuilding.
## A level that says nothing gets exactly the look it has now.
var lean := TAPER_RATE
var lean_min_width := TAPER_MIN_WIDTH
var brk_step := EDGE_STEP
var brk_jitter := EDGE_JITTER
var body_alpha := BODY_TEXTURE
## Nudges for the rock columns, so the edge art can be aligned by eye in the
## editor on top of the automatic bleed correction below. Positive moves right.
var edge_dx_left := 0.0
var edge_dx_right := 0.0
## Hand-sculpted outlines, keyed by the cliff's own left x. A cliff that has one
## ignores the lean and the breaks entirely and follows the drawn edge instead;
## everything without one keeps the procedural shape. Written by the editor.
var profiles: Dictionary = {}
## Depth between one sculpting handle and the next, when a level does not say.
const PROFILE_STEP := 48.0
## How tall each step of a leaning column is. One tile per step made stairs a
## whole 58 units deep; one grid tile keeps the slope reading as a slope while
## still stepping, which is how pixel art draws a diagonal.
const COLUMN_STEP := 12.0

func _cliff(r: Rect2) -> void:
	var wide: bool = r.size.x >= CAP_MIN_TILES * size_of("grass_strip").x / 3.0
	# Where the two faces would meet, and how far down the wedge is drawn: its
	# own point, or the bottom of the rectangle, whichever comes first.
	var sculpted: bool = profiles.has(str(int(round(r.position.x))))
	var leans: bool = wide and (sculpted or r.size.x >= lean_min_width)
	var closes: float = (r.size.x * 0.5) / maxf(lean, 0.01) if leans else 0.0
	# A drawn cliff runs its whole height: its shape is the handles, not a wedge
	# that has to stop before the two faces meet.
	var depth: float = r.size.y if sculpted else (minf(r.size.y, closes) if leans else r.size.y)
	var most: float = (r.size.x * 0.5) if sculpted else lean * depth
	var bottom: float = r.position.y + depth

	var shape := _silhouette(r, bottom, most if leans else 0.0)
	draw_colored_polygon(shape, fill)

	# Nothing over the fill. The pack's cliff interiors are one flat colour, and
	# body_stone.png is a single fin shape, so UV-tiling it across the silhouette
	# turned one accent into wallpaper - the grid you saw before you saw any rock.
	# Fins inside a body are set dressing a level places as `body_stone` decor,
	# where the author chooses how many and where; see _decor.

	# The rock first, then the grass over its top: turf grows across the lip, and
	# drawing the column last put bare rock on top of the grass at both corners.
	# ground_left and ground_right are NOT drawn: they are square blocks 69 and 33
	# wide, and any face that began with one began with a box.
	if wide:
		_column("edge_left", r, r.position.x, bottom, most if leans else 0.0)
		_column("edge_right", r, r.end.x, bottom, -most if leans else 0.0)
	_grass(r, most if leans else 0.0)

## Where one face sits at this depth: the steady lean, plus a break that wanders
## in and out. A face that falls in a perfectly straight line reads as cut, not
## as rock that gave way, however steeply it leans.
##
## The break is a hash of the cliff's own left edge and the step number, so it is
## identical on every frame and every run - nothing shimmers - while no two
## cliffs and no two depths break the same way. It eases in over the first two
## steps so the top corners still meet the grass square, and is clamped so the
## face never wanders back outside the rectangle it belongs to.
func _face_x(r: Rect2, side_x: float, y: float, pull: float) -> float:
	var depth: float = maxf(y - r.position.y, 0.0)
	var drawn: float = _sculpted(r, depth, pull >= 0.0)
	if not is_nan(drawn):
		# A drawn edge wins outright. The handles are the shape; the lean and the
		# breaks are only what a cliff falls back on when nobody has drawn one.
		return side_x + (drawn if pull >= 0.0 else -drawn)
	if is_zero_approx(pull):
		return side_x
	var slide: float = minf(self.lean * depth, absf(pull))
	var step: float = floorf(depth / brk_step)
	var ease: float = clampf(depth / (brk_step * 2.0), 0.0, 1.0)
	var wobble: float = (_break(r.position.x + side_x, step) - 0.5) * 2.0 * brk_jitter
	return side_x + signf(pull) * clampf(slide + wobble * ease, 0.0, absf(pull))

## How far in the drawn edge is at this depth, or NAN if this cliff has none.
## Held flat past the last handle rather than snapping back to the rectangle.
func _sculpted(r: Rect2, depth: float, is_left: bool) -> float:
	var prof: Dictionary = profiles.get(str(int(round(r.position.x))), {})
	if prof.is_empty():
		return NAN
	var side: Array = prof.get("left" if is_left else "right", [])
	if side.is_empty():
		return NAN
	var step: float = maxf(float(prof.get("step", PROFILE_STEP)), 4.0)
	var at: int = clampi(int(floor(depth / step)), 0, side.size() - 1)
	return float(side[at])

func _break(a: float, b: float) -> float:
	## Deterministic, the same way player_sprite.gd keeps its dust reproducible.
	return absf(fmod(sin(a * 0.1237 + b * 78.233) * 43758.5453, 1.0))

func _silhouette(r: Rect2, bottom: float, lean: float) -> PackedVector2Array:
	## Built as a staircase, two vertices per break, rather than one vertex per
	## break joined by a diagonal. The rock columns hold each break for its whole
	## depth, so a polygon that sloped smoothly between them drifted off the rock
	## by half a step in the middle of every band.
	var lefts := PackedVector2Array()
	var rights := PackedVector2Array()
	var y: float = r.position.y
	while true:
		var lx: float = _face_x(r, r.position.x, y, lean)
		var rx: float = _face_x(r, r.end.x, y, -lean)
		var next: float = minf(y + brk_step, bottom)
		# The width test closes the wedge once the two faces have converged, so it
		# only applies once a band exists. Without `not lefts.is_empty()` it also
		# fired on the FIRST pass for any cliff narrower than one break step - a
		# 12-wide ledge against break_step 48 - which returned a single point, drew
		# no rock under its grass, and logged "pointcount < 3" every frame.
		if y >= bottom or (not lefts.is_empty() and rx - lx <= brk_step):
			var mid: float = (lx + rx) * 0.5
			lefts.append(Vector2(mid, minf(y, bottom)))
			break
		lefts.append(Vector2(lx, y))
		lefts.append(Vector2(lx, next))
		rights.append(Vector2(rx, y))
		rights.append(Vector2(rx, next))
		y = next
	var shape := PackedVector2Array()
	for point in rights:
		shape.append(point)
	for i in range(lefts.size() - 1, -1, -1):
		shape.append(lefts[i])
	return shape

func _grass(r: Rect2, lean: float) -> void:
	## The turf along the top, as a shape that narrows with the face rather than
	## a full-width run of tiles. At the rate the face leans it had come in 14
	## units by the strip's own bottom edge, so a rectangular strip overhung the
	## wedge and left a hard square block at each top corner - the last straight
	## line on the cliff.
	if not pieces.has("grass_strip"):
		return
	var cell := size_of("grass_strip")
	var top: float = r.position.y - surface_of("grass_strip")
	var foot: float = top + cell.y
	var shape := PackedVector2Array([
		Vector2(r.position.x, top), Vector2(r.end.x, top),
		Vector2(_face_x(r, r.end.x, foot, -lean), foot),
		Vector2(_face_x(r, r.position.x, foot, lean), foot)])
	var uvs := PackedVector2Array()
	for point in shape:
		uvs.append(Vector2((point.x - r.position.x) / cell.x, (point.y - top) / cell.y))
	draw_colored_polygon(shape, Color.WHITE, uvs, pieces["grass_strip"])

func _column(key: String, r: Rect2, side_x: float, to_y: float, lean: float) -> void:
	## One piece repeated down a face, following it break for break. `side_x` is
	## the edge the column hangs on; a right-hand face hangs its column inboard of
	## that edge so the rock ends where the silhouette does.
	if not pieces.has(key) or to_y <= r.position.y:
		return
	var tex: Texture2D = pieces[key]
	var cell := size_of(key)
	var source := Vector2(tex.get_width(), tex.get_height())
	var y: float = r.position.y
	var phase := 0.0
	while y < to_y:
		var span: float = minf(COLUMN_STEP, minf(to_y - y, cell.y - phase))
		var face: float = _face_x(r, side_x, y, lean)
		# Aligned by the ROCK, not by the rect: back the sprite out by its own
		# transparent margin so its outermost pixel lands on the silhouette.
		var bleed := bleed_of(key)
		var x: float = (face - bleed.x + edge_dx_left) if lean >= 0.0 					   else (face - cell.x + bleed.y + edge_dx_right)
		draw_texture_rect_region(tex, Rect2(Vector2(x, y), Vector2(cell.x, span)),
								 Rect2(Vector2(0.0, phase / scale_art),
									   Vector2(source.x, span / scale_art)))
		y += span
		phase = fmod(phase + span, cell.y)

func _bridge(r: Rect2) -> void:
	## Planking, drawn from its deck rather than its top-left: the posts and the
	## rope hang below the surface you walk on, which is the rectangle's top.
	var deck := surface_of("bridge_mid")
	var ends := size_of("bridge_left")
	var top := r.position.y - deck
	var inner: float = maxf(r.size.x - ends.x * 2.0, 0.0)
	_blit("bridge_left", Vector2(r.position.x, top))
	_run("bridge_mid", Vector2(r.position.x + ends.x, top), inner)
	_blit("bridge_right", Vector2(r.end.x - ends.x, top))

# --- set dressing ------------------------------------------------------------

func _decor() -> void:
	## [x, y, "piece"] with the piece's BOTTOM edge at y, because everything in
	## this list stands on something: a tree on the ground, an archway on the
	## floor of its arena. Islands are the exception and are placed by their
	## standable surface, since a level puts a solid under them.
	for entry in game.level.get("decor", []):
		if float(entry[0]) >= backdrop_span.x and float(entry[0]) < backdrop_span.y:
			continue  # inside a demo image; its set dressing is already in the picture
		var key: String = str(entry[2])
		# A dark rock mass: the hanging stalactite and the legs/top of the archway
		# formation. Not a sprite - it is the same fill-plus-cave-rock the cliff
		# bodies wear, so it reads as the same rock, only hung from the sky instead
		# of grown from the ground. [cx, top_y, "rock_mass", width, height, taper].
		if key == "rock_mass":
			var taper: float = float(entry[5]) if entry.size() > 5 else 0.0
			_rock_mass(float(entry[0]), float(entry[1]),
					   float(entry[3]), float(entry[4]), taper)
			continue
		if not pieces.has(key):
			continue
		var at := Vector2(float(entry[0]), float(entry[1]))
		var cell := size_of(key)
		var standable: bool = bool(data.pieces[key].get("standable", false))
		# Top-left relative to the base at `at`; the base is the pivot a tilt turns
		# about, so a leaned tree still stands where it was planted.
		var off := -Vector2(cell.x / 2.0, surface_of(key) if standable else cell.y)
		var ang: float = deg_to_rad(float(entry[3])) if entry.size() > 3 else 0.0
		if is_zero_approx(ang):
			_blit(key, at + off)
		else:
			draw_set_transform(at, ang, Vector2.ONE)
			draw_texture_rect(pieces[key], Rect2(off, cell), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## A block of the same cave rock a cliff body is made of, centred on `cx` with its
## top edge at `top`. `taper` narrows it toward the bottom: 0 is a straight column
## (the archway legs and top bar), high is a wedge closing to a near-point (the
## hanging stalactite). Drawn a touch darker than a lit cliff, because these hang
## in shadow. No grass and no collision - it is set dressing, placed not derived.
func _rock_mass(cx: float, top: float, w: float, h: float, taper: float) -> void:
	## Torn down each side rather than ruled, the same break the cliff faces use,
	## keyed off this mass's own centre so it is stable across frames. `taper`
	## closes the width toward the bottom: 0 keeps a straight column, high draws a
	## wedge tapering to a near-point.
	var bottom: float = top + h
	var steps: int = maxi(int(round(h / brk_step)), 2)
	var jit: float = minf(brk_jitter * 0.35, 14.0)
	var lefts := PackedVector2Array()
	var rights := PackedVector2Array()
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var half: float = lerpf(w * 0.5,
			maxf(w * (1.0 - clampf(taper, 0.0, 0.95)) * 0.5, 3.0), t)
		var y: float = top + h * t
		lefts.append(Vector2(cx - half + (_break(cx - 7.0, i) - 0.5) * 2.0 * jit, y))
		rights.append(Vector2(cx + half + (_break(cx + 7.0, i) - 0.5) * 2.0 * jit, y))
	var shape := PackedVector2Array()
	for point in rights:
		shape.append(point)
	for i in range(lefts.size() - 1, -1, -1):
		shape.append(lefts[i])
	draw_colored_polygon(shape, fill)
	if pieces.has("body_stone"):
		var cell := size_of("body_stone")
		var uvs := PackedVector2Array()
		for point in shape:
			uvs.append(Vector2(point.x / cell.x, point.y / cell.y))
		draw_colored_polygon(shape, Color(1, 1, 1, body_alpha), uvs, pieces["body_stone"])
	# A touch darker than the sunlit cliffs it is the same rock as: it hangs in shadow.
	draw_colored_polygon(shape, Color(0, 0, 0, 0.1))
