extends SceneTree
## The Dragon's Roost with both bosses: the dragon and the Dragon Lord side by
## side, the two-boss plate (green Lord, red dragon), the leap-slam, and the
## player flung off his feet. Needs a renderer — run WITHOUT --headless.
const Game = preload("res://game/session.gd")
var game: Node2D
var lord: Area2D
var flyer: Area2D

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

var output: String

func run() -> void:
	output = ProjectSettings.globalize_path("res://../evidence/roost")
	DirAccess.make_dir_recursive_absolute(output)
	game = Game.new()
	game.level_id = "dragons_roost"
	root.add_child(game)
	game.start_session()
	game.player.test_control = true
	await step()
	for foe in game.enemies:
		if foe.kind == "dragon_lord":
			lord = foe
		elif foe.kind == "dragon":
			flyer = foe
	var deck := 648.0

	# 1) Side by side at the mouth of the fight, both awake, both bars full.
	#    Captured within a few frames of the wake: the dragon takes off almost at
	#    once, so this catches the pair of them still on the deck together.
	game.player.position = Vector2(lord.home.x - 360.0, deck)
	game.player.velocity = Vector2.ZERO
	lord.target = game.player
	flyer.target = game.player
	lord.engaged = true
	flyer.engaged = true
	for i in range(4):
		await step()
		game.player.position = Vector2(lord.home.x - 360.0, deck)
		game.player.velocity = Vector2.ZERO
		game.player.health = game.player.MAX_HEALTH
	await shoot("01-two-bosses-side-by-side")

	# 2) Two bars, two bosses: knock the Lord to ~60% and the dragon to ~30% so
	#    the green (Lord) and the red (dragon) read as clearly different levels.
	lord.health = int(lord.max_health * 0.6)
	flyer.health = int(flyer.max_health * 0.3)
	for i in range(45):
		await step()
		game.player.position = Vector2(lord.home.x - 360.0, deck)
		game.player.velocity = Vector2.ZERO
		game.player.health = game.player.MAX_HEALTH
	await shoot("02-a-bar-for-each-boss")

	# Park the flyer on its perch for the Lord's own shots, so the camera and the
	# action are his.
	flyer.reset()
	flyer.target = null
	flyer.engaged = false

	# 3 & 4) The leap-slam: airborne on the way down, then the ground shock.
	lord.reset()
	lord.target = game.player
	lord.engaged = true
	lord.special_ready = 0.0
	lord.cooldown = 0.0
	game.player.position = Vector2(lord.home.x - 80.0, deck)
	var shot_air := false
	var shot_impact := false
	for i in range(200):
		await step()
		game.player.position = Vector2(lord.home.x - 80.0, deck)
		game.player.velocity = Vector2.ZERO
		game.player.health = game.player.MAX_HEALTH
		if lord.move == "slam" and not lord.grounded and not shot_air:
			shot_air = true
			await shoot("03-leap-slam-airborne")
		if lord.move == "slam" and lord.slam_hit and not shot_impact:
			shot_impact = true
			await shoot("04-slam-impact")
			break
	print("slam: air=%s impact=%s" % [shot_air, shot_impact])

	# 5) Flung: a plain swing throws the player off his feet, and he is caught in
	#    the air on the way back.
	lord.reset()
	lord.target = game.player
	lord.engaged = true
	lord.special_ready = 999.0    # a swing, not the slam
	lord.cooldown = 0.0
	game.player.reset_at(Vector2(lord.home.x - 70.0, deck))
	game.player.enabled = true
	var shot_fling := false
	for i in range(200):
		await step()
		if not game.player.is_on_floor() and game.player.fling_t > 0.0 and not shot_fling:
			shot_fling = true
			await shoot("05-player-flung")
			break
		# Keep him in the Lord's reach until the blow lands.
		if game.player.is_on_floor() and game.player.fling_t <= 0.0:
			game.player.position = Vector2(lord.home.x - 70.0, deck)
			game.player.velocity = Vector2.ZERO
		game.player.health = game.player.MAX_HEALTH
	print("fling shot=%s" % shot_fling)
	quit()
