extends SceneTree
## Diagnostic: the pause screen's music toggle. Headless is fine — nothing here
## listens, it reads the mixer level and the button geometry.
const Game = preload("res://game/session.gd")
const Music = preload("res://game/music.gd")
var game: Node2D
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func step() -> void:
	await physics_frame
	await process_frame

func check(id: String, passed: bool, observed: Dictionary) -> void:
	if not passed:
		failures += 1
	print(JSON.stringify({"id": id, "status": "PASS" if passed else "FAIL",
						  "observed": observed}))

func node() -> AudioStreamPlayer:
	return root.get_node_or_null(Music.NODE)

func run() -> void:
	Music.muted = false
	game = Game.new()
	game.test_mode = true
	game.level_id = "fractured_isles"      # a level that names a track
	root.add_child(game)
	game.start_session()
	await step()

	check("the-level-cued-its-track", node() != null and node().track == "magic_cliffs",
		{"track": node().track if node() else "<no node>",
		 "db": node().volume_db if node() else 0.0})
	check("it-starts-audible", is_equal_approx(node().volume_db, Music.LEVEL_DB),
		{"db": node().volume_db, "expected": Music.LEVEL_DB})

	# The toggle is only offered on the pause screen.
	check("no-toggle-while-playing", game.hud.music_rect().size.x == 0.0,
		{"rect": str(game.hud.music_rect()), "state": game.state})
	game.set_paused(true)
	await step()
	var toggle: Rect2 = game.hud.music_rect()
	check("paused-offers-the-toggle", toggle.size.x > 0.0,
		{"rect": str(toggle), "label": game.hud.music_label()})
	check("the-toggle-clears-the-resume-button",
		not toggle.intersects(game.hud.button_rect()),
		{"toggle": str(toggle), "resume": str(game.hud.button_rect())})

	# The click path cannot be driven from here: the session reads the LIVE mouse
	# position rather than the event's — shared with the confirm button, which
	# has always worked that way — so a synthetic click has nowhere to aim. What
	# IS testable is the routing it depends on. The toggle is hit-tested before
	# the resume button, so the two must not overlap (checked above), and a
	# hidden toggle must swallow nothing.
	game.set_paused(false)
	await step()
	check("a-hidden-toggle-catches-no-click",
		not game.hud.music_rect().has_point(Vector2.ZERO)
		and not game.hud.music_rect().has_point(toggle.get_center()),
		{"rect": str(game.hud.music_rect()), "state": game.state})
	game.set_paused(true)
	await step()

	game._unhandled_input(_press("music"))
	await step()
	check("the-key-silences-the-music",
		Music.muted and is_equal_approx(node().volume_db, Music.SILENT_DB),
		{"muted": Music.muted, "db": node().volume_db,
		 "label": game.hud.music_label()})
	check("it-is-still-the-same-track-playing",
		node().playing and node().track == "magic_cliffs",
		{"playing": node().playing, "track": node().track})

	game._unhandled_input(_press("music"))
	await step()
	check("the-key-brings-it-back",
		not Music.muted and is_equal_approx(node().volume_db, Music.LEVEL_DB),
		{"muted": Music.muted, "db": node().volume_db})

	# Not offered anywhere but the pause screen.
	game.set_paused(false)
	await step()
	game._unhandled_input(_press("music"))
	await step()
	check("the-key-does-nothing-while-playing", not Music.muted,
		{"muted": Music.muted, "state": game.state})
	game.set_paused(true)
	await step()

	# Silenced, a level change must not turn it back on.
	game._unhandled_input(_press("music"))
	await step()
	game.load_level("first_steps")
	game.start_session()
	await step()
	check("a-level-change-leaves-it-silenced",
		Music.muted and is_equal_approx(node().volume_db, Music.SILENT_DB),
		{"muted": Music.muted, "db": node().volume_db, "level": game.level_id})

	# So must a brand new session, which is what the title screen builds.
	game.queue_free()
	await step()
	var second := Game.new()
	second.test_mode = true
	second.level_id = "fractured_isles"
	root.add_child(second)
	second.start_session()
	await step()
	check("a-new-session-leaves-it-silenced",
		Music.muted and is_equal_approx(node().volume_db, Music.SILENT_DB),
		{"muted": Music.muted, "db": node().volume_db})

	Music.silence(self, false)
	print("MUSIC DIAG: %d failure(s)" % failures)
	quit()

func _press(action: String) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	return e
