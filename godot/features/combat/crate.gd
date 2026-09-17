extends "res://features/combat/prop.gd"
## The breakable prop: a boulder with a glowing seam down its cracks. Everything
## it does — being knocked into the air, tumbling, landing, skidding, settling,
## shattering — is prop.gd; this is the numbers and the art it does it with.
##
## Still called the crate, and the levels still place it with a `crates` entry,
## because that is the slot rather than the drawing: it is the one thing in a
## level you can punch, lift and throw. It was LF2's wooden box until the rock
## sheet arrived; renaming the slot would have touched two hundred references
## across the level files, the validator and the tests to change nothing about
## what it does.
##
## Three things about the rock that the box did not need:
##
##   * Its resting art is six frames of the same boulder with the light in its
##     cracks brightening and dimming, so it breathes where it stands rather
##     than sitting there as a still image.
##   * The sheet draws no tumble angles for it, so it turns by rotating its own
##     sprite — see spins_sprite. A boulder is round enough for that to read;
##     the box had six drawn angles and must not be rotated on top of them.
##   * It has a drawn shatter, five frames of it coming apart where it stands,
##     which plays before the pieces are thrown. The box had no such art and
##     went straight to flying planks.

func _configure() -> void:
	max_health = 40  # two jabs, or any heavier blow plus a jab
	# The rock is drawn 36 x 48 in texture pixels, which is 27 x 36 in the world
	# at the manifest's 0.75. Narrower than the old crate's box because the
	# boulder is narrower than the box was, and two pixels TALLER than it is
	# drawn on purpose: the blast leaves the player's hand at y -34.5, so a box
	# ending at -34 is one the blast sails over. It broke the blast test before
	# it broke anything a player would have noticed.
	body = Vector2(26, 38)
	# Two-handed: hoisted overhead, and all he can do with it is throw it.
	heavy = true
	throw_damage = 45  # more than a jab, less than a flying kick
	art_rest = "rock"
	# A slow breath: six frames at six a second is a second to the loop.
	rest_fps = 6.0
	# No drawn angles on the sheet, so the sprite itself turns.
	art_spin = ""
	spins_sprite = true
	art_break = "rock_break"
	break_step = 0.07  # five frames, so the drawn break runs about a third of a second
	art_debris = "rock_debris"
	# The sheet draws each piece once rather than in four rotations.
	debris_spins = 1
	# Nine pieces out of the eight drawn, weighted toward the small chips and
	# the dust: a break that is all big chunks reads as the rock splitting in
	# half rather than shattering.
	debris_types = [0, 1, 2, 3, 3, 5, 6, 7, 7]
