extends Node2D
## Procedurally-built wide, multi-level pinball table (Devil/Alien Crush style).
## Everything (walls, rails, elements) is built from the constants below so the
## layout is easy to tune. Visible rails are drawn from the SAME points used for
## collision, so what you see is what the ball actually hits.

const BALL_SCENE := preload("res://scenes/ball.tscn")
const BUMPER := preload("res://scenes/bumper.tscn")
const SLING_L := preload("res://scenes/slingshot_left.tscn")
const SLING_R := preload("res://scenes/slingshot_right.tscn")
const FLIP_L := preload("res://scenes/flipper_left.tscn")
const FLIP_R := preload("res://scenes/flipper_right.tscn")
const DROP_TARGET := preload("res://scripts/drop_target.gd")

const W := 1280.0
const H := 2560.0

const WALL_COLOR := Color(0.45, 0.72, 1.0)
const RAIL_COLOR := Color(0.55, 0.85, 0.95)

# --- Element positions (tune these) ---
const BUMPERS := [Vector2(640, 430), Vector2(470, 590), Vector2(810, 590)]
const MID_BUMPERS := [Vector2(640, 1480), Vector2(505, 1610), Vector2(775, 1610), Vector2(640, 1740), Vector2(300, 1360), Vector2(980, 1360)]
const DROP_TARGETS := [Vector2(500, 1010), Vector2(600, 1010), Vector2(700, 1010), Vector2(800, 1010)]
const UPPER_FLIP_L := Vector2(380, 1380)
const UPPER_FLIP_R := Vector2(900, 1380)
const MAIN_FLIP_L := Vector2(486, 2280)
const MAIN_FLIP_R := Vector2(794, 2280)
const SLING_L_POS := Vector2(365, 2040)
const SLING_R_POS := Vector2(915, 2040)
const ROLLOVERS := [Vector2(430, 250), Vector2(640, 220), Vector2(850, 250)]
const LANE_X := 1120.0            # centre of shooter lane
const BALL_LAUNCH := Vector2(1120, 2360)

var _wall_seg := PackedVector2Array()
var _rails: Node2D
var _drops: Array = []
var _drops_down := 0
var _launch_charge := 0.0
var _resetting_bank := false

@onready var _hud := $HUD


func _ready() -> void:
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP_WIDTH
	win.content_scale_size = Vector2i(1280, 720)

	GameManager.reset()
	GameManager.game_over.connect(_on_game_over)

	_rails = Node2D.new()
	add_child(_rails)

	_build_gravity_zone()
	_build_boundary()
	_build_shooter()
	_build_top_rails()
	_finalize_walls()

	_build_bumpers()
	_build_slingshots()
	_build_drop_targets()
	_build_flippers()
	_build_rollovers()
	_build_drain()

	_spawn_ball()


# ---------------------------------------------------------------- walls
func _wall(points: PackedVector2Array, width := 9.0, color := WALL_COLOR) -> void:
	var line := Line2D.new()
	line.points = points
	line.width = width
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_rails.add_child(line)
	for i in points.size() - 1:
		_wall_seg.append(points[i])
		_wall_seg.append(points[i + 1])


func _arc(center: Vector2, radius: float, a0_deg: float, a1_deg: float, steps := 16) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		var t := deg_to_rad(lerpf(a0_deg, a1_deg, float(i) / steps))
		pts.append(center + Vector2(cos(t), sin(t)) * radius)
	return pts


func _finalize_walls() -> void:
	var body := StaticBody2D.new()
	body.name = "Walls"
	var mat := PhysicsMaterial.new()
	mat.friction = 0.1
	mat.bounce = 0.25
	body.physics_material_override = mat
	var cs := CollisionShape2D.new()
	var shape := ConcavePolygonShape2D.new()
	shape.segments = _wall_seg
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


func _build_boundary() -> void:
	# Left inlane + left wall + top dome + right wall, with a drain gap at the
	# bottom centre (between the two main flippers).
	var left := PackedVector2Array()
	left.append(Vector2(430, 2300))          # left inlane top (by left flipper)
	left.append(Vector2(150, 2010))           # funnel up to left wall
	left.append(Vector2(110, 1900))
	left.append_array(_arc(Vector2(300, 300), 190, 180, 270, 14))  # top-left corner (110,300)->(300,110)
	# left wall is the vertical part just below the corner; prepend not needed
	_wall(left)

	var top := PackedVector2Array()
	top.append(Vector2(300, 110))
	top.append(Vector2(980, 110))
	top.append_array(_arc(Vector2(980, 300), 190, 270, 360, 14))   # top-right corner ->(1170,300)
	_wall(top)


func _build_shooter() -> void:
	# Outer right wall + lane floor + inner lane wall, plus a deflector at the
	# top that throws the launched ball left into the dome.
	var outer := PackedVector2Array()
	outer.append(Vector2(1170, 300))
	outer.append(Vector2(1170, 2440))         # right outer wall down
	outer.append(Vector2(1060, 2440))         # lane floor
	_wall(outer)

	var inner := PackedVector2Array()
	inner.append(Vector2(1060, 2380))          # inner lane wall (ball rests just above)
	inner.append(Vector2(1060, 1980))
	inner.append(Vector2(1030, 1900))
	inner.append(Vector2(960, 2130))           # right funnel down toward right flipper
	inner.append(Vector2(850, 2300))
	_wall(inner)

	# top-of-lane deflector: sends ball from the lane leftward under the dome
	var defl := PackedVector2Array()
	defl.append(Vector2(1170, 360))
	defl.append(Vector2(1010, 300))
	_wall(defl, 9.0, RAIL_COLOR)


func _build_top_rails() -> void:
	# Inner orbit rails on each side of the dome to create side lanes.
	_wall(_arc(Vector2(320, 620), 190, 250, 335, 12), 9.0, RAIL_COLOR)
	_wall(_arc(Vector2(960, 620), 190, 205, 290, 12), 9.0, RAIL_COLOR)
	# small stand ledges under the upper flippers
	_wall(PackedVector2Array([Vector2(250, 1440), UPPER_FLIP_L + Vector2(-6, 40)]), 9.0, RAIL_COLOR)
	_wall(PackedVector2Array([Vector2(1030, 1440), UPPER_FLIP_R + Vector2(6, 40)]), 9.0, RAIL_COLOR)


# ---------------------------------------------------------------- elements
func _add_scored(scene: PackedScene, pos: Vector2, tint := Color.WHITE) -> Node:
	var n: Node2D = scene.instantiate()
	n.position = pos
	if tint != Color.WHITE:
		n.set("texture_override", null)  # keep default sprite; tint via modulate
		n.modulate = tint
	add_child(n)
	return n


func _build_bumpers() -> void:
	var tints := [Color(0.7, 0.85, 1.0), Color(1.0, 0.7, 0.8), Color(1.0, 0.85, 0.6)]
	var idx := 0
	for p in BUMPERS:
		var b: Node2D = BUMPER.instantiate()
		b.position = p
		b.modulate = tints[idx % tints.size()]
		add_child(b)
		idx += 1
	for p in MID_BUMPERS:
		var b: Node2D = BUMPER.instantiate()
		b.position = p
		b.modulate = Color(0.8, 1.0, 0.85)
		add_child(b)


func _build_slingshots() -> void:
	var sl: Node2D = SLING_L.instantiate()
	sl.position = SLING_L_POS
	add_child(sl)
	var sr: Node2D = SLING_R.instantiate()
	sr.position = SLING_R_POS
	add_child(sr)


func _build_drop_targets() -> void:
	for p in DROP_TARGETS:
		var dt := StaticBody2D.new()
		dt.set_script(DROP_TARGET)
		dt.position = p

		var shape := RectangleShape2D.new()
		shape.size = Vector2(64, 34)
		var cs := CollisionShape2D.new()
		cs.name = "CollisionShape2D"
		cs.shape = shape
		dt.add_child(cs)

		var vis := Polygon2D.new()
		vis.name = "Visual"
		vis.polygon = PackedVector2Array([Vector2(-32, -17), Vector2(32, -17), Vector2(32, 17), Vector2(-32, 17)])
		vis.color = Color(1.0, 0.55, 0.25)
		dt.add_child(vis)

		add_child(dt)
		dt.hit.connect(_on_drop_hit)
		_drops.append(dt)


func _build_flippers() -> void:
	_add_flipper(FLIP_L, MAIN_FLIP_L)
	_add_flipper(FLIP_R, MAIN_FLIP_R)
	_add_flipper(FLIP_L, UPPER_FLIP_L)
	_add_flipper(FLIP_R, UPPER_FLIP_R)


func _add_flipper(scene: PackedScene, pos: Vector2) -> void:
	var f: Node2D = scene.instantiate()
	f.position = pos
	f.set("rotate_speed", 15.0)
	add_child(f)


func _build_rollovers() -> void:
	for p in ROLLOVERS:
		var area := Area2D.new()
		area.position = p
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(60, 60)
		cs.shape = shape
		area.add_child(cs)
		var vis := Polygon2D.new()
		vis.polygon = PackedVector2Array([Vector2(-30, -30), Vector2(30, -30), Vector2(30, 30), Vector2(-30, 30)])
		vis.color = Color(0.3, 0.9, 0.5, 0.35)
		area.add_child(vis)
		add_child(area)
		area.body_entered.connect(_on_rollover.bind(area))


func _build_drain() -> void:
	var area := Area2D.new()
	area.name = "Drain"
	area.position = Vector2(640, 2520)
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(1280, 80)
	cs.shape = shape
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_drain_body_entered)


func _build_gravity_zone() -> void:
	# Slightly stronger gravity than the classic table for snappier play,
	# scoped to this table only.
	var area := Area2D.new()
	area.position = Vector2(W * 0.5, H * 0.5)
	area.gravity_space_override = Area2D.SPACE_OVERRIDE_REPLACE
	area.gravity = 1500.0
	area.priority = 1
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(W, H)
	cs.shape = shape
	area.add_child(cs)
	add_child(area)


# ---------------------------------------------------------------- ball / flow
func _spawn_ball() -> void:
	var ball: RigidBody2D = BALL_SCENE.instantiate()
	ball.position = BALL_LAUNCH
	ball.max_contacts_reported = 10
	add_child(ball)
	_launch_charge = 0.0


func _get_ball() -> RigidBody2D:
	var balls := get_tree().get_nodes_in_group("ball")
	return balls[0] if not balls.is_empty() else null


func _physics_process(delta: float) -> void:
	var ball := _get_ball()
	if ball == null:
		return
	# Launch: charge while held in the lane, fire up on release.
	var in_lane := ball.global_position.x > 1040.0 and ball.global_position.y > 1950.0
	if in_lane and Input.is_action_pressed("launch"):
		_launch_charge = minf(_launch_charge + delta / 1.1, 1.0)
	elif in_lane and _launch_charge > 0.0:
		var speed := lerpf(1600.0, 3200.0, _launch_charge)
		ball.linear_velocity = Vector2(0, -speed)
		_launch_charge = 0.0


func _on_drain_body_entered(body: Node) -> void:
	if not body.is_in_group("ball"):
		return
	body.queue_free()
	GameManager.lose_ball()
	if not GameManager.is_game_over:
		await get_tree().create_timer(0.9).timeout
		_spawn_ball()


func _on_rollover(body: Node, _area: Area2D) -> void:
	if body.is_in_group("ball"):
		GameManager.add_score(250)


func _on_drop_hit(_target) -> void:
	_drops_down += 1
	if _drops_down >= _drops.size() and not _resetting_bank:
		_resetting_bank = true
		GameManager.add_score(5000)
		await get_tree().create_timer(1.2).timeout
		for dt in _drops:
			dt.reset_target()
		_drops_down = 0
		_resetting_bank = false


func _on_game_over() -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/table_select.tscn")
	elif event.is_action_pressed("restart") and GameManager.is_game_over:
		GameManager.reset()
		for dt in _drops:
			dt.reset_target()
		_drops_down = 0
		_resetting_bank = false
		_spawn_ball()
