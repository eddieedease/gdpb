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
## Collision thickness in pixels. The wall's drawn line stays where it is; this
## only gives the barrier some body so a fast ball cannot cross it. Small enough
## (half a ball radius) that the play surface does not visibly move.
@export var thickness := 14.0


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
	# One THICK convex quad per segment, rather than a zero-width polyline.
	# A ConcavePolygonShape2D of segments is a hairline barrier: a ball driven
	# hard into it, or squeezed against it by a flipper, can end up on the far
	# side and out of play. Real thickness is what stops that - the same fix the
	# deck cage needed. Each quad overhangs its ends so neighbours overlap at
	# the joints and leave no gap to slip through, and the quads stay convex,
	# which the physics engine handles far more robustly than a concave chain.
	var half := thickness * 0.5
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var dir := (b - a)
		if dir.length() < 0.001:
			continue
		dir = dir.normalized()
		var nrm := Vector2(-dir.y, dir.x) * half
		var ea := a - dir * half
		var eb := b + dir * half
		var cp := CollisionPolygon2D.new()
		cp.polygon = PackedVector2Array([ea + nrm, eb + nrm, eb - nrm, ea - nrm])
		body.add_child(cp)
	add_child(body)
