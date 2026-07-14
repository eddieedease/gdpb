extends StaticBody2D
## A drop target: knocked down (hidden + non-colliding) when hit, awarding
## points. A bank of them is reset together by the table controller.
## Self-heals: if its CollisionShape2D / Visual children are missing (e.g. they
## got deleted while editing), it rebuilds defaults so it never errors.

signal hit(target)

@export var points := 500
@export var target_size := Vector2(64, 34)

var is_down := false
var _collision: CollisionShape2D
var _visual: CanvasItem


func _ready() -> void:
	_collision = get_node_or_null("CollisionShape2D")
	if _collision == null:
		_collision = CollisionShape2D.new()
		_collision.name = "CollisionShape2D"
		var shape := RectangleShape2D.new()
		shape.size = target_size
		_collision.shape = shape
		add_child(_collision)
	_visual = get_node_or_null("Visual")
	if _visual == null:
		var poly := Polygon2D.new()
		poly.name = "Visual"
		poly.color = Color(1, 0.55, 0.25)
		var hx := target_size.x * 0.5
		var hy := target_size.y * 0.5
		poly.polygon = PackedVector2Array([Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)])
		add_child(poly)
		_visual = poly


func on_ball_hit(_ball: RigidBody2D) -> void:
	if is_down:
		return
	is_down = true
	_collision.set_deferred("disabled", true)
	if _visual:
		_visual.visible = false
	GameManager.add_score(points)
	GameManager.impact.emit(6.0)
	SoundManager.play("target")
	hit.emit(self)


func reset_target() -> void:
	is_down = false
	_collision.set_deferred("disabled", false)
	if _visual:
		_visual.visible = true
