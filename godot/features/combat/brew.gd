extends "res://features/combat/bottle.gd"
## The brown bottle: everything the milk bottle is, filled with mana.
##
## Same block of the LF2 items sheet, four rows down, drawn at the same scale
## with the same forty rotations — so it lifts, drinks, spills, tumbles and
## smashes on exactly the milk bottle's code. Only the art, the halo and the bar
## it pours into are different.
##
## It is a subclass rather than a flag on the bottle because prop.gd runs
## _configure() from _init(), which is before the session has had a chance to
## say which bottle it just made; the hit box and the art names have to be
## settled by then.

func _configure() -> void:
	super._configure()
	refills = "mana"
	# A hand taller than the milk bottle and no wider: 14 x 32 on the sheet
	# against the milk bottle's 15 x 25, both drawn at three-quarter size. The
	# box keeps the milk bottle's margin over the art for the same reason — see
	# the note on `body` there — and the spin centre follows the taller sprite,
	# or a knocked bottle would pivot around a point below its own middle.
	body = Vector2(16, 30)
	spin_lift = 12.0
	upright_anchor = Vector2(0, 12.0)
	carry_anchor = upright_anchor
	art_rest = "brew"
	art_spin = "brew_spin"
	art_debris = "brew_debris"
	art_drink = "brew_drink"
	# Amber, to read as the same light the mana bar is lit with rather than the
	# cream halo the milk bottle sits in.
	glow = Color("e8a838")
