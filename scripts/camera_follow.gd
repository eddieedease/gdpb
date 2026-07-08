extends Camera2D
## Follows the ball vertically; the Camera2D limits keep the view on the table.

## Higher = more zoomed in (table appears larger/wider on screen). 1.0 = fit
## the full 720-wide table across the viewport.
@export var zoom_level := 1.2


func _ready() -> void:
	zoom = Vector2(zoom_level, zoom_level)


func _process(_delta: float) -> void:
	var balls := get_tree().get_nodes_in_group("ball")
	if not balls.is_empty():
		position.y = balls[0].global_position.y
