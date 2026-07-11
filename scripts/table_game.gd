extends Node2D
## Logic-only controller for an editable pinball table scene. It owns NO
## geometry - walls, bumpers, flippers etc. are real nodes in the .tscn that
## you can move in the editor. This script just runs the ball, launch, drain,
## scoring, drop-target bank and rollovers. It finds pieces by node name and
## by group ("drop_targets", "rollovers"), so add/remove pieces freely.

const BALL_SCENE := preload("res://scenes/ball.tscn")

@export var lane_min := Vector2(1040, 1950)   # ball is "in the shooter lane" past this
@export var launch_min_speed := 2700.0
@export var launch_max_speed := 3000.0
## Slight leftward tilt so the launched ball drifts into the playfield once it
## clears the inner lane wall, instead of falling straight back down the lane.
@export var launch_direction := Vector2(-0.1, -1.0)

@onready var _spawn: Node2D = $BallSpawn
@onready var _drain: Area2D = $Drain

var _drops: Array = []
var _drops_down := 0
var _resetting_bank := false
var _launch_charge := 0.0


func _ready() -> void:
	GameManager.reset()
	_drain.body_entered.connect(_on_drain_body_entered)

	_drops = get_tree().get_nodes_in_group("drop_targets")
	for d in _drops:
		if d.has_signal("hit"):
			d.hit.connect(_on_drop_hit)

	for r in get_tree().get_nodes_in_group("rollovers"):
		r.body_entered.connect(_on_rollover.bind(r))

	_spawn_ball()


func _spawn_ball() -> void:
	var ball: RigidBody2D = BALL_SCENE.instantiate()
	ball.position = _spawn.global_position
	ball.max_contacts_reported = 10
	add_child(ball)
	_launch_charge = 0.0


func _get_ball() -> RigidBody2D:
	var balls := get_tree().get_nodes_in_group("ball")
	return balls[0] if not balls.is_empty() else null


func _physics_process(delta: float) -> void:
	var ball := _get_ball()
	if ball == null:
		return
	var in_lane := ball.global_position.x > lane_min.x and ball.global_position.y > lane_min.y
	if in_lane and Input.is_action_pressed("launch"):
		_launch_charge = minf(_launch_charge + delta / 1.1, 1.0)
	elif in_lane and _launch_charge > 0.0:
		var sp := lerpf(launch_min_speed, launch_max_speed, _launch_charge)
		ball.linear_velocity = launch_direction.normalized() * sp
		_launch_charge = 0.0


func _on_drain_body_entered(body: Node) -> void:
	if not body.is_in_group("ball"):
		return
	body.queue_free()
	GameManager.lose_ball()
	if not GameManager.is_game_over:
		await get_tree().create_timer(0.9).timeout
		_spawn_ball()


func _on_rollover(body: Node, _area: Area2D) -> void:
	if body.is_in_group("ball"):
		GameManager.add_score(250)


func _on_drop_hit(_target) -> void:
	_drops_down += 1
	if _drops_down >= _drops.size() and not _resetting_bank:
		_resetting_bank = true
		GameManager.add_score(5000)
		await get_tree().create_timer(1.2).timeout
		for d in _drops:
			d.reset_target()
		_drops_down = 0
		_resetting_bank = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/table_select.tscn")
	elif event.is_action_pressed("restart") and GameManager.is_game_over:
		GameManager.reset()
		for d in _drops:
			d.reset_target()
		_drops_down = 0
		_resetting_bank = false
		_spawn_ball()
