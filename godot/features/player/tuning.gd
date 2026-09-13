extends Resource
## Values from GDD 0.2.0, rescaled x2 for the taller character. A shared resource
## for gameplay and fixtures.
##
## Positions, velocities and accelerations all scale by the same factor, which
## leaves timing untouched: apex time is still jump_velocity/gravity = 0.333 s.
## The forgiveness windows are measured in ticks, not pixels, so they do NOT scale.
@export var speed: float = 320.0
@export var acceleration: float = 2560.0
@export var deceleration: float = 3840.0
@export var jump_velocity: float = -640.0
@export var gravity: float = 1920.0
@export var terminal_velocity: float = 960.0
@export var coyote_ticks: int = 6
@export var buffer_ticks: int = 6
