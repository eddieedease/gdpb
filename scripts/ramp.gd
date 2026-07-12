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

@onready var _left: Line2D = $Left
@onready var _right: Line2D = $Right


func _ready() -> void:
	_connect_curve()
	_refresh()
	if not Engine.is_editor_hint():
		_build_wall($Left.points)
		_build_wall($Right.points)
		var center := curve.tessellate(5, smoothness)
		if center.size() >= 2:
			_build_portal(center[0])
			_build_portal(center[center.size() - 1])


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


func _build_portal(local_pos: Vector2) -> void:
	var area := Area2D.new()
	area.position = local_pos
	area.collision_mask = 1 | RAMP_BIT   # detect balls whether on or off the ramp
	var cs := CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = channel_width * 0.7
	cs.shape = circ
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_portal)


func _on_portal(body: Node) -> void:
	if not body.is_in_group("ball"):
		return
	if body.get_meta("on_ramp", false):
		# leave the ramp -> back to normal play
		body.collision_layer = 1
		body.collision_mask = 1
		body.z_index = 0
		body.set_meta("on_ramp", false)
	else:
		# board the ramp -> ride over the playfield
		body.collision_layer = RAMP_BIT
		body.collision_mask = RAMP_BIT
		body.z_index = 10
		body.set_meta("on_ramp", true)
		if ramp_score > 0:
			GameManager.add_score(ramp_score)
