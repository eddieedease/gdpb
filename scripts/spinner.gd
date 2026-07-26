extends Area2D
## A spinner: a blade mounted across a lane that the ball whips through. It has
## no collision of its own (Area2D), so it never slows the ball down - it just
## measures how hard the ball went past and spins accordingly, ticking and
## scoring once per revolution as it coasts to a stop.
##
## The 3D view builds the real spinning blade from this node and reads `spin`
## and `angle` each frame, so the visual and the scoring always agree.

signal spun(total_revolutions: int)

## Points per revolution. A fast shot through a spinner is worth a lot in
## total, which is the whole appeal of one.
@export var points_per_rev := 130
## Ball speed (px/s) -> revolutions per second handed to the blade.
@export var speed_to_spin := 0.0055
## How quickly the blade coasts down, in rev/s lost per second.
@export var friction := 1.7
## Lane width; the blade is drawn this wide.
@export var width := 76.0:
	set(v):
		width = v
		_apply_width()
@export var max_spin := 13.0

## Current spin rate in revolutions per second, and the blade's angle in turns
## (0..1). Both read by the 3D view.
var spin := 0.0
var angle := 0.0

var _shape: CollisionShape2D
var _rev_accum := 0.0
var _total_revs := 0
var _last_tick_ms := 0


func _ready() -> void:
	_shape = get_node_or_null("CollisionShape2D")
	if _shape == null:
		_shape = CollisionShape2D.new()
		_shape.name = "CollisionShape2D"
		_shape.shape = RectangleShape2D.new()
		add_child(_shape)
	elif not (_shape.shape is RectangleShape2D):
		_shape.shape = RectangleShape2D.new()
	_apply_width()
	collision_mask = 1   # playfield balls only
	monitoring = true
	body_entered.connect(_on_body_entered)


func _apply_width() -> void:
	if _shape and _shape.shape is RectangleShape2D:
		(_shape.shape as RectangleShape2D).size = Vector2(width, 26.0)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("ball") or not body is RigidBody2D:
		return
	# Only the component of travel ACROSS the blade spins it - clipping the end
	# of a spinner sideways shouldn't send it flying round.
	var across: Vector2 = Vector2.DOWN.rotated(global_rotation)
	var through: float = absf(body.linear_velocity.dot(across))
	spin = clampf(maxf(spin, through * speed_to_spin), 0.0, max_spin)


func _physics_process(delta: float) -> void:
	if spin <= 0.0:
		return
	angle = fmod(angle + spin * delta, 1.0)
	_rev_accum += spin * delta
	while _rev_accum >= 1.0:
		_rev_accum -= 1.0
		_total_revs += 1
		GameManager.add_score(points_per_rev, global_position)
		# One tick per revolution, but rate-limited: at full tilt a spinner
		# would otherwise fire dozens of overlapping clicks a second.
		var now := Time.get_ticks_msec()
		if now - _last_tick_ms > 55:
			_last_tick_ms = now
			SoundManager.play("spinner", randf_range(0.92, 1.12))
		spun.emit(_total_revs)
	spin = maxf(spin - friction * delta, 0.0)
