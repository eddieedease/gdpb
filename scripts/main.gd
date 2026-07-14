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


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("nudge_left"):
		_nudge(-1.0)
	if Input.is_action_just_pressed("nudge_right"):
		_nudge(1.0)


func _nudge(dir: float) -> void:
	for b in get_tree().get_nodes_in_group("ball"):
		if b is RigidBody2D:
			b.apply_central_impulse(Vector2(dir * 300.0, -90.0))
	var cam := get_node_or_null("Camera2D")
	if cam and cam.has_method("shake"):
		cam.shake(11.0)


func _on_drain_body_entered(body: Node) -> void:
	if not body.is_in_group("ball"):
		return
	body.queue_free()
	SoundManager.play("drain")
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
