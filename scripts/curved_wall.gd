@tool
extends Path2D
## A smooth curved wall. Edit it like any Path2D: select it, pick the "Add
## Point" tool in the toolbar, click to drop points, then drag each point's
## round bezier handles to bend the curve. The blue line you see and its
## collision are generated automatically from the curve - what you draw is
## what the ball hits.
##
## Tip: to curl a point, drag its handle out; hold Shift while dragging a
## handle to break it so the two sides bend independently.

## Curve smoothness: lower = more segments = smoother (degrees of tolerance).
@export_range(1.0, 30.0) var smoothness := 4.0:
	set(v):
		smoothness = v
		_refresh()
@export var wall_bounce := 0.25
@export var wall_friction := 0.1

@onready var _line: Line2D = $Line


func _ready() -> void:
	_connect_curve()
	_refresh()
	if not Engine.is_editor_hint():
		_build_collision()


func _connect_curve() -> void:
	if curve and not curve.changed.is_connected(_refresh):
		curve.changed.connect(_refresh)


func _refresh() -> void:
	_connect_curve()
	if _line == null:
		_line = get_node_or_null("Line")
	if _line == null or curve == null:
		return
	_line.points = curve.tessellate(5, smoothness)


func _build_collision() -> void:
	var pts := _line.points
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
