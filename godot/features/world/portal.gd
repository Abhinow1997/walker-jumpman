extends Node2D
## The way out of a level: a pierced stone hanging over the finish with light
## coming through it and falling to the ground.
##
## What it replaces was a flat salmon triangle on a grey pole, drawn in
## session.gd from the days when this game was rectangles on a page. Against
## the greybox it read fine. Against the Magic Cliffs coast it was the only
## thing on screen with smooth edges, one flat colour and no shading, and it
## announced "placeholder" more clearly than it announced "this way out".
##
## The stone is the art pack's own `archway` piece, which is not an archway: it
## is a floating rock with an eye-shaped hole bored through it, and the pack
## hangs it in the sky as scenery. Lit from behind it is a gate, which is what
## the end of a level is. Everything else is drawn here, in rows one art pixel
## tall, because every other edge in this world is a step of one art pixel and
## a smooth curve in front of them reads as interface rather than as a thing
## standing in the level.
##
## Collision is untouched: the goal is still the level's own `finish` rect,
## built in session.gd. This is only what stands in it.

## One pixel of the art pack, in world units. magic_cliffs.json renders at 0.75
## and the viewport is scaled by 4/3 on the way to the window, so one art pixel
## is one screen pixel — which is why every size below is a multiple of this
## and not a round number.
const CELL := 0.75

## The pack's hanging rock, and the size it is drawn at: 96 x 112 art pixels.
## Loaded by path rather than asked of scenery.gd, because the greybox levels
## have no scenery at all and the marker still has to be there.
const STONE_ART := "res://features/world/art/magic_cliffs/archway.png"
const STONE := Vector2(72.0, 84.0)
## Anything this opaque in the sprite is rock. The import bleeds colour into the
## transparent border (`fix_alpha_border`), so the test has to be on alpha and
## has to have some room in it.
const SOLID := 0.35

## How far the stone's lowest point floats above the ground. With the stone's
## own height that puts its top 153 above the foot line — a little taller than
## the pennant it replaces, and comfortably inside the 242 the camera shows
## above a standing player, so it is never cropped by the top of the screen.
##
## It hung 15 higher at first and the silhouette was a lollipop: a bright round
## head on a thin stalk. The light has to reach the floor as light rather than
## as a stem, which means a short drop and a wide one.
const DROP := 69.0

## The light itself: an upright oval in the sprite's own pixel coordinates,
## centred on the hole and just inside it at its widest. Every row of it is
## then clipped to the rock actually in the way — see `hole`. The oval is what
## gives the light a shape; the clip is what keeps it behind the stone.
const ORB_AT := Vector2(48.0, 53.0)
const ORB_R := Vector2(19.0, 30.0)
## The four passes it is built from: how far each shrinks toward the centre,
## its colour, and its alpha. Laid over each other they ramp from warm at the
## rim to near-white in the middle with no pass having an edge of its own.
##
## The shrink is on BOTH axes. Narrowing them only in x stacked four full-
## height slivers down the middle of the oval and what came back was a leaf
## with a vein up it.
const THROUGH := [
	[1.00, "edge", 0.46],
	[0.76, "mid", 0.56],
	[0.50, "core", 0.62],
	[0.26, "core", 0.90],
]
## How far the inner passes wander side to side, in art pixels, and how fast.
## The rim is left alone: with everything drifting the whole gate wobbles like
## jelly, and with nothing drifting it is a painted oval.
const SWIRL := 1.5
const SWIRL_TIME := 2.2
## The bloom behind the rock, which is what puts a warm rim on it against a
## cyan sky. A fraction of the sprite rather than a measurement: it is meant to
## be bigger than the stone and to have no edge you can point at.
const BLOOM_R := Vector2(0.46, 0.44)
const BLOOM_A := 0.12

## The shaft falling out of the hole and the pool it throws on the ground. It
## leaves the rock about as wide as the hole's lower end and flares on the way
## down; the flare is eased so it stays a beam for most of its length instead
## of reading as a flat triangle.
const SHAFT_TOP := 6.0
const SHAFT_FOOT := 33.0
const POOL_R := Vector2(33.0, 7.5)

## Warm, and specifically the accent the menu and the old pennant already used.
## The coast is green rock under a cyan sky: there is no cool colour left that
## would carry across it, and a warm light is a thing this world does not
## otherwise have, so nothing else can be mistaken for it.
const GLOW_CORE := Color("fff4d6")
const GLOW_MID := Color("ffc57e")
const GLOW_EDGE := Color("ef875f")

## The stone rises and falls on one clock and the light breathes on another,
## and the two periods are deliberately not a ratio of each other: matched, the
## pair beat together every cycle and the whole thing blinks like a warning
## light instead of hanging there.
const BOB := 3.0
const BOB_TIME := 2.6
const PULSE_TIME := 1.7
const PULSE_LOW := 0.84

## Sparks lifted off the ground and drawn up into the hole. Nine is enough to
## read as a current at a glance and few enough that none of them is ever the
## thing you are looking at.
const MOTES := 9
const MOTE_TIME := 2.9
const MOTE_SPREAD := 17.25
const MOTE_CONVERGE := 3.0

## Half a viewport plus half the marker, measured from its middle: 480 + the 33
## the pool reaches sideways, and 270 + half of DROP + STONE.y. Past either the
## marker is off the screen and the frame it would be redrawn into cannot show
## any part of it.
##
## It matters more than it looks. _draw() lays about 535 rows a frame and the
## engine only re-runs it when queue_redraw() is called, so a marker that asks
## for one every frame costs that whether or not anyone can see it — and it is
## off screen for all but the last stretch of every level. Measured at 1.1 ms a
## frame on the machine this was written on; see tests/diag_portal.gd.
const IN_SHOT := Vector2(516.0, 350.0)

## The session, for the clock and the camera. Assigned before the node is added,
## the way scenery.gd is.
var game: Node2D
var stone: Texture2D
var clock: float = 0.0

## Where the rock is, read off the sprite's own alpha rather than guessed at:
## for each art row, the columns between the left rock and the right rock. The
## light is clipped to this, so it never paints over the stone however the
## oval above is tuned, and it follows the art if the art is ever recut.
##
## Only a clip, not the shape. This sprite is loose chunks rather than a solid
## ring — four rows near the top have a gap in BOTH inner arcs and the scan
## runs all the way out to the outer chunks, 68 wide — so light drawn to these
## spans alone floods the whole sprite and the rocks read as floating on it.
var hole: PackedVector2Array = PackedVector2Array()

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if ResourceLoader.exists(STONE_ART):
		stone = load(STONE_ART)
		_read_hole()
	else:
		push_warning("portal: no art at %s (run scripts/extract_magic_cliffs.py, then --import)" % STONE_ART)

func _process(delta: float) -> void:
	# Frozen unless the game is running. Pause here is a State rather than a
	# paused SceneTree — see set_paused in session.gd — so a node with a clock
	# of its own keeps ticking through the pause screen and the level list
	# unless it asks.
	if is_instance_valid(game) and game.state != game.State.PLAYING:
		return
	clock += delta
	if not _in_shot():
		return
	queue_redraw()

func _in_shot() -> bool:
	if not is_instance_valid(game) or not is_instance_valid(game.camera):
		return true
	var camera: Node2D = game.camera
	# Measured from the middle of the marker rather than its foot, so a level
	# whose finish is near the top of the shot is not culled while its light is
	# still in frame.
	var middle := position - Vector2(0.0, (DROP + STONE.y) / 2.0)
	var away := (camera.position - middle).abs()
	return away.x < IN_SHOT.x and away.y < IN_SHOT.y

## Where the marker stands: the middle of the level's finish rect, on the solid
## its foot line meets. Snapped to the art grid so every row drawn below lands
## on a whole art pixel instead of straddling two.
static func stand_at(finish: Array) -> Vector2:
	return Vector2(
		snappedf(float(finish[0]) + float(finish[2]) / 2.0, CELL),
		snappedf(float(finish[1]) + float(finish[3]), CELL))

func _read_hole() -> void:
	var img := stone.get_image()
	var w := img.get_width()
	var h := img.get_height()
	var mid := w / 2
	for y in h:
		var left := -1
		var x := mid
		while x >= 0:
			if img.get_pixel(x, y).a > SOLID:
				left = x
				break
			x -= 1
		var right := -1
		x = mid
		while x < w:
			if img.get_pixel(x, y).a > SOLID:
				right = x
				break
			x += 1
		# Rock on both sides or it is not a hole — above the stone and below it
		# the scan runs off the sprite, and at the very middle of a closed row
		# the two edges meet.
		if left < 0 or right < 0 or right - left < 3:
			hole.append(Vector2.ZERO)
			continue
		hole.append(Vector2(float(left + 1), float(right)))

func _draw() -> void:
	var bob: float = sin(clock * TAU / BOB_TIME) * BOB
	var lift: float = PULSE_LOW + (1.0 - PULSE_LOW) * (
			0.5 + 0.5 * sin(clock * TAU / PULSE_TIME))
	var origin := Vector2(-STONE.x / 2.0, -DROP - STONE.y + bob)

	# The ground and the shaft first, then the rock over both: the stone's lower
	# point has to be a silhouette against the light coming past it, or it reads
	# as a decal pasted on top of a beam.
	_ellipse(Vector2.ZERO, POOL_R, _tint(GLOW_EDGE, 0.30 * lift))
	_ellipse(Vector2.ZERO, POOL_R * 0.55, _tint(GLOW_MID, 0.44 * lift))
	_ellipse(Vector2.ZERO, POOL_R * 0.26, _tint(GLOW_CORE, 0.55 * lift))
	var mouth: float = origin.y + (ORB_AT.y + ORB_R.y) * CELL
	_shaft(mouth, SHAFT_TOP, SHAFT_FOOT, GLOW_EDGE, 0.34 * lift, 0.12 * lift)
	_shaft(mouth, SHAFT_TOP * 0.55, SHAFT_FOOT * 0.42,
			GLOW_MID, 0.30 * lift, 0.10 * lift)
	_ellipse(origin + ORB_AT * CELL, STONE * BLOOM_R,
			_tint(GLOW_EDGE, BLOOM_A * lift))
	for pass_spec in THROUGH:
		_through(origin, float(pass_spec[0]), _named(str(pass_spec[1])),
				float(pass_spec[2]) * lift)
	if stone != null:
		draw_texture_rect(stone, Rect2(origin, STONE), false)
	_motes(lift)

func _named(key: String) -> Color:
	match key:
		"core":
			return GLOW_CORE
		"mid":
			return GLOW_MID
	return GLOW_EDGE

func _tint(base: Color, alpha: float) -> Color:
	return Color(base.r, base.g, base.b, clampf(alpha, 0.0, 1.0))

func _through(origin: Vector2, shrink: float, base: Color, alpha: float) -> void:
	## One pass of the oval, row by row, each row trimmed to the rock in the way
	## of it. Drawn in the sprite's own pixel grid: `origin` is the stone's top
	## left corner, so a row is a row of the art whether the stone is at the top
	## of its bob or the bottom of it.
	var tint := _tint(base, alpha)
	var radius := ORB_R * shrink
	var drift: float = 0.0 if shrink >= 1.0 else SWIRL * (1.0 - shrink)
	for i in int(radius.y * 2.0):
		var y: float = ORB_AT.y - radius.y + float(i)
		var t: float = 1.0 - pow((y + 0.5 - ORB_AT.y) / radius.y, 2.0)
		if t <= 0.0:
			continue
		var half: float = radius.x * sqrt(t)
		var at: float = ORB_AT.x + sin(y * 0.22 + clock * SWIRL_TIME) * drift
		var row := int(y)
		if row >= 0 and row < hole.size():
			# Trimmed to the gap in the rock, and to the middle of that gap:
			# the sprite is not symmetrical and a row held to the oval centre
			# pokes out through the narrower side.
			var span: Vector2 = hole[row]
			if span.y <= span.x:
				continue
			var room: float = (span.y - span.x) * 0.5
			var middle: float = (span.x + span.y) * 0.5
			at = clampf(at, middle - maxf(room - half, 0.0),
					middle + maxf(room - half, 0.0))
			half = minf(half, room)
		half = snappedf(half * CELL, CELL)
		if half < CELL:
			continue
		draw_rect(Rect2(origin.x + snappedf(at * CELL, CELL) - half,
				origin.y + y * CELL, half * 2.0, CELL), tint)

func _ellipse(at: Vector2, radius: Vector2, tint: Color) -> void:
	## An ellipse as a stack of rows one art pixel tall, which is how the pack's
	## own sprites draw one. draw_circle would put a true curve in a picture
	## where nothing else has one.
	if radius.x < CELL or radius.y < CELL:
		return
	var rows := int(round(radius.y * 2.0 / CELL))
	for i in rows:
		var y: float = -radius.y + i * CELL
		var t: float = 1.0 - pow((y + CELL * 0.5) / radius.y, 2.0)
		if t <= 0.0:
			continue
		var half: float = snappedf(radius.x * sqrt(t), CELL)
		if half < CELL:
			continue
		draw_rect(Rect2(at.x - half, at.y + y, half * 2.0, CELL), tint)

func _shaft(top: float, top_half: float, foot_half: float, base: Color,
		top_alpha: float, foot_alpha: float) -> void:
	## Light falling from `top` to the ground at local y 0, widening and fading
	## as it goes. Squared rather than linear so it holds its width for most of
	## the drop and splays near the floor — a straight taper from a small hole
	## to a wide pool is a triangle, and a triangle is what was here before.
	if top >= -CELL:
		return
	var rows := int(round(-top / CELL))
	for i in rows:
		var y: float = top + i * CELL
		var t: float = float(i) / float(rows)
		var half: float = snappedf(lerpf(top_half, foot_half, t * t), CELL)
		if half < CELL:
			continue
		draw_rect(Rect2(-half, y, half * 2.0, CELL),
				_tint(base, lerpf(top_alpha, foot_alpha, t)))

func _motes(lift: float) -> void:
	## Sparks lifted off the ground and drawn into the hole, so the shaft has a
	## direction: the light goes UP into the gate, which is where the player is
	## going. Deterministic — position comes from the index and the clock, not
	## from a seed — so two runs of a capture give the same picture.
	var rise: float = DROP + STONE.y - ORB_AT.y * CELL
	for i in MOTES:
		var phase: float = fposmod(clock / MOTE_TIME + float(i) / float(MOTES), 1.0)
		var y: float = snappedf(-rise * phase, CELL)
		var sway: float = lerpf(MOTE_SPREAD, MOTE_CONVERGE, phase)
		var x: float = snappedf(sin(float(i) * 2.4 + phase * 4.2) * sway, CELL)
		var size: float = CELL * (3.0 if i % 4 == 0 else 2.0)
		var tint := GLOW_CORE if i % 3 == 0 else GLOW_MID
		draw_rect(Rect2(x, y, size, size),
				_tint(tint, sin(phase * PI) * 0.95 * lift))
