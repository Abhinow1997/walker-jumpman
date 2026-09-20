extends SceneTree
## The boss health plate, shot at the states that matter. Needs a renderer —
## run WITHOUT --headless.
##
## The plate carries two bars showing one number at two speeds: green is the
## dragon's health now, magma is the same health a moment ago. The band of red
## between them after a hit is the point of the art, and it only exists for
## about half a second, so it is shot deliberately rather than hoped for.
const Game = preload("res://game/session.gd")

const LEVEL := "dragons_roost"
const DECK := 648.0

var game: Node2D
var wyrm: Area2D
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
	print("shot %-28s health %3d/%d  green %.2f  magma %.2f" % [
		label, wyrm.health, wyrm.max_health,
		game.hud.boss_shown["health"], game.hud.boss_shown["magma"]])

func check(id: String, passed: bool, observed: Dictionary) -> void:
	if not passed:
		failures += 1
	print(JSON.stringify({"id": id, "status": "PASS" if passed else "FAIL",
						  "observed": observed}))

func hold(ticks: int) -> void:
	for i in range(ticks):
		game.player.health = game.player.MAX_HEALTH
		await step()

func run() -> void:
	output = ProjectSettings.globalize_path("res://../evidence/bossbar")
	DirAccess.make_dir_recursive_absolute(output)
	game = Game.new()
	game.test_mode = true
	game.level_id = LEVEL
	root.add_child(game)
	game.start_session()
	game.player.test_control = true
	await step()
	wyrm = game.enemies[0]
	check("the-plate-art-is-imported",
		game.hud.boss_plate != null and game.hud.boss_bars.size() == 2,
		{"plate": game.hud.boss_plate != null, "bars": game.hud.boss_bars.keys()})

	# 01 — before the fight. No plate: the dragon is on its perch and has not
	# noticed anybody, and a boss bar for a boss you have not met is a spoiler.
	game.player.position = Vector2(wyrm.home.x - wyrm.aggro - 80.0, DECK)
	game.player.velocity = Vector2.ZERO
	await hold(20)
	await shoot("bossbar-01-before-the-fight")
	check("no-plate-until-it-notices-you",
		not wyrm.engaged and game.hud.boss() == null,
		{"engaged": wyrm.engaged})

	# 02 — full, the moment the fight starts.
	game.player.position = Vector2(wyrm.home.x - 420.0, DECK)
	game.player.velocity = Vector2.ZERO
	await hold(30)
	await shoot("bossbar-02-full")
	check("the-plate-is-up-and-full",
		game.hud.boss() == wyrm and float(game.hud.boss_shown["health"]) > 0.98,
		{"green": game.hud.boss_shown["health"]})

	# 03 — a blow just landed. Green has dropped and magma has not caught up:
	# the gap between them is the damage, and it is the whole reason the plate
	# is drawn with two tracks.
	var _hit: bool = wyrm.take_hit(90, game.player.global_position)
	await hold(9)
	await shoot("bossbar-03-the-hit-shows-as-a-gap")
	var green: float = float(game.hud.boss_shown["health"])
	var magma: float = float(game.hud.boss_shown["magma"])
	check("the-damage-shows-as-a-gap-between-them",
		magma - green > 0.08,
		{"green": green, "magma": magma, "gap": magma - green})

	# 04 — and it closes. Same number, one just took longer to get there.
	await hold(120)
	await shoot("bossbar-04-the-gap-closes")
	check("and-then-the-gap-closes",
		absf(float(game.hud.boss_shown["magma"])
			 - float(game.hud.boss_shown["health"])) < 0.02,
		{"green": game.hud.boss_shown["health"],
		 "magma": game.hud.boss_shown["magma"]})

	# 05 — beaten. The bar is empty and stays up while it flies out, which is
	# what says the fight is over rather than paused.
	var _down: bool = wyrm.take_hit(wyrm.health, game.player.global_position)
	await hold(60)
	await shoot("bossbar-05-beaten")
	check("an-empty-plate-stays-up-while-it-leaves",
		game.hud.boss() == wyrm and float(game.hud.boss_shown["health"]) < 0.02,
		{"green": game.hud.boss_shown["health"], "visible": wyrm.visible})

	# 06 — and goes when the body does.
	for i in range(400):
		game.player.health = game.player.MAX_HEALTH
		await step()
		if not wyrm.visible:
			break
	await hold(4)
	await shoot("bossbar-06-gone")
	check("the-plate-goes-with-the-body",
		game.hud.boss() == null,
		{"visible": wyrm.visible})

	print("BOSS BAR CAPTURE: %d failures -> %s" % [failures, output])
	quit(1 if failures else 0)
