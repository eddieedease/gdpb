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
## Very slight leftward tilt; the top deflector does most of the work steering
## the ball into the playfield.
@export var launch_direction := Vector2(-0.04, -1.0)
## Sideways shove applied to the ball(s) by a nudge (Q/E or the sticks).
@export var nudge_impulse := 320.0

## One-way gate (scenes/gate.tscn) dropped at the mouth of the shooter lane:
## the ball passes up through it on launch, then can never fall back in. Tilt
## keeps a ball that lands on it rolling off into the playfield.
const GATE_SCENE := preload("res://scenes/gate.tscn")
@export var gate_position := Vector2(1115, 1895)
@export var gate_rotation := -0.12

@onready var _spawn: Node2D = $BallSpawn
@onready var _drain: Area2D = $Drain

## A set of drop targets that resets together once every one of them is down.
## The table has more than one: the main playfield bank, and the upper deck's
## own bank, which must reset independently (they are separate levels, so
## clearing one has nothing to do with the other).
class Bank:
	var targets: Array = []
	var down := 0
	var resetting := false
	var bonus := 5000

var _main_bank := Bank.new()
var _deck_bank := Bank.new()
## Rollover lights (scenes/rollover.tscn) expose the same hit / reset_target
## interface as drop targets, so they run on the same bank machinery.
var _light_bank := Bank.new()
var _launch_charge := 0.0

## Multiball is lit by clearing the DECK bank twice and the LOWER bank three
## times. Progress only accumulates while multiball is INACTIVE - clears made
## during multiball count for nothing - and both counters go back to zero when
## it ends, so each multiball has to be earned from scratch.
@export var multiball_deck_clears := 2
@export var multiball_main_clears := 3
## How many extra balls multiball puts into play.
@export var multiball_extra_balls := 2
## Where the extra balls are fed in from.
@export var multiball_feed_position := Vector2(640, 300)

var _deck_clears := 0
var _main_clears := 0
var _multiball := false


func _ready() -> void:
	# Widescreen, fill the whole width (the Classic table switches the window to
	# portrait, so every scene must claim its own view on entry).
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP_WIDTH
	win.content_scale_size = Vector2i(1280, 720)

	GameManager.reset()
	_build_gate()
	_drain.body_entered.connect(_on_drain_body_entered)

	_main_bank.targets = get_tree().get_nodes_in_group("drop_targets")
	_deck_bank.targets = get_tree().get_nodes_in_group("deck_targets")
	_deck_bank.bonus = 10000   # harder to reach up there, so it pays more
	_light_bank.targets = get_tree().get_nodes_in_group("rollover_lights")
	_light_bank.bonus = 7500
	for bank in [_main_bank, _deck_bank, _light_bank]:
		for d in bank.targets:
			if d.has_signal("hit"):
				d.hit.connect(_on_drop_hit.bind(bank))

	for r in get_tree().get_nodes_in_group("rollovers"):
		r.body_entered.connect(_on_rollover.bind(r))

	GameManager.game_over.connect(_on_game_over)

	_spawn_ball()


func _build_gate() -> void:
	# Skip if the scene already contains a hand-placed gate node.
	if has_node("LaneGate"):
		return
	var gate: Node2D = GATE_SCENE.instantiate()
	gate.name = "LaneGate"
	gate.position = gate_position
	gate.rotation = gate_rotation
	add_child(gate)


func _spawn_ball() -> void:
	var ball: RigidBody2D = BALL_SCENE.instantiate()
	ball.position = _spawn.global_position
	ball.max_contacts_reported = 10
	add_child(ball)
	_launch_charge = 0.0


func _get_ball() -> RigidBody2D:
	# get_nodes_in_group() can transiently include a queue_free()'d node until
	# the deferred deletion actually happens - skip any that are already gone
	# rather than handing back a stale reference callers would assign into.
	for b in get_tree().get_nodes_in_group("ball"):
		if is_instance_valid(b):
			return b
	return null


func _physics_process(delta: float) -> void:
	var ball := _get_ball()
	if ball == null:
		return
	# Safety net: a ball that escaped the table (e.g. stranded on a ramp layer)
	# must never be lost off-screen. Restore normal collision and drain it.
	if _out_of_bounds(ball):
		ball.collision_layer = 1
		ball.collision_mask = 1
		ball.z_index = 0
		ball.set_meta("on_ramp", false)
		_on_drain_body_entered(ball)
		return
	if Input.is_action_just_pressed("nudge_left"):
		_nudge(-1.0)
	if Input.is_action_just_pressed("nudge_right"):
		_nudge(1.0)
	var in_lane := ball.global_position.x > lane_min.x and ball.global_position.y > lane_min.y
	if in_lane and Input.is_action_pressed("launch"):
		_launch_charge = minf(_launch_charge + delta / 1.1, 1.0)
	elif in_lane and _launch_charge > 0.0:
		var sp := lerpf(launch_min_speed, launch_max_speed, _launch_charge)
		ball.linear_velocity = launch_direction.normalized() * sp
		SoundManager.play("launch", lerpf(0.9, 1.2, _launch_charge))
		_launch_charge = 0.0


func _nudge(dir: float) -> void:
	for b in get_tree().get_nodes_in_group("ball"):
		if b is RigidBody2D:
			b.apply_central_impulse(Vector2(dir * nudge_impulse, -nudge_impulse * 0.3))
	var cam := get_node_or_null("Camera2D")
	if cam and cam.has_method("shake"):
		cam.shake(11.0)


func _out_of_bounds(ball: RigidBody2D) -> bool:
	var p := ball.global_position
	return p.x < -80.0 or p.x > 1360.0 or p.y < -80.0 or p.y > 2640.0


func _on_drain_body_entered(body: Node) -> void:
	if not body.is_in_group("ball"):
		return
	# Count what is STILL in play before freeing this one. During multiball,
	# losing one ball costs nothing - only draining the last ball ends the
	# ball-in-play, or every multiball would cost two extra lives.
	var others := _live_balls(body)
	body.queue_free()
	SoundManager.play("drain")
	if others > 0:
		# Down to a single ball again: multiball is over.
		if others == 1:
			_end_multiball()
		return
	_end_multiball()
	GameManager.lose_ball()
	if not GameManager.is_game_over:
		await get_tree().create_timer(0.9).timeout
		_spawn_ball()


## Let the final score sit on screen for a moment, then hand over to the high
## score table - which decides for itself whether that score earned a place.
func _on_game_over() -> void:
	var final_score := GameManager.score
	await get_tree().create_timer(2.6).timeout
	if not is_inside_tree():
		return
	HighScores.pending_score = final_score
	get_tree().change_scene_to_file("res://scenes/high_scores.tscn")


func _on_rollover(body: Node, _area: Area2D) -> void:
	if body.is_in_group("ball"):
		GameManager.add_score(250, _area.global_position)
		SoundManager.play("target")


## Average position of a bank's pieces, for centring the celebration on it.
func _bank_centre(bank: Bank) -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for t in bank.targets:
		if is_instance_valid(t):
			sum += t.global_position
			count += 1
	return sum / maxi(count, 1)


## Bank clears build toward multiball, but ONLY while it is inactive - during
## multiball a clear earns its bonus and nothing more.
func _count_toward_multiball(bank: Bank) -> void:
	if _multiball:
		return
	if bank == _deck_bank:
		_deck_clears += 1
	elif bank == _main_bank:
		_main_clears += 1
	else:
		return   # the rollover set doesn't feed multiball
	GameManager.multiball_progress.emit(_deck_clears, _main_clears)
	if _deck_clears >= multiball_deck_clears and _main_clears >= multiball_main_clears:
		_start_multiball()


func _start_multiball() -> void:
	if _multiball:
		return
	_multiball = true
	# Zero the counters now: the next multiball has to be earned from scratch,
	# and this also stops a clear landing mid-multiball from re-triggering.
	_deck_clears = 0
	_main_clears = 0
	GameManager.multiball_progress.emit(0, 0)
	GameManager.multiball_changed.emit(true)
	SoundManager.play("launch", 1.15)
	GameManager.impact.emit(14.0)
	# Feed the extra balls in over a beat so they don't all appear on top of
	# each other, and from the top of the playfield so they immediately matter.
	for i in multiball_extra_balls:
		await get_tree().create_timer(0.35).timeout
		if not is_inside_tree() or GameManager.is_game_over:
			return
		var extra: RigidBody2D = BALL_SCENE.instantiate()
		extra.position = multiball_feed_position + Vector2(randf_range(-40.0, 40.0), 0.0)
		extra.max_contacts_reported = 10
		add_child(extra)
		extra.linear_velocity = Vector2(randf_range(-160.0, 160.0), 380.0)


func _end_multiball() -> void:
	if not _multiball:
		return
	_multiball = false
	_deck_clears = 0
	_main_clears = 0
	GameManager.multiball_progress.emit(0, 0)
	GameManager.multiball_changed.emit(false)


## Balls currently in play, ignoring any that are already queued for deletion.
func _live_balls(excluding: Node = null) -> int:
	var n := 0
	for b in get_tree().get_nodes_in_group("ball"):
		if is_instance_valid(b) and b != excluding:
			n += 1
	return n


func _on_drop_hit(_target, bank: Bank) -> void:
	bank.down += 1
	if bank.down >= bank.targets.size() and not bank.resetting:
		bank.resetting = true
		GameManager.add_score(bank.bonus, _target.global_position)
		SoundManager.play("target", 0.7)
		# Celebrate over the middle of the whole group, not the last piece hit,
		# so the burst reads as "that set is cleared".
		GameManager.bank_completed.emit(_bank_centre(bank))
		_count_toward_multiball(bank)
		await get_tree().create_timer(1.2).timeout
		for d in bank.targets:
			d.reset_target()
		bank.down = 0
		bank.resetting = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/table_select.tscn")
	elif event.is_action_pressed("restart") and GameManager.is_game_over:
		GameManager.reset()
		for bank in [_main_bank, _deck_bank, _light_bank]:
			for d in bank.targets:
				d.reset_target()
			bank.down = 0
			bank.resetting = false
		_end_multiball()
		_spawn_ball()
