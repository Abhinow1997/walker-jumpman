extends "res://features/combat/prop.gd"
## A breakable crate. Everything it does — being knocked into the air, tumbling,
## landing, skidding, settling, shattering — is prop.gd; this is the numbers and
## the art it does it with.
##
## The crate at rest is LF2's own box, and the tumble is the six angles LF2 drew
## for a box in the air, ordered so they roll continuously. It shatters into
## LF2's plank debris, four fragment sizes in the crate's palette with four
## drawn rotations each. No part of it is invented art.

func _configure() -> void:
	max_health = 40  # two jabs, or any heavier blow plus a jab
	# Matched to the drawn crate, kept just inside it so a punch that visibly
	# grazes the edge does not miss. Scaled with the art (x0.75) from 52 x 48.
	body = Vector2(39, 36)
	# Two-handed: hoisted overhead, and all he can do with it is throw it.
	heavy = true
	throw_damage = 45  # more than a jab, less than a flying kick
	art_rest = "crate"
	art_spin = "crate_spin"
	art_debris = "crate_debris"
	# Nine pieces, weighted toward the smaller fragments.
	debris_types = [0, 1, 1, 2, 2, 3, 3, 3, 3]
