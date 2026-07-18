extends Node3D
## 2.5D presentation for the Crush table. The 2D table runs unchanged inside a
## SubViewport and is projected into 3D, where a perspective Camera3D follows
## the ball at a slant. ALL gameplay stays 2D.
##
## Elevation/parallax: playfield pieces are split over three render tiers
## (base surface / mid / top) using CanvasItem.visibility_layer bits. Two extra
## SubViewports share the SAME 2D world but cull to one tier each, and each
## tier is projected onto its own transparent plane at increasing height above
## the table. With the perspective camera this produces true parallax - you
## can see around raised pieces. The ball hops to the top tier while riding a
## ramp, so ramps visibly elevate it.
##
## A simple 3D arcade cabinet (body, rails, legs, glowing backbox) sits under
## the projected playfield.

const PX_PER_M := 100.0          # 2D pixels -> 3D metres
const TABLE_SIZE := Vector2(1280, 2560)

# Elevation tiers. Mid/top pieces are MOVED into their own SubViewports, which
# render them on separate transparent planes (a viewport reliably renders only
# its own children). Their physics bodies/areas are then re-homed into the
# table's physics space at the PhysicsServer level, so gameplay stays one
# unified world. The ball stays on the base plane - correct for pinball, where
# the ball meets a bumper's skirt at floor level while the body towers above.

## Height of the mid / top tiers above the playfield, in metres.
@export var mid_height := 0.11
@export var top_height := 0.21
## Drop shadows: each tier is drawn a second time on the table surface,
## darkened and offset, which anchors the raised pieces visually.
@export var shadow_offset := Vector2(0.2, 0.16)
@export var shadow_opacity := 0.45

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

var _vp_mid: SubViewport
var _vp_top: SubViewport
var _last_ball := Vector2(1120, 2360)   # start aimed at the plunger
var _punch := 0.0


func _ready() -> void:
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP_WIDTH
	win.content_scale_size = Vector2i(1280, 720)

	# Table surface colour (drawn behind the table inside the viewport).
	var surface := ColorRect.new()
	surface.color = Color(0.16, 0.17, 0.22)
	surface.size = TABLE_SIZE
	_vp.add_child(surface)
	_vp.move_child(surface, 0)

	# The 3D camera replaces the table's own 2D camera and HUD (the HUD lives
	# in this scene instead, drawn flat on the real screen).
	var table := _vp.get_node("Table")
	var cam2d := table.get_node_or_null("Camera2D")
	if cam2d:
		cam2d.queue_free()
	var table_hud := table.get_node_or_null("HUD")
	if table_hud:
		table_hud.queue_free()

	# --- elevation tiers ---
	_vp_mid = _make_tier_viewport()
	_vp_top = _make_tier_viewport()
	var space: RID = _vp.find_world_2d().space
	for child in table.get_children().duplicate():
		var n: String = child.name
		if n.contains("Ramp") or n.contains("Rail"):
			# Ramps AND rails are elevated channels drawn as sloped 3D rails
			# (board level at the mouths, rising to top_height). Physics stays
			# 2D and untouched; only the flat art is replaced.
			child.reparent(_vp_top)
			_rehome_physics(child, space)
			_build_ramp_rails(child)
		elif n.begins_with("Bumper") or n.begins_with("DropTarget"):
			child.reparent(_vp_top)
			_rehome_physics(child, space)
		elif n.begins_with("Flipper") or n.begins_with("Slingshot") or n == "LaneGate":
			child.reparent(_vp_mid)
			_rehome_physics(child, space)
	_add_screen(_vp.get_texture(), 0.0, false)
	_add_shadow(_vp_mid.get_texture(), 0.012, 0.6)
	_add_shadow(_vp_top.get_texture(), 0.024, 1.0)
	_add_screen(_vp_mid.get_texture(), mid_height, true)
	_add_screen(_vp_top.get_texture(), top_height, true)

	_build_environment()
	_build_cabinet()

	_cam.fov = camera_fov
	_cam.position = _table_to_world(_last_ball) + Vector3(0, camera_height, camera_back)
	GameManager.impact.connect(_on_impact)


func _make_tier_viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = _vp.size
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	return vp


## Replace a ramp's flat 2D rail art with 3D ribbons that rise from board
## level at each mouth to top_height along the middle - the visual "pass"
## between levels. Built from the ramp's own Left/Right polylines.
func _build_ramp_rails(ramp: Node2D) -> void:
	# Handle ramps nested inside other ramps too (easy to create by accident
	# when instancing in the editor).
	for c in ramp.get_children():
		if c is Node2D and c.get_node_or_null("Left") != null:
			_build_ramp_rails(c)
	for rail_name in ["Left", "Right"]:
		var line: Line2D = ramp.get_node_or_null(rail_name)
		if line == null or line.points.size() < 2:
			continue
		var pts := line.points
		var n := pts.size()
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in n:
			var t := float(i) / float(n - 1)
			# smoothstep rise over the first/last 30% of the curve
			var k := clampf(minf(t, 1.0 - t) / 0.3, 0.0, 1.0)
			var h := top_height * k * k * (3.0 - 2.0 * k)
			var w := _table_to_world(line.to_global(pts[i]))
			st.add_vertex(Vector3(w.x, h + 0.03, w.z))
			st.add_vertex(Vector3(w.x, h - 0.09, w.z))
		var mesh := MeshInstance3D.new()
		mesh.mesh = st.commit()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = line.default_color   # ramps orange, rails blue
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.material_override = mat
		add_child(mesh)
		line.visible = false


## Move every physics body/area under `node` into the table's physics space so
## pieces rendered in a tier viewport still collide with the ball.
func _rehome_physics(node: Node, space: RID) -> void:
	if node is Area2D:
		PhysicsServer2D.area_set_space(node.get_rid(), space)
	elif node is CollisionObject2D:
		PhysicsServer2D.body_set_space(node.get_rid(), space)
	for c in node.get_children():
		_rehome_physics(c, space)


## A darkened, offset copy of a tier texture drawn just above the table
## surface - reads as the tier's drop shadow. Higher tiers get a larger
## offset (offset_scale) so taller pieces cast a longer shadow.
func _add_shadow(tex: Texture2D, height: float, offset_scale: float) -> void:
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = TABLE_SIZE / PX_PER_M
	mesh.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = tex
	mat.albedo_color = Color(0, 0, 0, shadow_opacity)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat
	mesh.rotation_degrees.x = -90.0
	mesh.position = Vector3(shadow_offset.x * offset_scale, height, shadow_offset.y * offset_scale)
	add_child(mesh)


func _add_screen(tex: Texture2D, height: float, transparent: bool) -> void:
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = TABLE_SIZE / PX_PER_M
	mesh.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = tex
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat
	mesh.rotation_degrees.x = -90.0
	mesh.position.y = height
	add_child(mesh)


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.01, 0.01, 0.04)
	sky_mat.sky_horizon_color = Color(0.05, 0.04, 0.11)
	sky_mat.ground_bottom_color = Color(0.01, 0.01, 0.02)
	sky_mat.ground_horizon_color = Color(0.05, 0.04, 0.11)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.7)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, 28, 0)
	light.light_energy = 1.1
	light.shadow_enabled = true
	add_child(light)


func _build_cabinet() -> void:
	var w := TABLE_SIZE.x / PX_PER_M      # 12.8
	var l := TABLE_SIZE.y / PX_PER_M      # 25.6
	var body_col := Color(0.09, 0.10, 0.15)
	var rail_col := Color(0.14, 0.15, 0.22)
	var neon := Color(0.3, 0.85, 1.0)

	# main body slab under the playfield
	_box(Vector3(w + 1.0, 1.0, l + 1.0), Vector3(0, -0.52, 0), body_col)
	# side rails + end caps (slightly proud of the playfield)
	_box(Vector3(0.35, 0.6, l + 1.0), Vector3(-(w * 0.5 + 0.32), -0.05, 0), rail_col)
	_box(Vector3(0.35, 0.6, l + 1.0), Vector3(w * 0.5 + 0.32, -0.05, 0), rail_col)
	_box(Vector3(w + 1.0, 0.6, 0.35), Vector3(0, -0.05, l * 0.5 + 0.32), rail_col)
	_box(Vector3(w + 1.0, 0.6, 0.35), Vector3(0, -0.05, -(l * 0.5 + 0.32)), rail_col)
	# neon accent strips along the rail tops
	_box(Vector3(0.08, 0.06, l + 1.0), Vector3(-(w * 0.5 + 0.32), 0.28, 0), neon, 1.6)
	_box(Vector3(0.08, 0.06, l + 1.0), Vector3(w * 0.5 + 0.32, 0.28, 0), neon, 1.6)
	# legs
	for corner in [Vector3(-w * 0.5 - 0.2, -2.2, l * 0.5 + 0.2), Vector3(w * 0.5 + 0.2, -2.2, l * 0.5 + 0.2),
			Vector3(-w * 0.5 - 0.2, -2.2, -l * 0.5 - 0.2), Vector3(w * 0.5 + 0.2, -2.2, -l * 0.5 - 0.2)]:
		_box(Vector3(0.3, 3.4, 0.3), corner, body_col)
	# backbox with glowing panel at the far (top) end
	_box(Vector3(w + 1.0, 4.6, 0.9), Vector3(0, 2.0, -(l * 0.5 + 1.0)), body_col)
	_box(Vector3(w - 1.0, 3.4, 0.1), Vector3(0, 2.1, -(l * 0.5 + 0.52)), Color(0.15, 0.1, 0.35), 1.3)
	# floor far below
	_box(Vector3(90, 0.2, 90), Vector3(0, -4.0, 0), Color(0.03, 0.03, 0.05))


func _box(size: Vector3, pos: Vector3, color: Color, emission := 0.0) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	mesh.material_override = mat
	mesh.position = pos
	add_child(mesh)


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
