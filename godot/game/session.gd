extends Node2D

const Player = preload("res://features/player/player.gd")
const Hud = preload("res://ui/hud.gd")
const Crate = preload("res://features/combat/crate.gd")
const Blast = preload("res://features/combat/blast.gd")
const Bottle = preload("res://features/combat/bottle.gd")
const Brew = preload("res://features/combat/brew.gd")
const Enemy = preload("res://features/combat/enemy.gd")
const Arrow = preload("res://features/combat/arrow.gd")
const Stone = preload("res://features/combat/stone.gd")
const Scenery = preload("res://features/world/scenery.gd")
const Portal = preload("res://features/world/portal.gd")
const Music = preload("res://game/music.gd")
const LEVEL_DIR := "res://levels/"
## What boots, and what every test gets unless it asks for something else.
##
## Deliberately the fixture rather than a level anyone plays: see the why_note in
## levels/greybox.json. Nothing reaches this default in normal play — the title
## screen names the level for both of its rows — so it is the suites' stage and
## nobody else's.
const DEFAULT_LEVEL := "greybox"

## Half the 960x540 viewport. The camera centres on its own position, so this
## is both where it starts and how close to either end of the level it may get
## before the edge would come into shot.
const VIEW_HALF := Vector2(480, 270)
## The HUD is laid out in a 640x360 design space and every coordinate in hud.gd
## is written in it. The viewport is 960x540, so the layer is scaled back up to
## keep the HUD the size it has always been on screen rather than reflowing it.
const HUD_SCALE := 960.0 / 640.0

## Appended to, never reordered: the tests record `state` as a number.
enum State { MENU, PLAYING, PAUSED, DYING, COMPLETE }
var state: State = State.MENU
## Which level this session is running. Assign before add_child() to boot into
## one directly; load_level() is the way to change it once it is running.
var level_id: String = DEFAULT_LEVEL
## Which row the level-select menu is sitting on.
var menu_index: int = 0
static var _catalogue: Array = []
## The extra ids the level list offers beyond the course — see listing().
static var _also_listed: Array = []
static var _levels: Dictionary = {}
var player: CharacterBody2D
var camera: Camera2D
var hud: Control
## Draws the world for a level with a `theme`. Null for the greybox levels,
## which session.gd draws procedurally in _draw() instead.
var scenery: Node2D
## How far the camera may travel vertically, worked out from the level in
## _build_world. The camera used to be pinned at y 500 for every level, which was
## invisible while every level was flat and hid the lower half of the first one
## that was not: the player simply walked off the bottom of the screen.
var view_top: float = 500.0
var view_bottom: float = 500.0
var level: Dictionary
## The section walls, one per entry in the level's `gates`, and the x each one
## stands on. A wall is a real StaticBody2D built once and switched in and out of
## the World layer, rather than added and freed, so nothing has to be rebuilt in
## the middle of a fight.
var gates: Array = []
var gate_walls: Array[StaticBody2D] = []
var hazard_areas: Array[Area2D] = []
var crates: Array[Area2D] = []
var bottles: Array[Area2D] = []
var enemies: Array[Area2D] = []
## The bottle currently in his hand, for the six seconds a drink takes. Held
## separately from bottle_in_reach because the two diverge the moment he steps
## away mid-drink, which is exactly the case that has to be caught.
var drinking_bottle: Area2D = null
var blasts: Array[Node2D] = []
## Arrows in flight, the archer's. Like blasts, they outlive whoever fired them
## and are cleared on reset and level change.
var arrows: Array[Node2D] = []
## Rocks falling down the shafts of a climbing level, and when each of that
## level's `rockfall` sources is next due to let one go. Both are empty for
## every level that names no rockfall, which is every level but The Climb.
var stones: Array[Node2D] = []
var rockfall_due: Array[float] = []
var goal: Area2D
## What STANDS in the goal — the lit stone over the finish. Drawn by its own
## node rather than in _draw() below, because it moves: this node redraws once
## when the level is built and the marker breathes every frame.
var portal: Node2D
var deaths: int = 0
var elapsed: float = 0.0
var retry_remaining: float = 0.0
var death_reason: String = ""
var last_finish_time: float = 0.0
var test_mode: bool = false
var contact_settle_ticks: int = 0

func _ready() -> void:
	process_physics_priority = 10
	setup_input()
	_make_fade()
	_make_story()
	_build_world()

## Which level is loaded. Set it before add_child() to boot straight into one;
## the default is the tutorial, which is what every test expects.
func load_level(id: String) -> void:
	## Tears the world down and builds the next one in place. The session node
	## itself survives, so the camera, the HUD and every signal the level does
	## not own are re-made rather than re-wired from outside.
	level_id = id
	menu_index = maxi(listing().find(id), 0)
	_clear_world()
	_build_world()
	deaths = 0
	elapsed = 0.0
	last_finish_time = 0.0
	state = State.MENU

func _clear_world() -> void:
	## remove_child before queue_free: freeing is deferred, and a solid still in
	## the tree for one more frame would collide with the level replacing it.
	for child in get_children():
		if child == fade_layer or child == story_layer:
			continue  # both outlive the world under them: see _make_fade/_make_story
		remove_child(child)
		child.queue_free()
	hazard_areas.clear()
	crates.clear()
	bottles.clear()
	enemies.clear()
	blasts.clear()
	arrows.clear()
	stones.clear()
	rockfall_due.clear()
	goal = null
	portal = null
	scenery = null
	player = null
	camera = null
	gates.clear()
	gate_walls.clear()
	seal_wall = null
	seal_at = INF
	sealed = false
	boss_track[0] = null
	boss_track[1] = null
	hud = null
	drinking_bottle = null

func _build_world() -> void:
	level = level_data(level_id).duplicate(true)
	if level.is_empty():
		return
	# Whatever this level names, or silence. Asking for the track already playing
	# does nothing, so arriving from the title screen — which plays the same loop
	# The Fractured Isles does — carries straight on rather than starting over.
	# A greybox level names none and the music stops. See music.gd.
	Music.cue(get_tree(), str(level.get("music", "")))
	# Read before anything is built: the camera, the fatal line and the shafts
	# all ask. False and empty for every level that says neither.
	climbing = bool(level.get("climb", false))
	climb_mark = INF
	_arm_rockfall()
	# First child, so it is behind everything, and before the solids so that the
	# terrain it generates from them is already on screen when they exist.
	var theme := str(level.get("theme", ""))
	if theme != "":
		scenery = Scenery.new()
		scenery.game = self
		scenery.theme = theme
		add_child(scenery)
	for entry in level.solids:
		_add_solid(Rect2(entry[0], entry[1], entry[2], entry[3]))
	# The ends of the world. Measured off the level rather than the fixed 0..860
	# box this used to be: that box was taller than every level that existed
	# when it was written, and a tower rises straight out through the top of it
	# — a player stepping off the side at height would have met no wall at all.
	var sky: float = float(level.fall_y)
	for entry in level.solids:
		sky = minf(sky, float(entry[1]))
	sky -= 600.0
	var deep: float = float(level.fall_y) + 600.0
	_add_solid(Rect2(-64.0, sky, 64.0, deep - sky))
	_add_solid(Rect2(float(level.width), sky, 64.0, deep - sky))
	for entry in level.hazards:
		hazard_areas.append(_add_area(Rect2(entry[0], entry[1], entry[2], entry[3]), 8, true))
	var f: Array = level.finish
	goal = _add_area(Rect2(f[0], f[1], f[2], f[3]), 16, false)
	# Added before the crates and the player so both draw over it: he walks INTO
	# the light rather than behind it.
	portal = Portal.new()
	portal.game = self
	portal.position = Portal.stand_at(f)
	add_child(portal)
	# Crates are added before the player so he draws over them, and they are
	# Area2D with no collision mask: they are targets, never obstacles. Walking
	# into one does nothing, so no crate can block or alter the platforming route.
	for entry in level.get("crates", []):
		var crate := Crate.new()
		crate.position = Vector2(entry[0], entry[1])
		# A crate is knocked about when hit, so it needs to know where the level
		# gives up on anything that falls.
		crate.fall_limit = float(level.fall_y)
		crates.append(crate)
		add_child(crate)
	# [x, y] or [x, y, segments]. The third value is BAR SEGMENTS, not points:
	# [470, 640, 2] is a bottle worth two of the bar's five bars. It used to be
	# raw points, so an old level file's 50 would now read as fifty bars — check
	# any level authored before this changed.
	#
	# "bottles" is the white milk bottle and fills the health bar; "brews" is the
	# brown one and fills the mana bar. Both are the same prop on the same
	# physics and both land in `bottles`, which is the list of things that can be
	# drunk rather than the list of milk.
	for entry in level.get("bottles", []):
		_add_bottle(Bottle.new(), entry)
	for entry in level.get("brews", []):
		_add_bottle(Brew.new(), entry)
	# Spawned before the player so he draws in front of them, and so `target`
	# can be handed over the moment he exists.
	# [x, y] per enemy, or [x, y, "kind"] to pick which one — "bandit" (the
	# default) or "mark". More is another entry, not more code. `kind` is set
	# before add_child so it is in place when the enemy reads its manifest.
	#
	# A fourth value "perch" stands this one on a high shelf over the fight: it
	# snipes down into it and holds its gate like the rest, but it only comes off
	# the shelf once the ground below it is clear. See perched/descend in enemy.gd.
	# A level may also set what a kind of enemy is worth ON IT, which is how the
	# dragon is 1500 on the isles where it is the whole fight and 1140 on the
	# Roost where it is half of one. By kind and not by entry: a level that
	# wanted two of something at two sizes would want a reason first.
	var tuned: Dictionary = level.get("enemy_health", {})
	for entry in level.get("enemies", []):
		var foe := Enemy.new()
		foe.position = Vector2(entry[0], entry[1])
		if entry.size() > 2 and str(entry[2]) != "":
			foe.kind = str(entry[2])
		if entry.size() > 3 and str(entry[3]) == "perch":
			foe.perched = true
		# Before add_child, like `kind`: _ready reads it.
		if tuned.has(foe.kind):
			foe.health_override = int(tuned[foe.kind])
		foe.fall_limit = float(level.fall_y)
		foe.struck_player.connect(_on_player_struck)
		foe.fired_arrow.connect(_on_arrow_fired)
		enemies.append(foe)
		add_child(foe)
	_build_gates()
	_fence_flyers()
	_build_arena()
	player = Player.new()
	player.blast_fired.connect(_on_blast_fired)
	player.drink_ended.connect(_on_drink_ended)
	player.threw.connect(_on_threw)
	add_child(player)
	player.reset_at(Vector2(level.spawn[0], level.spawn[1]))
	_measure_view()
	camera = Camera2D.new()
	camera.position = Vector2(VIEW_HALF.x, camera_home_y())
	# Straight back to a hard cut: a retry or a level swap is a cut, not a pan.
	camera_held = 0.0
	add_child(camera)
	var layer := CanvasLayer.new()
	layer.scale = Vector2(HUD_SCALE, HUD_SCALE)
	add_child(layer)
	hud = Hud.new()
	hud.game = self
	layer.add_child(hud)
	# Guarded: _build_world runs again on every level change, and connecting a
	# second time would pause the game twice for one lost focus.
	if not get_window().focus_exited.is_connected(_on_focus_lost):
		get_window().focus_exited.connect(_on_focus_lost)
	_load_story_cards()
	queue_redraw()

## --- sections ---------------------------------------------------------------
##
## A level may cut itself into sections with `gates`: a list of x positions, each
## the end wall of one section, so three gates make four. While any enemy in a
## section still holds it, that section's wall is solid and the camera stops with
## the wall at the right edge of the screen — you can see you have run out of
## screen rather than out of floor, which is the beat-em-up convention and the
## reason the wall does not need to be drawn. Clearing the section opens both.
##
## Nothing blocks going back. The rule is about not skipping a fight, and a wall
## behind the player only takes away the room he needs to fight in.
##
## A level with no `gates` — both greybox levels — behaves exactly as before.

## How wide the wall is, and how far above and below the level it runs. Tall
## enough that nothing jumps it: the level's own ceiling is well inside this.
const GATE_WALL := Vector2(24.0, 2400.0)
## How far inside the right edge of the screen the wall sits while it is shut.
## Without it the camera stops with the wall exactly on the edge, and a player
## standing against the wall is half off the screen — he is the one thing that
## must never be clipped. A sliver of the ground past the wall shows instead,
## which costs nothing: the wall is at the edge either way.
const GATE_INSET := 48.0

## --- the door behind a boss -------------------------------------------------
##
## Ordinary gates only ever stop you going ON. Walking back is never blocked,
## because a wall behind you in a fight takes away the room you need to fight
## in. A boss is the exception, and The Fractured Isles showed why: the dragon
## is fenced into its own section (see _fence_flyers), so a player who simply
## walked west out of the arena stood two sections back on a deck it could not
## follow him onto, and the fight stopped happening. The gate ahead of him held
## the flag; nothing held the way out.
##
## So while a boss is fighting, the wall BEHIND its section is solid too, and
## the camera stops against it the same way it stops against the one in front.
## The box that closes is the boss's own section — which is already the arena
## as far as everything else is concerned: it is what fly_bounds fences the
## dragon into, so the two of them end up shut in exactly the same room.
##
## A boss arena is the level's `boss_arena`: the x its fight is sealed behind.
## Optional, and both of the levels with a boss name one. The Fractured Isles
## says 6912, the lip of the dragon's deck. Its SECTION opens at 6110, out in the middle of the chasm,
## which would leave the four stepping stones inside the fight (the ledges he
## crossed to get there) and stand the wall in mid-air over the water.
##
## Named rather than worked out from the deck the boss stands on, which was
## the first cut of this and is wrong on The Dragon's Roost: its two bosses
## stand on 1512..2148 and one of the two floating stones you need to reach
## the flying one is at 1188, outside it. A derived line would have walled that
## stone out of its own fight. Where an arena begins is a level's decision.
##
## The wall, where it stands, and whether it is shut. LATCHED rather than
## recomputed every frame, for two reasons: it cannot flicker while he stands
## on the line, and it only latches once he is CLEAR of it, so a fight that
## somehow began with him on the wrong side can still be walked into. Cleared
## by the boss going, which a retry does for free — reset() puts every enemy
## back on its feet and takes `engaged` with it.
var seal_wall: StaticBody2D = null
var seal_at: float = INF
var sealed: bool = false
## How far past the line he has to be before it shuts behind him. One wall
## width: he is 15 across and the wall stands WEST of the line, so at 24 he is
## clear of it and cannot be caught inside it when it turns solid.
##
## Not more than that. The Fractured Isles wakes its dragon from a story card
## cued at 6960, which is 48 past the lip at 6912 — a margin of 64 never
## latched at all, and the first run of tests/diag_arena_seal.gd watched him
## stroll back out over the stones with the fight on.
const SEAL_MARGIN := 24.0

func _build_gates() -> void:
	gates.clear()
	gate_walls.clear()
	for entry in level.get("gates", []):
		var x := float(entry)
		gates.append(x)
		# Built once and switched in and out of the World layer by _sync_gates,
		# rather than created and freed as fights start and end.
		var wall := _add_solid(Rect2(x, -GATE_WALL.y / 2.0, GATE_WALL.x, GATE_WALL.y))
		gate_walls.append(wall)

func arena_of(foe: Node2D) -> Vector2:
	## The box a boss fight happens in: its section, cut back to the level's
	## `boss_arena` line when it names one. The section is the outside edge —
	## it is where the gate ahead stands and nothing may cross that — and the
	## arena line is the inside one.
	var box := section_bounds(section_of(foe.home.x))
	box.x = maxf(box.x, arena_line())
	return box

func arena_line() -> float:
	## Where this level seals a boss fight behind, or -INF for a level that
	## does not. One number per level: a level with two bosses fights them in
	## one room.
	return float(level.get("boss_arena", -INF))

func _fence_flyers() -> void:
	## A flyer is fenced into its arena. Everything else in the cast is bounded
	## by the floor running out from under it; a flyer has no floor, and backs
	## away from a player who crowds it, so without this a player in the corner
	## of a gated arena can push the boss out through the side of the screen.
	## See fly_bounds in features/combat/enemy.gd for the measurement, and
	## tests/diag_arena.gd for how to take it again.
	##
	## The arena and not the framed section. A gate frames the last 960 before
	## its wall, and The Dragon's Roost arena is wider than that — fencing to
	## the frame would keep its dragon out of the half of its own deck the
	## player can stand on. On a level that names a `boss_arena` it is that box
	## and not the whole section either: the same room the player is sealed
	## into, so the boss cannot drift out over a chasm he cannot follow it onto
	## and off the side of the screen. A level naming none is fenced to its
	## section exactly as before.
	for foe in enemies:
		if is_instance_valid(foe) and foe.is_flyer():
			foe.fly_bounds = arena_of(foe)

func _build_arena() -> void:
	## The wall that shuts behind a boss fight, built with the level and left
	## open until there is a fight to shut in. Its own body rather than one of
	## the gate walls: a gate stands on a line the level author chose for the
	## fight AHEAD of it, and the back of an arena is a different place — 6912
	## against 6110 on the Isles.
	seal_wall = null
	seal_at = INF
	sealed = false
	if arena_line() == -INF:
		return          # this level does not shut its fights in
	for foe in enemies:
		if is_instance_valid(foe) and foe.is_boss():
			seal_at = minf(seal_at, arena_of(foe).x)
	if seal_at == INF or seal_at <= 0.0:
		return          # no boss, or its arena starts at the edge of the level
	# West of the line, so the whole deck stays standable.
	seal_wall = _add_solid(Rect2(seal_at - GATE_WALL.x, -GATE_WALL.y / 2.0,
			GATE_WALL.x, GATE_WALL.y))
	seal_wall.collision_layer = 0

func section_of(x: float) -> int:
	## Which section a point is in. The last section has no gate, so anything
	## past the final one belongs to it.
	for i in gates.size():
		if x < float(gates[i]):
			return i
	return gates.size()

func section_bounds(index: int) -> Vector2:
	var low: float = 0.0 if index <= 0 else float(gates[index - 1])
	var high: float = float(level.get("width", 0)) if index >= gates.size() else float(gates[index])
	return Vector2(low, high)

func section_holders(index: int) -> Array:
	## The enemies whose gate this is: spawned inside the section and not marked
	## as a perch. Judged on `home`, where it was placed, rather than on where it
	## has walked to — an enemy that chases the player over a line must not hand
	## its gate to the next section.
	var bounds := section_bounds(index)
	var out: Array = []
	for foe in enemies:
		if is_instance_valid(foe) and foe.holds_gate 				and bounds.x <= foe.home.x and foe.home.x < bounds.y:
			out.append(foe)
	return out

func section_clear(index: int) -> bool:
	for foe in section_holders(index):
		if foe.alive():
			return false
		# A beaten BOSS holds its wall until its body is off the screen. It
		# takes seconds to die — the fall, the two it lies there, the card
		# cued off that, the climb out — and on The Fractured Isles the flag
		# is 132 px past the wall. Without this a player who beat it backed
		# against the wall, which is where a gated fight usually ends, runs
		# straight out through the ending: measured at 0.82 s to the flag
		# against 2.05 s for the card. tests/diag_endcard.gd is that
		# measurement. It frames the death as well — the camera stays on the
		# arena while the dragon goes down and climbs out of it.
		if foe.is_boss() and foe.visible:
			return false
	return true

func gate_shut_at() -> float:
	## The x of the wall holding the player in, or INF when he is free to go on.
	## Only his own section can hold him: everything behind him is already clear
	## by definition, and everything ahead is somebody else's fight.
	if gates.is_empty() or not is_instance_valid(player):
		return INF
	var index := section_of(player.position.x)
	if index >= gates.size() or section_clear(index):
		return INF
	return float(gates[index])

func _sync_gates() -> void:
	## One pass a frame: each wall is solid exactly while its own section is not
	## clear, or while it is the door shut behind a boss fight. Driven off
	## alive() rather than off a death signal, so a retry — which puts every
	## enemy back on its feet — closes the walls again with no extra bookkeeping.
	_sync_boss_seal()
	for i in gate_walls.size():
		var wall := gate_walls[i]
		if not is_instance_valid(wall):
			continue
		# Layer 1 is World, which is the only thing the player collides with.
		# Dropping to 0 leaves the body in place and lets him walk through it.
		wall.collision_layer = 0 if section_clear(i) else 1

func _sync_boss_seal() -> void:
	## Shuts the arena behind a boss fight and opens it again when the fight is
	## over. See seal_wall.
	if not is_instance_valid(seal_wall):
		return
	if boss() == null:
		sealed = false
	elif not sealed and is_instance_valid(player) \
			and player.position.x > seal_at + SEAL_MARGIN:
		sealed = true
	seal_wall.collision_layer = 1 if sealed else 0

func gate_behind_at() -> float:
	## The x of the wall shut behind him, or -INF. The camera reads it for its
	## left edge, the way gate_shut_at gives it the right one.
	return seal_at if sealed else -INF

func _sync_descent() -> void:
	## The perch snipers come off their shelves once the ground below them is
	## clear — "if everyone is killed below, they come down." Driven off alive()
	## like the gates, so a retry (which stands everyone back up) puts them back on
	## the shelf with no extra bookkeeping. Cheap: a handful of enemies, once a
	## frame. The cue is one-way within an attempt; only reset() takes it back.
	for i in range(gates.size() + 1):
		var bounds := section_bounds(i)
		var ground_alive := false
		var roost: Array = []
		for foe in enemies:
			if not is_instance_valid(foe) or not foe.holds_gate:
				continue
			if not (bounds.x <= foe.home.x and foe.home.x < bounds.y):
				continue
			if foe.perched:
				roost.append(foe)
			elif foe.alive():
				ground_alive = true
		if not ground_alive:
			for foe in roost:
				foe.descend = true

## --- story cards ------------------------------------------------------------
##
## A level may hold story panels, and what brings each one up:
##
##     "cutscene": [
##      {"panel": "dragon_fight_start", "audio": "dragon_fight_start",
##       "out_audio": "dragon_roar", "at": 6960},
##      {"panel": "dragon_fight_end", "audio": "dragon_fight_end",
##       "after": "boss"}
##     ]
##
## The level stops where it stands, the picture comes up over it, and when the
## picture goes the level is handed back. The Fractured Isles has both of these
## and no other level has any.
##
## TWO CUES, one per card. `at` is an x he has to cross ON HIS FEET — the
## footing matters because a line on the mouth of an arena you jump into would
## otherwise put the picture up over a player frozen in mid-air, who then drops
## out of the bottom of it when it goes. `after: "boss_down"` waits until the
## level's boss is beaten and has FALLEN — for the dragon, the moment the
## collapse has played out and it is lying on the deck. The picture is of it
## leaving, so it belongs between the fall and the leaving rather than after
## both: the card stops the world with the body on the deck, and the dragon
## gets up and climbs out of the level the moment the picture is gone.
##
## THE CLIP DECIDES HOW LONG THE PICTURE HOLDS. A card with `audio` holds until
## its own clip is out, read off the stream's length, so re-rendering one
## longer lengthens the card and nothing here or in the level has a duration
## written in it. `out_audio` is the sound it leaves on rather than arrives
## with — for the first card that is the dragon's roar, which starts as the
## picture begins to dissolve and carries into the fight underneath it.
##
## A card may also refuse to be skipped, with `"skip": false`. Both of the
## dragon's do: they are four and ten seconds each, they play once per visit,
## and what they carry — who the drake is and what happens to it — is the only
## story the level tells. The key is still swallowed, so an unskippable card
## cannot be paused out from under either.
##
## Its own layer over a level that is still there, rather than a scene in front
## of one, which is the whole difference between this and ui/storyboard.gd. The
## opening replaces the screen and can afford to be a scene; this has to leave
## the world underneath intact, because the world comes back.
##
## ONCE PER VISIT, per card, not once per attempt. Dying to the dragon and
## walking back up the level does not play the standoff again — a cutscene
## between a player and another go at a boss is the one everybody learns to
## hate — but leaving to the menu and starting the level over does, because
## that is a new run at it.
const STORY_DIR := "res://ui/art/storyboard/"
const STORY_AUDIO_DIR := "res://audio/"
## Up and away. What is between them is the clip's business — see STORY_HOLD.
const STORY_IN := 0.7
const STORY_OUT := 0.6
## How long one panel dissolves into the next WITHIN a single beat — two panels
## over one clip, The Dragon's Roost. The new panel fades in over the old with
## the dim held full, so the level never shows between them: only the first panel
## fades up from the level and only the last fades back to it. See _begin_swap.
const STORY_SWAP := 0.5
## How long a card with no clip holds, and the floor under one that has a clip
## too short to read the picture in.
const STORY_HOLD := 2.6
## How far down the level behind the card goes. Not all the way: the picture is
## the screen now, but the edges of the frame should still say the game is
## there and waiting rather than that it has been replaced.
const STORY_DIM := 0.88

## The subtitle under a card, if it has one. Deliberately the same column,
## baseline, size and scrim ui/storyboard.gd gives the opening's captions —
## both are in the same 960x540 space, and the two should read as one piece of
## typography rather than as two people's ideas about subtitles.
##
## The scrim is not decoration. These sit over bright cloud in one card and
## dark cliff in the next, and an outline alone loses the thin strokes against
## the clouds. It is drawn full width, like the opening's, with the text in a
## 760 column inside it.
const STORY_LINE_BOTTOM := 494.0
const STORY_LINE_PAD := Vector2(100.0, 9.0)
const STORY_LINE_SIZE := 17
const STORY_LINE_INK := Color(0.96, 0.97, 0.98)
const STORY_LINE_EDGE := Color(0.0, 0.0, 0.0, 0.75)
const STORY_LINE_SCRIM := Color(0.0, 0.0, 0.0, 0.44)

## Appended to, never reordered — SWAP is the panel-to-panel dissolve within one
## beat, added after the three that existed. See _begin_swap.
enum Story { NONE, IN, HOLD, OUT, SWAP }
var story_phase: Story = Story.NONE
var story_clock: float = 0.0
## The level's cards, parsed once in _build_world. Each is
## {tex, voice, tail, at, after, hold, seen}; `seen` is the once-per-visit flag
## and the only field that changes while the level runs.
var story_cards: Array = []
## Which card is up, or -1.
var story_at: int = -1
var story_layer: CanvasLayer
var story_dim: ColorRect
var story_art: TextureRect
## The outgoing panel during a same-beat dissolve — held solid behind story_art
## while the incoming panel fades in over it, so the level never shows through
## between panels. Idle (transparent) at every other time. See _begin_swap.
var story_art_prev: TextureRect
var story_line: Label
var story_voice: AudioStreamPlayer

func _make_story() -> void:
	## Built once in _ready beside the fade, and skipped by _clear_world for the
	## same reason: it has to be able to outlive the world it is drawn over.
	##
	## Its own CanvasLayer at scale 1 rather than a corner of the HUD, because
	## the HUD is laid out in a 640x360 design space and this is a full-screen
	## picture — at scale 1 every number below is a viewport pixel.
	story_layer = CanvasLayer.new()
	# Over the HUD, which _build_world adds at the default layer 0, and under
	# the fade at 100 — a level swap has to be able to cover the card too.
	story_layer.layer = 50
	story_layer.visible = false
	story_dim = ColorRect.new()
	story_dim.color = Color(0.03, 0.04, 0.06, 0.0)
	story_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	story_layer.add_child(story_dim)
	# Two panel layers: the outgoing one (added first, so it sits behind) holds
	# solid during a same-beat dissolve while the incoming one fades in over it.
	story_art_prev = _new_story_art()
	story_layer.add_child(story_art_prev)
	story_art = _new_story_art()
	story_layer.add_child(story_art)
	story_line = Label.new()
	story_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	story_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story_line.add_theme_font_size_override("font_size", STORY_LINE_SIZE)
	story_line.add_theme_color_override("font_color", STORY_LINE_INK)
	story_line.add_theme_color_override("font_outline_color", STORY_LINE_EDGE)
	story_line.add_theme_constant_override("outline_size", 4)
	var scrim := StyleBoxFlat.new()
	scrim.bg_color = STORY_LINE_SCRIM
	scrim.content_margin_left = STORY_LINE_PAD.x
	scrim.content_margin_right = STORY_LINE_PAD.x
	scrim.content_margin_top = STORY_LINE_PAD.y
	scrim.content_margin_bottom = STORY_LINE_PAD.y
	story_line.add_theme_stylebox_override("normal", scrim)
	story_line.visible = false
	story_layer.add_child(story_line)
	# The card's own voice. Not the music node: that one outlives scenes on
	# purpose and is a looping bed, and this is a clip that belongs to a level.
	story_voice = AudioStreamPlayer.new()
	story_layer.add_child(story_voice)
	add_child(story_layer)

func _new_story_art() -> TextureRect:
	## One full-frame panel layer. Two of these are stacked so a same-beat
	## dissolve can hold the old panel solid behind the new one.
	var art := TextureRect.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	# A reduction of a painted sheet rather than pixel art — see the note in
	# scripts/extract_storyboard.py — so the same filter hud.gd gives the bars.
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	art.position = Vector2.ZERO
	art.size = VIEW_HALF * 2.0
	art.modulate.a = 0.0
	return art

func _load_story_cards() -> void:
	## This level's cards, or none. Every level but the Isles takes the early
	## return with an empty list.
	if not is_instance_valid(story_art):
		return
	_end_story()
	_stop_story_voice()
	story_cards.clear()
	story_art.texture = null
	for entry in level.get("cutscene", []):
		var card := _read_story_card(entry)
		if not card.is_empty():
			story_cards.append(card)

func _read_story_card(entry: Dictionary) -> Dictionary:
	var art := str(entry.get("panel", ""))
	var path := STORY_DIR + art + ".png"
	if art == "" or not ResourceLoader.exists(path):
		push_warning("levels: %s names the story panel %s, which is not imported. Run scripts/extract_storyboard.py."
					 % [level_id, path])
		return {}
	var voice := _story_clip(str(entry.get("audio", "")))
	var card := {
		"tex": load(path),
		"line": str(entry.get("caption", "")),
		"skip": bool(entry.get("skip", true)),
		"voice": voice,
		"tail": _story_clip(str(entry.get("out_audio", ""))),
		"at": float(entry.get("at", INF)),
		"after": str(entry.get("after", "")),
		"hold": float(entry.get("hold", STORY_HOLD)),
		# A panel that continues the PREVIOUS card's audio rather than starting
		# its own — how one clip is spread across two panels so the second comes
		# in on the dialogue instead of after the whole thing. See The Dragon's
		# Roost, and _begin_story / _begin_story_out, which leave the clip running.
		"keep_audio": bool(entry.get("keep_audio", false)),
		"seen": false,
	}
	# The clip decides the hold — less the fade it is already playing under,
	# floored so a two-second sting still holds long enough to read — UNLESS the
	# level pins one. A pinned hold is what lets a multi-panel beat cut from one
	# panel to the next partway through a single clip, on the dialogue's own beat.
	if voice != null and not entry.has("hold"):
		card["hold"] = maxf(STORY_HOLD, voice.get_length() - STORY_IN)
	return card

func _story_clip(name: String) -> AudioStream:
	if name == "":
		return null
	var path := STORY_AUDIO_DIR + name + ".mp3"
	if not ResourceLoader.exists(path):
		push_warning("levels: %s names the clip %s, which is not there. Run scripts/extract_storyboard.py."
					 % [level_id, path])
		return null
	return load(path)

func story_running() -> bool:
	return story_phase != Story.NONE

func story_alpha() -> float:
	## How far up the card is, 0 to 1. Public for the reason fade_alpha is: a
	## capture has to be able to assert the dissolve rather than trust it.
	match story_phase:
		Story.IN:
			return clampf(story_clock / STORY_IN, 0.0, 1.0)
		Story.HOLD:
			return 1.0
		Story.SWAP:
			# Full: the dim stays up through a panel-to-panel dissolve, only the
			# picture crossfades. See _show_story.
			return 1.0
		Story.OUT:
			return clampf(1.0 - story_clock / STORY_OUT, 0.0, 1.0)
	return 0.0

func boss() -> Node2D:
	## The boss whose fight is happening right now, or null. Two things read
	## this — the plate across the bottom of the screen and which track is
	## playing — and they must not be able to disagree about when a fight is on.
	##
	## `engaged` keeps it null until the fight starts, so neither the plate nor
	## the music is a spoiler; `visible` keeps it non-null through the death,
	## because the dragon is on screen for seconds after it is beaten and both
	## the empty bar and the fight music belong to it until it is gone.
	for foe in enemies:
		if is_instance_valid(foe) and foe.is_boss() and foe.engaged and foe.visible:
			return foe
	return null

## Which boss is on each of the plate's two tracks — [green, magma] — for as
## long as the fight lasts. A track KEEPS the boss it was handed, dead or
## alive: a beaten boss's bar drains to empty and STAYS empty until the whole
## fight is over.
##
## Sticky rather than worked out each frame from whoever is still standing,
## which is what it was and which was wrong on The Dragon's Roost. Both tracks
## used to answer "who is fighting me now", so the moment one of its two
## bosses went down the survivor slid onto the green and the red went back to
## shadowing it: the plate answered a death by showing one full green bar,
## which reads as a fight STARTING rather than as one half won, and the bar
## you had been watching drain was simply gone. Two bosses, two indicators,
## and neither moves off its own track.
var boss_track: Array[Node2D] = [null, null]

func boss_main() -> Node2D:
	## The boss on the plate's main (green) track. When two are fighting — The
	## Dragon's Roost — this is the one on its feet, the Dragon Lord you close
	## with; the flyer takes the second track. With a single boss it is simply
	## that boss. Non-null exactly while a fight is on, which is what the plate
	## is drawn on.
	_sync_boss_track()
	return boss_track[0]

func boss_second() -> Node2D:
	## The boss on the plate's second (magma/red) track, or null on a level that
	## fights one. With one, the red track goes back to lagging the green, which
	## is the damage band; with two it is the second boss's own live health, and
	## it stays his after he falls.
	_sync_boss_track()
	return boss_track[1]

func _sync_boss_track() -> void:
	## Hands a track to each boss as it engages, and takes both back when the
	## fight is over.
	##
	## Cleared on boss() going null — nothing engaged still on screen — which is
	## the same line the plate and the battle track are drawn on, so the next
	## fight cannot inherit the last one's empty bar. Nothing else takes a track
	## away from a boss: that is the whole point of it.
	if boss() == null:
		boss_track[0] = null
		boss_track[1] = null
		return
	# Grounded before flyers, so two waking on the same frame — which is what
	# the standoff card does — take the tracks in that order and the green is
	# the Dragon Lord's however the level happens to list its enemies.
	#
	# `visible` as well as `engaged`, which is boss()'s own test for being in a
	# fight: a boss beaten and cleared BEFORE this fight started is not in it and
	# must not hold a track through it. Keeping one once it has been handed over
	# is a different question, and the answer to that one is yes.
	for flying in [false, true]:
		for foe in enemies:
			if is_instance_valid(foe) and foe.is_boss() and foe.engaged \
					and foe.visible and foe.is_flyer() == flying:
				_take_track(foe)

func _take_track(foe: Node2D) -> void:
	## Puts a boss on the first free track, and does nothing whatever if it is
	## already on one — which is what keeps a bar with its boss. A third boss
	## would get no track at all; the plate is drawn with two and no level
	## fights three.
	for slot in boss_track:
		if slot == foe:
			return
	for i in boss_track.size():
		if boss_track[i] == null:
			boss_track[i] = foe
			return

func _boss_fallen() -> bool:
	## Down, and done being down. See fallen() and DOWN_TIME in enemy.gd — for
	## the dragon this is two seconds after it hits the deck, which is the end
	## of the fall and the frame before the climb out.
	for foe in enemies:
		if is_instance_valid(foe) and foe.is_boss() and foe.fallen():
			return true
	return false

## The loop the level plays while a boss is fighting you, named in the level
## file as `boss_music`. Asked for every tick rather than cued at the moment a
## fight starts, because that is not the only way in or out of one: dying puts
## the player back at the spawn with the boss on its perch, and the level's own
## track has to come back with him rather than leaving him to walk the whole
## course to boss music.
func current_track() -> String:
	## The battle track belongs to the FIGHT, and the fight ends when the boss
	## does rather than when its body is finally off the screen. Everything
	## after the killing blow — the two seconds it lies there, the card, the
	## climb out — is the aftermath, and the level's own quiet loop is the bed
	## for all three. The plate deliberately outlasts the track: see boss(),
	## where an empty bar under a departing dragon is the whole point and a
	## battle loop under the same moment would undo it.
	if boss_fighting() != null:
		var fight := str(level.get("boss_music", ""))
		if fight != "":
			return fight
	return str(level.get("music", ""))

func boss_fighting() -> Node2D:
	## The boss the battle track belongs to: engaged, on screen and still on
	## its feet. Any of them, not the first one the level happens to list.
	##
	## It used to ask boss() and then whether THAT one was alive, which is the
	## same question on a level with one boss and the wrong one on The Dragon's
	## Roost. Its enemies list the dragon first, so beating the dragon while
	## the Dragon Lord was still swinging dropped the track to the level's
	## quiet loop — and then put it back four and a half seconds later, when
	## the dragon's body finally left the level and boss() moved on to the Lord.
	## A hole in the middle of the last fight in the game. See
	## tests/diag_boss_track.gd, which walks both levels through both deaths.
	##
	## `alive()` is what makes this different from boss(): the plate outlasts
	## the track on purpose — an empty bar under a departing dragon is the
	## point of it, and a battle loop under the same moment would undo it.
	for foe in enemies:
		if is_instance_valid(foe) and foe.is_boss() and foe.engaged 				and foe.visible and foe.alive():
			return foe
	return null

func _story_due() -> int:
	## The first card whose cue has come up, or -1. On his feet for either cue:
	## a picture that arrives while he is in the air freezes him there.
	if story_cards.is_empty() or not is_instance_valid(player):
		return -1
	if not player.is_on_floor():
		return -1
	for i in story_cards.size():
		var card: Dictionary = story_cards[i]
		if card["seen"]:
			continue
		if str(card["after"]) == "boss_down":
			if _boss_fallen():
				return i
		elif player.position.x >= float(card["at"]):
			return i
	return -1

func _advance_story(delta: float) -> bool:
	## Returns true while a card is holding the world still, which is what
	## takes the frame away from everything below it in _physics_process:
	## nothing moves, and the level clock does not run either.
	if story_phase == Story.NONE:
		var due := _story_due()
		if due < 0:
			return false
		_begin_story(due)
		if story_phase == Story.NONE:
			return false  # test_mode: the beat happened, the picture did not
	story_clock += delta
	match story_phase:
		Story.IN:
			if story_clock >= STORY_IN:
				story_phase = Story.HOLD
				story_clock = 0.0
		Story.HOLD:
			if story_clock >= float(story_cards[story_at]["hold"]):
				# A same-beat successor is dissolved to directly, with the level
				# kept covered; only a card with nothing continuing it fades back
				# out to the world. See _begin_swap and _begin_story_out.
				if _successor_keeps_audio():
					_begin_swap()
				else:
					_begin_story_out()
		Story.SWAP:
			if story_clock >= STORY_SWAP:
				story_phase = Story.HOLD
				story_clock = 0.0
		Story.OUT:
			if story_clock >= STORY_OUT:
				_end_story()
				return false  # the level gets the rest of this tick back
	_show_story()
	return true

func _begin_swap() -> void:
	## Cut from this panel to the next of the SAME beat without letting the level
	## show between them: the incoming panel fades in over the outgoing one, which
	## is held solid behind it, and the dim stays full and the world stays frozen.
	## Only the first panel of a beat fades up from the level and only the last
	## fades back to it. The clip is left running (keep_audio) so the dialogue
	## carries across the cut. Falls back to a plain fade-out if there is no next.
	var nxt := story_at + 1
	if nxt >= story_cards.size():
		_begin_story_out()
		return
	var card: Dictionary = story_cards[nxt]
	card["seen"] = true
	# The old panel is held solid underneath while the new one dissolves in.
	story_art_prev.texture = story_art.texture
	story_art_prev.modulate.a = 1.0
	story_art.texture = card["tex"]
	story_at = nxt
	story_phase = Story.SWAP
	story_clock = 0.0
	_set_story_line(str(card["line"]))
	if not bool(card.get("keep_audio", false)):
		_play_story_clip(card["voice"])
	_show_story()

func _begin_story(index: int) -> void:
	var card: Dictionary = story_cards[index]
	card["seen"] = true
	# The same shape begin_swap has: in a suite the beat still happens, it just
	# does not take ten seconds of wall clock to happen in. A test that wants
	# to watch a card turns test_mode off.
	if test_mode:
		_wake_boss()
		return
	story_at = index
	story_phase = Story.IN
	story_clock = 0.0
	player.enabled = false
	player.velocity = Vector2.ZERO
	_freeze_world(true)
	story_art.texture = card["tex"]
	_set_story_line(str(card["line"]))
	story_layer.visible = true
	# Under, not off: see Music.DUCK_DB.
	Music.duck(get_tree(), true)
	# A panel that keeps the previous card's audio does not restart it — the clip
	# runs on under the crossfade, so the dialogue never stutters between panels.
	if not bool(card.get("keep_audio", false)):
		_play_story_clip(card["voice"])
	_show_story()

func _begin_story_out() -> void:
	## The picture starts to go and the level starts again underneath it. The
	## world is let go here and the player at the end of the dissolve, six
	## tenths later, so what the card dissolves into is the dragon already on
	## its way rather than a still of one — and he is not asked to fight
	## through the last of the picture.
	var was := story_alpha()
	story_phase = Story.OUT
	# Out from wherever it had got to, so a skip taken while it is still coming
	# up dissolves from there instead of snapping to full first.
	story_clock = (1.0 - was) * STORY_OUT
	# Whatever the card arrived on stops here whether it had finished or not,
	# which is what makes a skip a skip, and the roar takes its place — UNLESS the
	# next panel is keeping this clip going (a multi-panel beat over one dialogue),
	# in which case it is left running to carry across the crossfade.
	var tail: AudioStream = story_cards[story_at]["tail"] if story_at >= 0 else null
	if tail != null:
		_play_story_clip(tail)
	elif not _successor_keeps_audio():
		_play_story_clip(null)
	_freeze_world(false)
	_wake_boss()

func _successor_keeps_audio() -> bool:
	## Is the card that will follow this one part of the same audio beat — a panel
	## that continues this card's clip rather than starting its own? Checked at a
	## card's dissolve so its clip is left running instead of cut. The successor is
	## the next in the list, which is the order _story_due plays cards at one cue.
	if story_at < 0 or story_at + 1 >= story_cards.size():
		return false
	var next: Dictionary = story_cards[story_at + 1]
	return not bool(next["seen"]) and bool(next.get("keep_audio", false))

func _end_story() -> void:
	story_phase = Story.NONE
	story_clock = 0.0
	story_at = -1
	_freeze_world(false)
	# The loop comes back up. Deliberately NOT stopping story_voice: the first
	# card goes out on a roar and that is meant to carry into the fight.
	Music.duck(get_tree(), false)
	if is_instance_valid(story_layer):
		story_layer.visible = false
		story_dim.color.a = 0.0
		story_art.modulate.a = 0.0
		story_art_prev.modulate.a = 0.0
	if is_instance_valid(player) and state == State.PLAYING:
		player.enabled = true
		# Whatever was held down to skip the card must not also be a jump the
		# instant control comes back: the same guard set_paused keeps.
		player.require_jump_release = true
		player.jump_request_tick = -1000

func skip_story() -> bool:
	## Past it, and the level still starts again: skipping the picture has to
	## leave things in the state watching it does.
	##
	## False when the card refuses to be skipped. `"skip": false` in the level
	## marks one the author wants watched — both of the dragon's are — and the
	## key is still swallowed by the caller either way, so an unskippable card
	## cannot let escape fall through and pause the game behind its own picture.
	if story_phase == Story.NONE or story_phase == Story.OUT:
		return false
	if story_at >= 0 and not bool(story_cards[story_at]["skip"]):
		return false
	_begin_story_out()
	_show_story()
	return true

func _play_story_clip(clip: AudioStream) -> void:
	if not is_instance_valid(story_voice):
		return
	story_voice.stop()
	story_voice.stream = clip
	if clip != null:
		story_voice.play()

func _stop_story_voice() -> void:
	## Cuts whatever the card was saying. For the retry and the level change —
	## a roar carrying over a respawn belongs to a fight that is over.
	if is_instance_valid(story_voice):
		story_voice.stop()

func _set_story_line(line: String) -> void:
	## The card's subtitle, laid out bottom-centred. Sized from the text rather
	## than given a fixed box, so the scrim is a band the height of the line
	## and a two-line caption pushes its own top edge up instead of overflowing.
	if not is_instance_valid(story_line):
		return
	story_line.visible = line != ""
	if line == "":
		return
	story_line.text = line
	story_line.size = Vector2(VIEW_HALF.x * 2.0, 0.0)
	var tall := story_line.get_minimum_size().y
	story_line.size = Vector2(VIEW_HALF.x * 2.0, tall)
	story_line.position = Vector2(0.0, STORY_LINE_BOTTOM - tall)

func _show_story() -> void:
	var lit := story_alpha()
	story_dim.color.a = lit * STORY_DIM
	story_line.modulate.a = lit
	if story_phase == Story.SWAP:
		# Panel-to-panel dissolve within one beat: the new panel fades in over the
		# old, which is held solid behind it, so the level never shows between them.
		story_art.modulate.a = clampf(story_clock / STORY_SWAP, 0.0, 1.0)
		story_art_prev.modulate.a = 1.0
	else:
		story_art.modulate.a = lit
		story_art_prev.modulate.a = 0.0

func _freeze_world(frozen: bool) -> void:
	## Everything in the level that moves under its own steam, stopped where it
	## stands. The player is held separately, by `enabled`, because he is let go
	## later than the rest of it — see _begin_story_out.
	for group in [enemies, blasts, arrows, crates, bottles]:
		for thing in group:
			if is_instance_valid(thing):
				thing.set_physics_process(not frozen)

func _wake_boss() -> bool:
	## The standoff card's last act: the fight starts. Set here rather than left
	## to the boss's own aggro, so that "the picture, then the fight" happens
	## the same way every time — the cue line is outside its 560 and it would
	## otherwise stand on its perch until the player had walked the rest of the
	## way in. A no-op for the card at the end of the fight, which has no live
	## boss left to wake.
	##
	## ALL of them, not the first: The Dragon's Roost fights two bosses at once,
	## and a cutscene that woke only one would leave the other asleep on the deck
	## until its own aggro caught up. Every boss the card hands the level to wakes
	## together.
	var woke := false
	for foe in enemies:
		if is_instance_valid(foe) and foe.is_boss() and foe.alive():
			foe.engaged = true
			woke = true
	return woke

func _add_bottle(bottle: Node2D, entry: Array) -> void:
	## One bottle of either kind, placed and registered. The kind is already
	## settled by the class — see brew.gd on why it cannot be a field set here.
	bottle.position = Vector2(entry[0], entry[1])
	# A bottle is knocked about when hit, same as a crate.
	bottle.fall_limit = float(level.fall_y)
	if entry.size() > 2:
		bottle.refill_segments = int(entry[2])
	bottles.append(bottle)
	add_child(bottle)

## Finishing a level loads the next one in the index. Empty on the last level,
## where there is nothing to advance to.
func next_level_id() -> String:
	var order := catalogue()
	var i := order.find(level_id)
	if i < 0 or i + 1 >= order.size():
		return ""
	return order[i + 1]

func advance_level() -> bool:
	var next := next_level_id()
	if next == "":
		return false
	_swap_now(next)
	return true

# --- the swap between levels -------------------------------------------------

## Changing level is a cut: one frame the flag, the next the new spawn, with
## every pixel on screen different and the music with it. It reads worst at the
## finish, which is where it is always seen — the flag sits about 350 past the
## point the camera stops, so the player is already pressed against the edge of
## a frame that then changes all at once. The screen dips to black and back
## instead, and the swap happens while it is dark.
##
## Presentation only. load_level() and advance_level() still do the work in one
## synchronous call, and test_mode takes that path directly, so a test can call
## confirm(), step two frames and read the result as it always could.
const FADE_OUT := 0.22
const FADE_IN := 0.30
## A moment held at full black between the two halves. Without it the darkest
## frame lasts a single tick and the dip reads as a blink, not a transition.
const FADE_HOLD := 0.09

## Which half is running. Deliberately NOT part of State: the game is still
## COMPLETE or MENU while the screen happens to be dark, and State is recorded
## by the tests as a number that must not shift.
enum Fade { NONE, OUT, HOLD, IN }
var fade_phase: Fade = Fade.NONE
var fade_clock: float = 0.0
## Built in _ready and skipped by _clear_world, because the whole point is that
## it is still covering the screen while the world underneath it is replaced.
var fade_layer: CanvasLayer
var fade_rect: ColorRect
## The level to load once the screen is black. Empty replays the current one.
var swap_to: String = ""

func _make_fade() -> void:
	fade_layer = CanvasLayer.new()
	# Above the HUD, which _build_world adds at the default layer 0.
	fade_layer.layer = 100
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_layer.add_child(fade_rect)
	add_child(fade_layer)

## Take the next level behind a fade. `next_id` empty replays this one.
func begin_swap(next_id: String) -> void:
	if test_mode:
		_swap_now(next_id)
		return
	if fade_phase != Fade.NONE:
		return  # already going; a second confirm must not stack another swap
	swap_to = next_id
	fade_phase = Fade.OUT
	fade_clock = 0.0

func _swap_now(next_id: String) -> void:
	## The swap itself, in one place so the faded path and the immediate one
	## cannot drift. Empty means stay on this level and start it again.
	if next_id != "":
		load_level(next_id)
	start_session()

## Drives the dip. Returns true on the tick the world was replaced, so the
## caller can end its frame there and let the new level start on the next one.
func _advance_fade(delta: float) -> bool:
	fade_clock += delta
	var swapped := false
	match fade_phase:
		Fade.OUT:
			if fade_clock >= FADE_OUT:
				_swap_now(swap_to)
				swap_to = ""
				swapped = true
				fade_phase = Fade.HOLD
				fade_clock = 0.0
		Fade.HOLD:
			if fade_clock >= FADE_HOLD:
				fade_phase = Fade.IN
				fade_clock = 0.0
		Fade.IN:
			if fade_clock >= FADE_IN:
				fade_phase = Fade.NONE
				fade_clock = 0.0
	if is_instance_valid(fade_rect):
		fade_rect.color.a = fade_alpha()
	return swapped

## How black the screen is, 0 to 1. Public so a capture can assert the dip.
func fade_alpha() -> float:
	match fade_phase:
		Fade.OUT:
			return clampf(fade_clock / FADE_OUT, 0.0, 1.0)
		Fade.HOLD:
			return 1.0
		Fade.IN:
			return clampf(1.0 - fade_clock / FADE_IN, 0.0, 1.0)
	return 0.0

## The course order, from levels/index.json. Static because it is the same for
## every session and the menu reads it before a session has been started.
## THE COURSE: what NEW JOURNEY plays through and what each level chains into.
## Not what the level list shows — see listing(), which is a superset.
static func catalogue() -> Array:
	if _catalogue.is_empty():
		_read_index()
	return _catalogue

## EVERY LEVEL THE MENU OFFERS: the course, then anything the index also lists,
## then nothing else. A level can be picked from LOAD GAME without being part of
## the journey — the difference between "playable" and "on the course" — though
## `also_listed` is empty now, so the list is exactly the course. The mechanism
## stays: an id added to also_listed shows up here without being chained into.
##
## Derived from catalogue() rather than read separately, so a test that stands a
## pretend course up in _catalogue gets a menu that matches it.
static func listing() -> Array:
	# catalogue() reads the index (both lists together) on the first call, so
	# _also_listed is already loaded by the time we append it. It is empty now
	# that nothing ships off the course; the loop then adds nothing and the list
	# is exactly the course. (This used to re-read the index whenever _also_listed
	# was empty — a lazy-load guard that mis-fired once empty was a real state.)
	var out: Array = catalogue().duplicate()
	for id in _also_listed:
		if not out.has(id) and not _hidden(id):
			out.append(id)
	return out

## A level that says `"listed": false` stays out of the list however it is
## reached. The test fixture is the only one, and it is one so that nobody is
## ever offered it as something to play.
static func _hidden(id: String) -> bool:
	return not bool(level_data(id).get("listed", true))

static func _read_index() -> void:
	var text := FileAccess.get_file_as_string(LEVEL_DIR + "index.json")
	var parsed = JSON.parse_string(text) if not text.is_empty() else null
	if parsed == null:
		push_error("levels: %sindex.json is missing or unreadable" % LEVEL_DIR)
	if _catalogue.is_empty():
		_catalogue = parsed.get("order", []) if parsed else []
		# An index that parses but lists nothing would leave the menu indexing
		# an empty array, so it falls back rather than crashing on the title screen.
		if _catalogue.is_empty():
			push_error("levels: index.json lists no levels")
			_catalogue = [DEFAULT_LEVEL]
	if _also_listed.is_empty():
		_also_listed = parsed.get("also_listed", []) if parsed else []

## One level file, parsed once. The menu needs every level's title before any of
## them is loaded, so this is keyed by id rather than held by the session.
static func level_data(id: String) -> Dictionary:
	if not _levels.has(id):
		var text := FileAccess.get_file_as_string(LEVEL_DIR + id + ".json")
		if text.is_empty():
			push_error("levels: %s%s.json is missing" % [LEVEL_DIR, id])
			_levels[id] = {}
		else:
			var parsed = JSON.parse_string(text)
			_levels[id] = parsed if parsed else {}
	return _levels[id]

static func level_title(id: String) -> String:
	return str(level_data(id).get("title", id))

## How high and low the camera may look, from the level's own geometry: never
## far above its highest ledge, never past the line a fall is fatal at.
const SKY_ABOVE := 240.0
const BELOW_FALL := 40.0
## How fast the camera gives back the ground a shut gate was holding it off, in
## px per second. The worst case is finishing a fight with your back to the wall,
## which is about 570 px and takes a bit under two thirds of a second — a pan at
## roughly twice a running player's speed. It used to be one frame.
const GATE_RELEASE := 900.0
## How far behind its own target the camera is being held right now. A shut gate
## is the only thing that sets it and it decays to nothing once the gate lets go,
## so it is zero for the whole of ordinary play — which is why nothing about
## ordinary following changed.
var camera_held: float = 0.0

## The camera only moves when the player leaves a band this tall around its
## centre. Without it the view bobs on every jump, since one jump rises 107.
const CAMERA_DEADZONE := 90.0
## How quickly the view settles back onto him once he lands, per physics tick.
const CAMERA_RECENTRE := 0.06

# --- climbing levels ---------------------------------------------------------

## A level that sets `"climb": true` is a tower rather than a course, and two
## things change for it. The view ratchets: it rises as he climbs and never
## comes back down. And the fatal line rides with it instead of sitting at a
## fixed y, so falling off the bottom of the screen is what kills him rather
## than reaching the sea a second and a half later.
##
## Both are one rule in play — the ground you have left is gone — and the second
## is also what makes the first fair. Without it a missed jump near the summit
## is four seconds of watching him drop past scenery he has already beaten.
var climbing: bool = false
## The highest ledge he has STOOD on, and what the view and the fatal line are
## both measured from. INF until he first touches down.
##
## Deliberately his standing height and not his airborne one. One jump rises
## 107 against a 90 deadzone, so ratcheting on where he actually is would lift
## the view 17 px every time he hopped on the spot and never give it back —
## twenty hops standing still and the fatal line is at his feet.
var climb_mark: float = INF
## How far below that ledge the fall becomes fatal. Half a viewport puts the
## line exactly on the bottom edge of the screen; the rest is so that he is
## visibly gone before it takes him rather than dying on the last visible row.
const CLIMB_DROP := VIEW_HALF.y + 50.0

## The line a fall ends at: the level's own sea, or the bottom of the screen on
## a climb, whichever he would meet first. Every level that is not a climb gets
## `fall_y` and nothing else, exactly as before.
func fatal_y() -> float:
	if not climbing or climb_mark == INF:
		return float(level.fall_y)
	return minf(float(level.fall_y), climb_mark + CLIMB_DROP)

func _measure_view() -> void:
	var highest: float = INF
	for entry in level.get("solids", []):
		highest = minf(highest, float(entry[1]))
	if highest == INF:
		highest = 500.0
	view_top = highest - SKY_ABOVE + VIEW_HALF.y
	view_bottom = float(level.get("fall_y", 860)) + BELOW_FALL - VIEW_HALF.y
	if view_bottom < view_top:
		# The whole level fits in one screen, so there is nothing to follow.
		view_top = (view_top + view_bottom) * 0.5
		view_bottom = view_top

## A level that names camera_y pins the camera there. The two greybox levels do,
## to keep the framing they were built and screenshotted with; anything authored
## since simply follows, which is what a level with height needs.
func camera_home_y() -> float:
	if level.has("camera_y"):
		return float(level.camera_y)
	if not is_instance_valid(player):
		return clampf(float(level.get("spawn", [0, 500])[1]), view_top, view_bottom)
	return clampf(player.position.y, view_top, view_bottom)

func _follow_y(current: float) -> float:
	if level.has("camera_y"):
		return float(level.camera_y)
	var target: float = current
	if player.position.y < current - CAMERA_DEADZONE:
		target = player.position.y + CAMERA_DEADZONE
	elif player.position.y > current + CAMERA_DEADZONE:
		target = player.position.y - CAMERA_DEADZONE
	# Once he is standing again, ease back onto him. Without this the camera
	# keeps whatever offset the last descent left it with, which puts the horizon
	# a deadzone above his feet and makes him look waist-deep in the sea.
	if player.is_on_floor():
		target = lerpf(target, player.position.y, CAMERA_RECENTRE)
	# A climb only lets it up. It may still RISE with a jump, which is ordinary
	# following; what it may not do is come back down past the highest ledge he
	# has reached, because that is the line the fall is measured from.
	if climbing:
		target = minf(target, climb_mark)
	return clampf(target, view_top, view_bottom)

## Static, and public, because the title screen needs the same menu_up/menu_down/
## confirm bindings before any session exists. Registering is idempotent, so
## whichever of the two runs first defines them and the other no-ops.
static func setup_input() -> void:
	## W/S and the up/down arrows are free during play — movement is A/D and the
	## left/right arrows — so the menu can have them without a mode switch.
	var actions := {"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT], "jump": [KEY_SPACE], "drink": [KEY_E], "attack": [KEY_J, KEY_X], "blast": [KEY_K, KEY_C], "pause": [KEY_ESCAPE, KEY_P], "restart": [KEY_R], "confirm": [KEY_ENTER], "menu": [KEY_M], "menu_up": [KEY_W, KEY_UP], "menu_down": [KEY_S, KEY_DOWN],
			"music": [KEY_N]}
	for action in actions:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in actions[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)

## Installs a session as the current scene and frees the screen it replaces.
## Static, and public, because two front-end screens hand off this way now: the
## title's rows and the opening storyboard they lead into. The order is the
## point — level_id is set before add_child, which is what boots straight into a
## level instead of into DEFAULT_LEVEL and then changing its mind one frame
## later. Returns the session so the caller can carry a fade across the handoff.
static func boot(tree: SceneTree, id: String, playing: bool) -> Node2D:
	if tree == null:
		return null
	var game = new()
	game.level_id = id
	var outgoing := tree.current_scene
	tree.root.add_child(game)
	tree.current_scene = game
	if playing:
		game.start_session()
	if outgoing != null:
		outgoing.queue_free()
	return game

func _add_solid(rect: Rect2) -> StaticBody2D:
	## Returns the body, which the level's own geometry ignores and the section
	## walls keep: a gate has to be able to switch its own wall off.
	var body := StaticBody2D.new()
	body.position = rect.position + rect.size / 2
	body.collision_layer = 1
	body.collision_mask = 2
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	return body

func _add_area(rect: Rect2, layer: int, spikes: bool) -> Area2D:
	var area := Area2D.new()
	area.position = rect.position
	area.collision_layer = layer
	area.collision_mask = 2
	if spikes:
		# Three exact triangular trigger silhouettes; no oversized invisible box.
		for i in range(3):
			var triangle := CollisionPolygon2D.new()
			var x := float(i) * rect.size.x / 3.0
			var half := rect.size.x / 6.0
			triangle.polygon = PackedVector2Array([Vector2(x, rect.size.y), Vector2(x + half, 0), Vector2(x + half * 2.0, rect.size.y)])
			area.add_child(triangle)
	else:
		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		collision.shape = shape
		collision.position = rect.size / 2.0
		area.add_child(collision)
	add_child(area)
	return area

func start_session() -> void:
	if state == State.PLAYING:
		return
	deaths = 0
	restart_attempt()

func restart_attempt() -> void:
	state = State.PLAYING
	# A card still up when the attempt restarts goes with the attempt, and so
	# does whatever it was saying. It does not play again on the way back up
	# the level — see ONCE PER VISIT.
	_end_story()
	_stop_story_voice()
	elapsed = 0.0
	retry_remaining = 0.0
	# Area2D overlaps are physics-step snapshots. Discard pre-teleport contacts
	# until the broadphase has observed the reset, preventing a phantom second death.
	contact_settle_ticks = 2
	# A crate the player already broke has to come back, or every retry hands
	# them a slightly emptier level than the one they died in.
	for crate in crates:
		crate.reset()
	for bottle in bottles:
		bottle.reset()
	for foe in enemies:
		foe.reset()
		foe.target = player
	drinking_bottle = null
	for blast in blasts:
		if is_instance_valid(blast):
			blast.queue_free()
	blasts.clear()
	for arrow in arrows:
		if is_instance_valid(arrow):
			arrow.queue_free()
	arrows.clear()
	# A retry is a fresh climb: the shafts are swept, every source goes back to
	# its own opening delay, and the view drops to the foot of the tower with
	# the mark it was ratcheting against.
	for stone in stones:
		if is_instance_valid(stone):
			stone.queue_free()
	stones.clear()
	_arm_rockfall()
	climb_mark = INF
	player.reset_at(Vector2(level.spawn[0], level.spawn[1]))
	player.enabled = true
	camera.position = Vector2(VIEW_HALF.x, camera_home_y())
	# Straight back to a hard cut: a retry or a level swap is a cut, not a pan.
	camera_held = 0.0

func set_paused(value: bool) -> void:
	if value and state == State.PLAYING:
		state = State.PAUSED
		player.enabled = false
	elif not value and state == State.PAUSED:
		state = State.PLAYING
		# Not if a story card is still holding him: alt-tabbing away during one
		# pauses the game, and coming back must not be what gives him his legs
		# back four seconds early.
		player.enabled = not story_running()
		player.require_jump_release = true
		player.jump_request_tick = -1000

func _on_focus_lost() -> void:
	## Not while a story card is up. The card is advanced from the PLAYING
	## branch of the tick and owns the keyboard while it runs, so pausing under
	## one stops it where it is with no key left that would start it again —
	## alt-tabbing away for a second would strand the player behind a still
	## picture. Nothing is lost by letting it run: the world under it is frozen
	## either way, and it is four seconds.
	if not test_mode and not story_running():
		set_paused(true)

func _on_player_struck(damage: int, from: Vector2, fling: float = 0.0,
		fire: bool = false) -> void:
	## A punk landed one. He decides he hit; the player decides whether the blow
	## counts, because only the player knows about its own invulnerable window.
	##
	## `fling` is the knockback the blow carries — non-zero only for the Dragon
	## Lord (see fling_for() in enemy.gd) — and `fire` says it was a breath, which
	## the player burns for rather than flinching. The arrow and the falling stone
	## connect this same handler with a two-argument signal, so their hits default
	## both and neither fling nor burn, which is what the defaults keep.
	if state != State.PLAYING:
		return
	var _landed: bool = player.take_damage(damage, from, fling, fire)

func enemies_down() -> int:
	var n := 0
	for foe in enemies:
		if not foe.alive():
			n += 1
	return n

func _on_blast_fired(at: Vector2, direction: float) -> void:
	## The projectile belongs to the level, not to the player: once thrown it
	## keeps its own heading and must not follow him if he turns or dies.
	var blast := Blast.new()
	blast.direction = direction
	blast.position = at
	blasts.append(blast)
	add_child(blast)
	# Everyone gets told. The blast itself is not given the roster and is never
	# told who guarded it — an enemy decides on his own whether he saw it coming
	# in time to get his arms up, which is what makes the answer to a guard be
	# "throw it from closer" rather than anything the projectile knows about.
	# See warn_of_blast in features/combat/enemy.gd.
	# Only as far as the thing can actually fly. An enemy who braces for a blast
	# that dies of old age two hundred px short of him is bracing for nothing,
	# and would stay braced through a fight he is not in.
	for foe in enemies:
		if is_instance_valid(foe) and foe.alive() \
				and absf(foe.global_position.x - at.x) <= Blast.RANGE:
			foe.warn_of_blast(at, direction, Blast.SPEED)

func _on_arrow_fired(at: Vector2, heading: Vector2, damage: int) -> void:
	## The archer's arrow is a level object too: it keeps its heading and reports
	## its hit the same way a melee blow does, through the player's own window.
	var arrow := Arrow.new()
	arrow.heading = heading
	arrow.direction = signf(heading.x) if heading.x != 0.0 else 1.0
	arrow.damage = damage
	arrow.position = at
	arrow.struck_player.connect(_on_player_struck)
	arrows.append(arrow)
	add_child(arrow)

# --- falling rock ------------------------------------------------------------

## A source in a level's `rockfall` is [x, y, every, first]: a stone leaves
## (x, y) every `every` seconds, the first one `first` seconds in, and falls
## straight down its own lane until it meets a ledge, the player, or the sea.
##
## There is no randomness in any of it. A lane learned on one attempt behaves
## identically on the next, which is the only thing that makes a level where a
## single mistake is fatal worth retrying rather than worth resenting.

## How far above him a source may be and still be dropping. Barely more than the
## 540 the screen is tall, so a live shaft is one whose source is just off the
## top of the view — which is also what lets each source wake as he climbs into
## it and go quiet once he is past, with no level having to say when.
const ROCKFALL_REACH := 560.0

func _arm_rockfall() -> void:
	## Every source back to its own opening delay. Called on build and on every
	## retry, so the shafts run to the same rhythm on the twentieth attempt as
	## on the first.
	rockfall_due.clear()
	for entry in level.get("rockfall", []):
		rockfall_due.append(float(entry[3]) if entry.size() > 3 else 0.0)

func _tick_rockfall(_delta: float) -> void:
	var sources: Array = level.get("rockfall", [])
	if sources.is_empty():
		return
	stones = stones.filter(func(s): return is_instance_valid(s))
	for i in mini(sources.size(), rockfall_due.size()):
		if elapsed < rockfall_due[i]:
			continue
		var entry: Array = sources[i]
		# The clock is advanced whether or not a stone comes of it, so the
		# rhythm belongs to the level rather than to where he happens to be.
		# Walking into range mid-cycle means waiting out the rest of it.
		rockfall_due[i] = elapsed + maxf(float(entry[2]), 0.1)
		var at := Vector2(float(entry[0]), float(entry[1]))
		var drop: float = player.position.y - at.y
		if drop <= 0.0 or drop > ROCKFALL_REACH:
			continue
		_drop_stone(at)

func _drop_stone(at: Vector2) -> Node2D:
	var stone := Stone.new()
	stone.position = at
	# Past the sea rather than at it: a stone with nothing under it should leave
	# the screen falling, not wink out on the waterline.
	stone.fall_limit = float(level.fall_y) + 80.0
	stone.struck_player.connect(_on_player_struck)
	stones.append(stone)
	add_child(stone)
	return stone

## How close he has to be to pick something up. Generous, like the bottle's
## drink reach: this is "am I standing at it", not "am I touching it".
const PICKUP_RANGE := Vector2(54.0, 70.0)

func to_hud(at: Vector2) -> Vector2:
	## A point in the world, in the HUD's own 640x360 design space.
	##
	## Here rather than in hud.gd because the three numbers it needs — where the
	## camera is, half a viewport, and the scale the HUD layer is drawn at — all
	## live here, and a second copy of them is a second place to be wrong. It is
	## what lets a prompt be drawn OVER the thing it is about instead of in the
	## middle of the screen.
	if not is_instance_valid(camera):
		return at
	return (at - camera.position + VIEW_HALF) / HUD_SCALE

func carryable_in_reach() -> Node2D:
	## The nearest thing he could pick up, or null. Crates and bottles are the
	## same question, so they are asked it the same way rather than the bottle
	## keeping its own private answer.
	var best: Node2D = null
	var best_gap := INF
	for prop in (crates + bottles):
		if not is_instance_valid(prop) or not prop.can_be_carried():
			continue
		var gap: Vector2 = prop.global_position - player.global_position
		if absf(gap.x) > PICKUP_RANGE.x or absf(gap.y) > PICKUP_RANGE.y:
			continue
		if absf(gap.x) < best_gap:
			best_gap = absf(gap.x)
			best = prop
	return best

func pick_up() -> bool:
	## Lifts whatever is at his feet. Deliberately not automatic on contact: the
	## tutorial is teaching that picking things up is an action, the same reason
	## drinking is not automatic.
	if state != State.PLAYING or player.is_carrying():
		return false
	var prop := carryable_in_reach()
	if prop == null:
		return false
	return player.begin_pickup(prop, bool(prop.heavy))

func bottle_being_carried() -> Node2D:
	## The bottle in his hands, or null. The HUD asks so it can prompt to drink
	## rather than to pick up.
	if not player.is_carrying():
		return null
	return player.carrying if bottles.has(player.carrying) else null

func _on_threw(object: Node2D, velocity: Vector2) -> void:
	## The object leaves his hands and becomes a live thing again. Everything
	## after this is prop.gd: it flies, it hits what is on the Hittable layer,
	## and it comes apart on whatever it reaches first.
	if is_instance_valid(object):
		object.launch(velocity)

func drink() -> bool:
	## Starts a six-second drink on the bottle in reach. Deliberately not
	## automatic on touch: the tutorial is teaching that the action exists, which
	## a silent pickup does not do. Drinking at full health is refused rather
	## than wasting the bottle, and so is drinking a brown one on full mana.
	##
	## Nothing is spent and nothing is restored here — see _on_drink_ended.
	## He has to be holding it. Picking it up is its own beat now, so the bottle
	## is lifted first and drunk second.
	if state != State.PLAYING or not player.is_carrying():
		return false
	var held: Node2D = player.carrying
	if not bottles.has(held) or not held.available():
		return false
	if player.refill_full(held.refills):
		return false
	if not player.begin_drink(held.refill_segments, held.contents, held.refills):
		return false
	# The bottle leaves the ground the moment he raises it, and the one in his
	# hand is drawn by the visual at the frame's weapon point, exactly as LF2
	# composites a held object.
	# Already in his hands, so nothing is lifted here. Six seconds from now
	# _on_drink_ended decides whether it was spent.
	held.set_drinking(true)
	drinking_bottle = held
	return true

func _on_drink_ended(_completed: bool, reason: String) -> void:
	## The only place a bottle is ever spent, and it is spent by the mouthful.
	## Whatever he swallowed comes out of the bottle; an empty one is gone, and
	## anything left goes back on the floor to be finished later.
	if not is_instance_valid(drinking_bottle):
		drinking_bottle = null
		return
	var bottle: Area2D = drinking_bottle
	drinking_bottle = null
	bottle.set_drinking(false)
	bottle.set_contents(player.last_drink_left)
	# He is still holding it, whatever stopped him — a drink interrupted is a
	# bottle lowered from his mouth, not dropped, so he can start again without
	# bending down for it. Only draining it takes it off his hands.
	if bottle.consumed and player.carrying == bottle:
		player.drop_carried()

func crates_broken() -> int:
	var count := 0
	for crate in crates:
		if crate.broken:
			count += 1
	return count

func resolve_contacts(fatal: bool, finished: bool) -> void:
	if state != State.PLAYING:
		return
	if fatal:
		state = State.DYING
		deaths += 1
		retry_remaining = 0.55
		player.enabled = false
		player.velocity = Vector2.ZERO
		player.on_death()
	elif finished:
		state = State.COMPLETE
		last_finish_time = elapsed
		player.enabled = false
		player.velocity = Vector2.ZERO

func _physics_process(delta: float) -> void:
	# Ahead of the state machine, and a swap ends the tick: the world it just
	# built should start on the next one, not half way through this one.
	if fade_phase != Fade.NONE and _advance_fade(delta):
		return
	if state == State.DYING:
		retry_remaining -= delta
		if retry_remaining <= 0:
			restart_attempt()
	elif state == State.PLAYING and not _advance_story(delta):
		# _advance_story is false for every frame of every level that has no
		# card, which is every level but one, so nothing below has changed.
		#
		# The level's own loop, or the boss's while one is fighting you — see
		# current_track(). cue() is a no-op when the name already matches, so
		# on every level that names no boss track this is a string compare.
		# Not while a card is up: _advance_story ducks the loop and owns it
		# until it hands the level back.
		Music.cue(get_tree(), current_track())
		elapsed += delta
		blasts = blasts.filter(func(b): return is_instance_valid(b))
		arrows = arrows.filter(func(a): return is_instance_valid(a))
		# He carries the bottle now, so he cannot walk away from it — the old
		# out-of-reach interruption is gone with the reach. What can still
		# happen is losing hold of it: knocked out of his hands, or smashed
		# while he drinks.
		if player.is_drinking() and (not is_instance_valid(drinking_bottle)
				or player.carrying != drinking_bottle):
			player.interrupt_drink(player.DRINK_LEFT)
		elif player.is_drinking():
			# The bottle empties as he drinks, not when he stops.
			drinking_bottle.set_contents(player.drink_fill_left())
		# The mark only moves when he LANDS — see climb_mark — and on anything
		# that is not a climb neither line runs at all.
		if climbing and player.is_on_floor():
			climb_mark = minf(climb_mark, player.position.y)
		_tick_rockfall(delta)
		var fatal := player.position.y > fatal_y()
		# The cause line under the MISSION FAILED banner — see the DYING branch in
		# ui/hud.gd. Kept generic rather than naming a foe: the same line has to
		# read right whether a bandit, a hunter or a dragon finished him.
		death_reason = "You missed the landing" if fatal else "The spikes got you"
		# An empty bar is fatal on the same terms as a pit: the session decides,
		# the player only spends the health. Checked before the hazards so the
		# reason names what actually finished him.
		if not fatal and player.health <= 0:
			fatal = true
			death_reason = "You were beaten"
		for hazard in hazard_areas:
			fatal = fatal or hazard.overlaps_body(player)
		if contact_settle_ticks > 0:
			contact_settle_ticks -= 1
		else:
			resolve_contacts(fatal, goal.overlaps_body(player))
		_sync_gates()
		_sync_descent()
		# Lookahead is a world distance and does not scale with the viewport; the
		# bound is half the viewport, so the camera stops before either end of the
		# level would come into shot.
		#
		# A shut gate pulls that far bound in to itself, which is what makes the
		# wall legible: the fight is framed, and the wall lands exactly on the
		# right edge of the screen rather than somewhere off in the dark.
		var far: float = float(level.width) - VIEW_HALF.x
		var shut := gate_shut_at()
		if shut < INF:
			far = minf(far, shut - VIEW_HALF.x + GATE_INSET)
		# Tightens at once, lets go slowly. Walking into a fight should frame it
		# on the frame you arrive; walking out of one should pan.
		#
		# This is the only smoothing on the camera's x and it exists for one
		# moment: the frame the last enemy in a section falls. A shut gate holds
		# the far edge at the wall; clearing the section moved that edge to the
		# end of the level in a single frame, so a player who finished the fight
		# pressed against the wall — which is where a fight backed into a gate
		# always ends — got the whole world yanked 570 px sideways under him,
		# usually while still mid-swing.
		#
		# Kept as the DISTANCE the camera is being held back rather than as a
		# smoothed position, because that number is exactly zero for the whole of
		# ordinary play: no gate, nothing held, camera on its mark to the pixel
		# the way it has always been. Only the release is eased, and only while
		# it lasts.
		# The near edge is half a viewport into the level, or the door shut
		# behind a boss fight when there is one — same inset as the far edge,
		# so the wall lands just inside the screen instead of exactly on it and
		# he is never the thing that gets clipped.
		var near: float = VIEW_HALF.x
		var behind := gate_behind_at()
		if behind > -INF:
			near = maxf(near, behind + VIEW_HALF.x - GATE_INSET)
		var want: float = maxf(player.position.x + 200, near)
		var bound: float = maxf(far, near)
		if want > bound:
			camera_held = want - bound          # held: exact, and it snaps
		else:
			camera_held = maxf(0.0, camera_held - GATE_RELEASE * delta)
		# Clamped to `near` after the hold as well as before it: the hold is a
		# distance left over from a gate that has just opened, and it must not
		# drag the view back through a door that is still shut.
		camera.position.x = maxf(want - camera_held, near)
		camera.position.y = _follow_y(camera.position.y)
	if is_instance_valid(hud):
		hud.queue_redraw()
	# The background parallaxes against the camera, so it is redrawn with it.
	if is_instance_valid(scenery):
		scenery.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if story_running() and state == State.PLAYING:
		# A card owns the keyboard while it is up — but only while the tick is
		# actually advancing it, so that a card left up by anything that paused
		# the game still has escape to get out from under it. Three actions end it early —
		# space is what a player presses at a cutscene, enter confirms and
		# escape gets out of things — and nothing else reaches the game under
		# it. The same three ui/storyboard.gd skips the opening on.
		if event.is_action_pressed("jump") or event.is_action_pressed("confirm") \
				or event.is_action_pressed("pause"):
			# Swallowed whether or not this card lets itself be skipped: see
			# skip_story.
			var _skipped: bool = skip_story()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("menu_up") and state == State.MENU:
		menu_index = posmod(menu_index - 1, listing().size())
	elif event.is_action_pressed("menu_down") and state == State.MENU:
		menu_index = posmod(menu_index + 1, listing().size())
	elif event.is_action_pressed("confirm"):
		confirm()
	elif event.is_action_pressed("pause"):
		set_paused(state != State.PAUSED)
	elif event.is_action_pressed("drink"):
		# One key for both beats: drink what you are already holding, or lift
		# what is at your feet.
		if not drink():
			pick_up()
	elif event.is_action_pressed("restart") and state in [State.PLAYING, State.PAUSED, State.DYING]:
		restart_attempt()
	elif event.is_action_pressed("menu") and state in [State.PAUSED, State.COMPLETE]:
		open_menu()
	elif event.is_action_pressed("music") and state == State.PAUSED:
		# Offered on the pause screen only, which is where it is labelled. N rather
		# than M, which is already the way back to the main menu.
		Music.toggle(get_tree())
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var at: Vector2 = hud.get_local_mouse_position()
		var row: int = hud.row_at(at)
		if state == State.MENU and row >= 0:
			menu_index = row
			confirm()
		elif hud.music_rect().has_point(at):
			# Ahead of the confirm button: the four share a row while paused, and
			# a click that missed one used to fall through and resume the game.
			Music.toggle(get_tree())
		elif hud.restart_rect().has_point(at):
			restart_attempt()
		elif hud.menu_rect().has_point(at):
			open_menu()
		elif hud.button_rect().has_point(at):
			confirm()

func open_menu() -> void:
	## The menu opens on the level you were just in, not back at the top.
	state = State.MENU
	menu_index = maxi(listing().find(level_id), 0)
	if is_instance_valid(player):
		player.enabled = false

func confirm() -> void:
	## One button, three meanings: start the highlighted level, resume, or take
	## the next one. Reachable from the keyboard and from the HUD button alike.
	match state:
		State.MENU:
			# The list, not the course: LOAD GAME offers every level that ships.
			var rows := listing()
			var pick: String = rows[clampi(menu_index, 0, rows.size() - 1)]
			begin_swap(pick if pick != level_id else "")
		State.COMPLETE:
			# The last level has nowhere to advance to, so it replays instead.
			begin_swap(next_level_id())
		State.PAUSED:
			set_paused(false)

func _draw() -> void:
	if level.is_empty():
		return
	# The flag and the painted area names belong to the LEVEL rather than to
	# either renderer, so both get them. They used to live in the greybox block
	# below, which a themed level skips wholesale — so on The Fractured Isles the
	# finish was an invisible rectangle you walked into and six authored signs
	# were never once on screen. scenery.gd draws cliffs and set dressing from
	# the solids and has no idea where the level ends; this does.
	_draw_markers()
	# A themed level draws its world in scenery.gd from this same level data.
	# Everything below is the original greybox, kept for the levels without one.
	if is_instance_valid(scenery):
		return
	var ink := Color("25354a")
	# Hazard and finish decoration read their geometry from the level data now, so a
	# future rescale moves the art with the collision instead of drifting off it.
	var floor_y: float = level.solids[0][1]
	var width: float = level.width
	# Label positions are world coordinates and scaled with the level, but the
	# viewport did not scale, so font sizes and line widths stay as they were:
	# one world unit is still one on-screen logical pixel.
	# All visual assets are original Godot vector drawing, not recovered art.
	draw_rect(Rect2(-800, -400, 3600, 1800), Color("f6f3ec"))
	for x in range(0, int(width) + 1, 64):
		draw_line(Vector2(x, 160), Vector2(x, floor_y), Color("e7e5df"), 1)
	for y in range(192, int(floor_y) + 1, 64):
		draw_line(Vector2(0, y), Vector2(width, y), Color("e7e5df"), 1)
	# Hill peaks are level data. A level that names none gets six spaced evenly
	# across its width, so a new level is never authored against a blank sky.
	var hills: Array = level.get("hills", [])
	if hills.is_empty():
		for i in range(6):
			hills.append(width * (float(i) + 0.5) / 6.0)
	for x in hills:
		draw_colored_polygon(PackedVector2Array([Vector2(x-190,floor_y),Vector2(x,floor_y-190),Vector2(x+190,floor_y)]), Color("e4e8e3"))
	for entry in level.solids:
		var r := Rect2(entry[0], entry[1], entry[2], entry[3])
		draw_rect(r, ink)
		draw_rect(Rect2(r.position, Vector2(r.size.x, 8)), Color("438e7d"))
		for x in range(int(r.position.x)+24, int(r.end.x), 48):
			draw_line(Vector2(x, r.position.y+24), Vector2(x+14, r.position.y+38), Color("405166"), 2)
	for entry in level.hazards:
		var spike_base: float = entry[1] + entry[3]
		var spike_w: float = entry[2] / 3.0
		for i in range(3):
			var x: float = entry[0] + i * spike_w
			draw_colored_polygon(PackedVector2Array([Vector2(x,spike_base),Vector2(x+spike_w*0.5,entry[1]),Vector2(x+spike_w,spike_base)]), Color("d24e42"))

## The painted area names — see the note in _draw about why these are not part
## of the greybox above.
##
## The end of the level used to be drawn here too: a pole and a pennant, three
## flat polygons. It is features/world/portal.gd now, a node of its own, because
## what stands there moves and this canvas is redrawn once per level.
func _draw_markers() -> void:
	var font := ThemeDB.fallback_font
	var ink := Color("25354a")
	# Signs are painted on the background from the level file: [x, y, heading]
	# or [x, y, heading, subtitle]. They were three hard-coded draw_string calls
	# naming First Steps' own zones, which no second level could ever reuse.
	#
	# Outlined, because these now sit over painted sky and cliffs rather than
	# over a flat greybox page: dark text alone vanished against the rock.
	for marker in level.get("signs", []):
		var at := Vector2(float(marker[0]), float(marker[1]))
		draw_string_outline(font, at, str(marker[2]), HORIZONTAL_ALIGNMENT_LEFT,
				-1, 15, 5, Color("f6f3ec"))
		draw_string(font, at, str(marker[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ink)
		if marker.size() > 3:
			var under := at + Vector2(0.0, 22.0)
			draw_string_outline(font, under, str(marker[3]),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 5, Color("f6f3ec"))
			draw_string(font, under, str(marker[3]), HORIZONTAL_ALIGNMENT_LEFT,
					-1, 13, ink)
