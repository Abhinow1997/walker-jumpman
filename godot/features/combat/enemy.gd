extends Area2D
## An enemy: closes on the player and strikes when it is near enough to land a
## blow. HOW it closes, how hard it hits and how much it can take are its own —
## see PROFILES. The bandit rushes you with a committed dash, Mark walks through
## your blows and answers with a heavy one, the hunter keeps his distance and shoots.
##
## One script, a roster of enemies. Which one this is comes from `kind` — the
## folder under art/ and the stem of its manifest, and the row it reads from
## PROFILES — so a bandit and a mark are the same code pointed at different art
## and different numbers. It defaults to the bandit, the enemy this game had
## before there was more than one.
##
## Art is Little Fighter 2, cut by scripts/extract_<kind>.py and scaled 0.75 like
## the rest of the cast, so an enemy shares the player's palette and painted look
## rather than sitting beside it in a different decade of pixel art. Fan-ripped
## LF2 content: fine for coursework, not for release — see the PROVENANCE.md in
## each art/<kind>/ folder.
##
## Nothing here is specific to one enemy. The manifest shape is shared, so a new
## kind is a new art folder and a new extractor, not new code — its frames, its
## reach and its hit box all come from the manifest.
##
## He satisfies prop.gd's contract — Hittable layer, take_hit(damage, from) —
## without extending it. A struck crate tumbles and shatters; a struck bandit
## staggers and plays a hurt animation, so almost none of prop.gd's body would
## have been used. The contract is what matters, and every one of the player's
## attacks already works against him because of it.
##
## Deliberately an Area2D with no collision mask, like the props: the player
## walks through him. A solid enemy in a corridor this narrow pins the player
## against geometry with no way out, and this level has no room to dodge.
##
## He does his own gravity and his own floor-finding — see _integrate — which is
## also what lets him jump. The terrain is his problem rather than the player's
## free win: a gap is measured and leapt if he can make it, a ledge is climbed,
## and a player who jumps over his head is followed up. See the jump block below
## and _maybe_jump, which is where all of that is decided.
##
## He also guards. A thrown blast is announced to him while it is still in the
## air, and if he had time to see it coming his arms go up — which is what stops
## the ranged attack being the answer to every fight in the game. See the guard
## block below and warn_of_blast.
##
## One of them does none of that, because it never lands. The dragon is a
## `flyer`: it stands on its perch until the fight starts, takes off, and from
## then on holds an altitude instead of a footing, swoops instead of walking in,
## climbs over a blast instead of blocking it and flies out of the level instead
## of falling over. Every one of those is a branch off the same states and the
## same take_hit — see the flying block below, _advance_flyer and _depart.

const ART_ROOT := "res://features/combat/art/"
## An enemy entry that names no kind is the bandit, the one this game had first.
const DEFAULT_KIND := "bandit"

const HITTABLE := 64   # physics layer 7, the layer the player's strikes query
const PLAYER := 2      # physics layer 2, what his own punch looks for
const WORLD := 1       # what he stands on

## "The same energy as the user." Five jabs, two flying kicks, or three blasts —
## the player's whole moveset is calibrated against a health bar this size, so
## he reads as an even match rather than a punching bag.
const MAX_HEALTH := 100

## Hit box, matched to the drawn body (~26 x 51) and kept just inside it.
const BODY := Vector2(22, 45)

## Slower than the player's 320 on purpose: he must always be outrunnable. The
## player's answer to a bandit he does not want to fight is to leave.
const WALK_SPEED := 70.0
## Starts walking at this distance. Where he commits to a punch is derived from
## his own reach — see attack_range() — rather than hard-coded, so swapping the
## enemy art cannot leave him swinging at air from out of range.
const AGGRO_RANGE := 280.0
## He may not chain punches; the gap is the player's window to answer.
const ATTACK_COOLDOWN := 0.8
## Struck, he cannot act. Long enough that the player's two-jab combo lands in
## full, short enough that it is not a stun-lock.
const STAGGER_TIME := 0.3
## Knocked back by a blow, scaled by its damage against this.
const KNOCK_REFERENCE := 40.0
const KNOCK_X := 90.0
const GRAVITY := 1440.0
## How long the body lies there before it is cleared.
const DEAD_LINGER := 1.6

## Each enemy fights to its own personality. One script still, but the numbers
## and the approach are read from here, keyed by kind. A kind with no row falls
## back to DEFAULT_PROFILE, the plain walker this started as.
##
##   style       how it closes, and what it is
##   walker      walks in and jabs — the original
##   charger     dashes the last stretch: it commits, and it hurts to stand there
##   bruiser     slow and heavy, and armoured mid-swing — you cannot trade with him
##   archer      keeps his distance and looses arrows; forced to his fists up close
##   flyer       takes off and never lands: cruises out of reach and swoops
##
## Fields: health, speed (walk), damage (per melee hit), cooldown (between
## attacks), stagger (hurt time), knock (knockback taken, scaled), aggro (approach
## range), armor (super-armour during its own attack), leap (how fast he may
## travel through the air, which is what decides how wide a gap he can clear),
## guard (what a block can soak before it breaks, as a multiple of his own
## health) and react (how many seconds of warning he needs before he can get his
## arms up at all — times the blast's 560 px/s, that is the range inside which
## he simply cannot).
## Charger adds charge_speed and charge_range; archer adds fire_range, fire_min,
## shoot_cooldown and arrow_damage; flyer adds cruise, dive, swoop_cooldown and
## climbs — see the flying block below.
const DEFAULT_PROFILE := {
	"style": "walker", "health": MAX_HEALTH, "speed": WALK_SPEED,
	"damage": 20, "cooldown": ATTACK_COOLDOWN, "stagger": STAGGER_TIME,
	"knock": 1.0, "aggro": AGGRO_RANGE, "armor": false, "leap": 170.0,
	"guard": 1.5, "react": 0.32,
}
const PROFILES := {
	# The rusher: light on his feet, closes with a committed dash.
	# He leaps as hard as he charges: 215 px/s carries him 161 px through a
	# 0.75 s hop, which is every gap on the course bar the two widest.
	"bandit": {
		"style": "charger", "health": 100, "speed": 84.0, "damage": 20,
		"cooldown": 0.68, "stagger": 0.28, "knock": 1.1, "aggro": 340.0,
		"armor": false, "charge_speed": 215.0, "charge_range": 200.0,
		"leap": 215.0,
		# Quick hands: 0.30 s is 168 px of warning cold, 76 px once he is braced.
		"guard": 1.5, "react": 0.30,
	},
	# The bruiser: soaks damage, hits like a truck, and will not be staggered out
	# of his own swing. Slow enough that the answer is footwork, not trading.
	# Heavy in the air as well as on the ground: 150 px/s is 112 px of hop, which
	# takes the Isles' short gaps and stops dead at its chasms. Not lower — at
	# 110 he could not clear a single hole on the course and the whole thing was
	# decoration on him. Not higher either: a bruiser who can follow you over a
	# chasm leaves you nowhere to put the fight down.
	"mark": {
		"style": "bruiser", "health": 175, "speed": 46.0, "damage": 32,
		"cooldown": 1.05, "stagger": 0.12, "knock": 0.3, "aggro": 300.0,
		"armor": true, "leap": 150.0,
		# Slowest to read one — 0.50 s is 280 px, so anything thrown at conversational
		# range goes straight through him. He already has super-armour; a bruiser who
		# both eats your blows and guards them has no way in at all.
		"guard": 1.0, "react": 0.50,
	},
	# The archer: keeps his distance and looses arrows, kiting backwards to hold
	# the gap open. Light and fragile, and forced to his fists if you close in.
	# Light, so he gets across a gap easily — but he only ever jumps to keep his
	# footing. An archer who leaps at you has given up the one thing he is for;
	# see the leap gate in _maybe_jump.
	"hunter": {
		"style": "archer", "health": 82, "speed": 78.0, "damage": 14,
		"cooldown": 0.7, "stagger": 0.32, "knock": 1.25, "aggro": 520.0,
		"armor": false, "fire_range": 430.0, "fire_min": 150.0,
		"shoot_cooldown": 1.05, "arrow_damage": 12, "leap": 195.0,
		# Watching the gap is his whole job, so he reads one fastest — but there is
		# not much behind the bow, and his pool is the shallowest of the three.
		"guard": 1.2, "react": 0.26,
	},
	# A bruiser turned up: twice a mark's
	# health, hits harder, and barely rocks when hit. His reach is not set here
	# — it is measured off the flame in the art by extract_dragon_lord.py — and
	# it is long, so the gap that is safe against a mark is not safe against him.
	#
	# NO LEVEL PLACES HIM at the moment: he held the Archway platform at the end
	# of The Fractured Isles until the dragon took that fight. Everything about
	# him still works and test_combat still exercises all of it, so putting him
	# back is one entry in a level's `enemies` array and nothing else.
	# Slow on purpose: the answer is the footwork the course has been teaching,
	# and at twice the cast's size he is easy to read coming. He does not leap;
	# the arena is flat and a boss who follows you over a chasm leaves nowhere
	# to put the fight down.
	"dragon_lord": {
		"style": "bruiser", "health": 420, "speed": 52.0, "damage": 38,
		"cooldown": 1.35, "stagger": 0.10, "knock": 0.15, "aggro": 460.0,
		"armor": true, "leap": 0.0, "body": Vector2(44, 88),
		# No guard — the pack ships no defend frame, so there is nothing to put on
		# screen and a block nobody can see is worse than no block. He answers a
		# thrown blast by breathing on it instead: see `burns` and the burning
		# block above. Better suited to him anyway.
		"guard": 0.0, "burns": true,
		# Seconds between specials. Long: they are the beats of the fight, and
		# a boss who breathes fire every time he is in range is just a longer
		# punch. Between them he swings like the bruiser he is.
		"special_cooldown": 5.0,
	},
	# The dragon: the last fight on the course, and the only enemy that is
	# really two. In the air nothing else here is anything like it and its
	# whole approach is _advance_flyer; on its feet it is an ordinary bruiser
	# running the same chase everything else does. See the flying block and the
	# phase block below for what these numbers mean.
	#
	# Not to be confused with "dragon_lord" above, who is a bipedal boss you
	# fight toe to toe and nothing else. This one does that AND flies, because
	# the pack draws both — fourteen animations, thirteen of them recovered out
	# of watermarked previews by scripts/extract_dragon.py.
	#
	# `cruise` 156 is the one number the rest of it is built around, and it is
	# the answer to two measurements that nearly meet:
	#   * the player's jump apexes at 107 and his highest hit box reaches 36
	#     above his feet, so from the deck he strikes at 143 — 13 short of the
	#     dragon's belly. Cruising, it simply cannot be reached from the floor.
	#   * the camera shows 270 above his feet, and the dragon's raised wingtip
	#     is 104 above its own soles, so 156 puts the whole animal on screen
	#     with 10 to spare. Any higher and it flies out of the top of the shot.
	# The arena answers the first: two floating stones 96 up, from which a
	# jumped strike reaches 239 and lands. That is the air half of the fight —
	# take the height, or wait for it to come down. It always does.
	"dragon": {
		"style": "flyer", "health": 240, "speed": 150.0, "damage": 34,
		"cooldown": 1.2, "stagger": 0.24, "knock": 0.35, "aggro": 560.0,
		# Armoured, like the other boss and for the same reason turned up: you
		# cannot stagger it out of a swoop it has already committed to. The red
		# flash still fires on every blow, so the hits read even when nothing
		# visibly stops.
		"armor": true, "leap": 0.0, "body": Vector2(118, 96),
		# It does not stay up. After `air_time` in the air it comes down and
		# fights on its feet for `ground_time`, then takes off again — see the
		# phase block below. Both halves are drawn: the pack has a ground idle,
		# a walk, a claw and a standing fire breath, and none of them would
		# ever be seen by a dragon that only ever circled.
		"air_time": 9.0, "ground_time": 7.0,
		# Seconds between fire breaths, which are the specials of both phases.
		"special_cooldown": 4.0,
		# No guard. There is no block anywhere in the pack's fourteen clips,
		# and a guard nobody can see is worse than none — the same call the
		# Dragon Lord's `burns` was. Its answer is `climbs`: it goes over the
		# top of a blast, which costs it the pass it was in the middle of.
		# Grounded it has no answer at all, which is part of why coming down is
		# a real risk to it and not just a change of scenery.
		"guard": 0.0, "climbs": true, "react": 0.30,
		"cruise": 156.0, "dive": 320.0, "swoop_cooldown": 1.4,
	},
}

## A charge is a committed dash: it runs at most this long, then he pulls up with
## a moment's recovery. That whiff window is the counter to standing your ground.
const CHARGE_TIME := 0.6
const CHARGE_RECOVER := 0.3

# --- the jump ----------------------------------------------------------------
#
# Deliberately a little weaker than the player's, and measured the same way:
# apex = v^2 / 2g. His is 640^2/(2*1920) = 106.7 px; this is 540^2/(2*1440) =
# 101.3. So every step on the course he can climb, they can follow him up, and
# there is nowhere he can stand that they can reach and he cannot leave.
#
# It also has to stay UNDER the perch ledges. The hunters on the Isles' high
# shelves sit 144 px above the deck at the lowest — see holds_gate — and the
# whole gate design rests on them being out of the fight. 101 px of jump keeps
# them up there, and DROP_LIMIT keeps them from coming down.
const JUMP_VELOCITY := -540.0
## How far ahead he looks for the edge he is about to walk off.
const EDGE_PROBE := 20.0
## Landings are searched outward in steps this size. Coarse on purpose: this runs
## per enemy per frame and 12 px is finer than any ledge on the course.
const LANDING_STEP := 12.0
## He aims this far PAST the lip he is clearing rather than at it, so a jump that
## is a pixel short still puts him on the ledge instead of in the wall.
const LANDING_INSET := 18.0
## The biggest drop he will take on purpose, by jumping or by stepping off a
## ledge. Under the 144 px perches for the reason above, and under the player's
## own jump, so he never puts himself somewhere the player cannot follow.
const DROP_LIMIT := 120.0
## After a jump: a moment on the floor before the next one. Long after a leap at
## the player, so he cannot pogo on your head; short after a platforming hop, or
## a staircase would take him all day.
const HOP_RECOVER := 0.9
const STEP_RECOVER := 0.25
## Landing from his own jump leaves him briefly flat-footed — the counter to an
## enemy who follows you into the air.
const LAND_RECOVER := 0.16

# --- the guard ---------------------------------------------------------------
#
# The answer to mashing K. A blast is thrown, it flies flat at a known speed, and
# anyone with time to see it coming gets his arms up — see warn_of_blast, which
# the session calls on every enemy the moment one leaves the player's hand.
#
# Three things keep it from simply switching the blast off:
#
#   * Distance. He has to SEE it coming: inside his reaction time there is no
#     guard at all, so closing the range is the counter.
#   * A pool. Each block spends what it soaked, and the blow that empties the
#     pool is not blocked — it lands clean and staggers him. Guards break.
#   * A leak. A fifth of a blocked blast gets through anyway, so shooting a
#     guarding enemy is weak rather than pointless.
#
## What gets through a block.
const GUARD_SOAK := 0.2
## He throws his arms up this long before the blast reaches him and holds them
## there a moment after. Deliberately not "the instant it is thrown": an enemy
## who freezes the moment you press K, across the whole room, stops being a
## fight and becomes a statue you are keeping still.
const GUARD_LEAD := 0.18
const GUARD_TIME := 0.40
## Having just seen one thrown, he is expecting the next — so the reaction he
## needs is a fraction of the cold one. THIS is the anti-spam rule: mash K and
## he reads them from close enough that only the first gets through.
const BRACE_TIME := 2.0
const BRACED_REACTION := 0.45
## A spent guard is back in about this long. Long enough that a broken guard is
## an opening worth pressing.
const GUARD_REGEN_TIME := 6.0

# --- burning one out of the air ----------------------------------------------
#
# The Dragon Lord's answer instead of a guard. His pack ships no defend frame —
# idle, walk, attack, hurt, death and two specials, nothing else — so he cannot
# put his arms up. What he can do is breathe on it: told a blast is coming, he
# throws his attack early enough that the fire is out when it arrives, and
# anything that flies into the fire is destroyed rather than resolved.
#
# It suits him better than a guard would. A boss who blocks is a wall; a boss who
# answers a thrown fireball by throwing a bigger one is a fight.
#
## How long the fire is actually drawn for, in frames either side of the move's
## own hit frame. Read off the sheets: his attack breathes on frames 4 to 9 of
## 16 and its hit frame is 5, which is exactly this window, and the same window
## sits inside the flame on both specials.
const BURN_BEFORE := 1
const BURN_AFTER := 4
## Thrown a little early, so the blast meets the fire rather than its first
## frame. Slack for the fact that the player is usually moving while he throws.
const BURN_LEAD := 0.05

# --- flying ------------------------------------------------------------------
#
# The fifth style, and the only one with no feet on the ground. Everything
# above this line — gravity, the floor probe, the walk, the charge, the jump,
# the kiting — is about a body standing on terrain, and a flyer uses none of
# it. Its whole approach is _advance_flyer, and _integrate skips the floor for
# it entirely.
#
# It starts PERCHED. The level stands it on a solid like anything else, which
# is what lets scripts/check_levels.py measure it and what makes the take-off
# a beat of the fight rather than something that happened before you arrived.
# It launches when the fight starts and never lands again — not to rest, and
# not to die.
#
# Every altitude below is measured from `deck_y`, the height it took off from.
# That is a real constraint on a level: stand a flyer's perch level with the
# ground its fight happens over, or it will cruise relative to somewhere else.
#
## How long one pass runs before it pulls up, connected or not. Long enough to
## nose down and then cross the arena, short enough to be a pass rather than a
## pursuit — see the two halves of it in _advance_flyer.
const SWOOP_TIME := 1.7
## Where the bottom of a pass puts its soles, relative to the player's, and how
## close to that it has to have got before it will bite.
##
## Both are set by the two boxes that have to meet it down there, and there is
## less room than it looks. Its strike box hangs 44 below its own sole and
## reaches 78 above — that is the wing on the downstroke, measured off the art
## by scripts/extract_dragon.py — so anything under about 86 connects with a
## 42-tall player. The BLAST is the tight one: it flies at 25 to 43 above the
## floor, and the dragon's own body box starts at its soles, so a pass that
## bottoms out above 43 cannot be shot at all, at any range. 16 with 8 of
## slack measures out at about 23, which leaves 20 of overlap with the blast
## and 13 with a standing jab. It was 22 and 10, which came out at 29 and
## left the jab seven — a boss fight decided by seven pixels.
const STRIKE_HEIGHT := 16.0
const STRIKE_SETTLED := 8.0
## The ceiling on its vertical speed, and how hard it pulls toward the height
## it wants. The gain is per second: 3.0 is a bird correcting, not a lift.
const CLIMB_SPEED := 340.0
const CLIMB_GAIN := 3.0
## How a pass splits into its two halves. It opens the throttle in proportion
## to how close it has got to the line it is diving onto: at SWOOP_SETTLE off
## it is down to SWOOP_NOSE_DOWN of its dive speed, and at nothing off it is
## flat out. Which makes the first half of a swoop a descent and the second
## half a run, rather than one diagonal that arrives early and high.
const SWOOP_SETTLE := 90.0
const SWOOP_NOSE_DOWN := 0.25
## The ring it circles in between passes: closer than NEAR it backs off,
## further than FAR it drifts in, and in between it holds. NEAR is also the
## shortest run-in it will begin a pass from, which is what actually sets it.
##
## A pass has to fall 134 px before it is level with anybody. That takes about
## 0.87 s and eats about 140 px of ground, and the strike goes in from roughly
## 180 out — so a dragon starting a pass from inside those two added together
## is still coming down when it swings. It did exactly that: strikes thrown
## from 65 px out, by which time the wind-up had carried it clean past the
## player and the blow landed behind him. It waits for the room now.
const STANDOFF_NEAR := 340.0
const STANDOFF_FAR := 470.0
## It may not fly into the ground it took off from. Nothing else would stop it:
## there is no collision under a flyer and no gravity to land it.
const FLOOR_CLEAR := 10.0
## Its answer to a thrown blast, in place of a guard: it goes over the top. The
## thing flies dead flat, so height is a real dodge rather than a special case
## — the 60 px test at the top of warn_of_blast is the same one that decided it
## was in the way at all. The cost is the pass it was in the middle of, which
## is what makes this a trade and not a switch that turns the blast off.
const DODGE_TIME := 0.6
const DODGE_LIFT := 90.0
## Put down, it goes down on the deck first and leaves afterwards — see
## _advance_flyer_death, which plays the pack's own collapse and then picks the
## body up and flies it out of the level.
const DEPART_SPEED := 300.0
const DEPART_CLIMB := -180.0
## How long the departure runs before the body is cleared.
const DEPART_TIME := 2.4
## And how long a body killed in mid-air is allowed to fall before the collapse
## starts anyway. Only reached by a dragon put down over a hole.
const FLYER_FALL_MAX := 1.2

# --- the two phases ----------------------------------------------------------
#
# A flyer is two enemies in one body, because the pack draws two. In the air it
# is everything above: cruise, pass, strike, climb. On the ground it is an
# ordinary bruiser and runs _advance_chase unchanged — it walks in, it claws,
# and it breathes fire at mid range. That is the point of the split: the ground
# half needed no new movement code at all.
#
# It changes over on a clock rather than on damage, so the fight has a rhythm
# you can learn: `air_time` up, `ground_time` down, and a drawn take-off and
# landing between them that are committed and cannot be interrupted.
#
## How far through the take-off its feet leave the ground, and how far through
## the landing they find it again. Both clips are drawn with the transition in
## the middle rather than at an end, so the lift follows the picture instead of
## snapping on the last frame.
const LIFT_AT := 0.62
const TOUCH_AT := 0.55

enum State { IDLE, WALK, PUNCH, HURT, DEAD, CHARGE, SHOOT, JUMP, BLOCK }

## The session connects this; it owns the player's health, not the enemy.
signal struck_player(damage: int, from: Vector2)
## The archer looses an arrow: the session spawns it as its own travelling object,
## so it outlives the archer that fired it.
signal fired_arrow(at: Vector2, direction: float, damage: int)

## Which enemy this is: the folder under art/ and the stem of its manifest. Set
## by the spawner before add_child(); left at the default it is the bandit.
var kind: String = DEFAULT_KIND

## Manifests cached per kind, so a level holding both a bandit and a mark loads
## each one once rather than once per body on screen.
static var _data_by_kind: Dictionary = {}

var health: int = MAX_HEALTH
var state: State = State.IDLE
var facing: float = -1.0
var clock: float = 0.0
var frame: int = 0
var velocity: Vector2 = Vector2.ZERO
var cooldown: float = 0.0
var stagger: float = 0.0
## Counts down after a blow lands, exactly as the player's does. Until now a hit
## on an enemy was legible only from the recoil frame, which the bruiser eats
## outright through his super-armour — so the one enemy you most need feedback
## from was the one that gave you none.
##
## Kept in step with HURT_FLASH and HURT_TINT in features/player/player_sprite.gd
## by a check in test_combat.gd: being hit has to read the same whoever it
## happens to.
var hurt_flash: float = 0.0
const HURT_FLASH := 0.35
const HURT_TINT := Color(1.0, 0.42, 0.38)
var dead_t: float = 0.0
## His hit box. Built in _init at the cast's size, before the kind is even
## known, and refitted in _ready once the profile has been read.
var box: CollisionShape2D
## Which attack is mid-swing. Every kind but the boss only has the one.
var move: String = "punch"
## Counts down between specials, so they punctuate the fight rather than
## becoming it. Starts loaded, so he opens with an ordinary swing.
var special_ready: float = 0.0
## One punch may only land once, however many frames its box is open for.
var landed_this_punch: bool = false
## One draw of the bow looses one arrow, however long the release frame is held.
var fired: bool = false
## Set by whoever spawns him.
var home: Vector2 = Vector2.ZERO
## Whether the fight has started. Until it has he stands where the level put
## him, which is what `aggro` is for: without that gate every enemy in the level
## sets off the moment it loads and the first hunter arrives while the player is
## still on the opening ledge.
##
## Once it HAS started, aggro stops gating him and he follows. Backing off three
## steps and watching a bruiser give up, turn round and stand there reads as him
## being broken rather than as an escape — and the fight you walked away from is
## one the section gate will not let you leave anyway.
##
## Set by walking into his aggro range or by being hit from outside it, so a
## blast from across the room starts a fight rather than poking a statue.
## Cleared only by a retry: see reset().
var engaged: bool = false
## Whether this one holds its section's gate shut — see the sections block in
## session.gd. True for anything standing on ground the player runs along.
##
## The level marks the exceptions with "perch". The four on the Isles' high
## ledges stand 144 px above the deck and more: the player's jump apexes at 107,
## and both the blast and the arrow fly dead flat, so there is no way at all to
## kill them. A gate waiting on one of those could never open, and an unopenable
## gate is a worse bug than a sniper you have to run past.
##
## Their own jump does not change that: it is smaller than the player's, and
## DROP_LIMIT stops them stepping off a shelf that high — see the jump block.
var holds_gate: bool = true
var fall_limit: float = INF
var target: Node2D = null

var sprite: AnimatedSprite2D
var art_faces: float = -1.0
## Texture pixel to world unit, read from the manifest in _ready.
var art_scale: float = 1.0

## Personality, resolved from PROFILES in _ready. Kept in fields rather than read
## from the dict each frame so the hot path stays cheap and readable.
var prof: Dictionary = DEFAULT_PROFILE
var style: String = "walker"
var max_health: int = MAX_HEALTH
var speed: float = WALK_SPEED
var aggro: float = AGGRO_RANGE
var attack_cooldown: float = ATTACK_COOLDOWN
var stagger_time: float = STAGGER_TIME
var knock: float = 1.0
var armor: bool = false
## How fast he may travel horizontally through a jump, which is what sets the
## widest gap he can clear: reach = leap_speed * air_time().
var leap_speed: float = 170.0
## Whether his feet are on the floor this frame — a charge and the archer's kiting
## both need floor under them, and an airborne enemy is left to its momentum.
var grounded: bool = true
## Counts down after a jump, so he cannot pogo. Separate from `cooldown` because
## that one gates his fists: a landed enemy must be able to punch immediately.
var hop_cooldown: float = 0.0

# --- the guard, as state -----------------------------------------------------
## What the block can still soak. Spent by what it absorbs, refilled over
## GUARD_REGEN_TIME while it is down, and the blow that empties it is the one
## that gets through — see take_hit.
var guard: float = 0.0
var max_guard: float = 0.0
## How many seconds of warning he needs to get his arms up, from his profile.
var guard_reaction: float = 0.32
## Counting down to a blast he has seen and intends to meet. Negative when there
## is nothing incoming. He keeps walking until it reaches zero: the guard goes up
## just before the blast does, not the moment it was thrown.
var guard_due: float = -1.0
## Seconds left with the arms up.
var guard_hold: float = 0.0
## Set whenever a blast goes past, hit or miss. While it runs he is expecting the
## next one and reads it from much closer — the reason mashing K stops working.
var braced: float = 0.0
## Drawn on the frame a guard gives way, so the break reads as a break.
var guard_broke: float = 0.0
const GUARD_BREAK_FLASH := 0.28
## Whether his attacks destroy what flies into them, from his profile.
var burns: bool = false
## Counting down to the swing he intends to meet a blast with; negative when
## there is nothing to meet. The Dragon Lord's half of the guard — see the
## burning block above.
var counter_due: float = -1.0
## Which way the blast he is answering is coming from, so he turns into it.
var counter_face: float = 0.0

# --- flying, as state --------------------------------------------------------
## False while it is still standing where the level put it. Until this flips a
## flyer is an ordinary grounded body in every respect, which is what lets it
## be placed, validated and drawn like one.
var aloft: bool = false
## The height it took off from. Every altitude it holds is measured from here.
var deck_y: float = 0.0
## The last height the target was STANDING at, which is what a pass dives onto
## — not the target itself.
##
## The difference is the whole shape of the fight. Tracking the player through
## a jump means the dragon holds station just over his head wherever he goes,
## and his own air kick reaches 25 above his feet against a body that starts at
## 22: a boss fight decided by three pixels, which measured as 212 swings and
## nothing landed. Diving at the FLOOR he is standing on instead means jumping
## carries him up into it, which is the answer the arena's two stones exist to
## teach — and a jump timed over the top of a pass is a real dodge rather than
## an invitation.
var mark_y: float = 0.0
## Counting down the pass it is in the middle of; negative between them.
var swoop: float = -1.0
## Which way this pass is going, committed at the top of it so it flies through
## and past rather than turning round the moment it overshoots.
var swoop_dir: float = 0.0
## Between passes.
var swoop_ready: float = 0.0
## Holding height out of a blast's flat path.
var dodge: float = 0.0
## Whether it answers a blast by climbing, from its profile.
var climbs: bool = false
## Seconds left in the phase it is in. One counts down while it is up, the
## other while it is down, and whichever runs out sends it the other way.
var air_left: float = 0.0
var ground_left: float = 0.0
## The take-off or the landing, mid-clip. Negative when it is neither. Both are
## committed: nothing interrupts them, which is what makes them read as a
## decision the dragon made rather than a state that flickered.
var shift: float = -1.0
var shift_up: bool = false
## When a dead flyer reached the deck, so the collapse starts on landing rather
## than in mid-air. Negative until it does.
var down_at: float = -1.0

func profile() -> Dictionary:
	return PROFILES.get(kind, DEFAULT_PROFILE)

func art_dir() -> String:
	return ART_ROOT + kind + "/"

func data() -> Dictionary:
	if not _data_by_kind.has(kind):
		var path := art_dir() + kind + ".json"
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			push_error("enemy: %s is missing. Run scripts/extract_%s.py." % [path, kind])
			_data_by_kind[kind] = {"animations": {}, "cell": [1, 1], "origin": [0, 0],
					"faces": -1, "render_scale": 1.0,
					"hit_frame": 0, "hit_rect": [0, 0, 0, 0], "hit_damage": 0}
		else:
			_data_by_kind[kind] = JSON.parse_string(text)
	return _data_by_kind[kind]

func _init() -> void:
	collision_layer = HITTABLE
	# He detects nothing by standing there; his punch queries for itself.
	collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = BODY
	box = CollisionShape2D.new()
	box.shape = shape
	box.position = Vector2(0, -BODY.y / 2.0)
	add_child(box)

func _ready() -> void:
	home = position
	# Personality first, so his health and reach are his own before anything reads them.
	prof = profile()
	style = str(prof.get("style", "walker"))
	max_health = int(prof.get("health", MAX_HEALTH))
	speed = float(prof.get("speed", WALK_SPEED))
	aggro = float(prof.get("aggro", AGGRO_RANGE))
	attack_cooldown = float(prof.get("cooldown", ATTACK_COOLDOWN))
	stagger_time = float(prof.get("stagger", STAGGER_TIME))
	knock = float(prof.get("knock", 1.0))
	armor = bool(prof.get("armor", false))
	# A kind drawn bigger than the cast needs a box to match, or the player
	# punches through the middle of him. Everyone else keeps the cast BODY.
	_fit_body(prof.get("body", BODY))
	# Starts loaded rather than ready, so the fight opens with a plain swing
	# and the first special has been earned.
	special_ready = float(prof.get("special_cooldown", 0.0))
	leap_speed = float(prof.get("leap", 170.0))
	guard_reaction = float(prof.get("react", 0.32))
	max_guard = float(max_health) * float(prof.get("guard", 1.5))
	guard = max_guard
	burns = bool(prof.get("burns", false))
	climbs = bool(prof.get("climbs", false))
	health = max_health
	move = basic_move()
	art_faces = float(data().get("faces", -1))
	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = _build_frames()
	sprite.centered = true
	sprite.offset = _pivot()
	## Linear, for the reason player_sprite.gd gives: this is painted LF2 art at
	## 0.75, not pixel art, and it only lands texel-perfect at two window sizes.
	## The whole cast shares the filter or a bandit standing next to him would be
	## visibly harder-edged than he is.
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	## The sheet is at the rip's own resolution; the node carries the
	## three-quarter cast size, the same as the player's.
	art_scale = float(data().get("render_scale", 1.0))
	sprite.scale = Vector2(art_faces, 1.0) * art_scale
	add_child(sprite)
	_play("idle")

## Sizes the hit box to this kind's art. The box is built in _init, before the
## kind is even known, so the default is the cast's and a bigger one is fitted
## here once the profile has been read.
func _fit_body(size: Vector2) -> void:
	if not is_instance_valid(box):
		return
	var shape := RectangleShape2D.new()
	shape.size = size
	box.shape = shape
	box.position = Vector2(0, -size.y / 2.0)

## One attack: which animation it wears, the frame it lands on, the box it
## lands with, and what it costs. A manifest with no `moves` — the three LF2
## rips — reports its top-level hit_frame and hit_rect as its only move, so
## nothing about those three changes.
func move_data(name: String) -> Dictionary:
	var moves: Dictionary = data().get("moves", {})
	if moves.has(name):
		return moves[name]
	return {"anim": "punch", "hit_frame": int(data().get("hit_frame", 0)),
			"hit_rect": data().get("hit_rect", [0, 0, 0, 0])}

## The special whose band this gap falls in, or "" for none. The bands do not
## overlap — see the manifest — so this is a straight lookup by distance and not
## a priority order.
func special_for(gap: float) -> String:
	var moves: Dictionary = data().get("moves", {})
	for name in moves:
		var spec: Dictionary = moves[name]
		# The plain attack is not a special. Named for the LF2 rips, flagged
		# for anything whose plain attack is called something else.
		if name == "punch" or bool(spec.get("basic", false)):
			continue
		# And a move drawn for one phase is never thrown in the other: a dragon
		# does not breathe standing fire while it is a hundred px up, and the
		# flying breath is drawn with no feet under it.
		var phase := str(spec.get("phase", ""))
		if (phase == "air") != aloft and phase != "":
			continue
		var band: Array = spec.get("range", [])
		if band.size() == 2 and gap >= float(band[0]) and gap <= float(band[1]):
			return name
	return ""

func _pivot() -> Vector2:
	## Puts his feet on the node origin, so he stands on the floor line
	## and mirrors about his own body rather than about the cell. In texture
	## pixels: the node's art_scale applies to the offset along with the art.
	var cell: Array = data().get("cell", [1, 1])
	var origin: Array = data().get("origin", [0, 0])
	return Vector2(float(cell[0]) / 2.0 - float(origin[0]),
				   float(cell[1]) / 2.0 - float(origin[1]))

func _build_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var cell: Array = data().get("cell", [1, 1])
	for key in data().get("animations", {}):
		var spec: Dictionary = data()["animations"][key]
		var path: String = art_dir() + str(spec.file)
		if not ResourceLoader.exists(path):
			push_warning("enemy: no sheet at %s (run scripts/extract_%s.py, then --import)" % [path, kind])
			continue
		var sheet: Texture2D = load(path)
		frames.add_animation(key)
		frames.set_animation_loop(key, bool(spec.loop))
		var durations: Array = spec.durations
		for i in durations.size():
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(i * float(cell[0]), 0, float(cell[0]), float(cell[1]))
			# Same arrangement as the player: speed pinned at 1 and each frame
			# carrying its own length, so the punch can hold on its extended
			# frame the way the pack's own preview does.
			frames.add_frame(key, atlas, float(durations[i]))
		frames.set_animation_speed(key, 1.0)
	return frames

func _play(name: String) -> void:
	var key := anim_for(name)
	if not is_instance_valid(sprite) or not sprite.sprite_frames.has_animation(key):
		return
	if sprite.animation == key and sprite.is_playing():
		return
	sprite.play(key)

func _show(name: String, index: int) -> void:
	## Attacks are stepped by this script rather than by the AnimatedSprite2D's
	## own clock, so the frame on screen is the frame whose hit box is live.
	var key := anim_for(name)
	if not is_instance_valid(sprite) or not sprite.sprite_frames.has_animation(key):
		return
	if sprite.animation != key:
		sprite.stop()
		sprite.animation = key
	sprite.frame = clampi(index, 0, sprite.sprite_frames.get_frame_count(key) - 1)

func anim_for(key: String) -> String:
	## Which animation actually plays for this key.
	##
	## A flyer has two of nearly everything, because the pack draws it fighting
	## in the air and fighting on its feet: two idles, two walks, two hurts and
	## two ways of breathing fire. While it is up, any key with an "_air"
	## variant uses it. Every other kind, and every key without one, is
	## unchanged — which is why nothing else in this file had to learn about
	## phases.
	##
	## _play, _show and _durations all resolve through here, so the frame on
	## screen and the clock stepping it can never be looking at different
	## animations.
	if aloft:
		var air := key + "_air"
		if data().get("animations", {}).has(air):
			return air
	return key

func _durations(key: String) -> Array:
	return data().get("animations", {}).get(anim_for(key), {}).get("durations", [])

func _total(key: String) -> float:
	var t := 0.0
	for hold in _durations(key):
		t += float(hold)
	return t

func _frame_at(key: String, t: float) -> int:
	## Which frame of a clip is up at time t, holding the last one past the end.
	var holds := _durations(key)
	var at := 0.0
	for i in holds.size():
		at += float(holds[i])
		if t < at:
			return i
	return maxi(holds.size() - 1, 0)

func alive() -> bool:
	return state != State.DEAD

func flying() -> bool:
	## Off the ground and staying there. False for a flyer still on its perch,
	## which is an ordinary grounded enemy in every respect — and false for
	## everything else always, which is what keeps the ground code untouched.
	return aloft and style == "flyer"

func basic_move() -> String:
	## The plain attack right now — what _start_punch throws and what reach()
	## and attack_range() are measured off.
	##
	## Everything in the cast has one of these. The dragon has two: it hits you
	## with its whole leading half in the air and with its claws on the ground,
	## and those are different moves with different boxes drawn on different
	## frames, so they cannot be one animation with a phase suffix the way the
	## idles and walks are.
	if style == "flyer":
		return "swoop" if aloft else "claw"
	return "punch"

func reach() -> float:
	## How far his fist gets from his own origin, straight off the hit box of
	## whatever his plain attack is at the moment.
	var r: Array = move_data(basic_move()).get("hit_rect",
			data().get("hit_rect", [0, 0, 0, 0]))
	return float(r[0]) + float(r[2])

func attack_range() -> float:
	## He commits a little inside his reach, so the blow lands on the player's
	## box rather than stopping a pixel short of it.
	return reach() + 4.0

func attack_damage() -> int:
	## What this blow costs the player. A special carries its own number, because
	## it is its own move; the plain swing is whatever the profile says, so tuning
	## him does not mean re-running the extractor.
	var spec := move_data(move)
	if spec.has("damage"):
		return int(spec["damage"])
	return int(prof.get("damage", data().get("hit_damage", 0)))

# --- seeing one coming -------------------------------------------------------

func guarding() -> bool:
	return state == State.BLOCK

func can_guard() -> bool:
	## Only off his own feet, and only out of something he can drop. A swing, a
	## dash, a draw and a jump are all committed — that is what makes each of
	## them a way through a guard. Asked twice: once when the blast is announced,
	## so a blow thrown at an enemy already mid-swing gets through, and again
	## when the guard falls due, so one who commits to something in the meantime
	## does not get to change his mind.
	return grounded and guard > 0.0 and state != State.DEAD \
		and state != State.HURT and not _attacking() and state != State.JUMP

func warn_of_blast(at: Vector2, direction: float, speed: float) -> void:
	## The session calls this on every enemy the moment the player throws one.
	## Whether anything comes of it is entirely his own business, which is the
	## point: the blast is not told who blocked it and the player is not told who
	## will.
	if state == State.DEAD or speed <= 0.0:
		return
	# Coming at him rather than away, and level enough to reach him — it flies
	# dead flat, so a blast thrown on another shelf is not his problem.
	var gap: float = global_position.x - at.x
	if absf(gap) < 1.0 or signf(gap) != signf(direction):
		return
	if absf(at.y - global_position.y) > 60.0:
		return
	var eta: float = absf(gap) / speed
	# He saw it thrown whether or not he can do anything about it, and that is
	# what he braces on. Set before the reaction test, so the shot that beats his
	# guard is still the shot that teaches him to expect the next.
	var need: float = guard_reaction * (BRACED_REACTION if braced > 0.0 else 1.0)
	braced = BRACE_TIME
	if eta < need:
		return
	# Height instead of arms. A flyer already lives on the one axis the blast
	# does not use, so it goes over the top — and pays for it with the pass it
	# was in the middle of, which is the whole trade. Only once it is up: on
	# its perch it is a standing target like anything else, and that first shot
	# is what puts it in the air.
	if climbs and aloft:
		dodge = maxf(dodge, DODGE_TIME)
		swoop = -1.0
		swoop_ready = maxf(swoop_ready, DODGE_TIME)
		return
	# Nothing to put his arms up with, but something to breathe. He needs the
	# time to see it AND the time to wind up, so the range he can burn one out of
	# the air from is set by his own animation rather than by a number: the fire
	# is 0.36 s into his swing, which is 200 px of the blast's flight.
	if burns and max_guard <= 0.0:
		var lead: float = hit_lead("punch")
		if eta < lead + BURN_LEAD:
			return
		var swing: float = eta - lead - BURN_LEAD
		counter_due = swing if counter_due < 0.0 else minf(counter_due, swing)
		counter_face = -direction
		return
	if not can_guard():
		return
	# Arms up just before it arrives, not now. Standing in a guard for the whole
	# flight would freeze him solid every time the player presses K.
	#
	# The soonest one wins: two thrown in quick succession are two threats, and
	# timing the guard for the later of them means walking into the earlier.
	var due: float = maxf(0.0, eta - GUARD_LEAD)
	guard_due = due if guard_due < 0.0 else minf(guard_due, due)

func hit_lead(name: String) -> float:
	## Seconds from the first frame of a move to the frame its blow is live on —
	## how far ahead of a blast he has to start swinging to meet it.
	var spec := move_data(name)
	var holds := _durations(str(spec.get("anim", "punch")))
	var t := 0.0
	for i in mini(int(spec.get("hit_frame", 0)), holds.size()):
		t += float(holds[i])
	return t

func burns_projectiles() -> bool:
	## Is the fire out? Anything that flies into it is destroyed rather than
	## resolved — see the burning block above, and blast.gd, which asks.
	##
	## Any of his attacks, not just the one he threw on purpose: a blast lobbed
	## into a swing he was already making burns for the same reason, and a player
	## who has to watch what the boss is doing before pressing K is the point.
	if not burns or state != State.PUNCH:
		return false
	var live: int = int(move_data(move).get("hit_frame", 0))
	return frame >= live - BURN_BEFORE and frame <= live + BURN_AFTER

func _tick_guard(delta: float) -> void:
	if braced > 0.0:
		braced = maxf(0.0, braced - delta)
	if guard_broke > 0.0:
		guard_broke = maxf(0.0, guard_broke - delta)
	if guard_hold > 0.0:
		guard_hold = maxf(0.0, guard_hold - delta)
	elif guard < max_guard and max_guard > 0.0:
		# Only while it is down: a guard held up is not a guard recovering.
		guard = minf(max_guard, guard + max_guard * delta / GUARD_REGEN_TIME)
	if guard_due >= 0.0:
		guard_due -= delta
		if guard_due <= 0.0:
			guard_due = -1.0
			if can_guard():
				guard_hold = GUARD_TIME
	if counter_due >= 0.0:
		counter_due -= delta
		if counter_due <= 0.0:
			counter_due = -1.0
			# Only out of something he can drop. Deliberately NOT gated on his
			# attack cooldown: that number paces the blows he chooses to throw at
			# the player, and this is a reaction to something thrown at him. Gated
			# on it he answered one blast in four, which is not an answer — and
			# the thing that keeps him from becoming a fire hose is that a swing
			# takes 1.2 s, so he can only ever meet about every other one.
			#
			# Caught mid-attack he does not start another. He does not need to:
			# the fire he is already breathing burns it anyway.
			if grounded and not _attacking() and state != State.HURT \
					and state != State.DEAD:
				if counter_face != 0.0:
					facing = counter_face
				_start_attack("punch")

# --- the contract -----------------------------------------------------------

func take_hit(damage: int, from: Vector2) -> bool:
	## prop.gd's contract. Returns false once he is down, so a strike passes
	## through a corpse and keeps looking for something else to hit.
	if state == State.DEAD:
		return false
	# Hit from anywhere, by anything: that is a fight started, even if it came
	# from a blast fired well outside his aggro range. True of a blocked one too
	# — a guard is still a hit, it is only a cheap one.
	engaged = true
	var front: bool = signf(from.x - global_position.x) == signf(facing)
	if guarding() and front:
		# A guard soaks what it has left. The blow that empties the pool is NOT
		# the one it stops: it is the one that gets through, which is the whole
		# reason a guard is a wall you can push over rather than one you cannot.
		if guard >= float(damage):
			guard -= float(damage)
			health -= int(round(float(damage) * GUARD_SOAK))
			hurt_flash = HURT_FLASH * 0.5
			# Shoved, not staggered. He keeps his feet and keeps his guard.
			velocity.x = -facing * KNOCK_X * 0.35 * knock
			guard_hold = maxf(guard_hold, 0.12)
			if health <= 0:
				return _go_down()
			return true
		# It gave. He wears the broken-guard frame, eats the blow whole, and is
		# open for as long as anyone else would be.
		guard = 0.0
		guard_hold = 0.0
		guard_broke = GUARD_BREAK_FLASH
	health -= damage
	# Set here rather than in any of the branches below, so every blow that lands
	# flashes: the killing one, the one a bruiser shrugs off mid-swing, and the
	# ordinary one that staggers him.
	hurt_flash = HURT_FLASH
	facing = 1.0 if from.x > global_position.x else -1.0
	var away := -facing
	# Knockback is scaled by how much the blow weighs against him: a bruiser barely
	# rocks, the light archer gets thrown.
	velocity.x = away * KNOCK_X * clampf(float(damage) / KNOCK_REFERENCE, 0.4, 1.6) * knock
	if health <= 0:
		return _go_down()
	# Super-armour: a bruiser does not drop his own swing for a single blow — he
	# eats it and follows through, which is why standing in front of him and
	# trading does not work. Only being put down stops him. Everyone else, and the
	# bruiser between swings, staggers as normal.
	if armor and _attacking():
		return true
	clock = 0.0
	frame = 0
	landed_this_punch = false
	state = State.HURT
	stagger = stagger_time
	_show("hurt", 0)
	return true

func _go_down() -> bool:
	## Put down. Its own function because there are two ways in now — the blow
	## that beats his health, and the trickle that gets through a guard while it
	## is already at nothing.
	health = 0
	state = State.DEAD
	dead_t = 0.0
	clock = 0.0
	frame = 0
	guard_hold = 0.0
	guard_due = -1.0
	landed_this_punch = false
	if style == "flyer":
		# It comes DOWN first. Whatever height it was at, the pack draws a
		# collapse on the deck and that is what plays — see
		# _advance_flyer_death, which then picks the body up and flies it out.
		#
		# Turned away here, once: take_hit has just faced it toward whoever
		# landed the blow, and a beaten dragon does not leave toward him.
		aloft = false
		swoop = -1.0
		shift = -1.0
		down_at = -1.0
		facing = -facing
		velocity.x = facing * 30.0
	_show("hurt", 0)
	return true

func _attacking() -> bool:
	return state == State.PUNCH or state == State.CHARGE or state == State.SHOOT

# --- his own attack ---------------------------------------------------------

func _hit_box() -> Rect2:
	var r: Array = move_data(move).get("hit_rect", [0, 0, 0, 0])
	var box := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	# Written facing forward, mirrored with him, exactly as the player's are.
	if facing < 0.0:
		box.position.x = -(box.position.x + box.size.x)
	box.position += global_position
	return box

func _try_to_land() -> void:
	if landed_this_punch:
		return
	var box := _hit_box()
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := RectangleShape2D.new()
	shape.size = box.size
	query.shape = shape
	query.transform = Transform2D(0.0, box.position + box.size / 2.0)
	query.collision_mask = PLAYER
	query.collide_with_areas = false
	query.collide_with_bodies = true
	for result in get_world_2d().direct_space_state.intersect_shape(query, 4):
		if result.collider == target:
			landed_this_punch = true
			struck_player.emit(attack_damage(), global_position)
			return

# --- step -------------------------------------------------------------------

func reset() -> void:
	position = home
	health = max_health
	state = State.IDLE
	facing = -1.0
	clock = 0.0
	frame = 0
	velocity = Vector2.ZERO
	cooldown = 0.0
	stagger = 0.0
	hurt_flash = 0.0
	engaged = false
	dead_t = 0.0
	grounded = true
	hop_cooldown = 0.0
	guard = max_guard
	guard_due = -1.0
	guard_hold = 0.0
	braced = 0.0
	guard_broke = 0.0
	counter_due = -1.0
	counter_face = 0.0
	landed_this_punch = false
	special_ready = float(prof.get("special_cooldown", 0.0))
	# Back on its perch, wings folded, waiting to be walked up to again. A
	# retry that left a flyer in the air would put the next attempt's first
	# swoop in before the player had crossed the arena.
	aloft = false
	deck_y = position.y
	mark_y = 0.0
	swoop = -1.0
	swoop_dir = 0.0
	swoop_ready = 0.0
	dodge = 0.0
	air_left = 0.0
	ground_left = 0.0
	shift = -1.0
	shift_up = false
	down_at = -1.0
	# After the phase is back down, or a flyer would be handed its AIR attack
	# to stand on the ground with.
	move = basic_move()
	visible = true
	_play("idle")

func _floor_below(from_y: float) -> float:
	var query := PhysicsRayQueryParameters2D.create(
		Vector2(position.x, from_y - 8.0), Vector2(position.x, position.y + 2.0), WORLD)
	query.collide_with_areas = false
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return INF if hit.is_empty() else float(hit.position.y)

func _physics_process(delta: float) -> void:
	if cooldown > 0.0:
		cooldown = maxf(0.0, cooldown - delta)
	if hop_cooldown > 0.0:
		hop_cooldown = maxf(0.0, hop_cooldown - delta)
	if special_ready > 0.0:
		special_ready = maxf(0.0, special_ready - delta)
	_tick_guard(delta)
	# The arms come up out of anything he is free to drop — standing and walking.
	# A swing, a dash, a draw and a jump are committed and ride through, which is
	# what makes each of them a way past a guard. Done here rather than inside
	# _advance_chase so a guard falling due mid-stride lands on the frame it was
	# due on.
	if guard_hold > 0.0 and (state == State.IDLE or state == State.WALK):
		state = State.BLOCK
		velocity.x = 0.0

	match state:
		State.DEAD:
			_advance_dead(delta)
		State.HURT:
			_advance_hurt(delta)
		State.PUNCH:
			_advance_punch(delta)
		State.CHARGE:
			_advance_charge(delta)
		State.SHOOT:
			_advance_shoot(delta)
		State.JUMP:
			_advance_jump(delta)
		State.BLOCK:
			_advance_block(delta)
		_:
			_advance_chase(delta)

	_integrate(delta)
	if hurt_flash > 0.0:
		hurt_flash = maxf(0.0, hurt_flash - delta)
	if is_instance_valid(sprite):
		sprite.scale = Vector2(facing * art_faces, 1.0) * art_scale
		# Fades back to white on its own clock, so the flash outlives the recoil
		# frame and a blow still registers on something that never staggered.
		sprite.modulate = Color.WHITE.lerp(HURT_TINT, hurt_flash / HURT_FLASH)

func _integrate(delta: float) -> void:
	if flying():
		# No gravity and no floor: it holds whatever height it steered itself
		# to, and a pit under it is scenery. The one hard limit is the deck it
		# took off from — a staggered or departing flyer has nothing else to
		# stop it sinking through the rock.
		position += velocity * delta
		var lowest := deck_y - FLOOR_CLEAR
		if position.y > lowest:
			position.y = lowest
			velocity.y = minf(velocity.y, 0.0)
		grounded = false
		return
	velocity.y += GRAVITY * delta
	var prev_y := position.y
	position += velocity * delta
	if position.y > fall_limit:
		# Walked into a pit. Gone, rather than falling for ever and leaving a
		# live target the player can never reach.
		state = State.DEAD
		dead_t = DEAD_LINGER
		visible = false
		return
	if velocity.y < 0.0:
		grounded = false
		return
	var floor_y := _floor_below(prev_y)
	if floor_y != INF and position.y >= floor_y:
		position.y = floor_y
		velocity.y = 0.0
		grounded = true
	else:
		grounded = false

func _advance_dead(delta: float) -> void:
	if style == "flyer":
		_advance_flyer_death(delta)
		return
	velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
	dead_t += delta
	# A pack with its own death sheet plays it. The LF2 rips have none, so they
	# run the hurt animation out and hold its last frame, which is the closest
	# thing they have to a collapsed heap.
	var key := "death" if not _durations("death").is_empty() else "hurt"
	var holds := _durations(key)
	if holds.is_empty():
		return
	var total := 0.0
	for hold in holds:
		total += float(hold)
	var t := 0.0
	var index := holds.size() - 1
	for i in holds.size():
		t += float(holds[i])
		if dead_t < t:
			index = i
			break
	_show(key, index)
	# DEAD_LINGER is the floor, not the rule. Both bosses run well past it and
	# neither may be cut off half way: the Dragon Lord's death is a two-second
	# burst, and the dragon's is a flight out of the level.
	if dead_t >= maxf(DEAD_LINGER, total):
		visible = false

func _advance_flyer_death(delta: float) -> void:
	## Two beats, because the pack draws both.
	##
	## First it goes down. Killed in the air it drops out of it, and on the
	## deck it plays the collapse the pack ships — folding forward until it is
	## flat, which is a real death animation and not a flap held still.
	##
	## Then it gets up and leaves, which is the ending the level exists for. It
	## turns away from whoever put it there, beats its wings and climbs out of
	## the shot over DEPART_TIME against 300 px/s out and 180 up, and the body
	## is cleared when it is well clear of the corner.
	dead_t += delta
	if down_at < 0.0:
		# Still falling out of the sky. The cap is for a dragon put down over a
		# hole, which would otherwise never find a deck to land on.
		if grounded or dead_t >= FLYER_FALL_MAX:
			down_at = dead_t
			velocity.x *= 0.4
		else:
			velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
			_show("hurt", maxi(_durations("hurt").size() - 1, 0))
			return
	var since: float = dead_t - down_at
	var collapse: float = _total("death")
	if since < collapse:
		velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
		_show("death", _frame_at("death", since))
		return
	if not aloft:
		# Up off the deck under its own power. From here _integrate stops
		# applying gravity to it, which is the only reason it can leave.
		aloft = true
		deck_y = position.y
		velocity = Vector2(facing * 60.0, -80.0)
		_play("idle")      # anim_for makes that the flap
	velocity.x = move_toward(velocity.x, facing * DEPART_SPEED,
			DEPART_SPEED * 1.4 * delta)
	velocity.y = move_toward(velocity.y, DEPART_CLIMB,
			absf(DEPART_CLIMB) * 1.6 * delta)
	if since >= collapse + DEPART_TIME:
		visible = false

func _advance_block(delta: float) -> void:
	## Arms up, feet planted. He does not advance behind a guard: a walking block
	## would mean a blast could neither hurt him nor slow him, and then there is
	## no reason to throw one at all. The trade is that guarding costs him ground.
	velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
	# Still watching: he turns to meet the blast rather than guarding the wrong
	# way, which is the only thing a guard cannot survive.
	if is_instance_valid(target):
		var gap: float = target.global_position.x - global_position.x
		if absf(gap) > 0.5:
			facing = signf(gap)
	_show("guard", 0)
	if guard_hold <= 0.0:
		state = State.IDLE
		_play("idle")

func _advance_hurt(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 500.0 * delta)
	stagger -= delta
	clock += delta
	var holds := _durations("hurt")
	var t := 0.0
	var index := 0
	for i in holds.size():
		t += float(holds[i])
		index = i
		if clock < t:
			break
	if guard_broke > 0.0:
		# The pack draws the moment a guard gives way as its own frame. Worth
		# showing: the blow that breaks a guard and the blow that just hurts feel
		# very different to throw, and they should not look the same.
		_show("guard", 1)
	else:
		_show("hurt", mini(index, 1))  # first two frames only: recoil, not collapse
	if stagger <= 0.0:
		state = State.IDLE
		clock = 0.0

func _advance_punch(delta: float) -> void:
	# He plants his feet to swing — unless they are not on the ground, in which
	# case the swing rides the jump it was thrown from. Zeroing this in mid-air
	# would stop him dead over a gap and drop him into it.
	if grounded:
		velocity.x = 0.0
	clock += delta
	var spec := move_data(move)
	var anim := str(spec.get("anim", "punch"))
	var holds := _durations(anim)
	if holds.is_empty():
		state = State.IDLE
		return
	var t := 0.0
	var index := holds.size() - 1
	var done := true
	for i in holds.size():
		t += float(holds[i])
		if clock < t:
			index = i
			done = false
			break
	frame = index
	_show(anim, index)
	if index == int(spec.get("hit_frame", 0)):
		_try_to_land()
	if done:
		_recover()

## After a completed attack: back to neutral, then wait out the cooldown. A swing
## thrown in mid-air goes back to falling rather than to standing, so the rest of
## the leap still happens.
func _recover() -> void:
	clock = 0.0
	cooldown = attack_cooldown
	# A special buys its own, much longer, wait before the next one.
	if move != basic_move():
		special_ready = float(prof.get("special_cooldown", 0.0))
	move = basic_move()
	if flying():
		# Out of the strike and straight back to steering. The pass is spent
		# whether or not it connected — a dragon that kept diving after biting
		# would fly itself into the deck — so what follows is the climb out.
		swoop = -1.0
		swoop_ready = float(prof.get("swoop_cooldown", 2.0))
		state = State.IDLE
		return
	if not grounded:
		state = State.JUMP
		return
	state = State.IDLE
	velocity.x = 0.0
	_play("idle")

func _start_punch() -> void:
	_start_attack(basic_move())

## Begins any attack. The plain swing and the boss's two specials run the same
## state, clock and hit query — all that differs is which move is named.
func _start_attack(name: String) -> void:
	move = name
	state = State.PUNCH
	clock = 0.0
	frame = 0
	landed_this_punch = false
	# Same reason as _advance_punch: planting his feet is only possible if they
	# are on something. A swing thrown mid-leap keeps the leap.
	if grounded:
		velocity.x = 0.0
	_show(str(move_data(move).get("anim", "punch")), 0)

func _advance_chase(delta: float) -> void:
	if not is_instance_valid(target):
		velocity.x = 0.0
		_play("idle")
		return
	var gap: float = target.global_position.x - global_position.x
	# Positive when the player is ABOVE him, which is the direction that matters:
	# it is the one he answers with a jump.
	var rise: float = global_position.y - target.global_position.y
	var reachable: bool = absf(rise) < 60.0
	if absf(gap) > 0.5:
		facing = signf(gap)

	# The flyer, which is two enemies sharing a body. In the air, mid take-off
	# and mid landing it has its own everything and handles the frame itself.
	# On its feet it returns false and falls straight through to the bruiser
	# code below — walk in, claw, breathe — which is the whole point of the
	# split: the dragon's ground half is not new movement, it is the movement
	# every other enemy in the game already uses.
	if style == "flyer" and _flyer_phase(delta, gap, rise):
		return

	# Airborne — a knock carried him off the floor — so let his momentum carry
	# rather than steering him in mid-air. He wears the jump pose while it lasts;
	# he is in the air, however he got there.
	if not grounded:
		_show("jump", 0 if velocity.y < 0.0 else 1)
		return

	# The archer fights at range; his whole approach is different.
	if style == "archer":
		_advance_archer(delta, gap, reachable)
		return

	# A kind with specials picks one by distance first, so being in melee range
	# does not always mean the same blow. Only once the fight is on: a special is
	# a beat of a fight, not an opener thrown at someone walking past. Kinds with
	# no `moves` get "" here and fall straight through to the swing.
	if engaged and reachable and cooldown <= 0.0 and special_ready <= 0.0:
		var special := special_for(absf(gap))
		if special != "":
			_start_attack(special)
			return

	# In range and off cooldown: strike.
	if reachable and absf(gap) <= attack_range() and cooldown <= 0.0:
		_start_punch()
		return

	# The charger commits a dash to close the last stretch from mid-range.
	if reachable and cooldown <= 0.0 and style == "charger" \
			and absf(gap) > attack_range() \
			and absf(gap) <= float(prof.get("charge_range", 200.0)) \
			and _floor_ahead(24.0):
		_start_charge()
		return

	if absf(gap) <= aggro:
		engaged = true

	# Over whatever is in the way: a gap, a step up, or a player who has taken to
	# the air. Ahead of the walk, because every one of those is a case where
	# walking is the wrong answer — and ahead of the `reachable` test, because a
	# player one ledge up is exactly who this is for.
	if engaged and _maybe_jump(gap, rise):
		return

	# Otherwise walk him in, or hold at idle out of range. `engaged` rather than
	# the aggro range: once the fight is on he keeps coming, however far the
	# player backs off — and `_following` rather than `reachable`, so a ledge
	# between them is something he walks up to and jumps, not something that
	# makes him forget the fight.
	if engaged and _following(rise) and absf(gap) > attack_range() * 0.8 \
			and _can_step(signf(gap)):
		state = State.WALK
		velocity.x = signf(gap) * speed
		_play("walk")
		return
	state = State.IDLE
	velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
	_play("idle")

# --- the flyer ---------------------------------------------------------------

func _flyer_phase(delta: float, gap: float, rise: float) -> bool:
	## Runs the flyer's own frames and says whether it did. False means it is
	## simply standing on the deck fighting, and _advance_chase plays that out
	## as an ordinary bruiser.
	if shift >= 0.0:
		_advance_shift(delta)
		return true
	if aloft:
		air_left = maxf(0.0, air_left - delta)
		_advance_flyer(delta)
		return true

	# On its feet. Three cases: it has not noticed the player, it is about to
	# launch, or it is fighting and the chase below should have the frame.
	if not engaged or not grounded:
		return false
	ground_left = maxf(0.0, ground_left - delta)
	if ground_left <= 0.0 and not _attacking() and state != State.HURT:
		_begin_shift(true)
		return true
	return false

func shift_frame() -> int:
	## Which frame of the take-off or the landing is on screen, or -1 when it is
	## doing neither. Public because a capture wants to catch the roar, which is
	## three specific frames of a clip nothing else in the game watches.
	if shift < 0.0:
		return -1
	return _frame_at("takeoff" if shift_up else "land", shift)

func _begin_shift(up: bool) -> void:
	## Commit to a take-off or a landing. Neither can be interrupted: they are
	## the two moments the dragon is neither one thing nor the other, and a
	## half-finished one would leave it flying with its feet on the ground.
	shift = 0.0
	shift_up = up
	clock = 0.0
	velocity.x = 0.0
	landed_this_punch = false
	state = State.IDLE
	_show("takeoff" if up else "land", 0)

func _advance_shift(delta: float) -> void:
	var key := "takeoff" if shift_up else "land"
	var run := _total(key)
	shift += delta
	_show(key, _frame_at(key, shift))
	var through: float = shift / maxf(run, 0.001)
	if shift_up:
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
		if not aloft and through >= LIFT_AT:
			# Feet off. From here it is a flyer: no gravity, no floor, and the
			# altitudes below are all measured from the height it left.
			aloft = true
			deck_y = position.y
			air_left = float(prof.get("air_time", 9.0))
			swoop = -1.0
			# A beat of climbing before the first pass, so the launch is a
			# thing the player watches rather than the opening of a dive.
			swoop_ready = float(prof.get("swoop_cooldown", 2.0))
			move = basic_move()
		if aloft:
			velocity.y = -CLIMB_SPEED
	else:
		# Coming down on the spot rather than drifting: it picked this patch of
		# ground when it started the landing, and the pass is long over.
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
		if aloft:
			velocity.y = clampf((deck_y - position.y) * CLIMB_GAIN,
					-CLIMB_SPEED, CLIMB_SPEED)
			if through >= TOUCH_AT:
				aloft = false
				move = basic_move()
	if shift >= run:
		shift = -1.0
		if shift_up:
			aloft = true
			state = State.WALK
			_play("walk")
		else:
			aloft = false
			ground_left = float(prof.get("ground_time", 7.0))
			state = State.IDLE
			velocity = Vector2.ZERO
			_play("idle")

func _advance_flyer(delta: float) -> void:
	## The air half: hold height out of reach, come down for a pass, climb out,
	## and come down properly when the phase runs out. The player's half is the
	## same question — take the height, or wait for the dragon to bring some.
	var gap: float = target.global_position.x - global_position.x
	var agap: float = absf(gap)
	if agap <= aggro:
		engaged = true
	# Where he is STANDING, remembered. See mark_y: a pass dives at his floor,
	# not at him, and a player in mid-air simply has not moved the mark yet.
	if mark_y == 0.0 or not target.has_method("is_on_floor") or target.is_on_floor():
		mark_y = target.global_position.y

	# Time to come down. Only out of a settled cruise and only over something
	# to land on: a dragon that began a landing mid-pass would drop out of its
	# own dive, and one that began it over the gap would land in the sea.
	if air_left <= 0.0 and swoop < 0.0 and dodge <= 0.0 and not _attacking() 			and _surface_at(position.x, position.y, position.y + 600.0) != INF:
		_begin_shift(false)
		return

	if dodge > 0.0:
		dodge = maxf(0.0, dodge - delta)
	if swoop >= 0.0:
		swoop -= delta
		# Past him: the pass is over the moment it is. What it threw on the way
		# in carries it the rest of the way through — see _advance_punch, which
		# leaves an airborne body's velocity alone — and what follows is the
		# climb. Also the bound on how far it overruns, which is the only thing
		# that would carry it off the end of the level.
		if swoop <= 0.0 or (agap > 0.5 and signf(gap) != swoop_dir):
			swoop = -1.0
			swoop_ready = float(prof.get("swoop_cooldown", 2.0))
	elif swoop_ready > 0.0:
		swoop_ready = maxf(0.0, swoop_ready - delta)
	elif engaged and dodge <= 0.0 and agap <= aggro and agap >= STANDOFF_NEAR \
			and not _lining_up(agap):
		# Committed here rather than re-chosen every frame, so it flies its
		# line through and past instead of turning round on the overshoot. The
		# lower bound is the run-in: see STANDOFF_NEAR. Too close and it waits,
		# which is what the circling between passes is for.
		swoop = SWOOP_TIME
		swoop_dir = signf(gap) if agap > 0.5 else facing

	# It looks where it is going, which through a pass is the line it picked.
	if swoop >= 0.0:
		facing = swoop_dir
	elif agap > 0.5:
		facing = signf(gap)

	# Altitude, and the four heights it has. Cruising it sits above anything
	# the player can reach from the floor; swooping it comes down onto him
	# wherever he is standing, ledge included; lining up a breath it drops to
	# that same line but holds its distance; reading a blast it goes over the
	# top of one.
	var breathing: bool = _lining_up(agap)
	var want_y: float = deck_y - float(prof.get("cruise", 150.0))
	if dodge > 0.0:
		want_y -= DODGE_LIFT
	elif swoop >= 0.0 or breathing:
		want_y = mark_y - STRIKE_HEIGHT
	var off_line: float = absf(want_y - position.y)
	velocity.y = clampf((want_y - position.y) * CLIMB_GAIN, -CLIMB_SPEED, CLIMB_SPEED)

	# Closing. A pass is flat out along its committed line; between them it
	# holds a standoff, drifting in when the player backs away and out when he
	# closes, so it circles rather than hanging over his head.
	var want_x: float = 0.0
	if swoop >= 0.0:
		# Down first, then flat out. A pass that opened the throttle at the top
		# would be on the player before it had finished descending and would
		# bite at him from over his head, which is what it did: it swung from
		# 78 px up and connected once in three. Throttle scaled by how far it
		# still is off the line it is diving onto, so the dive IS a dive.
		var settled: float = clampf(1.0 - off_line / SWOOP_SETTLE, 0.0, 1.0)
		want_x = swoop_dir * float(prof.get("dive", 300.0)) \
				* (SWOOP_NOSE_DOWN + (1.0 - SWOOP_NOSE_DOWN) * settled)
	elif breathing:
		pass                  # holds the range it picked the breath at
	elif agap > STANDOFF_FAR:
		want_x = signf(gap) * speed
	elif agap < STANDOFF_NEAR:
		want_x = -signf(gap) * speed
	velocity.x = move_toward(velocity.x, want_x, 900.0 * delta)

	# The strike is the ordinary punch — same state, same box, same armour. All
	# the pass does is bring it into reach.
	#
	# Thrown early by exactly its own wind-up, because at 320 px/s a swing
	# opened at arm's length lands a body length behind the player: hit_lead is
	# the seconds from the first frame of the move to the frame the blow is
	# live on, read off the sheet, so retiming the animation cannot desync the
	# swoop from it.
	# It also does not bite until it has finished coming down. Without that
	# gate the pass and the swing overlap and it swings on the way in, from
	# whatever height it happened to have reached — which is how it ended up
	# flapping at the player from 78 px over his head and connecting once in
	# three.
	#
	# `rise` is where the player actually is rather than where he was standing,
	# and it is the only place those two differ on purpose: a jump apexes at
	# 107 against a pass 16 off the floor, which puts him outside this band.
	# Going over the top of a swoop is a real dodge, and coming down out of it
	# is the cleanest strike the player has.
	# Down on his level and still in the band: breathe. It does not need to be
	# close, which is the point of it, and the counter is to get INSIDE the
	# band — the same counter the Dragon Lord's breath has.
	if breathing and off_line < STRIKE_SETTLED:
		velocity.y = 0.0
		_start_attack(special_for(agap))
		return

	var rise: float = absf(target.global_position.y - global_position.y)
	var lead: float = hit_lead(basic_move()) * absf(velocity.x)
	if cooldown <= 0.0 and rise < 80.0 and off_line < STRIKE_SETTLED \
			and agap <= attack_range() + lead:
		# Levelled out first. From here the strike is committed, and one thrown
		# while still descending would carry it into the deck.
		velocity.y = 0.0
		_start_punch()
		return

	if absf(velocity.x) > 20.0:
		state = State.WALK
		_play("walk")
	else:
		state = State.IDLE
		_play("idle")

func _lining_up(agap: float) -> bool:
	## Is it setting up the flying breath?
	##
	## A flyer never reaches the special pick in _advance_chase while it is up
	## — that code is for things that walk — so the one attack drawn for the
	## air has to be chosen here, or it would be a clip cut off the sheet and
	## never once thrown.
	##
	## Unlike a pass, this one holds its range: it drops to the player's own
	## level at a distance and hoses along the deck. Lining one up costs it the
	## pass it would otherwise have made, so the two never overlap.
	if not (aloft and engaged and swoop < 0.0 and dodge <= 0.0):
		return false
	return cooldown <= 0.0 and special_ready <= 0.0 and special_for(agap) != ""

# --- the jump ----------------------------------------------------------------

func jump_apex() -> float:
	## How high his own jump gets him, straight off the constants: v^2 / 2g.
	return JUMP_VELOCITY * JUMP_VELOCITY / (2.0 * GRAVITY)

func air_time() -> float:
	## How long he is off the ground for a jump that lands where it started.
	return -2.0 * JUMP_VELOCITY / GRAVITY

func _launch_for(dist: float, rise: float) -> float:
	## The horizontal speed that lands him `dist` away on ground `rise` px above
	## his feet — negative rise for a drop. The descending root of the same
	## envelope scripts/check_levels.py measures the player's jumps with, so an
	## enemy's reach and a player's are computed by one piece of arithmetic.
	##
	## -1 if his jump cannot rise that far at all.
	var u := -JUMP_VELOCITY
	var under := u * u - 2.0 * GRAVITY * rise
	if under < 0.0:
		return -1.0
	return dist * GRAVITY / (u + sqrt(under))

func _surface_at(x: float, top: float, bottom: float) -> float:
	## The highest solid surface in that column between two heights, or INF.
	var query := PhysicsRayQueryParameters2D.create(
		Vector2(x, top), Vector2(x, bottom), WORLD)
	query.collide_with_areas = false
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return INF if hit.is_empty() else float(hit.position.y)

func _following(rise: float) -> bool:
	## Is the player close enough in HEIGHT to be worth walking toward? One jump
	## above him, or a drop he would be willing to take. Beyond that there is no
	## route and he holds his ground — which is what keeps a deck enemy from
	## shuffling under a hunter's perch for ever.
	return rise <= jump_apex() + 40.0 and rise >= -DROP_LIMIT

func _can_step(dir: float) -> bool:
	## Is walking that way safe? Floor a stride ahead, or a drop short enough to
	## take on purpose. He will not walk into a pit: falling in was how an enemy
	## used to open his own section's gate for free, and one who strolls off a
	## cliff mid-chase reads as broken rather than as reckless.
	if _floor_ahead(EDGE_PROBE, dir):
		return true
	return _surface_at(position.x + dir * EDGE_PROBE,
			position.y + 4.0, position.y + DROP_LIMIT) != INF

func _landing_ahead(dir: float) -> float:
	## The horizontal speed that would put him on the nearest ledge he can reach
	## that way, or -1 if there is nowhere to land. Searched outward, so the near
	## side of a gap wins over anything beyond it, and aimed a little PAST each
	## lip so a jump that comes up short still lands on top of it.
	var apex := jump_apex()
	var limit := leap_speed * air_time()
	var d := EDGE_PROBE
	# Whether the search has passed over open air yet. Without this the very
	# first probe can come back with the top of the lip he is already standing
	# on — a "landing" 20 px away and level with his feet, which he would take,
	# and which puts him in the hole. A landing has to be somewhere else: over
	# the void, or higher up.
	var void_seen := false
	while d <= limit:
		var surface := _surface_at(position.x + dir * d,
				position.y - apex - 8.0, position.y + DROP_LIMIT)
		if surface == INF:
			void_seen = true
		else:
			var rise := position.y - surface     # + = the ledge is above him
			if (void_seen or rise > 8.0) and rise <= apex - 8.0:
				var want := _launch_for(d + LANDING_INSET, rise)
				if want > 0.0 and want <= leap_speed:
					return want
		d += LANDING_STEP
	return -1.0

func _maybe_jump(gap: float, rise: float) -> bool:
	## Decide and commit a jump. True if he left the ground.
	if not grounded or hop_cooldown > 0.0:
		return false
	var dir := signf(gap)
	if dir == 0.0:
		dir = facing

	# Going up after him. The player who jumps clean over an enemy's head, or
	# stands on the step above him and swings down, used to be untouchable: every
	# attack in this game is thrown flat, so anything higher than the 60 px
	# `reachable` band was safe ground. Now it is answered.
	#
	# Melee only. An archer who leaps at you has abandoned the one thing he is
	# for, and his answer to height is to back up and shoot.
	#
	# The floor check is what stops this being a way to farm him: a player
	# hanging in the air over a chasm is bait, and an enemy who takes it throws
	# himself into the pit and opens his own section's gate.
	if style != "archer" and rise > 40.0 and rise <= jump_apex() \
			and absf(gap) <= leap_speed * air_time() * 0.7 and cooldown <= 0.0 \
			and _surface_at(position.x + gap, position.y - jump_apex() - 8.0,
					position.y + DROP_LIMIT) != INF:
		_start_jump(clampf(gap / air_time(), -leap_speed, leap_speed), HOP_RECOVER)
		return true

	# The ground ahead has run out. A gap and a step up read the same to a floor
	# probe — both are "nothing to walk onto" — and the answer to both is the
	# same, so this does not care which it is.
	#
	# A shut section gate reads that way too: its wall is 2400 px tall, so a
	# probe standing inside it reports nothing and he hops over. Harmless — he
	# never collided with that wall in the first place, it is a barrier for the
	# player's camera and feet only — but it is why an enemy at a gate line may
	# be seen jumping at nothing.
	if _floor_ahead(EDGE_PROBE, dir):
		return false
	var want := _landing_ahead(dir)
	if want < 0.0:
		return false
	_start_jump(dir * want, STEP_RECOVER)
	return true

func _start_jump(vx: float, recover: float) -> void:
	state = State.JUMP
	clock = 0.0
	velocity = Vector2(vx, JUMP_VELOCITY)
	grounded = false
	hop_cooldown = recover
	landed_this_punch = false
	if absf(vx) > 1.0:
		facing = signf(vx)
	_show("jump", 0)

func _advance_jump(delta: float) -> void:
	## Committed, exactly like the charge: no steering in the air. What he leaves
	## the ground with is what he lands with, so a jump is a decision he can be
	## made to regret rather than a homing missile.
	clock += delta
	_show("jump", 0 if velocity.y < 0.0 else 1)
	# A swing thrown out of the jump. Nothing special about it — the same fists
	# and the same hit box, which rides the sprite and is therefore high when he
	# is high. That is the whole point of going up after someone.
	if is_instance_valid(target) and cooldown <= 0.0 and style != "archer":
		var gap: float = target.global_position.x - global_position.x
		var rise: float = global_position.y - target.global_position.y
		if absf(gap) <= attack_range() and absf(rise) < 60.0:
			_start_punch()
			return
	if grounded:
		state = State.IDLE
		velocity.x = 0.0
		# Flat-footed for a moment on landing: the counter to an enemy who
		# follows you into the air is to be somewhere else when he comes down.
		cooldown = maxf(cooldown, LAND_RECOVER)
		_play("idle")

# --- the charger's dash ------------------------------------------------------

func _start_charge() -> void:
	## Commit to a dash at the player. Fast, but side-steppable: standing still in
	## front of it is what gets punished.
	state = State.CHARGE
	clock = 0.0
	velocity.x = facing * float(prof.get("charge_speed", 200.0))
	_play("walk")

func _advance_charge(delta: float) -> void:
	if not is_instance_valid(target):
		_recover()
		return
	clock += delta
	velocity.x = facing * float(prof.get("charge_speed", 200.0))
	_play("walk")
	var gap: float = target.global_position.x - global_position.x
	var reachable: bool = absf(target.global_position.y - global_position.y) < 60.0
	if reachable and absf(gap) <= attack_range():
		_start_punch()
		return
	# He pulls up if he overruns the player, runs out of floor, or the dash has
	# run its length — the whiff leaves him briefly open, which is its counter.
	if signf(gap) != facing or not _floor_ahead(20.0) or clock >= CHARGE_TIME:
		state = State.IDLE
		velocity.x = 0.0
		cooldown = maxf(cooldown, CHARGE_RECOVER)

# --- the archer --------------------------------------------------------------

func _advance_archer(delta: float, gap: float, level: bool) -> void:
	var agap := absf(gap)
	# He has not noticed the player yet, so he stands where the level put him.
	#
	# This gate was missing, and its absence was not subtle: "too far to shoot"
	# below means walk in, and it had no upper bound, so every archer in the level
	# set off toward the player the instant it loaded. The first hunter was 1920
	# away at spawn and arrived while the player was still on the opening ledge.
	# The melee styles were always gated this way — see the aggro test at the foot
	# of _advance_chase — and the archer simply never got the same check.
	#
	# Same as those: it only holds him until the fight starts. After that he
	# closes the gap like anyone else, because an archer who lets you stroll out
	# of his range and then forgets you is not a fight.
	if agap <= aggro:
		engaged = true
	if not engaged:
		state = State.IDLE
		velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
		_play("idle")
		return
	# Someone closed to melee range: put his fists up. An archer up close is in
	# trouble, and the jab is his only answer there.
	if agap <= attack_range() and cooldown <= 0.0:
		_start_punch()
		return
	# Level with him, in range, and reloaded: draw the bow and loose.
	if cooldown <= 0.0 and level and agap > attack_range() \
			and agap <= float(prof.get("fire_range", 430.0)):
		_start_shoot()
		return
	# Nothing to shoot and ground in the way: he jumps it like anyone else.
	# _maybe_jump gives him the platforming half only — see the style gate on the
	# leap there — so he crosses a gap to reach his firing line and never hops at
	# the player.
	if _maybe_jump(gap, global_position.y - target.global_position.y):
		return

	# Otherwise hold the gap: close in if too far, kite backwards if too near, but
	# only onto floor — he will not back off a ledge to keep his distance.
	var want := 0.0
	if agap > float(prof.get("fire_range", 430.0)):
		want = signf(gap)
	elif agap < float(prof.get("fire_min", 150.0)):
		want = -signf(gap)
	if want != 0.0 and _floor_ahead(24.0, want):
		state = State.WALK
		velocity.x = want * speed
		_play("walk")
		return
	state = State.IDLE
	velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
	_play("idle")

func _start_shoot() -> void:
	state = State.SHOOT
	clock = 0.0
	fired = false
	velocity.x = 0.0
	_show("shoot", 0)

func _advance_shoot(delta: float) -> void:
	velocity.x = 0.0
	clock += delta
	# He tracks the player through the draw, so the arrow leaves pointed at him.
	if is_instance_valid(target) and absf(target.global_position.x - global_position.x) > 0.5:
		facing = signf(target.global_position.x - global_position.x)
	var holds := _durations("shoot")
	if holds.is_empty():
		state = State.IDLE
		return
	var t := 0.0
	var index := holds.size() - 1
	var done := true
	for i in holds.size():
		t += float(holds[i])
		if clock < t:
			index = i
			done = false
			break
	_show("shoot", index)
	# The arrow leaves on the release frame — the last one — exactly once.
	if index == holds.size() - 1 and not fired:
		fired = true
		var at := global_position + Vector2(facing * 22.0, -34.0)
		fired_arrow.emit(at, facing, int(prof.get("arrow_damage", 12)))
	if done:
		state = State.IDLE
		clock = 0.0
		cooldown = float(prof.get("shoot_cooldown", attack_cooldown))
		_play("idle")

func _floor_ahead(dist: float, dir: float = 0.0) -> bool:
	## Is there ground a short way off in the given direction (his facing by
	## default)? Keeps a charge from diving off a ledge, and the archer from kiting
	## backwards off one.
	var d := dir if dir != 0.0 else facing
	var x := position.x + d * dist
	var query := PhysicsRayQueryParameters2D.create(
		Vector2(x, position.y - 8.0), Vector2(x, position.y + 40.0), WORLD)
	query.collide_with_areas = false
	return not get_world_2d().direct_space_state.intersect_ray(query).is_empty()
