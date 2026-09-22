extends SceneTree
## Development tool: the boss plate when TWO bosses are fighting you.
##
## The Dragon's Roost is the only level that does, and its plate gives them a
## track each — the Dragon Lord on the green, the flying dragon on the magma.
## The thing to look at is what happens when one of them goes down: the bar of
## whoever fell empties and STAYS empty, and the other goes on reading its own
## health. It used to hand the survivor whichever track it asked for, so a
## death put one full green bar back on the plate and the fight looked like it
## had started over. Shot both ways round, because it read wrong both ways.
##
##     <godot> --path godot --script tests/capture_two_bars.gd
##
## Run WITHOUT --headless; it needs a real renderer.
const Game = preload("res://game/session.gd")

const LEVEL := "dragons_roost"
const DECK := 648.0
## Inside the sealed arena (it starts at 816) and short of the two of them at
## 1512, so both the plate and the fight it belongs to are in the picture.
const STAND := 1120.0

var game: Node2D
var lord: Area2D
var flyer: Area2D
var output: String
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func step() -> void:
	await physics_frame
	await process_frame

## Holds the player where he was put, on his feet and unhurt. The Lord's blows
## fling, and a picture of the plate is not a picture of the fight going badly.
func hold(ticks: int) -> void:
	for i in range(ticks):
		game.player.position = Vector2(STAND, DECK)
		game.player.velocity = Vector2.ZERO
		game.player.health = game.player.MAX_HEALTH
		await step()

func shoot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png("%s/%s.png" % [output, label])
	assert(err == OK)
	print("%-32s lord %3d/%-3d dragon %3d/%-3d   green %.2f  magma %.2f" % [
		label, lord.health, lord.max_health, flyer.health, flyer.max_health,
		game.hud.boss_shown["health"], game.hud.boss_shown["magma"]])

func check(id: String, passed: bool, observed: Dictionary) -> void:
	if not passed:
		failures += 1
	print(JSON.stringify({"id": id, "status": "PASS" if passed else "FAIL",
						  "observed": observed}))

## Waits out a death: the killing blow, the body on the deck, and for the
## dragon a flight out of the level. It is the body GOING that used to free a
## track, so a picture taken before then would not be a picture of the bug.
func wait_out(foe: Area2D) -> int:
	for i in range(600):
		game.player.position = Vector2(STAND, DECK)
		game.player.health = game.player.MAX_HEALTH
		await step()
		if not foe.visible:
			return i
	return -1

func fresh() -> void:
	if is_instance_valid(game):
		game.queue_free()
		await step()
	game = Game.new()
	game.test_mode = true
	game.level_id = LEVEL
	root.add_child(game)
	await step()
	game.start_session()
	game.player.test_control = true
	# No cutscene (it would wake them under the hand-held `engaged` below) and
	# no battle track, which is a 21 MB WAV this has no use for.
	game.story_cards.clear()
	game.level["boss_music"] = ""
	await step()
	lord = null
	flyer = null
	for foe in game.enemies:
		if foe.kind == "dragon_lord":
			lord = foe
		elif foe.kind == "dragon":
			flyer = foe
		else:
			foe.health = 0      # the deck to themselves
	game.player.position = Vector2(STAND, DECK)
	game.player.velocity = Vector2.ZERO
	lord.engaged = true
	flyer.engaged = true
	await hold(30)

## One fight, shot twice: both bosses up, then one of them beaten and gone.
func fight(first: String, n: int) -> void:
	await fresh()
	# Knocked down by different amounts, which is the whole claim: two bars
	# reading two numbers. Even halves would prove nothing.
	var _a: bool = lord.take_hit(int(lord.max_health * 0.40), game.player.global_position)
	var _b: bool = flyer.take_hit(int(flyer.max_health * 0.15), game.player.global_position)
	await hold(45)
	await shoot("%02d-both-up" % n)
	check("a-bar-each-and-they-read-different-numbers",
		game.boss_main() == lord and game.boss_second() == flyer
		and absf(float(game.hud.boss_shown["health"])
				 - float(game.hud.boss_shown["magma"])) > 0.15,
		{"green": game.hud.boss_shown["health"],
		 "magma": game.hud.boss_shown["magma"]})

	var felled: Area2D = flyer if first == "dragon" else lord
	var left: Area2D = lord if first == "dragon" else flyer
	var left_was: float = float(left.health) / float(left.max_health)
	var _down: bool = felled.take_hit(felled.health, game.player.global_position)
	var gone: int = await wait_out(felled)
	await hold(30)
	await shoot("%02d-%s-beaten" % [n + 1, first])
	var green: float = float(game.hud.boss_shown["health"])
	var magma: float = float(game.hud.boss_shown["magma"])
	var his: float = green if felled == lord else magma
	var hers: float = magma if felled == lord else green
	check("the-beaten-one-empties-and-the-other-stays-where-it-was",
		game.boss_main() == lord and game.boss_second() == flyer
		and his < 0.02 and absf(hers - left_was) < 0.02,
		{"beaten": first, "its_bar": his, "the_other": hers,
		 "the_other_was": left_was, "body_gone_after_s": gone / 60.0})

func run() -> void:
	output = ProjectSettings.globalize_path("res://../evidence/twobars")
	DirAccess.make_dir_recursive_absolute(output)
	await fight("dragon", 1)
	await fight("dragon_lord", 3)
	print("TWO-BAR CAPTURE: %d failures -> %s" % [failures, output])
	quit(1 if failures else 0)
