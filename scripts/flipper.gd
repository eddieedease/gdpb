extends AnimatableBody2D

@export var input_action := "flipper_left"
@export var rest_angle_deg := 25.0
@export var active_angle_deg := -30.0
## How fast the flipper snaps, in rad/s - this IS the flipper strength. ~19
## sends a ball from the lower flippers up to the mid/upper playfield; 15 is
## weak, 22+ launches clean off the top. Time the flip so the blade is still
## swinging when the ball meets it - a held-up flipper just deflects softly.
@export var rotate_speed := 19.0

var _was_pressed := false


func _ready() -> void:
	rotation = deg_to_rad(rest_angle_deg)


func _physics_process(delta: float) -> void:
	var pressed := Input.is_action_pressed(input_action)
	if pressed and not _was_pressed:
		SoundManager.play("flipper")
	_was_pressed = pressed
	var target := deg_to_rad(active_angle_deg if pressed else rest_angle_deg)
	rotation = move_toward(rotation, target, rotate_speed * delta)
