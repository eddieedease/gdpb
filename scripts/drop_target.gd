extends StaticBody2D
## A drop target: knocked down (hidden + non-colliding) when hit, awarding
## points. A bank of them is reset together by the table controller.

signal hit(target)

@export var points := 500

var is_down := false

@onready var _collision: CollisionShape2D = $CollisionShape2D
@onready var _visual: CanvasItem = get_node_or_null("Visual")


func on_ball_hit(_ball: RigidBody2D) -> void:
	if is_down:
		return
	is_down = true
	_collision.set_deferred("disabled", true)
	if _visual:
		_visual.visible = false
	GameManager.add_score(points)
	hit.emit(self)


func reset_target() -> void:
	is_down = false
	_collision.set_deferred("disabled", false)
	if _visual:
		_visual.visible = true
