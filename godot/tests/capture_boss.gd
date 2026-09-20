extends SceneTree
## The Dragon Lord on the last platform: what he looks like, and that he behaves
## like the boss his profile says he is. Shoots as it goes, so it needs a
## renderer — run without --headless.
##
## Every other enemy is parked throughout. They are a thousand pixels away and
## still managed to matter: the first version of this let the fight run, the
## player died to it, and restart_attempt put the boss back on his feet in the
## middle of his own death animation.
const Game = preload("res://game/session.gd")
var game: Node2D
var boss: Area2D
var output: String
var failures := 0
## Counted off the player's own signal rather than off button presses: a
## press made while he is still in the swing is swallowed, and a ledger that
## counts presses then reports a blast that never left his hand.
var thrown := 0

func _count_blast(_at: Vector2, _direction: float) -> void:
	thrown += 1

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

func park_everyone_but_the_boss() -> void:
	for foe in game.enemies:
		if foe != boss:
			foe.target = null

func run() -> void:
	output = ProjectSettings.globalize_path("res://../evidence/boss")
	DirAccess.make_dir_recursive_absolute(output)
	game = Game.new()
	game.test_mode = true
	game.level_id = "fractured_isles"
	root.add_child(game)
	game.start_session()
	game.player.test_control = true
	await step()

	for foe in game.enemies:
		if foe.kind == "dragon_lord":
			boss = foe
	check("the-boss-is-in-the-level", boss != null, {"enemies": game.enemies.size()})
	if boss == null:
		quit()
		return
	park_everyone_but_the_boss()

	var bandit: Area2D = null
	for foe in game.enemies:
		if foe.kind == "bandit":
			bandit = foe
			break
	check("he-outweighs-the-cast",
		boss.max_health > bandit.max_health * 2 and boss.reach() > bandit.reach() * 2
		and boss.armor,
		{"health": boss.max_health, "bandit_health": bandit.max_health,
		 "reach": boss.reach(), "bandit_reach": bandit.reach(), "armor": boss.armor})
	check("he-is-drawn-at-boss-size", boss.art_scale > 1.5,
		{"art_scale": boss.art_scale, "bandit": bandit.art_scale})
	check("he-holds-the-last-section", boss.holds_gate,
		{"holds_gate": boss.holds_gate, "section": game.section_of(boss.position.x)})
	check("he-stands-between-you-and-the-flag",
		boss.position.x < float(game.level.finish[0])
		and float(game.level.finish[0]) - boss.position.x < boss.aggro,
		{"boss_x": boss.position.x, "flag_x": game.level.finish[0], "aggro": boss.aggro})

	# Asleep until the player walks onto his platform.
	var where: float = boss.position.x
	for i in range(120): await step()
	check("he-waits-on-his-platform", absf(boss.position.x - where) < 8.0,
		{"was": where, "now": snappedf(boss.position.x, 0.1)})

	# Every placement below puts the player on the boss's own floor line rather
	# than on 640, which is the floor back at the start of the course. The Isles
	# deck he fights on is at 660, so 640 held the player 20 px above it and he
	# spent the fight falling those 20 px and landing again between pins.
	game.player.position = Vector2(boss.position.x - 260.0, boss.position.y)
	for i in range(8): await step()
	await shoot("01-approach")

	var punched := false
	for i in range(240):
		await step()
		# Topped up every tick: what is under test is his swing, not whether the
		# player survives it, and a death here would restart the level.
		game.player.health = game.player.MAX_HEALTH
		if boss.state == boss.State.PUNCH and not punched:
			punched = true
			for _j in range(5): await step()
			await shoot("02-his-flame")
	check("he-attacks-once-you-are-close", punched, {"state": boss.state})

	# --- the two specials ----------------------------------------------------
	# Each is driven at the gap its own band names, with the player pinned there:
	# the boss knocks him about, and a knock that drifts him out of the band
	# would be measuring the wrong move. Pinning also keeps him off the edge.
	#
	# The gap is worked out AFTER reset(), not before it. reset() does
	# `position = home`, so a boss who has walked 130 px off his mark chasing
	# the approach above snaps back the moment it is called — and a `stand`
	# measured from where he stood a line earlier leaves the player that 130 px
	# further out than the band under test. It put the slam's 63 at 197, which
	# is not in the slam's [0, 126] at all but is in the breath's [146, 274]:
	# he breathed, the check asked for a slam, and it failed. How far he had
	# drifted depended on how many physics ticks the approach loop happened to
	# get, which is what made it come and go between runs.
	var moves: Dictionary = boss.data().get("moves", {})
	check("the-boss-has-both-specials",
		moves.has("breath") and moves.has("slam"),
		{"moves": moves.keys()})

	for name in ["slam", "breath"]:
		var band: Array = moves[name]["range"]
		var at: float = (float(band[0]) + float(band[1])) * 0.5
		var hit_frame: int = int(moves[name]["hit_frame"])
		# Ready to go, and the fight already on: special_for is gated on engaged.
		boss.reset()
		boss.target = game.player
		boss.engaged = true
		boss.special_ready = 0.0
		boss.cooldown = 0.0
		var stand := Vector2(boss.position.x - at, boss.position.y)
		game.player.position = stand
		game.player.health = game.player.MAX_HEALTH
		var seen := false
		var landed := false
		var shot_it := false
		# Physics ticks, not step()s: a step() is a process frame and carries 0
		# to 8 ticks with it, so the pin below lands once per tick rather than
		# once per however many that frame happened to cost. 420 ticks is 7 s,
		# and the slam is the long one — 1.5 s to its hit frame, 1.72 s of
		# animation, and 1.35 s of cooldown behind it before the next swing.
		for i in range(420):
			game.player.position = stand          # pinned
			await physics_frame
			if boss.move == name:
				seen = true
				if boss.frame >= hit_frame and not shot_it:
					shot_it = true
					await shoot("05-%s" % name)
			if game.player.health < game.player.MAX_HEALTH:
				landed = true
			game.player.health = game.player.MAX_HEALTH
			if seen and boss.move == "punch" and landed:
				break
		check("he-throws-his-%s" % name, seen,
			{"gap": at, "band": band, "move": boss.move})
		check("the-%s-connects" % name, landed,
			{"gap": at, "damage": moves[name].get("damage")})

	# Out of the bands he falls back on the plain swing, or the specials would
	# just be a longer punch.
	boss.reset()
	boss.target = game.player
	boss.engaged = true
	boss.special_ready = 999.0
	game.player.position = Vector2(boss.position.x - 60.0, boss.position.y)
	var swung := false
	for i in range(240):
		game.player.position = Vector2(boss.position.x - 60.0, boss.position.y)
		await step()
		game.player.health = game.player.MAX_HEALTH
		if boss.move == "punch" and boss.state == boss.State.PUNCH:
			swung = true
			break
	check("on-cooldown-he-still-swings", swung, {"move": boss.move})

	# --- what he does instead of a guard -------------------------------------
	# The other three put their arms up when they see a blast coming. He cannot:
	# his pack ships idle, walk, attack, hurt and death and no defend frame. So
	# he breathes on it instead, timed off his own animation — the fire is 0.36 s
	# into the swing, so he starts it 0.36 s before the blast arrives and the two
	# meet. Anything that flies into the fire is destroyed rather than resolved.
	#
	# Which makes the range he can do it from his wind-up rather than a number:
	# 0.36 s of the blast's 560 px/s is about 200 px. Inside that, every one
	# lands — the same lesson the other three teach with their arms.
	# Clear the lane first. The arena keeps a rock at x7632, eighteen pixels in
	# front of him — a blast thrown at the boss smashes that instead and never
	# reaches him, which reads as a burn and is not one.
	for prop in game.crates + game.bottles:
		if is_instance_valid(prop) and prop.position.x > boss.position.x - 400.0 \
				and prop.position.x < boss.position.x + 40.0:
			prop.position = Vector2(prop.position.x, 640.0 - 2000.0)
	boss.reset()
	boss.target = null       # about the blast, not about the fight
	boss.engaged = true
	game.player.position = Vector2(boss.position.x - 340.0, boss.position.y)
	game.player.velocity = Vector2.ZERO
	game.player.facing = 1.0
	game.player.blast_fired.connect(_count_blast)
	for i in range(4): await step()
	var far_start: int = boss.health
	thrown = 0
	var saw_fire := false
	var burn_shot := false
	for i in range(420):
		game.player.mana = game.player.MAX_MANA
		if game.player.attack == "" and thrown < 8:
			game.player.test_blast_pressed = true
		await step()
		if boss.burns_projectiles() and not game.blasts.is_empty():
			saw_fire = true
			if not burn_shot:
				burn_shot = true
				await shoot("06-burning-one-out-of-the-air")
		if thrown >= 8 and game.blasts.is_empty():
			break
	var far_lost: int = far_start - boss.health
	check("he-burns-a-thrown-blast-out-of-the-air",
		saw_fire and thrown > 0 and far_lost < thrown * 45,
		{"thrown": thrown, "lost": far_lost, "if_all_landed": thrown * 45,
		 "burnt": thrown - far_lost / 45,
		 "wind_up_px": boss.hit_lead("punch") * 560.0})

	# And from inside the wind-up there is nothing he can do about them.
	boss.reset()
	boss.target = null
	boss.engaged = true
	game.player.position = Vector2(boss.position.x - 110.0, boss.position.y)
	game.player.velocity = Vector2.ZERO
	game.player.facing = 1.0
	for i in range(4): await step()
	var near_start: int = boss.health
	thrown = 0
	var near_fire := false
	for i in range(300):
		game.player.mana = game.player.MAX_MANA
		if game.player.attack == "" and thrown < 4:
			game.player.test_blast_pressed = true
		await step()
		if boss.burns_projectiles():
			near_fire = true
		if thrown >= 4 and game.blasts.is_empty():
			break
	check("but-not-one-thrown-from-close-up",
		thrown > 0 and not near_fire and near_start - boss.health == thrown * 45,
		{"thrown": thrown, "lost": near_start - boss.health,
		 "if_all_landed": thrown * 45, "fire_out": near_fire})
	game.player.blast_fired.disconnect(_count_blast)

	# The death gets a session of its own. On the shared one the fight above
	# knocks the player off the platform, he falls, and the retry 0.55 s later
	# puts the boss back on his feet in the middle of his own death animation —
	# healing him every tick does not help, because a fall is fatal regardless
	# of the bar. Nothing here touches him at all.
	game.queue_free()
	await step()
	game = Game.new()
	game.test_mode = true
	game.level_id = "fractured_isles"
	root.add_child(game)
	game.start_session()
	await step()
	for foe in game.enemies:
		foe.target = null
		if foe.kind == "dragon_lord":
			boss = foe
	# On his platform, so the camera frames him for the shots. Safe here despite
	# the fight above: with every enemy parked he never swings, so there is
	# nothing to knock the player off the edge.
	game.player.position = Vector2(boss.position.x - 230.0, boss.position.y)
	for i in range(4): await step()

	var swings := 0
	while boss.alive() and swings < 40:
		var _hit: bool = boss.take_hit(60, Vector2(boss.position.x - 600.0, boss.position.y))
		swings += 1
		for _j in range(2): await step()
	check("he-goes-down", not boss.alive(), {"swings": swings, "health": boss.health})
	check("he-dies-on-his-own-sheet", boss.sprite.animation == "death",
		{"animation": boss.sprite.animation})

	# Physics ticks, not step()s. A step() is a PROCESS frame and Godot runs up
	# to eight physics ticks inside one while it catches up, so "70 steps" is
	# somewhere between 1 and 12 seconds depending on how busy the run has been
	# — and his death animation is 2.3 s long. Sampled in ticks these two land
	# at 0.3 s and 1.5 s into it whatever else the script is doing.
	for i in range(18): await physics_frame
	var early: int = boss.sprite.frame
	await shoot("03-death-mid")
	for i in range(72): await physics_frame
	check("the-death-plays-through",
		boss.sprite.animation == "death" and boss.sprite.frame > early
		and game.deaths == 0,
		{"early_frame": early, "late_frame": boss.sprite.frame,
		 "animation": boss.sprite.animation, "deaths": game.deaths,
		 "dead_t": snappedf(boss.dead_t, 0.01)})
	await shoot("04-death-late")
	# It must run to its end rather than being cut at DEAD_LINGER, which is the
	# whole reason _advance_dead lingers for the animation's own length.
	for i in range(90): await step()
	check("the-death-reaches-its-last-frame",
		boss.sprite.frame >= boss.sprite.sprite_frames.get_frame_count("death") - 1,
		{"frame": boss.sprite.frame,
		 "frames": boss.sprite.sprite_frames.get_frame_count("death"),
		 "dead_t": snappedf(boss.dead_t, 0.01)})

	print("BOSS: %d failure(s)" % failures)
	quit()
