extends CharacterBody2D

const Tuning = preload("res://features/player/tuning.gd")
const Moveset = preload("res://features/player/moveset.gd")
# Swap this one line to change the protagonist's appearance.
# player_sprite.gd is the Anti-Davis sprite; player_visual.gd is the original
# procedural Wind-Up Knight rig, kept as a fallback that needs no art files.
const Visual = preload("res://features/player/player_sprite.gd")

## Fired when the blast animation reaches the frame that releases the projectile.
## The session spawns it, not the player: once thrown it must not move with him.
signal blast_fired(at: Vector2, direction: float)

## Physics layer 7. The strike is a shape query against this and nothing else,
## so anything that wants to be hittable has to be on it. See combat/crate.gd.
const HITTABLE := 64

## How each move behaves. What it looks like, how long each frame lasts and
## where it hits all come from moves.json, which the extractor generates from
## the pack; this table is only about how a move interacts with input and
## movement, which is a game design decision and not in the pack.
##
##   ground   must be standing on the floor to start it
##   chain    move this one buffers into when attack is pressed again
##   planted  ignores the movement axis while his feet are on the floor. It
##            cannot apply in mid-air, because there is nothing to plant: an
##            airborne move that zeroed the axis would brake the jump it was
##            thrown from and drop him short of wherever he was going.
##   drive    forced forward speed, for moves that carry you
##   ends_on_land  an air move that is cut short by touching down
##   loops         the animation repeats; the move's length is decided elsewhere
##   throw_frame   frame on which a carried object leaves his hands
##
## Not every entry is an attack. `drink` runs on exactly the same machinery and
## simply has no hit frames, which is the point: one clock, one set of rules for
## "the character is committed to an animation", rather than a second system.
## It is the only looping entry: LF2 drew four drink frames, and six seconds of
## drinking is those four frames over and over.
const MOVES := {
	"punch_a": {"ground": true,  "chain": "punch_b", "planted": true},
	"punch_b": {"ground": true,  "chain": "",        "planted": true},
	"kick":    {"ground": false, "chain": "",        "planted": false, "ends_on_land": true},
	"charge":  {"ground": true,  "chain": "",        "planted": false, "drive": 300.0},
	# Throwable in mid-air, unlike every other committed move here. He plants
	# his feet to throw one when he has feet to plant, and simply keeps his arc
	# when he does not — see `planted` above.
	#
	# It matters because the muzzle rides HIM: BLAST_MUZZLE is measured from
	# his feet, so a blast thrown at the top of a jump flies 107 px higher than
	# one thrown standing. That is the whole point of it. A flat shot passes
	# under a cruising dragon and over a crouching nobody; a jumped one is the
	# only way to put an energy strike into something above head height, and it
	# is equally the reason a jumped shot sails over a bandit standing right in
	# front of you. Height is now the player's decision rather than a constant.
	"blast":   {"ground": false, "chain": "",        "planted": true,  "spawn_frame": 4},
	"drink":   {"ground": true,  "chain": "",        "planted": true,  "loops": true},
	# Picking up and throwing. LF2 draws one bending pose for both weights and
	# tells them apart by where the weapon point puts the object, so the object
	# is attached on the first frame and rides the point up into his hands.
	"pick_light":  {"ground": true, "chain": "", "planted": true},
	"pick_heavy":  {"ground": true, "chain": "", "planted": true},
	# The release frame is not a guess: the weapon point leaps forward on it,
	# from (15,30) to (107,60) light and from (33,23) to (104,36) heavy.
	"throw_light": {"ground": true, "chain": "", "planted": true, "throw_frame": 2},
	"throw_heavy": {"ground": true, "chain": "", "planted": true, "throw_frame": 1},
}

## Attacking at or above this speed becomes the shoulder charge instead of a
## jab. Matches player_sprite.gd's RUN_SPEED so the move matches the pose he is
## already in when the button goes down.
const CHARGE_FROM := 150.0
## Where the projectile leaves his hand, relative to his feet. Read off the
## blast animation's release frame, then scaled with the art (x0.75).
const BLAST_MUZZLE := Vector2(22.5, -34.5)

## He starts full. It was 25, then 60, and it is the whole bar now: the first
## thing a player sees is the bar, and a bar that starts short reads as a
## punishment for something they have not done yet.
##
## What that costs, so it is a decision rather than a surprise: a milk bottle is
## worth two of the bar's five segments — 40 points — and drink() REFUSES a
## bottle at full health rather than wasting it. So a bottle found before the
## first fight cannot be drunk, and says ALREADY FULL instead. That is why both
## bottles on the practice course sit just after a fight and not before one; a
## level that puts one in front of an untouched player is putting a locked door
## there. The old 60 existed to make 60 + 40 land exactly on 100 so a full
## bottle could always be swallowed whole, which stops mattering once you are
## expected to have been hit before you reach one.
##
## The punks take it away a bar at a time. Spikes and falls remain instant death
## — that rule is the game's, and a health bar does not get to quietly replace
## it — so health is what enemies spend and hazards still ignore.
const MAX_HEALTH := 100
const START_HEALTH := MAX_HEALTH

## Mana is what the blast costs, and the blast is the only thing that spends it.
## Punches and kicks stay free: the blast is the move that reaches across the
## screen, and a ranged attack with no cost is the one that makes every other
## move pointless.
##
## A blast is cheap and the bar refills itself, slowly: five points a shot
## against a hundred, and five points back every ten seconds. So a full bar is
## twenty blasts, a spawn is twelve, and one free shot arrives every ten seconds
## whatever happens. At twenty a shot the bar emptied in five and only a brown
## bottle brought it back, which made the blast something to hoard rather than
## use — the opposite of the point of giving him one.
##
## The trickle also means he can never be permanently disarmed. Nothing here
## kills him either: out of mana just means the K key does nothing for a moment.
const MAX_MANA := 100
const START_MANA := 60
const BLAST_COST := 5
## Points a second. BLAST_COST every ten seconds, by construction — change the
## cost and the shot-per-ten-seconds promise follows it.
const MANA_REGEN := float(BLAST_COST) / 10.0

## No two blows may land inside this window. Without it a punk standing inside
## the player lands on consecutive frames and empties the whole bar in a third
## of a second, which reads as a bug rather than a fight.
const HURT_INVULNERABLE := 0.6
## How long a blow takes him out of his own hands. Shorter than the invulnerable
## window on purpose: he recovers and can move again well before he can be hit
## again, so a hit costs him a beat rather than stacking into a stun-lock.
##
## Gravity is untouched by it — a stun that froze him in mid-air over a pit would
## turn one punch into a death — and it is short enough not to be a sentence.
const HURT_STUN := 0.25

## Being FLUNG is heavier than being stunned, and only the Dragon Lord does it —
## his blows carry a knockback the rest of the cast does not (see fling_for() in
## enemy.gd). A flung blow throws him away from the fist and lifts him off his
## feet, so the fall is the second half of the blow: "hit, then thrown, then
## down." While he is flung his own momentum carries him — no walking, no air
## steering — exactly like an enemy's committed jump, and it ends when he lands.
##
## FLING_LIFT is the upward pop the horizontal throw is paired with. Well under
## his own -640 jump, so it reads as being knocked off balance rather than
## launched, and its 0.42 s of air outlasts the 0.25 s stun so control comes back
## as he is getting up rather than in the air.
const FLING_LIFT := -400.0
## The cap on how long the thrown momentum is held if he never finds a floor —
## flung out over the sea, say. In the ordinary case landing clears it first.
const FLING_TIME := 0.6
## How long a flung blow keeps him off his feet ALTOGETHER — the tumble, the
## landing and a beat on the deck before he is up again. Longer than
## FLING_TIME, which only protects his thrown momentum, and much longer than
## HURT_STUN, which is what an ordinary blow costs.
##
## LF2 draws it: frames 180-184, the falling sequence, which
## scripts/extract_anti_davis.py writes out as `death` because being put down
## for good is the other thing they are used for. Five frames at 9 fps is
## 0.56 s and the last is held for what is left.
##
## Only the dragon and the Dragon Lord fling at all, and the dragon's breath
## flings hardest — see fling_for() in features/combat/enemy.gd. So this is
## what being caught by the fire costs: the damage, the throw, and a second on
## the floor while the thing that threw you comes back round.
const DOWN_TIME := 0.95

## Carrying something heavy costs him speed. He can still outrun a bandit, but
## only just, so hauling a crate across the level is a decision.
const CARRY_SPEED := 0.55
## How hard a throw leaves his hands. The heavy throw is flatter and faster; a
## light object is lobbed.
const THROW_HEAVY := Vector2(430.0, -150.0)
const THROW_LIGHT := Vector2(330.0, -210.0)

## Emitted when a carried object leaves his hands, with the velocity to give it.
signal threw(object: Node2D, velocity: Vector2)
## A bottle is worth so many fifths of a bar rather than so many points, so
## "worth two bars" stays true whatever MAX_HEALTH or MAX_MANA is. Five is what
## the old segmented health asset drew; the bars are a continuous fill now, but
## the level files are written in these units and a fifth is still the step the
## eye can read off one.
const HEALTH_SEGMENTS := 5
const MANA_SEGMENTS := 5

## Which bar a bottle fills. The drink machinery is identical either way — the
## same animation, the same wait, the same mouthful-by-mouthful arrival — so the
## kind is carried through it rather than duplicated.
const REFILL_HEALTH := "health"
const REFILL_MANA := "mana"

## Seconds to drink a completely full bottle. A part-full one takes its share:
## a bottle half drunk, or cracked by a punch, is half the wait and half of
## whatever it was worth. Nothing here is all-or-nothing — he keeps whatever he swallowed and
## the bottle keeps the rest — so stopping is a decision about how long to stand
## still, not a gamble on losing the lot.
const FULL_DRINK_TIME := 6.0

## Why a drink stopped. The session cares about the difference: a drink he
## walked out of leaves the bottle standing, a drink he was hit during drops it.
const DRINK_HIT := "hit"
const DRINK_MOVED := "moved"
const DRINK_JUMPED := "jumped"
const DRINK_ATTACKED := "attacked"
const DRINK_KNOCKED := "knocked off his feet"
const DRINK_LEFT := "moved away"
const DRINK_EMPTY := "emptied the bottle"
const DRINK_FULL := "already full"

## Emitted whenever a drink stops. `reason` is one of the DRINK_* constants, and
## `last_drink_consumed` says how much of a full bottle went with it.
signal drink_ended(completed: bool, reason: String)

var tuning = Tuning.new()
var visual: Node2D
var enabled: bool = false
var tick: int = 0
var last_floor_tick: int = -1000
var jump_request_tick: int = -1000
var opportunity_consumed: bool = false
var require_jump_release: bool = true
var facing: float = 1.0
var jumps: int = 0
var health: int = START_HEALTH
var mana: int = START_MANA
## The part of a point trickled back but not yet banked. Held apart from `mana`,
## which is an integer everything else reasons about, and counted by
## mana_fraction() so the bar rises smoothly instead of ticking a pixel every
## two seconds.
var mana_pool: float = 0.0
var test_control: bool = false
var test_axis: float = 0.0
var test_jump_pressed: bool = false
var test_jump_held: bool = false

## Attack state. `attack` is "" whenever he is not mid-move, and the visual
## reads these three to decide what to draw; it owns none of them.
var attack: String = ""
var attack_frame: int = 0
var attack_clock: float = 0.0
var chain_queued: bool = false
## Targets this swing has already connected with. One swing hits a given target
## once, however many frames of it overlap.
var struck: Array = []
var blast_released: bool = false
## How much the bottle currently being drunk is worth, and whether it has been
## applied yet. Health lands partway through the animation rather than on the
## key press, so the bar moves when he actually tips the bottle back.
## Seconds into the current drink; how full the bottle was when he raised it;
## what a whole bottle of it is worth; and fractional health carried between
## frames, because health is an integer and a sip is not.
var drink_t: float = 0.0
var drink_fill: float = 1.0
var drink_segments: int = 0
var drink_pool: float = 0.0
## Which bar the bottle in his hand fills, one of the REFILL_* constants.
var drink_kind: String = REFILL_HEALTH
## Time left on the window above.
var hurt_cooldown: float = 0.0
## Time left on the stun, and how far into the hurt animation he is. Separate
## clocks because the stun can be re-tuned without the animation changing speed.
var hurt_stun: float = 0.0
var hurt_clock: float = 0.0
## Time left being flung. While it runs his thrown momentum is preserved — the
## normal ground friction and air control are skipped — and it is cleared the
## moment he lands. Zero for every blow that does not fling. See FLING_LIFT.
var fling_t: float = 0.0
## Seconds left of a knockdown. See DOWN_TIME.
var down_t: float = 0.0
## What he is holding, and whether it is the two-handed kind. The object is a
## real prop in the world, not a texture: the visual drives its position from
## the current frame's weapon point, so throwing it is just handing it back its
## own physics.
var carrying: Node2D = null
var carry_heavy: bool = false
var thrown_this_move: bool = false
## Fraction of a full bottle drunk by the drink that just ended, and how much
## was left in it. The session reads these to settle up with the bottle.
var last_drink_consumed: float = 0.0
var last_drink_left: float = 0.0
var hits_landed: int = 0
var attacks_thrown: int = 0
## Moves that run on the attack machinery because they commit him the same way,
## but that nobody would call a swing. They are kept out of attacks_thrown, the
## figure the evidence run reports and the one the level's coaching line asks
## before it stops telling you that J is a fist — see _coached in ui/hud.gd.
##
## Drinking was always out. The two pick-ups are out now: bending down for a
## rock is E, and the rock on First Steps stands at 1524, INSIDE the bandit
## stretch whose line says J is a fist. Lifting it retired that line before he
## had thrown a punch, which is exactly backwards — the prompt that told him to
## pick the rock up was what took the next lesson away.
const NOT_A_SWING := ["drink", "pick_light", "pick_heavy"]
## Of those, the ones that were blasts. Split out so "has he ever thrown a
## punch" and "has he ever thrown a blast" are separate questions — which is
## what the level's coaching lines ask before they stop showing themselves.
## Lifetime, like attacks_thrown: a retry does not un-learn a control, so
## neither is reset in reset_at.
var blasts_thrown: int = 0
var test_attack_pressed: bool = false
var test_blast_pressed: bool = false

func _ready() -> void:
	name = "Player"
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 2.0
	# Sized to the Anti-Davis body. He is drawn ~28 x 55 px, but most of that is
	# swinging arms and hair spikes; torso and legs are about this box. A hitbox
	# wider than the drawn body kills the player on spikes that visibly missed,
	# so it stays inside the silhouette on purpose. This is the old 20 x 56
	# scaled with the art, which went to 0.75 so the cast stands alongside the
	# 50 px CC0 street enemies.
	var shape := RectangleShape2D.new()
	shape.size = Vector2(15, 42)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = Vector2(0, -21)
	add_child(collider)
	visual = Visual.new()
	visual.body = self
	add_child(visual)

func reset_at(spawn: Vector2) -> void:
	position = spawn
	velocity = Vector2.ZERO
	last_floor_tick = -1000
	jump_request_tick = -1000
	opportunity_consumed = false
	require_jump_release = true
	test_jump_pressed = false
	jumps = 0
	health = START_HEALTH
	mana = START_MANA
	mana_pool = 0.0
	drink_pool = 0.0
	hurt_cooldown = 0.0
	hurt_stun = 0.0
	hurt_clock = 0.0
	burning = false
	fling_t = 0.0
	down_t = 0.0
	carrying = null
	carry_heavy = false
	thrown_this_move = false
	_finish_drink(false, "retry")
	_end_attack()
	test_attack_pressed = false
	test_blast_pressed = false
	if is_instance_valid(visual):
		visual.reset()

func on_death() -> void:
	## Appearance only; the session still owns the death state and retry timing.
	_finish_drink(false, "died")
	_end_attack()
	if is_instance_valid(visual):
		visual.on_death()

# --- health ----------------------------------------------------------------

func heal(amount: int) -> int:
	## Returns how much was actually restored, which is zero at full health.
	## The caller decides whether a drink that heals nothing should still be
	## spent; this only reports.
	var before := health
	health = clampi(health + amount, 0, MAX_HEALTH)
	return health - before

func health_fraction() -> float:
	return float(health) / float(MAX_HEALTH)

## Lit. Set by a blow made of fire and worn for as long as the stun that blow
## cost him, because the burn is what that stun LOOKS like rather than damage
## of its own — nothing in this game ticks a bar down over time, and a fire
## that did would be a second death the player cannot answer. Cleared by the
## next blow that is not fire, and by a retry.
##
## LF2 draws the burn as four frames, two in the air and two on the deck, which
## is the whole reason this exists: the art was in the pack and nothing asked
## for it. See is_burning(), the `burn` strip, and player_sprite.gd.
var burning: bool = false

func is_burning() -> bool:
	## On fire, and still reeling from what set him on fire. Tied to is_hurt()
	## rather than to a clock of its own so the flame goes out exactly when he
	## has his feet back, whether that was a flinch or a knockdown.
	return burning and is_hurt()

func take_damage(amount: int, from: Vector2, fling: float = 0.0,
		fire: bool = false) -> bool:
	## Spends health and breaks whatever he was concentrating on. Returns true
	## only when the blow actually landed, so an attacker can tell a hit from a
	## swing that arrived inside the invulnerable window.
	##
	## `fling` is the horizontal knockback the blow carries, in px/s, and is zero
	## for all but the Dragon Lord — see fling_for() in enemy.gd. A flung blow
	## throws him away from the fist and lifts him off his feet; everything else
	## still stuns him where he stands.
	##
	## Deliberately does NOT decide what an empty bar means. The session owns
	## death and retry timing, exactly as it does for spikes and pits.
	if not enabled or amount <= 0 or hurt_cooldown > 0.0:
		return false
	hurt_cooldown = HURT_INVULNERABLE
	hurt_stun = HURT_STUN
	hurt_clock = 0.0
	# Set from the blow rather than or-ed with what he was already wearing: a
	# punch through a burn puts the punch's own flinch on screen.
	burning = fire
	health = maxi(0, health - amount)
	if fling > 0.0:
		# Off his feet, away from the blow. He faces what hit him as he goes back,
		# and his momentum is held until he lands — see fling_t in _physics_process.
		var away := signf(global_position.x - from.x)
		if away == 0.0:
			away = -facing
		facing = -away
		velocity = Vector2(away * fling, FLING_LIFT)
		fling_t = FLING_TIME
		# And off his feet properly rather than merely shoved: the falling
		# sequence plays and he has no control until he is up. See DOWN_TIME.
		down_t = DOWN_TIME
	# A drink cannot survive a punch. This is what DRINK_HIT was built for: the
	# bottle is knocked out of his hand rather than set down, and he keeps only
	# the mouthfuls he had already swallowed.
	_finish_drink(false, DRINK_HIT)
	# Whatever he was swinging is over. Taking a punch interrupts a punch, and
	# knocks anything he was holding out of his hands.
	_end_attack()
	if is_carrying():
		var dropped := drop_carried()
		if is_instance_valid(dropped):
			threw.emit(dropped, Vector2(-facing * 70.0, -120.0))
	if is_instance_valid(visual) and visual.has_method("on_hurt"):
		visual.on_hurt()
	return true

func is_downed() -> bool:
	## Flung, and on the way to the floor or on it. A harder is_hurt: it gates
	## the same things for longer and draws a different animation.
	return down_t > 0.0

func down_clock() -> float:
	## How far into the knockdown he is, for the sprite to pick a frame with.
	return DOWN_TIME - down_t

func is_hurt() -> bool:
	## Reeling, and not free to act. A knockdown counts: everything that asks
	## this — the input gate, the attack gate, the pick-up gate — should treat
	## being on the floor as at least as disabling as being rocked, and this is
	## the one place to say so. The SPRITE tells them apart, because they are
	## drawn differently; nothing else has to.
	return hurt_stun > 0.0 or down_t > 0.0

# --- mana ------------------------------------------------------------------

func restore_mana(amount: int) -> int:
	## The mana twin of heal(), and reports the same way: how much actually went
	## in, which is nothing on a full bar.
	var before := mana
	mana = clampi(mana + amount, 0, MAX_MANA)
	return mana - before

func mana_fraction() -> float:
	## Counts the part-point still in the pool, so the bar shows the trickle as
	## it happens rather than jumping a whole point at a time.
	return clampf((float(mana) + mana_pool) / float(MAX_MANA), 0.0, 1.0)

func _regenerate_mana(delta: float) -> void:
	## The slow trickle. Runs whenever he is on his feet — not in a menu, not
	## mid-death — and banks whole points as they arrive.
	if mana >= MAX_MANA:
		mana_pool = 0.0
		return
	mana_pool += MANA_REGEN * delta
	var whole := int(floor(mana_pool))
	if whole > 0:
		mana_pool -= float(whole)
		mana = mini(MAX_MANA, mana + whole)

func segment_mana() -> int:
	## One fifth of the mana bar, in points.
	return int(round(float(MAX_MANA) / float(MANA_SEGMENTS)))

func can_blast() -> bool:
	## Whether there is a blast left in him. Asked before the move starts, so an
	## empty bar means the key does nothing rather than playing the animation and
	## firing a projectile that was never paid for.
	return mana >= BLAST_COST

# --- carrying ---------------------------------------------------------------

func is_carrying() -> bool:
	return is_instance_valid(carrying)

func begin_pickup(prop: Node2D, is_heavy: bool) -> bool:
	## Bends down and takes it. The object is attached immediately rather than
	## at the end of the animation, because LF2's pick-up frames carry a weapon
	## point that rises from the floor into his hands — attaching late would
	## leave it sitting on the ground for the whole lift.
	if not can_attack() or not is_on_floor() or is_carrying() or is_hurt():
		return false
	if not begin_attack("pick_heavy" if is_heavy else "pick_light"):
		return false
	carrying = prop
	carry_heavy = is_heavy
	prop.pick_up()
	return true

func begin_throw() -> bool:
	if not is_carrying() or not can_attack() or not is_on_floor() or is_hurt():
		return false
	if not begin_attack("throw_heavy" if carry_heavy else "throw_light"):
		return false
	thrown_this_move = false
	return true

func drop_carried() -> Node2D:
	## Hands it back to the world without throwing it. Used when he is hit, or
	## dies, or the attempt restarts.
	var held := carrying
	carrying = null
	carry_heavy = false
	return held

func segment_health() -> int:
	## One slot of the health bar, in points.
	return int(round(float(MAX_HEALTH) / float(HEALTH_SEGMENTS)))

func refill_segment(kind: String) -> int:
	## One fifth of whichever bar `kind` names, in that bar's points.
	return segment_mana() if kind == REFILL_MANA else segment_health()

func refill_full(kind: String) -> bool:
	return mana >= MAX_MANA if kind == REFILL_MANA else health >= MAX_HEALTH

func begin_drink(segments: int, fill: float, kind: String = REFILL_HEALTH) -> bool:
	## Starts a drink on a bottle that is `fill` full (0 to 1) and worth
	## `segments` bars of `kind` when whole. The caller has already decided the
	## drink is allowed; this only refuses when he is not in a position to start
	## — mid-move, or off the ground.
	if not can_attack() or not is_on_floor():
		return false
	if fill <= 0.0:
		return false
	if not begin_attack("drink"):
		return false
	if kind != drink_kind:
		# The carried fraction below is in the units of whichever bar it came
		# from, so it cannot follow him from a milk bottle to a brown one.
		drink_pool = 0.0
	drink_kind = kind
	drink_segments = segments
	drink_fill = clampf(fill, 0.0, 1.0)
	drink_t = 0.0
	return true

func is_drinking() -> bool:
	return attack == "drink"

func drink_span() -> float:
	## How long this particular drink takes: proportional to what is left in the
	## bottle, so a half-empty or cracked one is a correspondingly shorter wait.
	return drink_fill * FULL_DRINK_TIME

func drink_remaining() -> float:
	return maxf(0.0, drink_span() - drink_t)

func drink_fill_left() -> float:
	## How full the bottle in his hand is right now. The session pushes this into
	## the bottle every frame, so its contents are live rather than settled up at
	## the end — a drink cut off by anything at all still leaves the bottle
	## holding exactly what he did not swallow.
	if not is_drinking():
		return 0.0
	return maxf(0.0, drink_fill - drink_t / FULL_DRINK_TIME)

func drink_progress() -> float:
	## 0 to 1 through *this* drink. The HUD needs it: seconds of a looping
	## animation with no visible clock reads as the game being stuck.
	var span := drink_span()
	if not is_drinking() or span <= 0.0:
		return 0.0
	return clampf(drink_t / span, 0.0, 1.0)

func interrupt_drink(reason: String) -> void:
	## Ends a drink from outside. The session calls it when he walks out of
	## reach, and it is the hook damage hangs off: pass DRINK_HIT and the bottle
	## is knocked out of his hand rather than set down.
	_finish_drink(false, reason)

func _finish_drink(completed: bool, reason: String) -> void:
	if attack != "drink":
		return
	# Measured against a *full* bottle, which is the unit the bottle stores its
	# contents in. Health is already in him: it went in as he swallowed.
	last_drink_consumed = drink_t / FULL_DRINK_TIME
	last_drink_left = maxf(0.0, drink_fill - last_drink_consumed)
	_end_attack()
	drink_ended.emit(completed, reason)

func _advance_drink(delta: float) -> void:
	if not is_on_floor():
		_finish_drink(false, DRINK_KNOCKED)
		return
	var span := drink_span()
	# Clamped so the last frame cannot overshoot and credit him for more of the
	# bottle than was in it.
	var step: float = minf(delta, maxf(0.0, span - drink_t))
	drink_t += step
	# Health or mana arrives as he swallows rather than in a lump at the end, so
	# a drink cut short is worth exactly the part of it he got through.
	drink_pool += step / FULL_DRINK_TIME * float(drink_segments * refill_segment(drink_kind))
	var whole := int(floor(drink_pool))
	if whole > 0:
		drink_pool -= float(whole)
		if drink_kind == REFILL_MANA:
			restore_mana(whole)
		else:
			heal(whole)
	if refill_full(drink_kind):
		# Topped up with some still in the bottle. Stop rather than pour the
		# rest away — he can come back for it.
		_finish_drink(true, DRINK_FULL)
		return
	if drink_t >= span:
		_finish_drink(true, DRINK_EMPTY)

# --- attacks ---------------------------------------------------------------

func can_attack() -> bool:
	return enabled and attack == ""

func _choose_attack() -> String:
	## Context picks the move, so one button covers the whole ground moveset and
	## the player never has to learn a motion input to see all of it.
	if not is_on_floor():
		return "kick"
	if absf(velocity.x) >= CHARGE_FROM:
		return "charge"
	return "punch_a"

func begin_attack(key: String) -> bool:
	if not MOVES.has(key) or not Moveset.has(key):
		return false
	if MOVES[key].get("ground", false) and not is_on_floor():
		return false
	attack = key
	attack_frame = 0
	attack_clock = 0.0
	chain_queued = false
	blast_released = false
	struck.clear()
	if not NOT_A_SWING.has(key):
		attacks_thrown += 1
	if key == "blast":
		blasts_thrown += 1
	return true

func _end_attack() -> void:
	attack = ""
	attack_frame = 0
	attack_clock = 0.0
	chain_queued = false
	blast_released = false
	drink_t = 0.0
	drink_fill = 1.0
	drink_segments = 0
	# drink_pool is deliberately NOT cleared: it is the fraction of a health
	# point already swallowed but not yet worth a whole one. Dropping it on every
	# stop would quietly lose most of a bottle drunk in short sips.
	struck.clear()

func _advance_attack(delta: float) -> void:
	if attack == "":
		return
	attack_clock += delta
	var rules: Dictionary = MOVES[attack]
	if rules.get("loops", false):
		# The animation repeats for as long as the move runs, rather than its
		# length deciding when the move is over.
		var span := Moveset.length(attack)
		if span > 0.0:
			attack_clock = fmod(attack_clock, span)
	attack_frame = Moveset.frame_at(attack, attack_clock)

	if attack == "drink":
		# No hit frames, no chain, and its own clock decides when it ends.
		_advance_drink(delta)
		return
	if rules.has("throw_frame") and not thrown_this_move and attack_frame >= int(rules.throw_frame):
		thrown_this_move = true
		var object := drop_carried()
		if is_instance_valid(object):
			var speed: Vector2 = THROW_HEAVY if attack == "throw_heavy" else THROW_LIGHT
			threw.emit(object, Vector2(speed.x * facing, speed.y))
	if rules.has("spawn_frame") and not blast_released and attack_frame >= int(rules.spawn_frame):
		blast_released = true
		# Paid for on the frame that lets go, not on the key press: a blast a
		# punch interrupts before his hand comes up costs him nothing. Clamped
		# rather than asserted — can_blast() has already refused an empty bar,
		# and a mid-move drain is not worth a crash.
		mana = maxi(0, mana - BLAST_COST)
		blast_fired.emit(global_position + Vector2(BLAST_MUZZLE.x * facing, BLAST_MUZZLE.y), facing)

	_resolve_hits()

	# An air move that lands has nothing left to say; cutting it keeps him from
	# standing on the floor still kicking.
	if rules.get("ends_on_land", false) and is_on_floor() and attack_clock > 0.06:
		_end_attack()
		return
	if attack_clock < Moveset.length(attack):
		return
	var chain: String = rules.get("chain", "")
	if chain_queued and chain != "" and Moveset.has(chain):
		begin_attack(chain)
	else:
		_end_attack()

func _resolve_hits() -> void:
	var hits := Moveset.hits(attack, attack_frame)
	if hits.is_empty():
		return
	var space := get_world_2d().direct_space_state
	for hit in hits:
		var box: Rect2 = hit.rect
		# The art is drawn facing right and the boxes are transcribed in that
		# space, so both mirror together and the hit stays on the fist.
		if facing < 0.0:
			box.position.x = -(box.position.x + box.size.x)
		box.position += global_position
		var query := PhysicsShapeQueryParameters2D.new()
		var shape := RectangleShape2D.new()
		shape.size = box.size
		query.shape = shape
		query.transform = Transform2D(0.0, box.position + box.size / 2.0)
		query.collision_mask = HITTABLE
		query.collide_with_areas = true
		query.collide_with_bodies = false
		for result in space.intersect_shape(query, 16):
			var target = result.collider
			if target == null or struck.has(target) or not target.has_method("take_hit"):
				continue
			if target.take_hit(int(hit.damage), global_position):
				struck.append(target)
				hits_landed += 1

# --- step ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not enabled:
		return
	tick += 1
	# Gated on `enabled` by the return above, so it does not tick on a menu or
	# through a death: the bar he comes back with is the one he spawned with.
	_regenerate_mana(delta)
	if hurt_cooldown > 0.0:
		hurt_cooldown = maxf(0.0, hurt_cooldown - delta)
	if hurt_stun > 0.0:
		hurt_stun = maxf(0.0, hurt_stun - delta)
		hurt_clock += delta
	if fling_t > 0.0:
		fling_t = maxf(0.0, fling_t - delta)
		# Landed and no longer reeling: he has his feet back. Kept off the stun so
		# a flung blow that ends its stun in mid-air still rides the arc to ground.
		if is_on_floor() and velocity.y >= 0.0 and hurt_stun <= 0.0:
			fling_t = 0.0
	if down_t > 0.0:
		# The knockdown outlives the thrown momentum: he is on the floor for
		# the rest of it whether or not he has stopped sliding. See DOWN_TIME.
		down_t = maxf(0.0, down_t - delta)
	var axis := test_axis if test_control else Input.get_axis("move_left", "move_right")
	var held := test_jump_held if test_control else Input.is_action_pressed("jump")
	var pressed := test_jump_pressed if test_control else Input.is_action_just_pressed("jump")
	var attack_pressed := test_attack_pressed if test_control else Input.is_action_just_pressed("attack")
	var blast_pressed := test_blast_pressed if test_control else Input.is_action_just_pressed("blast")
	test_jump_pressed = false
	test_attack_pressed = false
	test_blast_pressed = false

	if is_hurt():
		# Reeling. He keeps falling if he was falling, but he does not walk,
		# jump or swing out of it.
		axis = 0.0
		pressed = false
		attack_pressed = false
		blast_pressed = false

	if attack == "drink":
		# Read before `planted` zeroes the axis, so this sees the movement key
		# even though the drink itself never moves him. Running before dispatch
		# means the same press then does whatever it was going to do.
		if not is_zero_approx(axis):
			_finish_drink(false, DRINK_MOVED)
		elif pressed:
			_finish_drink(false, DRINK_JUMPED)
		elif attack_pressed or blast_pressed:
			_finish_drink(false, DRINK_ATTACKED)

	if attack == "":
		if is_carrying():
			# Both hands are full. The attack button throws what he is holding
			# rather than swinging through it.
			if attack_pressed or blast_pressed:
				begin_throw()
		elif blast_pressed and can_blast():
			begin_attack("blast")
		elif attack_pressed:
			begin_attack(_choose_attack())
	elif attack_pressed:
		# Buffered, not immediate: pressing during the jab queues the cross and
		# it starts when the jab finishes, so the combo reads as two hits.
		chain_queued = true
	_advance_attack(delta)

	var rules: Dictionary = MOVES.get(attack, {})
	# Only where there is something to plant. Every other planted move is also
	# `ground`, so it can never be mid-air to begin with and nothing about them
	# changes; the blast is the one that can, and a blast that zeroed the axis
	# in flight would brake the jump it was thrown from.
	if rules.get("planted", false) and is_on_floor():
		axis = 0.0
	# A committed move cannot be jumped out of. The request is dropped rather
	# than buffered, so it does not fire the instant the move ends.
	if attack != "" and is_on_floor():
		pressed = false

	if not held:
		require_jump_release = false
	if is_on_floor() and velocity.y >= 0.0:
		last_floor_tick = tick
		opportunity_consumed = false
	if pressed and not require_jump_release:
		jump_request_tick = tick
	if fling_t > 0.0:
		# Thrown, and committed to it: neither friction nor air control touches his
		# horizontal speed, so the knockback carries its full distance and gravity
		# below brings him down. The same shape as an enemy's uninterruptible jump.
		pass
	elif rules.has("drive"):
		velocity.x = move_toward(velocity.x, facing * float(rules.drive), tuning.acceleration * delta)
	else:
		var rate: float = tuning.acceleration if not is_zero_approx(axis) else tuning.deceleration
		var top: float = tuning.speed * (CARRY_SPEED if (is_carrying() and carry_heavy) else 1.0)
		velocity.x = move_toward(velocity.x, axis * top, rate * delta)
	# Facing is frozen mid-move, otherwise the hitbox could flip away from the
	# fist between the wind-up and the contact frame.
	if not is_zero_approx(axis) and attack == "":
		facing = signf(axis)
	velocity.y = minf(velocity.y + tuning.gravity * delta, tuning.terminal_velocity)
	if not opportunity_consumed and tick - last_floor_tick <= tuning.coyote_ticks and tick - jump_request_tick <= tuning.buffer_ticks:
		velocity.y = tuning.jump_velocity
		opportunity_consumed = true
		jump_request_tick = -1000
		jumps += 1
	move_and_slide()
	position.x = maxf(position.x, 20.0)
	visual.advance(delta)
