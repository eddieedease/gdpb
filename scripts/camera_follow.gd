extends Camera2D
## Follows the ball vertically; the Camera2D limits keep the view on the table.


func _process(_delta: float) -> void:
	var balls := get_tree().get_nodes_in_group("ball")
	if not balls.is_empty():
		position.y = balls[0].global_position.y
