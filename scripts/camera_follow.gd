extends Camera2D
## Follows the ball vertically; the Camera2D limits keep the view on the table.

## Higher = more zoomed in (table appears larger/wider on screen). 1.0 = fit
## the full 720-wide table across the viewport.
@export var zoom_level := 1.2

var _shake := 0.0


func _ready() -> void:
	zoom = Vector2(zoom_level, zoom_level)
	GameManager.impact.connect(shake)


## Kick the camera - used by nudges for feel.
func shake(amount: float) -> void:
	_shake = minf(_shake + amount, 26.0)


func _process(delta: float) -> void:
	var balls := get_tree().get_nodes_in_group("ball")
	if not balls.is_empty():
		position.y = balls[0].global_position.y
	if _shake > 0.1:
		offset = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
		_shake = move_toward(_shake, 0.0, 70.0 * delta)
	elif offset != Vector2.ZERO:
		offset = Vector2.ZERO
