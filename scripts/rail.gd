@tool
extends Path2D
## A rail: a guided CHANNEL the ball travels along. Draw the centre line with
## the Path2D point/handle tools (like CurvedWall); this builds two parallel
## walls a fixed distance apart, forming a lane. Great for orbits, loops and
## guided ball paths.

## Distance between the two rail walls (fit it to ~1.5-2x the ball diameter).
@export var channel_width := 70.0:
	set(v):
		channel_width = v
		_refresh()
@export_range(1.0, 30.0) var smoothness := 4.0:
	set(v):
		smoothness = v
		_refresh()
@export var wall_bounce := 0.2
@export var wall_friction := 0.0

@onready var _left: Line2D = $Left
@onready var _right: Line2D = $Right


func _ready() -> void:
	_connect_curve()
	_refresh()
	if not Engine.is_editor_hint():
		_build_collision($Left.points)
		_build_collision($Right.points)


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


## Offset a polyline sideways by d (perpendicular to its direction), then remove
## self-intersection loops so the inner wall of a tight curve stays smooth (a
## naive offset barbs inward on tight bends and snags the ball).
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


## Drop any point whose incoming segment crosses an earlier segment - that loop
## is a self-intersection barb from offsetting a concave curve.
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


func _build_collision(pts: PackedVector2Array) -> void:
	if pts.size() < 2:
		return
	var body := StaticBody2D.new()
	var mat := PhysicsMaterial.new()
	mat.friction = wall_friction
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
