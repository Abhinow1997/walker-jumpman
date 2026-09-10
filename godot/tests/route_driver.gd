extends RefCounted
## Fixed input route through the real level. No position/velocity edits.
var jump_marks: Array[float] = [138.0, 292.0, 424.0, 548.0, 712.0]
var next_jump: int = 0

func step(player: CharacterBody2D) -> void:
	player.test_control = true
	player.test_axis = 1.0
	player.test_jump_held = false
	if next_jump < jump_marks.size() and player.position.x >= jump_marks[next_jump] and player.is_on_floor():
		player.test_jump_pressed = true
		next_jump += 1
