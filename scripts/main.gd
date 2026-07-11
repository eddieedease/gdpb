extends Node2D

const BALL_SCENE := preload("res://scenes/ball.tscn")
const BALL_SPAWN := Vector2(660, 1600)


func _ready() -> void:
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	win.content_scale_size = Vector2i(720, 800)
	GameManager.reset()
	_spawn_ball()


func _spawn_ball() -> void:
	var ball: RigidBody2D = BALL_SCENE.instantiate()
	ball.position = BALL_SPAWN
	add_child(ball)


func _on_drain_body_entered(body: Node) -> void:
	if not body.is_in_group("ball"):
		return
	body.queue_free()
	GameManager.lose_ball()
	if not GameManager.is_game_over:
		await get_tree().create_timer(1.0).timeout
		_spawn_ball()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/table_select.tscn")
	elif event.is_action_pressed("restart") and GameManager.is_game_over:
		GameManager.reset()
		_spawn_ball()
