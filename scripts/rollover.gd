extends Area2D
## A rollover light: a round insert set flush into the playfield. The ball
## rolls straight over it - being an Area2D it has no collision and so no
## friction at all, it never deflects or slows the ball - and lights up for
## points the first time it is crossed.
##
## They work as a GROUP. Put every light of a set in the same group (default
## "rollover_lights") and the table controller pays a bonus and darkens the
## whole set once every one of them is lit. Its `hit` / `reset_target()`
## interface is deliberately the same as a drop target's, so it plugs into the
## same bank machinery.
##
## Self-heals like drop_target.gd: rebuilds its shape and visual at runtime if
## those children were deleted while editing the table.

signal hit(target)

@export var points := 400
@export var radius := 34.0:
	set(v):
		radius = v
		_apply_radius()
## Colour of the insert when unlit / lit (2D fallback; the 3D view draws its
## own glowing disc from these same states).
@export var color_dark := Color(0.22, 0.25, 0.36)
@export var color_lit := Color(1.0, 0.80, 0.27)

var is_lit := false

var _shape: CollisionShape2D
var _visual: Polygon2D


func _ready() -> void:
	_shape = get_node_or_null("CollisionShape2D")
	if _shape == null:
		_shape = CollisionShape2D.new()
		_shape.name = "CollisionShape2D"
		_shape.shape = CircleShape2D.new()
		add_child(_shape)
	elif not (_shape.shape is CircleShape2D):
		_shape.shape = CircleShape2D.new()
	_visual = get_node_or_null("Visual") as Polygon2D
	if _visual == null:
		_visual = Polygon2D.new()
		_visual.name = "Visual"
		add_child(_visual)
	_apply_radius()
	_refresh_visual()
	# Only the ball, and only on the playfield layer - a ball riding a channel
	# or up on the deck passes over without triggering anything.
	collision_mask = 1
	monitoring = true
	body_entered.connect(_on_body_entered)


func _apply_radius() -> void:
	if _shape and _shape.shape is CircleShape2D:
		(_shape.shape as CircleShape2D).radius = radius
	if _visual:
		var pts := PackedVector2Array()
		for i in 24:
			var a := TAU * float(i) / 24.0
			pts.append(Vector2(cos(a), sin(a)) * radius)
		_visual.polygon = pts


func _on_body_entered(body: Node) -> void:
	if is_lit or not body.is_in_group("ball"):
		return
	is_lit = true
	_refresh_visual()
	GameManager.add_score(points, global_position)
	SoundManager.play("target", 1.25)
	hit.emit(self)


## Named to match drop_target.gd so a bank can reset either kind.
func reset_target() -> void:
	is_lit = false
	_refresh_visual()


func _refresh_visual() -> void:
	if _visual:
		_visual.color = color_lit if is_lit else color_dark
