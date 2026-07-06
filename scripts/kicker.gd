extends StaticBody2D
## Shared behaviour for anything the ball can hit for points:
## pop bumpers and slingshots (kick_speed > 0) and standup targets (kick_speed = 0).

@export var points := 100
@export var kick_speed := 0.0

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D")

var _base_scale := Vector2.ONE
var _base_modulate := Color.WHITE
var _tween: Tween


func _ready() -> void:
	if sprite:
		_base_scale = sprite.scale
		_base_modulate = sprite.modulate


func on_ball_hit(ball: RigidBody2D) -> void:
	if kick_speed > 0.0:
		var dir := (ball.global_position - global_position).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.UP
		ball.linear_velocity = dir * kick_speed
	GameManager.add_score(points)
	_flash()


func _flash() -> void:
	if sprite == null:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	sprite.scale = _base_scale * 1.15
	sprite.modulate = Color(1.5, 1.5, 1.5)
	_tween = create_tween()
	_tween.tween_property(sprite, "scale", _base_scale, 0.15)
	_tween.parallel().tween_property(sprite, "modulate", _base_modulate, 0.2)
