extends StaticBody2D
## Shared behaviour for anything the ball can hit for points:
## pop bumpers and slingshots (kick_speed > 0) and standup targets (kick_speed = 0).

## Emitted on every hit. The 2D sprite is hidden in the 3D view, so the solid
## geometry built for this piece listens for this to do its own squash-flash.
signal flashed

@export var points := 100
@export var kick_speed := 0.0
## Optional per-instance texture. Set on the instance root (survives editor
## re-saves, unlike child-node property overrides) to recolour a shared scene.
@export var texture_override: Texture2D
## "" auto-picks "target" (kick_speed == 0) or "bumper"; set explicitly for
## variants like "slingshot" that share this script but want a different sfx.
@export var sound_type := ""
## Slingshot behaviour: only ONE face fires the ball - the long rubber - and it
## fires along that face's outward normal, like a real slingshot. Glancing the
## short sides just deflects the ball, no kick and no score. A round pop bumper
## leaves this off and kicks radially from its centre no matter where it is hit.
## The rubber is found as the LONGEST edge of the collision polygon, so it needs
## no extra setup and survives the piece being rotated, mirrored or reshaped.
@export var directional_kick := false

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D")

var _base_scale := Vector2.ONE
var _base_modulate := Color.WHITE
var _tween: Tween


func _ready() -> void:
	if sprite:
		if texture_override:
			sprite.texture = texture_override
		_base_scale = sprite.scale
		_base_modulate = sprite.modulate


func on_ball_hit(ball: RigidBody2D) -> void:
	if kick_speed > 0.0:
		var dir := _kick_direction(ball)
		if dir == Vector2.ZERO:
			return   # glanced a dead face - it just deflects, nothing happens
		ball.linear_velocity = dir * kick_speed
	GameManager.add_score(points, global_position)
	GameManager.impact.emit(clampf(kick_speed / 60.0, 4.0, 16.0))
	SoundManager.play(_resolve_sound_type())
	flashed.emit()
	_flash()


## Which way to fire, or ZERO for "this face does not kick".
func _kick_direction(ball: Node2D) -> Vector2:
	var poly: CollisionPolygon2D = get_node_or_null("CollisionPolygon2D")
	if not directional_kick or poly == null or poly.polygon.size() < 3:
		var radial := (ball.global_position - global_position).normalized()
		return Vector2.UP if radial == Vector2.ZERO else radial

	# Work in global space throughout, so rotation and a mirrored scale (the
	# right slingshot is scaled -1 on Y) need no special handling.
	var pts: PackedVector2Array = poly.polygon
	var xf := poly.global_transform
	var n := pts.size()
	var centroid := Vector2.ZERO
	for p in pts:
		centroid += xf * p
	centroid /= float(n)

	var rubber := -1
	var rubber_len := -1.0
	var nearest := -1
	var nearest_dist := INF
	for i in n:
		var a: Vector2 = xf * pts[i]
		var b: Vector2 = xf * pts[(i + 1) % n]
		var length := a.distance_to(b)
		if length > rubber_len:
			rubber_len = length
			rubber = i
		var d := ball.global_position.distance_to(Geometry2D.get_closest_point_to_segment(
				ball.global_position, a, b))
		if d < nearest_dist:
			nearest_dist = d
			nearest = i
	if nearest != rubber:
		return Vector2.ZERO

	var ra: Vector2 = xf * pts[rubber]
	var rb: Vector2 = xf * pts[(rubber + 1) % n]
	var edge := (rb - ra).normalized()
	var nrm := Vector2(-edge.y, edge.x)
	if nrm.dot(((ra + rb) * 0.5) - centroid) < 0.0:
		nrm = -nrm   # always point away from the body of the slingshot
	return nrm


func _resolve_sound_type() -> String:
	if sound_type != "":
		return sound_type
	return "target" if kick_speed <= 0.0 else "bumper"


func _flash() -> void:
	if sprite == null:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	sprite.scale = _base_scale * 1.15
	sprite.modulate = Color(1.5, 1.5, 1.5)
	_tween = create_tween()
	_tween.tween_property(sprite, "scale", _base_scale, 0.15)
	_tween.parallel().tween_property(sprite, "modulate", _base_modulate, 0.2)
