extends SceneTree
## The three modal overlays — the level select, the pause message and the
## results — now that they wear the UI kit's panels. Needs a renderer.
const Game = preload("res://game/session.gd")
var game: Node2D
var output: String
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func step() -> void:
	await physics_frame
	await process_frame

func shoot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png("%s/%s.png" % [output, label])
	assert(err == OK)
	print("shot %s" % label)

func check(id: String, passed: bool, observed: Dictionary) -> void:
	if not passed:
		failures += 1
	print(JSON.stringify({"id": id, "status": "PASS" if passed else "FAIL",
						  "observed": observed}))

func run() -> void:
	output = ProjectSettings.globalize_path("res://../evidence/overlays")
	DirAccess.make_dir_recursive_absolute(output)
	var shipped: Array = Game.catalogue().duplicate()

	# A three-level course, so the list has rows to lay out. The shipped order
	# is one level long and would show a menu of one.
	Game._catalogue = ["fractured_isles", "first_steps", "the_climb"]
	game = Game.new()
	game.test_mode = true
	game.level_id = "fractured_isles"
	root.add_child(game)
	await step()
	check("the-panel-art-loaded", not game.hud.panels.is_empty(),
		{"panels": game.hud.panels.keys()})

	game.open_menu()
	for i in range(3): await step()
	var menu_rect: Rect2 = game.hud.panel_rect()
	check("the-menu-wears-the-big-panel", game.hud._panel_name() == "panel_menu",
		{"panel": game.hud._panel_name(), "rect": str(menu_rect)})
	check("the-menu-panel-is-on-screen",
		menu_rect.position.y >= 0.0 and menu_rect.end.y <= 360.0
		and menu_rect.position.x >= 0.0 and menu_rect.end.x <= 640.0,
		{"rect": str(menu_rect)})
	# Every row has to land inside the parchment, or the list is written on the
	# frame — which is the thing a fixed piece of art makes possible to get wrong.
	var inner: Rect2 = game.hud._face("interior")
	var inside := true
	for i in Game.catalogue().size():
		var row: Rect2 = game.hud._row_rect(i)
		if not (inner.encloses(Rect2(row.position, row.size)) or inner.intersects(row)):
			inside = false
		if row.end.y > game.hud._face("text_box").position.y:
			inside = false
	check("the-rows-fit-above-the-card", inside,
		{"rows": Game.catalogue().size(), "interior": str(inner),
		 "last_row": str(game.hud._row_rect(Game.catalogue().size() - 1))})
	check("the-button-clears-the-panel",
		game.hud.button_rect().position.y >= menu_rect.end.y
		and game.hud.button_rect().end.y <= 360.0,
		{"button": str(game.hud.button_rect()), "panel_bottom": menu_rect.end.y})
	# The session hit-tests clicks against these two, so a panel that moved has
	# to move them with it or the menu becomes unclickable by mouse.
	var round_trips := true
	for i in Game.catalogue().size():
		var row: Rect2 = game.hud._row_rect(i)
		if game.hud.row_at(row.position + row.size * 0.5) != i:
			round_trips = false
	check("clicking-a-row-picks-that-row", round_trips,
		{"rows": Game.catalogue().size()})
	check("clicking-off-the-list-picks-nothing",
		game.hud.row_at(Vector2(10, 10)) == -1
		and game.hud.row_at(game.hud.button_rect().get_center()) == -1,
		{"corner": game.hud.row_at(Vector2(10, 10))})
	await shoot("01-menu")

	game.menu_index = 1
	for i in range(2): await step()
	await shoot("02-menu-second-row")

	game.start_session()
	for i in range(3): await step()
	game.set_paused(true)
	for i in range(3): await step()
	check("pause-wears-the-pop-up", game.hud._panel_name() == "panel_popup",
		{"panel": game.hud._panel_name(), "state": game.state})
	await shoot("03-paused")
	# And with the music turned off, which is what that second plate is for.
	var Music = load("res://game/music.gd")
	Music.silence(self, true)
	for i in range(2): await step()
	check("the-toggle-relabels-when-silenced",
		game.hud.music_label().contains("ON"),
		{"label": game.hud.music_label(), "muted": Music.muted})
	await shoot("03b-paused-music-off")
	Music.silence(self, false)
	for i in range(2): await step()

	game.set_paused(false)
	game.state = Game.State.COMPLETE
	game.last_finish_time = 42.5
	game.deaths = 3
	for i in range(3): await step()
	await shoot("04-complete")

	Game._catalogue = shipped
	print("OVERLAYS: %d failure(s)" % failures)
	quit()
