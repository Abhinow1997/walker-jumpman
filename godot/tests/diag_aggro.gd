extends SceneTree
## Diagnostic: an enemy the player has not walked up to yet must stay where the
## level put it. The archer style had no aggro gate, so every hunter in the level
## started toward the player on load; this is what that regression would look
## like if it came back.
const Game = preload("res://game/session.gd")
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

func run() -> void:
	game = Game.new()
	game.test_mode = true
	game.level_id = "fractured_isles"
	root.add_child(game)
	game.start_session()
	game.player.test_control = true
	await step()

	# The first of each kind, found by position rather than named: the level is
	# still being authored and hard-coded coordinates go stale silently.
	var hunter: Area2D = _first("hunter")
	var bandit: Area2D = _first("bandit")
	var hx: float = hunter.position.x
	var bx: float = bandit.position.x
	print("spawn x=%.0f  hunter x=%.0f (aggro %.0f)  bandit x=%.0f (aggro %.0f)"
		  % [game.player.position.x, hx, hunter.aggro, bx, bandit.aggro])

	# Three seconds of the player standing still on the opening ledge.
	for i in range(180): await step()
	check("hunter-stays-put-while-unnoticed", absf(hunter.position.x - hx) < 8.0,
		{"was": hx, "now": snappedf(hunter.position.x, 0.1),
		 "gap": snappedf(absf(game.player.position.x - hunter.position.x), 0.1)})
	check("bandit-stays-put-while-unnoticed", absf(bandit.position.x - bx) < 8.0,
		{"was": bx, "now": snappedf(bandit.position.x, 0.1)})
	check("neither-has-fired", game.arrows.is_empty(), {"arrows": game.arrows.size()})

	# Now walk the player up to the archer and confirm the fight actually starts.
	# 300 short of him is inside both his aggro (520) and his fire range (430),
	# and is measured off where he actually is rather than assumed.
	game.player.position = Vector2(hx - 300.0, hunter.position.y)
	for i in range(150): await step()
	var engaged: bool = not game.arrows.is_empty() \
		or absf(hunter.position.x - hx) > 8.0 or absf(bandit.position.x - bx) > 8.0
	check("pair-engages-once-the-player-closes", engaged,
		{"arrows": game.arrows.size(),
		 "hunter_moved": snappedf(absf(hunter.position.x - hx), 0.1),
		 "bandit_moved": snappedf(absf(bandit.position.x - bx), 0.1)})

	print("AGGRO DIAG: %d failure(s)" % failures)
	quit()

## The one of this kind the player meets first, which is the one the
## complaint was about.
func _first(kind: String) -> Area2D:
	var best: Area2D = null
	for foe in game.enemies:
		if foe.kind != kind:
			continue
		if best == null or foe.position.x < best.position.x:
			best = foe
	assert(best != null, "no %s in the level" % kind)
	return best
