@tool
extends Line2D
## A drawable wall. Draw/edit it like any Line2D in the editor (select it and
## use the point handles), and it builds matching segment collision from its
## own points when the game runs. No separate collision node to maintain.
##
## To add a new wall: instance wall.tscn (or add a Line2D + attach this script),
## select it, and click points in the 2D viewport with the Line2D point tool.

@export var wall_bounce := 0.25
@export var wall_friction := 0.1


func _ready() -> void:
	if Engine.is_editor_hint():
		return  # in the editor it's just an editable Line2D; collision is built at runtime
	if points.size() < 2:
		return
	var body := StaticBody2D.new()
	var mat := PhysicsMaterial.new()
	mat.friction = wall_friction
	mat.bounce = wall_bounce
	body.physics_material_override = mat
	# ConcavePolygonShape2D with explicit segment pairs stays an OPEN polyline.
	# (CollisionPolygon2D would close the loop with an extra invisible segment.)
	var segs := PackedVector2Array()
	for i in points.size() - 1:
		segs.append(points[i])
		segs.append(points[i + 1])
	var shape := ConcavePolygonShape2D.new()
	shape.segments = segs
	var col := CollisionShape2D.new()
	col.shape = shape
	body.add_child(col)
	add_child(body)
