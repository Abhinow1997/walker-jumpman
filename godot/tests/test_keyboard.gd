extends SceneTree
const Game = preload("res://game/session.gd")
var game: Node2D
var results: Array[Dictionary] = []
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func steps(n: int) -> void:
	for i in range(n):
		await physics_frame
		await process_frame

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await steps(2)

func tap(code: Key) -> void:
	await key(code,true)
	await key(code,false)

func check(id: String, condition: bool, observed: String) -> void:
	results.append({"id":id,"status":"PASS" if condition else "FAIL","observed":observed})
	print(JSON.stringify(results.back()))
	if not condition: failures += 1

func run() -> void:
	game = Game.new()
	game.test_mode = true
	root.add_child(game)
	await steps(2)
	await tap(KEY_ENTER)
	check("enter-start",game.state == Game.State.PLAYING,"state="+str(game.state))
	await key(KEY_D,true)
	await steps(10)
	await key(KEY_D,false)
	check("keyboard-move",game.player.position.x > 170,"x="+str(game.player.position.x))
	await tap(KEY_SPACE)
	check("keyboard-jump",game.player.jumps == 1 and game.player.velocity.y < 0,"jumps="+str(game.player.jumps))
	await tap(KEY_ESCAPE)
	var y: float = game.player.position.y
	await steps(5)
	check("escape-pause",game.state == Game.State.PAUSED and game.player.position.y == y,"state="+str(game.state))
	await tap(KEY_ENTER)
	check("enter-resume",game.state == Game.State.PLAYING,"state="+str(game.state))
	await tap(KEY_R)
	check("r-retry",game.player.position.distance_to(Vector2(128,640)) < 1 and game.deaths == 0,"position="+str(game.player.position))
	game.resolve_contacts(false,true)
	await tap(KEY_ENTER)
	check("enter-replay",game.state == Game.State.PLAYING and game.player.jumps == 0,"state="+str(game.state))
	await tap(KEY_P)
	await tap(KEY_M)
	check("pause-main-menu",game.state == Game.State.MENU,"state="+str(game.state))
	await tap(KEY_ENTER)
	check("menu-start-again",game.state == Game.State.PLAYING,"state="+str(game.state))
	var out := ProjectSettings.globalize_path("res://../evidence")
	DirAccess.make_dir_recursive_absolute(out)
	var file := FileAccess.open(out+"/keyboard-"+str(Time.get_unix_time_from_system())+".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope":"Synthetic keyboard events through Godot Input, not human playtesting", "engine":Engine.get_version_info().string,"results":results,"failures":failures},"  "))
	file.close()
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
