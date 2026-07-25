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
	_set_visual_shown(false)
	GameManager.add_score(points, global_position)
	GameManager.impact.emit(6.0)
	# Its own mechanical clack, not the generic target ping - a drop target
	# physically falling through the playfield should sound like it.
	SoundManager.play("drop", randf_range(0.94, 1.08))
	hit.emit(self)


func reset_target() -> void:
	is_down = false
	_collision.set_deferred("disabled", false)
	_set_visual_shown(true)


## The 3D view replaces this flat art with a real standing plate and hides it.
## When it has, leave it alone: turning it back on at reset put the flat
## rectangle back on the tier plane UNDERNEATH the 3D plate, and the two
## together read as a solid block instead of a target.
func _set_visual_shown(shown: bool) -> void:
	if _visual and not get_meta("visual_owned_by_3d", false):
		_visual.visible = shown
