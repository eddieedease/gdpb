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
## Height of extruded 3D walls and flippers.
@export var wall_height := 0.16
@export var flipper_height := 0.14
## Drop shadows: each tier is drawn a second time on the table surface,
## darkened and offset. The offset direction follows the CAMERA each frame
## (shadows fall toward the viewer), so the perspective reads correctly as
## the camera moves.
@export var shadow_reach := 0.13
@export var shadow_opacity := 0.5

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
var _shadows: Array = []      # [MeshInstance3D, reach factor]
var _ball_fx := {}            # ball instance_id -> {sphere, blob, blob_mat, lift}
var _flippers: Array = []     # [flipper Node2D, MeshInstance3D]


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
	_add_shadow(_vp_mid.get_texture(), 0.012, 0.55)
	_add_shadow(_vp_top.get_texture(), 0.024, 1.0)
	_add_screen(_vp_mid.get_texture(), mid_height, true)
	_add_screen(_vp_top.get_texture(), top_height, true)

	_build_wall_visuals(table)
	_build_flipper_visuals()
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


## A channel's peak height scales with its length: short ramps stay low,
## long ones rise to the full top tier.
func _channel_peak(ramp: Node2D) -> float:
	if ramp.get("curve") == null:
		return top_height
	return top_height * clampf(ramp.curve.get_baked_length() / 800.0, 0.35, 1.0)


## Height of a channel at parameter t (0..1): smoothstep rise over the first
## and last 30%, flat along the middle. Shared by the rail ribbons, the
## support rings AND the riding ball, so they always agree.
func _channel_h(ramp: Node2D, t: float) -> float:
	var k := clampf(minf(t, 1.0 - t) / 0.3, 0.0, 1.0)
	return _channel_peak(ramp) * k * k * (3.0 - 2.0 * k)


## Channels are drawn as WIREFORM tubes (like real habitrail ramps): five
## longitudinal wires wrapping the ball (open top), a funnel that widens to
## each opening, ball-sized 'O' rings at the throats and along the run, and
## support posts. Built from the channel's centre curve.
const TUBE_R := 0.165          # wire ring radius: ball (0.14) + clearance
const WIRE_HALF := 0.008       # wire thickness
const WIRE_ANGLES := [-90.0, -45.0, -135.0, 0.0, 180.0]  # bottom, diagonals, sides

func _build_ramp_rails(ramp: Node2D) -> void:
	# Handle ramps nested inside other ramps too.
	for c in ramp.get_children():
		if c is Node2D and c.get_node_or_null("Left") != null:
			_build_ramp_rails(c)
	var left_line: Line2D = ramp.get_node_or_null("Left")
	var right_line: Line2D = ramp.get_node_or_null("Right")
	if left_line == null or ramp.get("curve") == null:
		return
	left_line.visible = false
	if right_line:
		right_line.visible = false
	var col: Color = left_line.default_color

	var cpts: PackedVector2Array = ramp.curve.tessellate(6, 3.0)
	var n := cpts.size()
	if n < 2:
		return
	# Centreline frames: position at ball-centre height, horizontal normal,
	# and tube radius (flared into a funnel over the first/last 8%).
	var centers: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var radii := PackedFloat32Array()
	for i in n:
		var t := float(i) / float(n - 1)
		var w := _table_to_world(ramp.to_global(cpts[i]))
		centers.append(Vector3(w.x, _channel_h(ramp, t) + BALL_R, w.z))
		var p_prev := cpts[maxi(i - 1, 0)]
		var p_next := cpts[mini(i + 1, n - 1)]
		var tg := (p_next - p_prev).normalized()
		normals.append(Vector3(-tg.y, 0.0, tg.x))
		var k := clampf(minf(t, 1.0 - t) / 0.08, 0.0, 1.0)
		radii.append(TUBE_R * lerpf(2.1, 1.0, k * k * (3.0 - 2.0 * k)))

	# --- the wires ---
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for phi_deg in WIRE_ANGLES:
		var phi := deg_to_rad(phi_deg)
		var cph := cos(phi)
		var sph := sin(phi)
		for i in n - 1:
			var a := centers[i] + normals[i] * cph * radii[i] + Vector3.UP * sph * radii[i]
			var b := centers[i + 1] + normals[i + 1] * cph * radii[i + 1] + Vector3.UP * sph * radii[i + 1]
			var up := Vector3.UP * WIRE_HALF
			_quad(st, a + up, b + up, b - up, a - up, col)
			_quad(st, a + normals[i] * WIRE_HALF, b + normals[i + 1] * WIRE_HALF,
					b - normals[i + 1] * WIRE_HALF, a - normals[i] * WIRE_HALF, col)
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	add_child(mesh)

	# --- shadow strip on the board, fading in with height ---
	var sh := SurfaceTool.new()
	sh.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in n:
		var lift := centers[i].y - BALL_R
		var a2 := clampf(lift / maxf(_channel_peak(ramp), 0.001), 0.0, 1.0) * 0.4
		var s := Vector3(centers[i].x, 0.012, centers[i].z)
		sh.set_color(Color(0, 0, 0, a2))
		sh.add_vertex(s + normals[i] * TUBE_R)
		sh.set_color(Color(0, 0, 0, a2))
		sh.add_vertex(s - normals[i] * TUBE_R)
	var smesh := MeshInstance3D.new()
	smesh.mesh = sh.commit()
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.vertex_color_use_as_albedo = true
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.cull_mode = BaseMaterial3D.CULL_DISABLED
	smesh.material_override = smat
	add_child(smesh)
	_shadows.append([smesh, 1.0])

	# --- 'O' rings: at each funnel throat and every ~180px along the tube ---
	var length: float = ramp.curve.get_baked_length()
	var ring_ts: Array[float] = [0.08, 0.92]
	var between := int(length * 0.84 / 180.0)
	for r in range(1, between):
		ring_ts.append(0.08 + 0.84 * float(r) / float(between))
	for t in ring_ts:
		var idx := clampi(int(t * (n - 1)), 0, n - 1)
		var c3 := centers[idx]
		var i2 := clampi(idx + 1, 0, n - 1)
		var i1 := clampi(idx - 1, 0, n - 1)
		var tang3 := centers[i2] - centers[i1]
		var yaw := atan2(tang3.x, tang3.z)
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = TUBE_R - 0.006
		torus.outer_radius = TUBE_R + 0.016
		ring.mesh = torus
		var rmat := StandardMaterial3D.new()
		rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rmat.albedo_color = col.lightened(0.2)
		ring.material_override = rmat
		ring.position = c3
		ring.rotation = Vector3(PI * 0.5, yaw, 0.0)
		add_child(ring)
		var post_h := c3.y - TUBE_R
		if post_h > 0.03:
			var post := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.022, post_h, 0.022)
			post.mesh = box
			var pmat := StandardMaterial3D.new()
			pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			pmat.albedo_color = Color(0.25, 0.28, 0.38)
			post.material_override = pmat
			post.position = Vector3(c3.x, post_h * 0.5, c3.z)
			add_child(post)


## Move every physics body/area under `node` into the table's physics space so
## pieces rendered in a tier viewport still collide with the ball.
func _rehome_physics(node: Node, space: RID) -> void:
	if node is Area2D:
		PhysicsServer2D.area_set_space(node.get_rid(), space)
	elif node is CollisionObject2D:
		PhysicsServer2D.body_set_space(node.get_rid(), space)
	for c in node.get_children():
		_rehome_physics(c, space)


## A darkened copy of a tier texture drawn just above the table surface -
## the tier's drop shadow. Its offset is set every frame from the camera
## direction (see _process); taller tiers get a larger reach factor.
func _add_shadow(tex: Texture2D, height: float, reach_factor: float) -> void:
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
	mesh.position = Vector3(0, height, 0)
	add_child(mesh)
	_shadows.append([mesh, reach_factor])


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


# ---------------------------------------------------------------- 3D walls
## Extrude every Wall / CurvedWall polyline into a low solid 3D wall:
## darker side faces + a bright top cap in the line's colour. The flat 2D
## line is hidden.
func _build_wall_visuals(table: Node2D) -> void:
	for child in table.get_children():
		if child is Line2D and child.get("wall_bounce") != null:
			_extrude_wall(child, child)
		elif child is Path2D and child.get("wall_bounce") != null:
			var line: Line2D = child.get_node_or_null("Line")
			if line:
				_extrude_wall(line, line)


func _extrude_wall(line: Line2D, space_ref: Node2D) -> void:
	var pts := line.points
	var n := pts.size()
	if n < 2:
		return
	var c := line.default_color
	var side := Color(c.r * 0.45, c.g * 0.45, c.b * 0.45)
	var w3: Array[Vector3] = []
	var perp: Array[Vector3] = []
	for i in n:
		w3.append(_table_to_world(space_ref.to_global(pts[i])))
		var p_prev := pts[maxi(i - 1, 0)]
		var p_next := pts[mini(i + 1, n - 1)]
		var tang := (p_next - p_prev).normalized()
		perp.append(Vector3(-tang.y, 0.0, tang.x) * 0.032)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n - 1:
		var ai := w3[i] + perp[i]
		var ao := w3[i] - perp[i]
		var bi := w3[i + 1] + perp[i + 1]
		var bo := w3[i + 1] - perp[i + 1]
		var h := Vector3(0, wall_height, 0)
		_quad(st, ai, bi, bi + h, ai + h, side)          # inner face
		_quad(st, ao + h, bo + h, bo, ao, side)          # outer face
		_quad(st, ai + h, bi + h, bo + h, ao + h, c)     # top cap
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	add_child(mesh)
	line.visible = false


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c2: Vector3, d: Vector3, col: Color) -> void:
	st.set_color(col)
	st.add_vertex(a)
	st.set_color(col)
	st.add_vertex(b)
	st.set_color(col)
	st.add_vertex(c2)
	st.set_color(col)
	st.add_vertex(a)
	st.set_color(col)
	st.add_vertex(c2)
	st.set_color(col)
	st.add_vertex(d)


# ---------------------------------------------------------------- 3D flippers
## Extrude each flipper's traced collision polygon into a solid paddle prism,
## driven every frame by the 2D flipper's position/rotation.
func _build_flipper_visuals() -> void:
	for f in _vp_mid.get_children():
		if not (f is Node2D) or not f.name.contains("Flipper"):
			continue
		var poly_node: CollisionPolygon2D = f.get_node_or_null("CollisionPolygon2D")
		if poly_node == null:
			continue
		var spr: CanvasItem = f.get_node_or_null("Sprite2D")
		if spr:
			spr.visible = false
		var pts := poly_node.polygon
		var scaled := PackedVector2Array()
		for p in pts:
			scaled.append(p * f.scale)
		var top := Color(0.5, 0.68, 1.0)
		var side := Color(0.2, 0.3, 0.55)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var idx := Geometry2D.triangulate_polygon(scaled)
		for i in idx:
			var p := scaled[i]
			st.set_color(top)
			st.add_vertex(Vector3(p.x / PX_PER_M, flipper_height, p.y / PX_PER_M))
		var m := scaled.size()
		for i in m:
			var a2 := scaled[i]
			var b2 := scaled[(i + 1) % m]
			var a3 := Vector3(a2.x / PX_PER_M, 0.01, a2.y / PX_PER_M)
			var b3 := Vector3(b2.x / PX_PER_M, 0.01, b2.y / PX_PER_M)
			var h := Vector3(0, flipper_height, 0)
			_quad(st, a3, b3, b3 + h, a3 + h, side)
		var mesh := MeshInstance3D.new()
		mesh.mesh = st.commit()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.material_override = mat
		add_child(mesh)
		_flippers.append([f, mesh])


# ---------------------------------------------------------------- 3D ball
const BALL_R := 0.14   # 14px 2D ball radius

func _make_ball_fx() -> Dictionary:
	var sphere := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = BALL_R
	sm.height = BALL_R * 2.0
	sphere.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.82, 0.84, 0.9)
	mat.metallic = 0.7
	mat.roughness = 0.25
	sphere.material_override = mat
	add_child(sphere)

	var blob := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = BALL_R * 1.15
	bm.height = 0.02
	blob.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.albedo_color = Color(0, 0, 0, 0.45)
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blob.material_override = bmat
	add_child(blob)
	return {"sphere": sphere, "blob": blob, "blob_mat": bmat, "lift": 0.0}


## The 2D ball sprite is hidden and replaced with a shaded 3D sphere that
## lifts to top-tier height while riding a ramp/rail - real elevation.
func _update_balls(delta: float, shadow_dir: Vector2) -> void:
	var seen := {}
	for b in get_tree().get_nodes_in_group("ball"):
		if not (b is Node2D):
			continue
		var id := b.get_instance_id()
		seen[id] = true
		if not _ball_fx.has(id):
			var spr: CanvasItem = b.get_node_or_null("Sprite2D")
			if spr:
				spr.visible = false
			_ball_fx[id] = _make_ball_fx()
		var fx: Dictionary = _ball_fx[id]
		# While riding a channel, the ball's height follows that channel's own
		# slope profile at its current position - it rolls up the entry, along
		# the top, and down the exit in sync with the rail visuals.
		var target_lift := 0.0
		if b.get_meta("on_ramp", false):
			var chan = b.get_meta("channel", null)
			if chan != null and is_instance_valid(chan) and chan.get("curve") != null:
				var local: Vector2 = chan.to_local(b.global_position)
				var off: float = chan.curve.get_closest_offset(local)
				target_lift = _channel_h(chan, off / maxf(chan.curve.get_baked_length(), 1.0))
			else:
				target_lift = top_height
		var lift: float = lerpf(fx.lift, target_lift, 1.0 - exp(-16.0 * delta))
		fx.lift = lift
		var w := _table_to_world(b.global_position)
		fx.sphere.position = Vector3(w.x, BALL_R + lift, w.z)
		var reach: float = shadow_reach * (0.5 + lift * 6.0)
		fx.blob.position = Vector3(w.x + shadow_dir.x * reach, 0.014, w.z + shadow_dir.y * reach)
		var k: float = clampf(lift / maxf(top_height, 0.01), 0.0, 1.0)
		fx.blob_mat.albedo_color = Color(0, 0, 0, lerpf(0.45, 0.25, k))
	for id in _ball_fx.keys().duplicate():
		if not seen.has(id):
			_ball_fx[id].sphere.queue_free()
			_ball_fx[id].blob.queue_free()
			_ball_fx.erase(id)


func _on_impact(strength: float) -> void:
	_punch = minf(_punch + strength * 0.02, 0.45)


func _process(delta: float) -> void:
	var balls := get_tree().get_nodes_in_group("ball")
	if not balls.is_empty():
		_last_ball = balls[0].global_position

	# Shadow direction is camera-relative but falls mostly SIDEWAYS to the
	# view (plus slightly toward the viewer): a shadow cast straight toward
	# the camera hides behind the piece itself and reads as nothing.
	var fwd := -_cam.global_transform.basis.z
	var g := Vector2(fwd.x, fwd.z)
	var shadow_dir := Vector2(0.85, 0.4).normalized()
	if g.length() > 0.01:
		g = g.normalized()
		var right := Vector2(-g.y, g.x)
		shadow_dir = (right * 0.85 - g * 0.4).normalized()
	for s in _shadows:
		var m: MeshInstance3D = s[0]
		var f: float = s[1]
		m.position.x = shadow_dir.x * shadow_reach * f
		m.position.z = shadow_dir.y * shadow_reach * f
	_update_balls(delta, shadow_dir)

	# 3D flipper paddles mirror their 2D physics flippers.
	for entry in _flippers:
		var f: Node2D = entry[0]
		var m: MeshInstance3D = entry[1]
		if not is_instance_valid(f):
			continue
		var w := _table_to_world(f.global_position)
		m.position = Vector3(w.x, 0.0, w.z)
		m.rotation.y = -f.rotation

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
