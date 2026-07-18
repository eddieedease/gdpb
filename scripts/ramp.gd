@tool
extends Path2D
## A ramp: a channel like Rail, but the ball rides OVER the playfield while on
## it - it ignores bumpers/walls below and renders on top, then returns to
## normal play at the far end. Draw the centre line with the Path2D tools.
##
## How it works: the ramp walls live on a separate physics layer. A portal at
## each end flips the ball onto (or off of) that layer, so a normal ball passes
## under the ramp until it enters a mouth, then is guided along it.

const RAMP_BIT := 1 << 3  # physics layer 4, reserved for ramps

@export var channel_width := 70.0:
	set(v):
		channel_width = v
		_refresh()
@export_range(1.0, 30.0) var smoothness := 4.0:
	set(v):
		smoothness = v
		_refresh()
@export var wall_bounce := 0.15
## Points awarded once each time a ball boards the ramp (0 = no scoring).
@export var ramp_score := 2000

## The "sucked in" feel: while captured, the ball is steered along the curve
## (speed preserved), pulled gently to the centreline, and gravity inside the
## channel is reduced so momentum carries it through climbs.
@export var guide_strength := 6.0
@export var centering := 8.0
@export var channel_gravity := 250.0

var _riding: Array[RigidBody2D] = []

@onready var _left: Line2D = $Left
@onready var _right: Line2D = $Right


func _ready() -> void:
	_connect_curve()
	_refresh()
	if not Engine.is_editor_hint():
		_build_wall($Left.points)
		_build_wall($Right.points)
		_build_field()


func _connect_curve() -> void:
	if curve and not curve.changed.is_connected(_refresh):
		curve.changed.connect(_refresh)


func _refresh() -> void:
	_connect_curve()
	if _left == null:
		_left = get_node_or_null("Left")
		_right = get_node_or_null("Right")
	if _left == null or _right == null or curve == null:
		return
	var center := curve.tessellate(5, smoothness)
	_left.points = _offset(center, channel_width * 0.5)
	_right.points = _offset(center, -channel_width * 0.5)


func _offset(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	var raw := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var dir: Vector2
		if i == 0:
			dir = pts[1] - pts[0]
		elif i == n - 1:
			dir = pts[i] - pts[i - 1]
		else:
			dir = pts[i + 1] - pts[i - 1]
		if dir.length() < 0.001:
			dir = Vector2.RIGHT
		dir = dir.normalized()
		raw.append(pts[i] + Vector2(-dir.y, dir.x) * d)
	return _remove_loops(raw)


## Drop self-intersection loops so a tight bend's inner wall stays smooth.
func _remove_loops(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p)
		var m := out.size()
		if m < 4:
			continue
		for j in range(m - 3):
			if _segments_cross(out[m - 2], out[m - 1], out[j], out[j + 1]):
				var keep := out.slice(0, j + 1)
				keep.append(out[m - 1])
				out = keep
				break
	return out


func _segments_cross(a: Vector2, b: Vector2, c: Vector2, e: Vector2) -> bool:
	var r := b - a
	var s := e - c
	var rxs := r.cross(s)
	if absf(rxs) < 0.0001:
		return false
	var t := (c - a).cross(s) / rxs
	var u := (c - a).cross(r) / rxs
	return t > 0.01 and t < 0.99 and u > 0.01 and u < 0.99


func _build_wall(pts: PackedVector2Array) -> void:
	if pts.size() < 2:
		return
	var body := StaticBody2D.new()
	body.collision_layer = RAMP_BIT   # only balls that are "on the ramp" hit these
	body.collision_mask = 0
	var mat := PhysicsMaterial.new()
	mat.friction = 0.05
	mat.bounce = wall_bounce
	body.physics_material_override = mat
	var segs := PackedVector2Array()
	for i in pts.size() - 1:
		segs.append(pts[i])
		segs.append(pts[i + 1])
	var shape := ConcavePolygonShape2D.new()
	shape.segments = segs
	var cs := CollisionShape2D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


# A single Area2D covering the whole channel interior. The ball is "on the
# ramp" exactly while it is inside this field; leaving it by ANY route (mouth,
# side, whatever) restores normal collision, so the ball can never get stranded
# on the ramp layer and fly off-screen.
func _build_field() -> void:
	var left: PackedVector2Array = $Left.points
	var right: PackedVector2Array = $Right.points
	if left.size() < 2 or right.size() < 2:
		return
	var poly := PackedVector2Array()
	poly.append_array(left)
	for i in range(right.size() - 1, -1, -1):
		poly.append(right[i])
	var area := Area2D.new()
	area.name = "Field"
	area.collision_mask = 1 | RAMP_BIT   # detect the ball whether on or off the ramp
	# Reduced gravity inside the channel (wins over the table's gravity zone)
	# so the ball keeps its momentum through climbs.
	area.gravity_space_override = Area2D.SPACE_OVERRIDE_REPLACE
	area.gravity = channel_gravity
	area.gravity_direction = Vector2.DOWN
	area.priority = 5
	var cp := CollisionPolygon2D.new()
	cp.polygon = poly
	area.add_child(cp)
	add_child(area)
	area.body_entered.connect(_on_field_entered)
	area.body_exited.connect(_on_field_exited)


func _on_field_entered(body: Node) -> void:
	if not body.is_in_group("ball") or body.get_meta("on_ramp", false):
		return
	# board the ramp -> ride over the playfield (but keep colliding with the
	# ramp walls so it stays guided)
	body.collision_layer = RAMP_BIT
	body.collision_mask = RAMP_BIT
	body.z_index = 10
	body.set_meta("on_ramp", true)
	if body is RigidBody2D and not _riding.has(body):
		_riding.append(body)
	SoundManager.play("whoosh")
	if ramp_score > 0:
		GameManager.add_score(ramp_score)


func _on_field_exited(body: Node) -> void:
	if not body.is_in_group("ball") or not body.get_meta("on_ramp", false):
		return
	body.collision_layer = 1
	body.collision_mask = 1
	body.z_index = 0
	body.set_meta("on_ramp", false)
	_riding.erase(body)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _riding.is_empty() or curve == null:
		return
	for ball: RigidBody2D in _riding.duplicate():
		if not is_instance_valid(ball):
			_riding.erase(ball)
			continue
		var speed: float = ball.linear_velocity.length()
		if speed < 80.0:
			continue
		# Direction of the channel at the ball's position (in global space).
		var local := to_local(ball.global_position)
		var off := curve.get_closest_offset(local)
		var ahead := curve.sample_baked(minf(off + 8.0, curve.get_baked_length()))
		var behind := curve.sample_baked(maxf(off - 8.0, 0.0))
		var tangent := (to_global(ahead) - to_global(behind)).normalized()
		if tangent.length_squared() < 0.5:
			continue
		# Steer along the channel, whichever way the ball is already moving,
		# preserving its speed - the "locked in, keeps momentum" feel.
		if ball.linear_velocity.dot(tangent) < 0.0:
			tangent = -tangent
		var target := tangent * speed
		ball.linear_velocity = ball.linear_velocity.lerp(target, clampf(guide_strength * delta, 0.0, 1.0))
		# Gentle pull toward the centreline.
		var to_center: Vector2 = to_global(curve.sample_baked(off)) - ball.global_position
		ball.linear_velocity += to_center * centering * delta
