extends AnimatableBody2D

@export var input_action := "flipper_left"
@export var rest_angle_deg := 25.0
@export var active_angle_deg := -30.0
@export var rotate_speed := 20.0  # radians per second


func _ready() -> void:
	rotation = deg_to_rad(rest_angle_deg)


func _physics_process(delta: float) -> void:
	var pressed := Input.is_action_pressed(input_action)
	var target := deg_to_rad(active_angle_deg if pressed else rest_angle_deg)
	rotation = move_toward(rotation, target, rotate_speed * delta)
