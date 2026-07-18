extends Node3D
## 2.5D presentation for the Crush table. The 2D table runs unchanged inside a
## SubViewport; its texture is projected onto a plane lying flat in 3D space,
## and a perspective Camera3D follows the ball down the table at a slant -
## like standing at a real machine. ALL gameplay stays 2D.
##
## Tune the view with the camera_* exports below.

const PX_PER_M := 100.0          # 2D pixels -> 3D metres
const TABLE_SIZE := Vector2(1280, 2560)

## Camera height above the table plane.
@export var camera_height := 8.2
## How far behind the ball (toward the drain) the camera trails.
@export var camera_back := 8.0
## How far ahead of the ball the camera aims (controls the slant/pitch).
@export var look_ahead := 4.2
## How much the camera follows the ball sideways (0 = stays centred).
@export var side_follow := 0.35
@export var follow_speed := 6.0
@export var camera_fov := 52.0

@onready var _vp: SubViewport = $GameViewport
@onready var _cam: Camera3D = $Camera3D

var _last_ball := Vector2(1120, 2360)   # start aimed at the plunger
var _punch := 0.0


func _ready() -> void:
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP_WIDTH
	win.content_scale_size = Vector2i(1280, 720)

	# Table surface colour (drawn behind the table inside the viewport) so the
	# playfield reads as a distinct slab against the darker 3D void.
	var surface := ColorRect.new()
	surface.color = Color(0.16, 0.17, 0.22)
	surface.size = TABLE_SIZE
	_vp.add_child(surface)
	_vp.move_child(surface, 0)

	# Dark world backdrop behind/around the table.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.03, 0.06)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# The 3D camera replaces the table's own 2D camera and HUD (the HUD lives
	# in this scene instead, drawn flat on the real screen).
	var table := _vp.get_node("Table")
	var cam2d := table.get_node_or_null("Camera2D")
	if cam2d:
		cam2d.queue_free()
	var table_hud := table.get_node_or_null("HUD")
	if table_hud:
		table_hud.queue_free()

	# Screen: a quad lying flat, showing the live table texture.
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = TABLE_SIZE / PX_PER_M
	mesh.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _vp.get_texture()
	mesh.material_override = mat
	mesh.rotation_degrees.x = -90.0
	add_child(mesh)

	_cam.fov = camera_fov
	_cam.position = _table_to_world(_last_ball) + Vector3(0, camera_height, camera_back)
	GameManager.impact.connect(_on_impact)


func _table_to_world(p: Vector2) -> Vector3:
	return Vector3((p.x - TABLE_SIZE.x * 0.5) / PX_PER_M, 0.0, (p.y - TABLE_SIZE.y * 0.5) / PX_PER_M)


func _on_impact(strength: float) -> void:
	_punch = minf(_punch + strength * 0.02, 0.45)


func _process(delta: float) -> void:
	var balls := get_tree().get_nodes_in_group("ball")
	if not balls.is_empty():
		_last_ball = balls[0].global_position
	var b := _table_to_world(_last_ball)
	b.x *= side_follow
	b.z = clampf(b.z, -TABLE_SIZE.y * 0.5 / PX_PER_M, TABLE_SIZE.y * 0.5 / PX_PER_M)

	var target := Vector3(b.x, camera_height, b.z + camera_back)
	_cam.position = _cam.position.lerp(target, 1.0 - exp(-follow_speed * delta))
	if _punch > 0.005:
		_cam.position += Vector3(randf_range(-_punch, _punch), randf_range(-_punch, _punch), 0)
		_punch = move_toward(_punch, 0.0, 2.2 * delta)
	_cam.look_at(Vector3(b.x, 0.0, b.z - look_ahead))


func _unhandled_input(event: InputEvent) -> void:
	# Forward input into the SubViewport so the table's own handlers
	# (Esc to menu, Enter to restart) keep working.
	_vp.push_input(event)
