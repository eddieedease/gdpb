extends AnimatableBody2D
## Spring plunger at the bottom of the shooter lane.
## The ball rests on the collision plate at the top of the spring.
## Hold "launch" to compress, release to fire the ball up the lane.

@export var floor_y := 1956.0
@export var rest_height := 146.0
@export var charged_height := 50.0
@export var charge_time := 1.1
@export var min_speed := 1200.0
@export var max_speed := 2600.0

@onready var spring: Sprite2D = $Spring

var _charge := 0.0
var _charging := false


func _physics_process(delta: float) -> void:
	var ball := _find_ball_in_lane()
	if ball != null and Input.is_action_pressed("launch"):
		_charging = true
		_charge = minf(_charge + delta / charge_time, 1.0)
	elif _charging:
		if ball != null:
			var speed := min_speed + _charge * (max_speed - min_speed)
			ball.linear_velocity = Vector2(0.0, -speed)
			SoundManager.play("launch", lerpf(0.9, 1.2, _charge))
		_charging = false
		_charge = 0.0

	var height := lerpf(rest_height, charged_height, _charge)
	position.y = floor_y - height
	spring.scale.y = (height + 45.0) / 450.0


func _find_ball_in_lane() -> RigidBody2D:
	for ball in get_tree().get_nodes_in_group("ball"):
		if ball.global_position.x > 630.0 and ball.global_position.y > 1450.0:
			return ball
	return null
