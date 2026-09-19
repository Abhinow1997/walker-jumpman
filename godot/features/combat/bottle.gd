extends "res://features/combat/prop.gd"
## A bottle of milk: LF2's own health item.
##
## The brown bottle in features/combat/brew.gd is this same class with different
## art and mana in it, so everything below is written in terms of "what it
## refills" rather than health — see `refills` and `refill_segments`.
##
## Two things at once. It is a pickup — stand near it, get prompted, drink, and
## the character plays LF2's weapon_drink frames with the bottle on his hand's
## weapon point. It is also a prop, so it can be knocked about and smashed like
## the crate, on exactly the same physics, with LF2's own glass debris.
##
## Smashing it destroys whatever it was worth. That is a real choice rather
## than an oversight: swinging at everything in the level has a cost.
##
## Drinking takes time, so a bottle has a third state between "on the floor" and
## "gone": lifted. It is off the ground and in his hand, but not yet spent.
##
## It also has contents, which is what makes stopping worth doing. Drinking
## drains it and a punch spills it, and both the wait and what it gives back
## are proportional to what is left, so a half-drunk bottle is a half-length top-up
## rather than a wasted one. An interrupted drink sets it back down; a drink
## broken by a hit knocks it out of his hand, and it falls and bounces on the
## same physics a punched bottle uses.
##
## It no longer keeps a reach area of its own. "Am I near enough" is the same
## question for a crate as for a bottle, so the session asks it once for every
## prop — see carryable_in_reach() — instead of the bottle answering privately.

## The drink frame it is tipped to his mouth with. Set in _configure() rather
## than fixed, because _init() runs _configure() before the session can say
## which bottle this is — which is why the brown one is a subclass and not a
## flag.
var art_drink := "bottle_drink"
## How far below the weapon point an upright bottle hangs: roughly its middle,
## since a hand closes around it there rather than under its base.
var upright_anchor := Vector2(0, 9.0)

## Which bar it fills, matching player.gd's REFILL_* constants, and how much of
## that bar one whole bottle is worth. Counted in bar segments rather than
## points, so "two bars" stays two bars whatever the maximum is. The session
## reads both rather than hard-coding them, so a weaker bottle is a spawn
## argument.
var refills := "health"
var refill_segments: int = 2
## How full it is, 0 to 1, in units of a whole bottle.
var contents: float = 1.0
## Tipped to his mouth. LF2 draws a separate sprite for this rather than
## rotating the upright one, and the pack ships it.
var drinking: bool = false
var drink_frame: Texture2D
## What a blow spills. Glass survives one hit and smashes on the second, so a
## cracked bottle is worth three quarters of a whole one.
const SPILL_PER_HIT := 0.25
var consumed: bool = false

func _configure() -> void:
	max_health = 20  # glass: anything breaks it in two hits
	# Taller than the 23 px it is drawn, deliberately. Every punch in the game
	# lands between y -55 and -25, measured from the feet; a hit box matching
	# the art would sit entirely underneath all of them and only the flying kick
	# and the blast could ever touch it. This lifts the box into reach without
	# changing where the bottle is drawn — see spin_lift below.
	body = Vector2(16, 27)
	spin_lift = 9.0
	# Light: carried in one hand, and drinking it is the point of carrying it.
	heavy = false
	throw_damage = 20
	carry_anchor = upright_anchor
	art_rest = "bottle"
	art_spin = "bottle_spin"
	art_debris = "bottle_debris"
	# Six pieces: two of the capped body, four of the small shards.
	debris_types = [0, 0, 1, 1, 1, 1]

func available() -> bool:
	return not consumed and not broken and contents > 0.001

## Seconds it would take to finish from here, for the prompt.
func drink_seconds(player: Node) -> float:
	return contents * float(player.FULL_DRINK_TIME)

func set_contents(value: float) -> void:
	## Set from the player while he drinks, so the level is always holding the
	## truth about how much is left rather than a figure settled up afterwards.
	## An empty bottle is a spent one.
	contents = clampf(value, 0.0, 1.0)
	if contents <= 0.001:
		consume()

## A struck bottle leaks, which is the other half of why a drink can be short.
func take_hit(damage: int, from: Vector2) -> bool:
	var landed: bool = super.take_hit(damage, from)
	if landed and not broken:
		contents = maxf(0.0, contents - SPILL_PER_HIT)
	return landed

func _on_ready() -> void:
	drink_frame = Items.frame(art_drink, 0)

func set_drinking(on: bool) -> void:
	drinking = on
	# The tipped sprite is drawn around its middle, so the weapon point is where
	# its centre goes; the upright one stands on its base and hangs from a hand.
	carry_anchor = Vector2.ZERO if on else upright_anchor
	_update_sprite()

func _update_sprite() -> void:
	super._update_sprite()
	if consumed and is_instance_valid(sprite):
		sprite.visible = false
		return
	if drinking and is_instance_valid(sprite) and drink_frame != null:
		sprite.texture = drink_frame
		sprite.offset = Items.pivot(art_drink)

## A bottle already drunk is not there to be hit. Being carried is handled by
## prop.gd, which refuses a hit on anything in his hands.
func _hittable() -> bool:
	return not consumed

## No _rest_offset override: a bottle stands on the floor. It used to bob two to
## four pixels off the ground to read as a pickup, which on a taller bottle just
## looked like it was hovering.

func reset() -> void:
	super.reset()
	consumed = false
	drinking = false
	carry_anchor = upright_anchor
	contents = 1.0

func consume() -> void:
	## Vanishes on the spot rather than fading away. The drink animation puts the
	## same bottle in his hand on the same frame, and a copy left fading on the
	## floor reads as a second bottle.
	if consumed:
		return
	consumed = true
	carried = false
	drinking = false
	if is_instance_valid(sprite):
		sprite.visible = false
	queue_redraw()

func _prop_process(_delta: float) -> void:
	if consumed or carried:
		if is_instance_valid(sprite):
			sprite.visible = false

## No _draw override: a bottle is its sprite and nothing else. It used to sit in
## a pulsing halo of three stacked circles, to make it findable at this size,
## but soft round gradients under crisp pixel art read as a smudge rather than a
## glow. prop.gd's own _draw still runs and still draws the debris.
