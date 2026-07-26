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

## Physics layer 9: the upper deck, a genuinely separate level. Deck pieces
## (its flippers, targets and cage walls) live on this layer ALONE, and a ball
## is moved onto it only when a "ToDeck" channel delivers it up there. So a
## playfield ball can never touch the deck just by rolling under its footprint
## - the deck is reachable by the ramp and nothing else - and a ball up on the
## deck can't touch the playfield below it. It leaves only by falling off the
## deck's open bottom edge, past its flippers.
const DECK_BIT := 1 << 8

## The apron - the board margin around the playfield artwork. Soft, wide
## diagonal stripes cycling through the three accents, like a deck chair or a
## beach towel. Kept low-contrast on purpose: it should furnish the empty
## border, never compete with the artwork or the pieces sitting on top of it.
const APRON_SHADER := "
shader_type canvas_item;
uniform vec3 base_color;
uniform vec3 rim_color;
uniform vec3 sheen_color;
uniform vec2 table_size;
uniform vec4 art_rect;   // x, y, w, h in table pixels; zero = no artwork
void fragment() {
	vec2 p = UV * table_size;
	// How far inside the artwork this pixel is, and a soft mask for it. The art
	// is semi-transparent, so anything drawn under it shows through - the apron
	// must fade to a plain base there or it reads as painted over the picture.
	vec2 inset = min(p - art_rect.xy, art_rect.xy + art_rect.zw - p);
	vec2 fade = smoothstep(vec2(0.0), vec2(70.0), inset);
	float under_art = fade.x * fade.y;
	float show = 1.0 - under_art;

	// Clean graded surface rather than stripes: lighter at the top of the
	// table, settling darker toward the player.
	vec3 col = mix(base_color, base_color * 0.78, smoothstep(0.0, 1.0, UV.y));

	// Backlit trim hugging the playfield edge - the apron reads as a lit
	// surround instead of decorated flooring.
	float edge = min(inset.x, inset.y);
	float rim = exp(-abs(edge) / 46.0);
	col += rim_color * rim * 0.55 * show;

	// A slow sheen travelling the length of the cabinet, so the surround is
	// alive without any pattern to look at.
	float t = fract((UV.y * 0.72 + UV.x * 0.28) - TIME * 0.055);
	float band = smoothstep(0.0, 0.06, t) * smoothstep(0.30, 0.12, t);
	col += sheen_color * band * 0.14 * show;

	COLOR = vec4(col, 1.0);
}
"

# Elevation tiers. Mid/top pieces are MOVED into their own SubViewports, which
# render them on separate transparent planes (a viewport reliably renders only
# its own children). Their physics bodies/areas are then re-homed into the
# table's physics space at the PhysicsServer level, so gameplay stays one
# unified world. The ball stays on the base plane - correct for pinball, where
# the ball meets a bumper's skirt at floor level while the body towers above.

## Height of the mid / top tiers above the playfield, in metres.
@export var mid_height := 0.14
@export var top_height := 0.26
## How high ramps and rails arc at their peak. Kept SEPARATE from top_height:
## that one also positions the pieces standing on the top tier, so raising the
## channels through it would launch the bumpers into the air with them.
@export var channel_height := 0.46
## Upper deck: a genuinely raised sub-playfield (its own flipper bank etc,
## node names starting with "Deck") rendered well above the top tier. Must stay
## clear of channel_height, or a channel arcing under the deck would poke up
## through its floor plate.
@export var deck_height := 0.68
@export_group("Colours")
## Everything the 3D scene is built from reads these, so the whole cabinet and
## backdrop can be re-themed from the inspector without touching code.
## Defaults are a "tropical pool party" set to go with the playfield art.
@export var cabinet_color := Color(0.055, 0.07, 0.15)
@export var rail_color := Color(0.10, 0.13, 0.24)
## The playfield BOARD itself - the apron stripes sit on this and the
## semi-transparent artwork is blended over it. Deliberately light and warm:
## the board used to share the void's dark blue-grey, which left the table
## looking bleak and made it blend into the 3D backdrop instead of reading as
## a lit surface sitting in front of it.
@export var board_color := Color(0.82, 0.79, 0.74)
## Three accents, used in rotation for neon trim, the deck and the floaters.
@export var accent_warm := Color(1.0, 0.42, 0.36)      # coral
@export var accent_cool := Color(0.13, 0.83, 0.78)     # turquoise
@export var accent_bright := Color(1.0, 0.80, 0.27)    # sunshine yellow
## The void the cabinet floats in, and the glow along its horizon.
@export var void_color := Color(0.035, 0.05, 0.14)
@export var horizon_color := Color(0.20, 0.13, 0.33)
## Default colour for flippers. Any individual flipper can override this by
## setting its own `modulate` on the instance in the 2D editor.
@export var flipper_color := Color(0.5, 0.68, 1.0)
## How many neon shapes drift around the cabinet (0 disables them).
@export var floater_count := 16
@export_group("")

## Marquee text on the backbox, above the live score readout.
@export var backbox_title := "NEON CRUSH"
## How solid the ramp/rail tubes look. Low enough to watch the ball travel
## inside them; raise it for frostier, more obviously glassy tubes.
@export_range(0.05, 0.9) var tube_opacity := 0.38

## Height of extruded 3D walls and flippers.
@export var wall_height := 0.34
@export var flipper_height := 0.22
## Solid geometry built from collision shapes for the scoring pieces.
@export var target_height := 0.30
## How deep a drop target's plate is - deliberately thin, it is a standing
## card the ball knocks flat, not a block.
@export var target_thickness := 0.055
## Deck targets stand taller - they are far up the table and seen steeply.
@export var deck_target_height := 0.48
@export var bumper_height := 0.42
@export var slingshot_height := 0.26
@export var gate_height := 0.20
@export var spinner_height := 0.19
## Drop shadows: each tier is drawn a second time on the table surface,
## darkened and offset. The offset direction follows the CAMERA each frame
## (shadows fall toward the viewer), so the perspective reads correctly as
## the camera moves.
##
## Keep this SMALL. A raised piece is drawn on a plane above the board, so the
## perspective camera ALREADY displaces it from its true ground position -
## that displacement is the depth cue. Adding a large shadow offset on top of
## it pushes the shadow away a second time and the shadow visibly detaches
## from the piece. Near-zero reach parks the shadow under the piece's actual
## ground position and lets the parallax do the work.
@export var shadow_reach := 0.04
@export var shadow_opacity := 0.5

## Camera height above the table plane.
@export var camera_height := 8.2
## How far behind the ball (toward the drain) the camera trails.
@export var camera_back := 8.0
## How far ahead of the ball the camera aims (controls the slant/pitch).
@export var look_ahead := 4.2
## How much the camera follows the ball sideways (0 = stays centred).
@export var side_follow := 0.35
## How far toward the player the camera is allowed to trail, in metres from the
## table centre. Lower = it hangs back less when the ball is at the bottom.
@export var camera_near_limit := 9.5
@export var follow_speed := 6.0
@export var camera_fov := 52.0

@onready var _vp: SubViewport = $GameViewport
@onready var _cam: Camera3D = $Camera3D

var _vp_mid: SubViewport
var _vp_top: SubViewport
var _vp_deck: SubViewport
var _last_ball := Vector2(1120, 2360)   # start aimed at the plunger
var _punch := 0.0
var _shadows: Array = []      # [MeshInstance3D, reach factor]
var _ball_fx := {}            # ball instance_id -> {sphere, blob, blob_mat, lift}
var _flippers: Array = []     # [flipper Node2D, MeshInstance3D, base_height]
var _floaters: Array = []     # background neon shapes; see _build_floating_shapes
var _elapsed := 0.0
var _score_label: Label3D
var _balls_label: Label3D
var _multiball_label: Label3D
var _multiball_lit := false
var _multiball_tween: Tween
## Mirrors table_game's multiball requirements, purely for the legend text.
const MULTIBALL_DECK_TARGET := 2
const MULTIBALL_MAIN_TARGET := 3
var _targets: Array = []      # drop-target blocks; see _build_target_visuals
var _lights: Array = []       # rollover discs; see _build_rollover_visuals
var _spinners: Array = []   # spinner blades; see _build_spinner_visuals
## Table-space footprint of the upper deck (padded bounding box of its
## content). Defines where the cage walls go and how far a ball must fall
## past the deck flippers before it rejoins the playfield below.
var _deck_rect := Rect2()
## The deck's outline in table space, straight from the DeckBounds polygon
## (empty if that node is missing). The cage walls trace this exactly, so the
## shape drawn in the editor is the shape the ball is contained by.
var _deck_poly := PackedVector2Array()


func _ready() -> void:
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP_WIDTH
	win.content_scale_size = Vector2i(1280, 720)

	var table := _vp.get_node("Table")

	# The surround under everything - it shows in the apron, the margin the
	# playfield artwork does not reach. See APRON_SHADER for what is drawn there.

	# Its z_index MUST stay below the art's (PlayfieldArt sits at -100):
	# being merely first in tree order is not enough, since z_index wins over
	# tree order and a z=0 rect would paint straight over a z=-100 sprite.
	# That mismatch is invisible in the editor, where this node doesn't exist.
	var surface := ColorRect.new()
	surface.size = TABLE_SIZE
	surface.z_index = -1000
	var apron_sh := Shader.new()
	apron_sh.code = APRON_SHADER
	var apron_mat := ShaderMaterial.new()
	apron_mat.shader = apron_sh
	apron_mat.set_shader_parameter("base_color", _v3(board_color))
	apron_mat.set_shader_parameter("rim_color", _v3(accent_cool))
	apron_mat.set_shader_parameter("sheen_color", _v3(accent_bright))
	apron_mat.set_shader_parameter("table_size", TABLE_SIZE)
	apron_mat.set_shader_parameter("art_rect", _playfield_art_rect(table))
	surface.material = apron_mat
	_vp.add_child(surface)
	_vp.move_child(surface, 0)

	# NOTE: the playfield artwork under the pieces is NOT built here - it is a
	# real "PlayfieldArt" Sprite2D in the table scene, so it can be positioned
	# and scaled against the actual walls in the 2D editor.

	# The 3D camera replaces the table's own 2D camera and HUD (the HUD lives
	# in this scene instead, drawn flat on the real screen).
	var cam2d := table.get_node_or_null("Camera2D")
	if cam2d:
		cam2d.queue_free()
	var table_hud := table.get_node_or_null("HUD")
	if table_hud:
		table_hud.queue_free()

	# --- elevation tiers ---
	_vp_mid = _make_tier_viewport()
	_vp_top = _make_tier_viewport()
	_vp_deck = _make_tier_viewport()
	var space: RID = _vp.find_world_2d().space
	for child in table.get_children().duplicate():
		var n: String = child.name
		if n.begins_with("Deck"):
			# Upper-deck pieces (its own flipper bank, targets, ...) get their
			# own much-higher tier - a genuinely separate raised platform - and
			# their own physics layer, so only a ball that has been delivered
			# to the deck can interact with them.
			child.reparent(_vp_deck)
			_rehome_physics(child, space)
			_set_deck_layer(child)
		elif n.contains("Ramp") or n.contains("Rail"):
			# Ramps AND rails are elevated channels drawn as sloped 3D rails
			# (board level at the mouths, rising to top_height). Physics stays
			# 2D and untouched; only the flat art is replaced.
			child.reparent(_vp_top)
			_rehome_physics(child, space)
			_build_ramp_rails(child)
			# A deck-feed channel hands its ball to the deck on a full ride.
			if n.contains("ToDeck") and child.has_signal("ball_released"):
				child.ball_released.connect(_on_deck_channel_released)
		elif n.begins_with("Bumper") or n.begins_with("DropTarget"):
			child.reparent(_vp_top)
			_rehome_physics(child, space)
		# begins_with, not ==: a table can hold several gates ("LaneGate2"...),
		# and an exact match left the extra ones behind on the base tier.
		elif n.begins_with("Flipper") or n.begins_with("Slingshot") or n.begins_with("LaneGate"):
			child.reparent(_vp_mid)
			_rehome_physics(child, space)
	_add_screen(_vp.get_texture(), 0.0, false)
	_add_shadow(_vp_mid.get_texture(), 0.012, 0.55)
	_add_shadow(_vp_top.get_texture(), 0.024, 1.0)
	_add_shadow(_vp_deck.get_texture(), 0.036, 1.8)
	_add_screen(_vp_mid.get_texture(), mid_height, true)
	_add_screen(_vp_top.get_texture(), top_height, true)
	_add_screen(_vp_deck.get_texture(), deck_height, true)

	_compute_deck_rect()
	_build_wall_visuals(table)
	_build_flipper_visuals()
	_build_target_visuals()
	_build_kicker_visuals()
	_build_gate_visuals(table)
	_build_rollover_visuals()
	_build_spinner_visuals()
	_build_deck_platform()
	_build_deck_cage(table)
	_build_environment()
	_build_cabinet()

	_cam.fov = camera_fov
	_cam.position = _table_to_world(_last_ball) + Vector3(0, camera_height, camera_back)
	GameManager.impact.connect(_on_impact)
	GameManager.points_scored.connect(_on_points_scored)
	GameManager.bank_completed.connect(_on_bank_completed)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	SoundManager.play_game_music()


## Confetti when a whole group is cleared: a one-shot burst of little coloured
## cards thrown up over the group, tumbling as they fall. Frees itself once the
## last card has died, so nothing accumulates over a long game.
func _on_bank_completed(at: Vector2) -> void:
	var w := _table_to_world(at)
	var p := GPUParticles3D.new()
	p.amount = 140
	p.lifetime = 1.9
	p.one_shot = true
	p.explosiveness = 0.92
	p.position = Vector3(w.x, 0.35, w.z)

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.5
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 55.0
	pm.initial_velocity_min = 2.4
	pm.initial_velocity_max = 5.2
	pm.gravity = Vector3(0, -6.5, 0)
	pm.damping_min = 0.4
	pm.damping_max = 1.2
	# Tumble: confetti that does not spin just reads as falling dots.
	pm.angular_velocity_min = -420.0
	pm.angular_velocity_max = 420.0
	pm.scale_min = 0.5
	pm.scale_max = 1.15
	# Random colour per card, drawn across the table's accents.
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	grad.colors = PackedColorArray([accent_warm, accent_cool, accent_bright,
			accent_warm.lerp(accent_bright, 0.5), Color.WHITE])
	var gtex := GradientTexture1D.new()
	gtex.gradient = grad
	pm.color_initial_ramp = gtex
	# Fade out at the end of life so they vanish rather than blinking off.
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.75, 1.0])
	fade.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	var ftex := GradientTexture1D.new()
	ftex.gradient = fade
	pm.color_ramp = ftex
	p.process_material = pm

	var card := QuadMesh.new()
	card.size = Vector2(0.09, 0.055)
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.vertex_color_use_as_albedo = true
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	card.material = cmat
	p.draw_pass_1 = card

	add_child(p)
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.6).timeout.connect(p.queue_free)


## Yellow "+N" popup rising from the piece that scored.
func _on_points_scored(points: int, at: Vector2) -> void:
	var lbl := Label3D.new()
	lbl.text = "+%d" % points
	lbl.font_size = 110
	lbl.outline_size = 26
	lbl.modulate = Color(1.0, 0.88, 0.2)
	lbl.outline_modulate = Color(0.25, 0.12, 0.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	var w := _table_to_world(at)
	lbl.position = Vector3(w.x, 0.5, w.z)
	add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", 1.3, 0.85).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.85).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(lbl.queue_free)


func _make_tier_viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = _vp.size
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	return vp


## A channel's peak height scales with its length: short ramps stay low,
## long ones rise to the full top tier - EXCEPT a channel whose name marks it
## as feeding the upper deck ("ToDeck"), which rises all the way to
## deck_height so its exit lands the ball smoothly at the deck's own
## elevation instead of popping up an extra step.
func _channel_peak(ramp: Node2D) -> float:
	if ramp.get("curve") == null:
		return channel_height
	# A dedicated deck-feed channel always reaches the deck's own height,
	# however long or short it is - it's not "how much pop should this piece
	# have" (that's what the length scaling below is for), it's "arrive at
	# this specific existing platform".
	if ramp.name.contains("ToDeck"):
		return deck_height
	# get_baked_length() is purely local to the curve resource - it knows
	# nothing about the node's own scale, so a scaled-up instance (e.g. one
	# stretching a small default curve to span a long distance) was always
	# being measured as if unscaled. Multiply by scale to get the true
	# world-space length.
	var length: float = ramp.curve.get_baked_length() * ramp.scale.x
	return channel_height * clampf(length / 800.0, 0.35, 1.0)


## Height of a channel at parameter t (0..1). Shared by the rail ribbons, the
## support rings AND the riding ball, so they always agree.
func _channel_h(ramp: Node2D, t: float) -> float:
	if ramp.name.contains("ToDeck"):
		# One-way lift: rise smoothly then STAY at the deck's height for a
		# seamless handoff - a ramp that arcs back down to the playfield
		# would dump the ball partway back down right as it reaches the deck.
		var k := clampf(t / 0.6, 0.0, 1.0)
		return _channel_peak(ramp) * k * k * (3.0 - 2.0 * k)
	var k := clampf(minf(t, 1.0 - t) / 0.3, 0.0, 1.0)
	return _channel_peak(ramp) * k * k * (3.0 - 2.0 * k)


## Channels are drawn as WIREFORM tubes (like real habitrail ramps): five
## longitudinal wires wrapping the ball (open top), a funnel that widens to
## each opening, ball-sized 'O' rings at the throats and along the run, and
## support posts. Built from the channel's centre curve.
const TUBE_R := 0.165          # tube radius: ball (0.14) + clearance
const WIRE_HALF := 0.008       # bottom-rail thickness
const TUBE_SEGS := 14          # facets around the sleeve

## Sample a curve at evenly spaced points along its length. Curve2D.tessellate()
## is adaptive - a long but nearly-straight stretch can collapse to just its
## raw control points (as few as 2-3 for a whole 800px channel), which is too
## sparse for the funnel/ring placement math below and was producing
## degenerate (zero-length-interval / non-finite) geometry. Fixed spacing
## guarantees a sane minimum point count regardless of curve shape.
func _sample_curve_even(curve: Curve2D, min_points: int = 40) -> PackedVector2Array:
	var length := curve.get_baked_length()
	var n := maxi(min_points, int(length / 20.0))
	var pts := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / float(n)
		pts.append(curve.sample_baked(t * length))
	return pts


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

	var cpts: PackedVector2Array = _sample_curve_even(ramp.curve)
	var n := cpts.size()
	if n < 2:
		return
	# Centreline positions first, at ball-centre height, with the tube radius
	# flared into a funnel over the first/last 10%.
	var centers: Array[Vector3] = []
	var radii := PackedFloat32Array()
	for i in n:
		var t := float(i) / float(n - 1)
		var w := _table_to_world(ramp.to_global(cpts[i]))
		centers.append(Vector3(w.x, _channel_h(ramp, t) + BALL_R, w.z))
		# Gentle funnel. A hard 2.1x flare made the mouths fan out into a
		# splayed mess (nothing ties the sleeve together out there), which read
		# as the rail fraying rather than opening up. A modest flare plus a rim
		# ring at the very end (below) gives a clean mouth.
		var k := clampf(minf(t, 1.0 - t) / 0.10, 0.0, 1.0)
		radii.append(TUBE_R * lerpf(1.45, 1.0, k * k * (3.0 - 2.0 * k)))

	# Then the cross-section frame at each sample, square to the tube's own 3D
	# direction. This MUST be derived from the WORLD centres above, never from
	# the curve's local points: the node's rotation sits between the two, so a
	# local-space normal points the wrong way round the tube. At 90 degrees of
	# node rotation it ends up pointing straight ALONG the tube and the sleeve
	# collapses to a flat ribbon - which is why the tube never filled its rings.
	var tangents: Array[Vector3] = []
	var side: Array[Vector3] = []
	var lift: Array[Vector3] = []
	for i in n:
		var tg: Vector3 = centers[mini(i + 1, n - 1)] - centers[maxi(i - 1, 0)]
		if tg.length_squared() < 0.000001:
			tg = Vector3.FORWARD
		tg = tg.normalized()
		var ref := Vector3.UP if absf(tg.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		var rgt := ref.cross(tg).normalized()
		tangents.append(tg)
		side.append(rgt)
		lift.append(tg.cross(rgt).normalized())

	# --- the tube: a closed, see-through sleeve swept along the curve, so the
	# ball is visibly travelling INSIDE the channel rather than along a set of
	# wires. Drawn transparent and without writing depth, so the opaque ball
	# (already in the depth buffer by the time transparent surfaces draw) shows
	# through the near wall while the far wall still reads behind it.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n - 1:
		for s in TUBE_SEGS:
			var a0 := TAU * float(s) / float(TUBE_SEGS)
			var a1 := TAU * float(s + 1) / float(TUBE_SEGS)
			# Shade the sleeve by angle so the tube has visible form instead of
			# reading as one flat wash of colour.
			var shade := 0.55 + 0.45 * (0.5 - 0.5 * cos(a0))
			var tc := Color(col.r * shade, col.g * shade, col.b * shade, 1.0)
			_quad(st,
					_tube_pt(centers[i], side[i], lift[i], radii[i], a0),
					_tube_pt(centers[i + 1], side[i + 1], lift[i + 1], radii[i + 1], a0),
					_tube_pt(centers[i + 1], side[i + 1], lift[i + 1], radii[i + 1], a1),
					_tube_pt(centers[i], side[i], lift[i], radii[i], a1), tc)
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	# Left SHADED on purpose: lighting across the curved sleeve is what makes
	# it read as a glass tube. Unshaded, it was just a flat wash of colour so
	# faint you could not tell there was a tube there at all.
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, tube_opacity)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.15
	mat.metallic = 0.35
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 0.45
	# A bright edge where the sleeve turns away from the viewer gives the tube
	# a visible silhouette without making it opaque.
	mat.rim_enabled = true
	mat.rim = 0.9
	mat.rim_tint = 0.6
	mesh.material_override = mat
	add_child(mesh)

	# An opaque rail along the bottom of the sleeve - the surface the ball
	# actually appears to roll on, and what stops a fully transparent tube
	# looking like it has no floor.
	var rail := SurfaceTool.new()
	rail.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n - 1:
		# "Down" is the tube's OWN down, so the rail stays on the floor of the
		# sleeve as it banks, rather than drifting off it.
		var a := centers[i] - lift[i] * radii[i]
		var b := centers[i + 1] - lift[i + 1] * radii[i + 1]
		_quad(rail, a + lift[i] * WIRE_HALF, b + lift[i + 1] * WIRE_HALF,
				b - lift[i + 1] * WIRE_HALF, a - lift[i] * WIRE_HALF, col)
		_quad(rail, a + side[i] * WIRE_HALF, b + side[i + 1] * WIRE_HALF,
				b - side[i + 1] * WIRE_HALF, a - side[i] * WIRE_HALF, col)
	var rmesh := MeshInstance3D.new()
	rmesh.mesh = rail.commit()
	var railmat := StandardMaterial3D.new()
	railmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	railmat.vertex_color_use_as_albedo = true
	railmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rmesh.material_override = railmat
	add_child(rmesh)

	# --- shadow strip on the board, fading in with height ---
	var sh := SurfaceTool.new()
	sh.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in n:
		var height := centers[i].y - BALL_R
		var a2 := clampf(height / maxf(_channel_peak(ramp), 0.001), 0.0, 1.0) * 0.4
		var s := Vector3(centers[i].x, 0.012, centers[i].z)
		# Flattened to the board: the shadow spreads sideways, not along the
		# tube's banked frame.
		var flat := Vector3(side[i].x, 0.0, side[i].z)
		flat = flat.normalized() * TUBE_R if flat.length() > 0.001 else Vector3(TUBE_R, 0, 0)
		sh.set_color(Color(0, 0, 0, a2))
		sh.add_vertex(s + flat)
		sh.set_color(Color(0, 0, 0, a2))
		sh.add_vertex(s - flat)
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

	# --- 'O' rings: a rim at each mouth, a throat ring just inside it, and
	# one every ~180px along the tube. The t=0/t=1 rims are what stop the
	# wires ending in mid-air; each ring is sized to the tube's local radius
	# so the flared mouths get correspondingly larger rims.
	var length: float = ramp.curve.get_baked_length()
	var ring_ts: Array[float] = [0.0, 0.08, 0.92, 1.0]
	var between := int(length * 0.84 / 180.0)
	for r in range(1, between):
		ring_ts.append(0.08 + 0.84 * float(r) / float(between))
	for t in ring_ts:
		var idx := clampi(int(t * (n - 1)), 0, n - 1)
		var c3 := centers[idx]
		var rr: float = radii[idx]
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = rr - 0.006
		torus.outer_radius = rr + 0.016
		ring.mesh = torus
		var rmat := StandardMaterial3D.new()
		rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rmat.albedo_color = col.lightened(0.2)
		ring.material_override = rmat
		# Exactly the frame the sleeve was swept with, so a ring can never
		# disagree with the tube it wraps. A TorusMesh's hole runs along its own
		# +Y, which is why the tangent goes in the basis's Y column.
		ring.transform = Transform3D(Basis(side[idx], tangents[idx], lift[idx]), c3)
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


## Table-space footprint of the upper deck: its floor plate, its cage walls
## and the line a ball must fall past to leave it all come from this rect.
##
## Preferred source is an explicit "DeckBounds" Polygon2D inside deck.tscn -
## a shape you can SEE and drag in the 2D editor, so the deck can be designed
## against the rest of the table instead of being an invisible rectangle
## inferred at runtime. Falls back to a padded bounding box of the deck's
## contents if that node is missing.
func _compute_deck_rect() -> void:
	for c in _descendants(_vp_deck):
		if c.name == "DeckBounds" and c is Polygon2D and c.polygon.size() >= 3:
			var bmin := Vector2(INF, INF)
			var bmax := Vector2(-INF, -INF)
			_deck_poly = PackedVector2Array()
			for p in c.polygon:
				# The node's own transform counts - the shape can be moved and
				# scaled in the editor like any other piece.
				var gp: Vector2 = c.to_global(p)
				_deck_poly.append(gp)
				bmin = bmin.min(gp)
				bmax = bmax.max(gp)
			_deck_rect = Rect2(bmin, bmax - bmin)
			return

	var pad := 90.0
	# Extra room along the BOTTOM edge: that edge is the deck's drain, so the
	# deck flippers need a genuine catch area under them. With only the
	# uniform padding the ball cleared the flipper line and dropped out in the
	# same breath, leaving nothing to actually play.
	var bottom_pad := 200.0
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	var found := false
	# Only real PIECES count toward the footprint - walls by their points,
	# everything else by where its collider sits. Plain Node2D containers are
	# skipped deliberately: the deck is an instanced sub-scene whose root sits
	# at the origin, and counting that would stretch the rect to (0,0).
	for c in _descendants(_vp_deck):
		if c is Line2D:
			for p in c.points:
				var gp: Vector2 = c.to_global(p)
				found = true
				min_p = min_p.min(gp)
				max_p = max_p.max(gp)
		elif c is CollisionObject2D:
			found = true
			min_p = min_p.min(c.global_position)
			max_p = max_p.max(c.global_position)
	if not found:
		return
	min_p -= Vector2(pad, pad)
	max_p += Vector2(pad, bottom_pad)
	_deck_rect = Rect2(min_p, max_p - min_p)


## A solid floor plate + neon trim + four corner support legs under the deck
## content, so it reads as an actual raised structure rather than parts
## floating in mid-air.
func _build_deck_platform() -> void:
	if _deck_rect.size.x <= 0.0:
		return
	var min_p := _deck_rect.position
	var max_p := _deck_rect.position + _deck_rect.size
	var center := _deck_rect.get_center()
	var wc := _table_to_world(center)
	var size_w := _deck_rect.size / PX_PER_M
	var plate_top := deck_height - 0.02
	# Thick enough that its side faces read clearly at the game's shallow
	# camera angle (a paper-thin slab all but vanishes edge-on), but its
	# underside stays comfortably above top_height so it can't occlude the
	# top-tier bumpers/targets that may sit within the same XY footprint.
	var plate_thickness := 0.14
	var plate_bottom := plate_top - plate_thickness

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size_w.x, plate_thickness, size_w.y)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = cabinet_color.lightened(0.12)
	mat.roughness = 0.55
	mesh.material_override = mat
	mesh.position = Vector3(wc.x, (plate_top + plate_bottom) * 0.5, wc.z)
	add_child(mesh)

	# Neon border: 4 thin strips tracing the platform's top edge, leaving its
	# dark centre visible underfoot (a full-footprint glow reads as a single
	# solid slab of colour, not a highlighted platform edge).
	var rim := 0.05
	var strips := [
		[Vector2(0, size_w.y * 0.5), Vector2(size_w.x + rim, rim)],
		[Vector2(0, -size_w.y * 0.5), Vector2(size_w.x + rim, rim)],
		[Vector2(size_w.x * 0.5, 0), Vector2(rim, size_w.y + rim)],
		[Vector2(-size_w.x * 0.5, 0), Vector2(rim, size_w.y + rim)],
	]
	for s in strips:
		var off: Vector2 = s[0]
		var sz: Vector2 = s[1]
		var strip := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(sz.x, 0.03, sz.y)
		strip.mesh = sb
		var tmat := StandardMaterial3D.new()
		tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tmat.albedo_color = accent_bright
		tmat.emission_enabled = true
		tmat.emission = accent_bright
		tmat.emission_energy_multiplier = 1.6
		strip.material_override = tmat
		strip.position = Vector3(wc.x + off.x, plate_top, wc.z + off.y)
		add_child(strip)

	for corner in [Vector2(min_p.x, min_p.y), Vector2(max_p.x, min_p.y),
			Vector2(min_p.x, max_p.y), Vector2(max_p.x, max_p.y)]:
		var cw := _table_to_world(corner)
		var leg := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(0.06, plate_bottom, 0.06)
		leg.mesh = lb
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = Color(0.25, 0.27, 0.36)
		leg.material_override = lmat
		leg.position = Vector3(cw.x, plate_bottom * 0.5, cw.z)
		add_child(leg)


## Every node under `root`, depth-first. Tier content may be a flat list of
## pieces OR a single instanced sub-scene (the upper deck is its own scene, so
## it can be moved/toggled as one unit), so discovery has to look deeper than
## one level.
func _descendants(root: Node) -> Array:
	var out: Array = []
	for c in root.get_children():
		out.append(c)
		out.append_array(_descendants(c))
	return out


## Put every collider under `node` on the deck's own physics layer, so it is
## invisible to ordinary playfield balls and solid only to a ball that has
## been delivered onto the deck.
func _set_deck_layer(node: Node) -> void:
	if node is CollisionObject2D:
		node.collision_layer = DECK_BIT
		node.collision_mask = DECK_BIT
	for c in node.get_children():
		_set_deck_layer(c)


## The cage: solid walls tracing the deck's outline so a ball up there stays
## up there and rattles around, exactly like a real second level. The wall
## follows the DeckBounds polygon edge for edge, so an angled or many-sided
## deck gets a matching cage rather than a box around it.
##
## The BOTTOM edge is deliberately left out - that gap, past the deck
## flippers, is the only way back down to the playfield. "Bottom" means any
## edge lying along the shape's lowest extent.
func _build_deck_cage(table: Node2D) -> void:
	if _deck_rect.size.x <= 0.0:
		return
	var outline := _deck_poly
	if outline.size() < 3:
		var min_p := _deck_rect.position
		var max_p := _deck_rect.position + _deck_rect.size
		outline = PackedVector2Array([
			Vector2(min_p.x, min_p.y), Vector2(max_p.x, min_p.y),
			Vector2(max_p.x, max_p.y), Vector2(min_p.x, max_p.y),
		])
	var floor_y := -INF
	for p in outline:
		floor_y = maxf(floor_y, p.y)
	var corners := []
	for i in outline.size():
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % outline.size()]
		if absf(a.y - floor_y) < 1.0 and absf(b.y - floor_y) < 1.0:
			continue   # the open bottom edge - the deck's drain
		corners.append(a)
		corners.append(b)
	if corners.is_empty():
		return
	var body := StaticBody2D.new()
	body.name = "DeckCage"
	body.collision_layer = DECK_BIT
	body.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.05
	pm.bounce = 0.4
	body.physics_material_override = pm
	# Each wall is a THICK convex slab, not a zero-width segment. A deck
	# flipper can pin the ball against a wall and squeeze it, and a hairline
	# barrier loses that fight - the ball pops through and is gone off the top
	# of the table. Give it real material to push against.
	var centroid := Vector2.ZERO
	for p in outline:
		centroid += p
	centroid /= float(outline.size())
	var thickness := 40.0
	for i in range(0, corners.size(), 2):
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[i + 1]
		var dir := (b - a).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		if nrm.dot(((a + b) * 0.5) - centroid) < 0.0:
			nrm = -nrm   # always push the slab OUTWARD, away from the deck
		# Overhang the ends so neighbouring slabs overlap at the corners and
		# leave no seam for the ball to squirt through.
		var ea := a - dir * thickness * 0.5
		var eb := b + dir * thickness * 0.5
		var cp := CollisionPolygon2D.new()
		cp.polygon = PackedVector2Array([ea, eb, eb + nrm * thickness, ea + nrm * thickness])
		body.add_child(cp)
	table.add_child(body)

	# 3D visual: a low glowing rail along those same three edges, sitting on
	# the deck plate so the cage reads as a boundary rather than an invisible
	# force field.
	var h := 0.13
	var base := deck_height - 0.02
	for i in range(0, corners.size(), 2):
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[i + 1]
		var wa := _table_to_world(a)
		var wb := _table_to_world(b)
		var mid := (wa + wb) * 0.5
		var span := Vector2(wb.x - wa.x, wb.z - wa.z)
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(maxf(span.length(), 0.04), h, 0.05)
		mesh.mesh = box
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = accent_cool
		mat.emission_enabled = true
		mat.emission = accent_cool
		mat.emission_energy_multiplier = 1.3
		mesh.material_override = mat
		mesh.position = Vector3(mid.x, base + h * 0.5, mid.z)
		mesh.rotation.y = -atan2(span.y, span.x)
		add_child(mesh)


## A channel named "*ToDeck*" finished a full ride: hand its ball to the deck.
func _on_deck_channel_released(body: Node, rode_through: bool) -> void:
	if not rode_through or not is_instance_valid(body):
		return
	body.collision_layer = DECK_BIT
	body.collision_mask = DECK_BIT
	body.z_index = 20
	body.set_meta("on_deck", true)


func _drop_from_deck(body: Node) -> void:
	body.collision_layer = 1
	body.collision_mask = 1
	body.z_index = 0
	body.set_meta("on_deck", false)


func _physics_process(_delta: float) -> void:
	# A ball leaves the deck by falling off its open bottom edge (past the
	# deck flippers) - at which point it rejoins ordinary play below.
	if _deck_rect.size.x <= 0.0:
		return
	var floor_y := _deck_rect.position.y + _deck_rect.size.y
	# Safety net: an on-deck ball collides ONLY with deck geometry, so if one
	# ever gets past the cage it would sail off the top of the table with
	# nothing to stop it. Anything outside the deck's footprint rejoins normal
	# play immediately, whichever side it left by.
	var escape := _deck_rect.grow(70.0)
	for b in get_tree().get_nodes_in_group("ball"):
		if not is_instance_valid(b) or not b.get_meta("on_deck", false):
			continue
		var p: Vector2 = b.global_position
		if p.y > floor_y or not escape.has_point(p):
			_drop_from_deck(b)


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
	sky_mat.sky_top_color = void_color
	sky_mat.sky_horizon_color = horizon_color
	sky_mat.ground_bottom_color = void_color.darkened(0.4)
	sky_mat.ground_horizon_color = horizon_color
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Warm-tinted fill so the table reads sunlit rather than moonlit.
	env.ambient_light_color = accent_bright.lerp(Color(0.7, 0.8, 1.0), 0.55)
	env.ambient_light_energy = 0.75
	# A little bloom makes the neon accents actually glow instead of just
	# being bright flat colour.
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, 28, 0)
	light.light_energy = 1.2
	light.light_color = Color(1.0, 0.95, 0.88)
	light.shadow_enabled = true
	add_child(light)


func _build_cabinet() -> void:
	var w := TABLE_SIZE.x / PX_PER_M      # 12.8
	var l := TABLE_SIZE.y / PX_PER_M      # 25.6
	var body_col := cabinet_color
	var rail_col := rail_color
	var neon := accent_cool

	# main body slab under the playfield
	_box(Vector3(w + 1.0, 1.0, l + 1.0), Vector3(0, -0.52, 0), body_col)
	# side rails + end caps (slightly proud of the playfield)
	_box(Vector3(0.35, 0.6, l + 1.0), Vector3(-(w * 0.5 + 0.32), -0.05, 0), rail_col)
	_box(Vector3(0.35, 0.6, l + 1.0), Vector3(w * 0.5 + 0.32, -0.05, 0), rail_col)
	_box(Vector3(w + 1.0, 0.6, 0.35), Vector3(0, -0.05, l * 0.5 + 0.32), rail_col)
	_box(Vector3(w + 1.0, 0.6, 0.35), Vector3(0, -0.05, -(l * 0.5 + 0.32)), rail_col)
	# neon accent strips along the rail tops - the two sides take different
	# accents so the cabinet reads as colourful rather than monochrome
	_box(Vector3(0.08, 0.06, l + 1.0), Vector3(-(w * 0.5 + 0.32), 0.28, 0), neon, 2.2)
	_box(Vector3(0.08, 0.06, l + 1.0), Vector3(w * 0.5 + 0.32, 0.28, 0), accent_warm, 2.2)
	# and a bright lip across the near and far ends
	_box(Vector3(w + 1.0, 0.06, 0.08), Vector3(0, 0.28, l * 0.5 + 0.32), accent_bright, 2.2)
	_box(Vector3(w + 1.0, 0.06, 0.08), Vector3(0, 0.28, -(l * 0.5 + 0.32)), accent_bright, 2.2)
	# legs
	for corner in [Vector3(-w * 0.5 - 0.2, -2.2, l * 0.5 + 0.2), Vector3(w * 0.5 + 0.2, -2.2, l * 0.5 + 0.2),
			Vector3(-w * 0.5 - 0.2, -2.2, -l * 0.5 - 0.2), Vector3(w * 0.5 + 0.2, -2.2, -l * 0.5 - 0.2)]:
		_box(Vector3(0.3, 3.4, 0.3), corner, body_col)
	# backbox with glowing panel at the far (top) end
	_box(Vector3(w + 1.0, 4.6, 0.9), Vector3(0, 2.0, -(l * 0.5 + 1.0)), body_col)
	_box(Vector3(w - 1.0, 3.4, 0.1), Vector3(0, 2.1, -(l * 0.5 + 0.52)),
			accent_warm.lerp(void_color, 0.55), 1.8)
	# a bright frame around that panel so the backbox reads as lit signage
	for edge in [[Vector3(w - 0.8, 0.12, 0.12), Vector3(0, 3.85, -(l * 0.5 + 0.5))],
			[Vector3(w - 0.8, 0.12, 0.12), Vector3(0, 0.35, -(l * 0.5 + 0.5))],
			[Vector3(0.12, 3.6, 0.12), Vector3(-(w * 0.5 - 0.4), 2.1, -(l * 0.5 + 0.5))],
			[Vector3(0.12, 3.6, 0.12), Vector3(w * 0.5 - 0.4, 2.1, -(l * 0.5 + 0.5))]]:
		_box(edge[0], edge[1], accent_bright, 2.4)
	_build_backbox_display(l)
	_build_grid_floor()
	_build_starfield()
	_build_floating_shapes()


## The backbox is the natural home for the score, exactly like a real machine:
## title marquee up top, big live score under it, balls remaining below. It
## reads straight off GameManager, so the panel is genuinely live rather than
## a painted-on decoration.
func _build_backbox_display(l: float) -> void:
	var face_z := -(l * 0.5 + 0.44)
	_backbox_label(backbox_title, 78, accent_bright, Vector3(0, 3.32, face_z))
	_score_label = _backbox_label("0", 142, Color(1, 0.97, 0.92), Vector3(0, 2.18, face_z))
	# Balls and the multiball legend share ONE line well below the score, both
	# small: stacked on separate lines they crowded the score badly. Kept as two
	# labels rather than one string so each keeps its own colour, laid out left
	# and right of centre.
	_balls_label = _backbox_label("BALLS 3", 40, accent_cool, Vector3(-4.35, 1.06, face_z))
	_multiball_label = _backbox_label("", 40, accent_warm, Vector3(1.15, 1.06, face_z))
	GameManager.score_changed.connect(_on_score_changed)
	GameManager.balls_changed.connect(_on_balls_changed)
	GameManager.multiball_progress.connect(_on_multiball_progress)
	GameManager.multiball_changed.connect(_on_multiball_changed)
	_on_score_changed(GameManager.score)
	_on_balls_changed(GameManager.balls_left)
	_on_multiball_progress(0, 0)


func _backbox_label(text: String, size: int, col: Color, pos: Vector3) -> Label3D:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = size
	lbl.pixel_size = 0.012
	lbl.modulate = col
	lbl.outline_size = 20
	lbl.outline_modulate = Color(0.05, 0.02, 0.10)
	lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lbl.shaded = false
	lbl.position = pos
	add_child(lbl)
	return lbl


func _on_score_changed(value: int) -> void:
	if not is_instance_valid(_score_label):
		return
	_score_label.text = _grouped(value)
	# A quick punch on every score, so the backbox reacts to play.
	var tw := create_tween()
	tw.tween_property(_score_label, "scale", Vector3.ONE * 1.13, 0.07)
	tw.tween_property(_score_label, "scale", Vector3.ONE, 0.20) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_balls_changed(value: int) -> void:
	if is_instance_valid(_balls_label):
		_balls_label.text = "BALLS %d" % maxi(value, 0)


## Legend on the backbox. While multiball is off it counts the two banks toward
## lighting it; while it runs it just says so, pulsing, and stops counting.
func _on_multiball_progress(deck_clears: int, main_clears: int) -> void:
	if not is_instance_valid(_multiball_label) or _multiball_lit:
		return
	_multiball_label.modulate = accent_warm
	_multiball_label.text = "MULTIBALL   DECK %d/%d   BANK %d/%d" % [
			deck_clears, MULTIBALL_DECK_TARGET, main_clears, MULTIBALL_MAIN_TARGET]


func _on_multiball_changed(active: bool) -> void:
	_multiball_lit = active
	if not is_instance_valid(_multiball_label):
		return
	if _multiball_tween and _multiball_tween.is_valid():
		_multiball_tween.kill()
	if active:
		_multiball_label.text = "*  M U L T I B A L L  *"
		_multiball_label.modulate = accent_bright
		_multiball_tween = create_tween().set_loops()
		_multiball_tween.tween_property(_multiball_label, "modulate", accent_warm, 0.35)
		_multiball_tween.tween_property(_multiball_label, "modulate", accent_bright, 0.35)
	else:
		_on_multiball_progress(0, 0)


## 1234500 -> "1,234,500" - a bare digit run is unreadable at a glance.
func _grouped(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if value < 0 else out


## Synthwave grid floor far below the cabinet.
const GRID_SHADER := "
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 base_color;
uniform vec3 line_color;
uniform vec3 line_color_alt;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 g = abs(fract(wpos.xz / 3.0) - 0.5);
	float line = smoothstep(0.44, 0.5, max(g.x, g.y));
	float fade = clamp(1.0 - length(wpos.xz) / 65.0, 0.0, 1.0);
	// Two accents woven across the grid so it is not one flat hue.
	float mixer = 0.5 + 0.5 * sin(wpos.x * 0.09 + wpos.z * 0.07 + TIME * 0.35);
	vec3 lc = mix(line_color, line_color_alt, mixer);
	// Held back to ~0.6: at full strength the grid is so bright it competes
	// with the playfield for attention instead of framing it.
	ALBEDO = mix(base_color, lc, line * fade * 0.6);
}
"

func _build_grid_floor() -> void:
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(140, 140)
	mesh.mesh = plane
	var sh := Shader.new()
	sh.code = GRID_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("base_color", Vector3(
			void_color.r * 0.4, void_color.g * 0.4, void_color.b * 0.4))
	mat.set_shader_parameter("line_color", Vector3(accent_cool.r, accent_cool.g, accent_cool.b))
	mat.set_shader_parameter("line_color_alt", Vector3(accent_warm.r, accent_warm.g, accent_warm.b))
	mesh.material_override = mat
	mesh.position = Vector3(0, -4.0, 0)
	add_child(mesh)


## Stars scattered around the void, tinted across the palette (a single-colour
## starfield reads as grey noise from a distance).
func _build_starfield() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.34, 0.34)
	mm.mesh = quad
	mm.instance_count = 300
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var tints := [accent_warm, accent_cool, accent_bright, Color(1, 1, 1)]
	for i in mm.instance_count:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.05, 1), rng.randf_range(-1, 1)).normalized()
		var pos := dir * rng.randf_range(45.0, 75.0)
		var s := rng.randf_range(0.6, 1.7)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s, s)), pos))
		var t: Color = tints[rng.randi() % tints.size()]
		mm.set_instance_color(i, t.lerp(Color.WHITE, rng.randf_range(0.0, 0.5)))
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	inst.material_override = mat
	add_child(inst)


## Neon shapes drifting around the cabinet: rings, cubes, prisms and spheres
## slowly tumbling and bobbing in the void, in the table's accent colours.
## They sit well outside the play area so they never fight the playfield for
## attention - they just stop the background being empty.
func _build_floating_shapes() -> void:
	if floater_count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var cols := [accent_warm, accent_cool, accent_bright,
			accent_warm.lerp(accent_bright, 0.5), accent_cool.lerp(accent_bright, 0.4)]
	for i in floater_count:
		var mesh := MeshInstance3D.new()
		match i % 4:
			0:
				var t := TorusMesh.new()
				t.inner_radius = rng.randf_range(0.5, 0.9)
				t.outer_radius = t.inner_radius + rng.randf_range(0.25, 0.5)
				mesh.mesh = t
			1:
				var b := BoxMesh.new()
				b.size = Vector3.ONE * rng.randf_range(0.9, 1.7)
				mesh.mesh = b
			2:
				var p := PrismMesh.new()
				p.size = Vector3.ONE * rng.randf_range(1.1, 1.9)
				mesh.mesh = p
			_:
				var s := SphereMesh.new()
				s.radius = rng.randf_range(0.45, 0.85)
				s.height = s.radius * 2.0
				mesh.mesh = s
		var col: Color = cols[rng.randi() % cols.size()]
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(col.r, col.g, col.b, 0.9)
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 1.7
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.material_override = mat

		# Ring them around the cabinet, biased to the sides and far end so
		# nothing hovers between the camera and the playfield.
		var ang := TAU * (float(i) / float(floater_count)) + rng.randf_range(-0.15, 0.15)
		var radius := rng.randf_range(17.0, 30.0)
		var y := rng.randf_range(-3.0, 13.0)
		mesh.position = Vector3(sin(ang) * radius, y, -cos(ang) * radius * 0.75)
		mesh.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		add_child(mesh)
		_floaters.append({
			"node": mesh,
			"axis": Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(),
			"spin": rng.randf_range(0.12, 0.45),
			"base_y": y,
			"bob": rng.randf_range(0.3, 1.1),
			"phase": rng.randf() * TAU,
		})


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


## Drop targets become real blocks standing on the playfield. When knocked
## they sink THROUGH the board and vanish, then rise back up on a bank reset -
## which is what a drop target physically does, and impossible to read from a
## flat rectangle that simply blinks out.
func _build_target_visuals() -> void:
	# The deck's targets get their own, taller height: they sit much further up
	# the table and are viewed from a steeper angle, so a plate sized for the
	# main playfield shrinks to a sliver up there.
	for tier in [[_vp_top, 0.0, target_height], [_vp_deck, deck_height, deck_target_height]]:
		var vp: SubViewport = tier[0]
		var base_h: float = tier[1]
		for t in _descendants(vp):
			if not (t is Node2D) or not t.has_method("reset_target"):
				continue
			var cs: CollisionShape2D = t.get_node_or_null("CollisionShape2D")
			if cs == null or not (cs.shape is RectangleShape2D):
				continue
			var size2: Vector2 = (cs.shape as RectangleShape2D).size
			var col := Color(1, 0.55, 0.25)
			var vis: Node = t.get_node_or_null("Visual")
			if vis is Polygon2D:
				col = (vis as Polygon2D).color
				vis.visible = false
				# Claim the flat art, so the target's own reset doesn't turn it
				# back on underneath the plate we're about to build.
				t.set_meta("visual_owned_by_3d", true)
			var height: float = tier[2]
			var mesh := MeshInstance3D.new()
			var box := BoxMesh.new()
			# A drop target is a thin upright PLATE, not a block. Taking the
			# depth from the collision box (which is as deep as the target is
			# wide) made them read as cubes sitting on the playfield.
			box.size = Vector3(size2.x / PX_PER_M, height, target_thickness)
			mesh.mesh = box
			var mat := StandardMaterial3D.new()
			mat.albedo_color = col
			mat.metallic = 0.1
			mat.roughness = 0.4
			mat.emission_enabled = true
			mat.emission = col
			mat.emission_energy_multiplier = 0.9
			mesh.material_override = mat
			add_child(mesh)

			# A lit cap along the top edge. The upper deck is viewed from a much
			# steeper angle than the main playfield, where an upright plate
			# foreshortens to almost nothing - a bright top FACE is the part
			# still facing the camera up there, and it's what makes the target
			# readable at all.
			var cap := MeshInstance3D.new()
			var cb := BoxMesh.new()
			cb.size = Vector3(size2.x / PX_PER_M * 1.04, 0.035, target_thickness * 2.2)
			cap.mesh = cb
			var capmat := StandardMaterial3D.new()
			capmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			# Near-white on purpose: a lightened tint of the plate's own colour
			# barely separated from it. A hot edge reads against any playfield
			# or deck colour underneath.
			capmat.albedo_color = col.lightened(0.85)
			capmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			capmat.emission_enabled = true
			capmat.emission = col.lightened(0.7)
			capmat.emission_energy_multiplier = 3.0
			cap.material_override = capmat
			cap.position = Vector3(0, height * 0.5, 0)
			mesh.add_child(cap)

			# A dark socket slot on the floor at the target's base. Real drop
			# targets sit in a recess, and it gives the plate local contrast
			# against whatever colour the board or deck happens to be - the deck
			# floor in particular can be bright enough to swallow a pale target.
			# NOT parented to the plate: the slot stays put when it drops.
			var slot := MeshInstance3D.new()
			var sb := BoxMesh.new()
			sb.size = Vector3(size2.x / PX_PER_M * 1.18, 0.014, target_thickness * 3.4)
			slot.mesh = sb
			var slotmat := StandardMaterial3D.new()
			slotmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			slotmat.albedo_color = Color(0.04, 0.04, 0.07)
			slot.material_override = slotmat
			add_child(slot)
			# Anchored to the COLLISION shape, not the body: the shape can be
			# offset from its parent in the editor (moving a target's children
			# rather than the target itself), and taking the body's position
			# then floats the block away from where the target really is.
			var w := _table_to_world(cs.global_position)
			# Start standing, not at the origin: animating up from y=0 on the
			# first frames tripped the sinking branch above and left the plate
			# permanently alpha-blended.
			mesh.position = Vector3(w.x, base_h + height * 0.5, w.z)
			slot.position = Vector3(w.x, base_h + 0.008, w.z)
			slot.rotation.y = -cs.global_rotation
			_targets.append({
				"node": t, "mesh": mesh, "mat": mat, "capmat": capmat,
				"xz": Vector2(w.x, w.z),
				"up_y": base_h + height * 0.5,
				"down_y": base_h - height * 0.75,
				"rot": cs.global_rotation,
			})


## One-way gates: a hinged flap on two posts, standing above the board. They
## were left as a flat line, so the one piece whose whole purpose is "the ball
## passes over this way but not back" read as painted on. Found by their
## one_way_collision shape rather than by name, so any gate gets the treatment.
func _build_gate_visuals(table: Node2D) -> void:
	var seen := {}
	for parent in [table, _vp_mid, _vp_top, _vp_deck]:
		for g in _descendants(parent):
			if not (g is Node2D) or seen.has(g.get_instance_id()):
				continue
			var cs: CollisionShape2D = g.get_node_or_null("CollisionShape2D")
			if cs == null or not cs.one_way_collision or not (cs.shape is RectangleShape2D):
				continue
			seen[g.get_instance_id()] = true
			var span: float = (cs.shape as RectangleShape2D).size.x / PX_PER_M
			var line: Node = g.get_node_or_null("Line2D")
			var col := accent_cool
			if line is Line2D:
				col = (line as Line2D).default_color
				col.a = 1.0
				line.visible = false
			var w := _table_to_world(cs.global_position)
			var root := Node3D.new()
			root.position = Vector3(w.x, 0.0, w.z)
			root.rotation.y = -cs.global_rotation
			add_child(root)

			# The flap, tilted back the way the ball pushes it open.
			var flap := MeshInstance3D.new()
			var fb := BoxMesh.new()
			fb.size = Vector3(span, gate_height * 0.9, 0.035)
			flap.mesh = fb
			var fmat := StandardMaterial3D.new()
			fmat.albedo_color = Color(col.r, col.g, col.b, 0.75)
			fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			fmat.emission_enabled = true
			fmat.emission = col
			fmat.emission_energy_multiplier = 1.2
			fmat.cull_mode = BaseMaterial3D.CULL_DISABLED
			flap.mesh.material = fmat
			flap.position = Vector3(0, gate_height * 0.52, 0)
			flap.rotation.x = deg_to_rad(-18.0)
			root.add_child(flap)

			for side in [-1.0, 1.0]:
				var post := MeshInstance3D.new()
				var pm := CylinderMesh.new()
				pm.top_radius = 0.028
				pm.bottom_radius = 0.032
				pm.height = gate_height
				post.mesh = pm
				var pmat := StandardMaterial3D.new()
				pmat.albedo_color = rail_color.lightened(0.35)
				pmat.metallic = 0.5
				pmat.roughness = 0.3
				post.mesh.material = pmat
				post.position = Vector3(side * span * 0.5, gate_height * 0.5, 0)
				root.add_child(post)


## Bumpers and slingshots get solid geometry built from their COLLISION shape,
## the same way flippers and walls do, instead of a flat sprite lying on the
## board: round bumpers become drums with a domed cap, and the polygon-shaped
## slingshots are extruded into wedges.
func _build_kicker_visuals() -> void:
	for tier in [[_vp_top, top_height], [_vp_mid, mid_height], [_vp_deck, deck_height]]:
		var vp: SubViewport = tier[0]
		var base_h: float = tier[1]
		for k in _descendants(vp):
			if not (k is Node2D) or k.get("kick_speed") == null:
				continue
			var col: Color = k.modulate
			if col == Color.WHITE:
				col = accent_warm
			var spr: Node = k.get_node_or_null("Sprite2D")
			if spr is CanvasItem:
				spr.visible = false
			var mesh: MeshInstance3D = null
			var circle: CollisionShape2D = k.get_node_or_null("CollisionShape2D")
			var poly: CollisionPolygon2D = k.get_node_or_null("CollisionPolygon2D")
			# Positioned from the collision node so an offset shape keeps the
			# geometry on top of the thing the ball actually hits.
			if circle and circle.shape is CircleShape2D:
				var w := _table_to_world(circle.global_position)
				mesh = _build_bumper_drum((circle.shape as CircleShape2D).radius / PX_PER_M, col)
				mesh.position = Vector3(w.x, base_h, w.z)
			elif poly:
				var w := _table_to_world(poly.global_position)
				mesh = _build_prism(poly.polygon, col, base_h)
				mesh.position = Vector3(w.x, 0.0, w.z)
				mesh.rotation.y = -poly.global_rotation
				mesh.scale = Vector3(k.scale.x, 1.0, k.scale.y)
			if mesh == null:
				continue
			add_child(mesh)
			if k.has_signal("flashed"):
				k.flashed.connect(_on_kicker_flashed.bind(mesh, mesh.scale))


## A pop bumper: skirt drum, bright cap, and a glowing collar.
func _build_bumper_drum(radius: float, col: Color) -> MeshInstance3D:
	var root := MeshInstance3D.new()
	var body := CylinderMesh.new()
	body.top_radius = radius * 0.62
	body.bottom_radius = radius
	body.height = bumper_height
	root.mesh = body
	root.position.y = bumper_height * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.35
	mat.metallic = 0.25
	root.material_override = mat

	var cap := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = radius * 0.62
	dome.height = radius * 0.62
	dome.is_hemisphere = true
	cap.mesh = dome
	cap.position.y = bumper_height * 0.5
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = col.lightened(0.45)
	cmat.emission_enabled = true
	cmat.emission = col
	cmat.emission_energy_multiplier = 1.6
	cap.material_override = cmat
	root.add_child(cap)

	var collar := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = radius * 0.94
	ring.outer_radius = radius * 1.06
	collar.mesh = ring
	collar.position.y = -bumper_height * 0.5 + 0.012
	var omat := StandardMaterial3D.new()
	omat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	omat.albedo_color = accent_bright
	omat.emission_enabled = true
	omat.emission = accent_bright
	omat.emission_energy_multiplier = 1.8
	collar.material_override = omat
	root.add_child(collar)
	return root


## Extrude a closed 2D collision polygon into a solid wedge (walls + top cap).
func _build_prism(poly: PackedVector2Array, col: Color, base_h: float) -> MeshInstance3D:
	if poly.size() < 3:
		return null
	var h := slingshot_height
	var side := Color(col.r * 0.5, col.g * 0.5, col.b * 0.5)
	var n := poly.size()
	# The live face is the LONGEST edge - the same rule kicker.gd uses to decide
	# which face actually fires, so the marking can never disagree with the
	# physics. It gets a bright rubber band; the dead sides stay dull.
	var rubber := 0
	var rubber_len := -1.0
	for i in n:
		var length: float = poly[i].distance_to(poly[(i + 1) % n])
		if length > rubber_len:
			rubber_len = length
			rubber = i
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		var a3 := Vector3(a.x / PX_PER_M, base_h, a.y / PX_PER_M)
		var b3 := Vector3(b.x / PX_PER_M, base_h, b.y / PX_PER_M)
		var up := Vector3(0, h, 0)
		_quad(st, a3, b3, b3 + up, a3 + up, side)
	# top cap as a fan from the first vertex (collision polys are convex here)
	for i in range(1, n - 1):
		st.set_color(col)
		st.add_vertex(Vector3(poly[0].x / PX_PER_M, base_h + h, poly[0].y / PX_PER_M))
		st.set_color(col)
		st.add_vertex(Vector3(poly[i].x / PX_PER_M, base_h + h, poly[i].y / PX_PER_M))
		st.set_color(col)
		st.add_vertex(Vector3(poly[i + 1].x / PX_PER_M, base_h + h, poly[i + 1].y / PX_PER_M))
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.4
	mesh.material_override = mat

	# The rubber itself: a glowing band standing slightly proud of the live
	# face, so it is obvious at a glance which side of a slingshot fires.
	var ra: Vector2 = poly[rubber]
	var rb: Vector2 = poly[(rubber + 1) % n]
	var mid := (ra + rb) * 0.5
	var edge := (rb - ra).normalized()
	var centroid := Vector2.ZERO
	for p in poly:
		centroid += p
	centroid /= float(n)
	var nrm := Vector2(-edge.y, edge.x)
	if nrm.dot(mid - centroid) < 0.0:
		nrm = -nrm
	var band := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(ra.distance_to(rb) / PX_PER_M, h * 0.44, 0.05)
	band.mesh = bb
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.albedo_color = accent_bright
	bmat.emission_enabled = true
	bmat.emission = accent_bright
	bmat.emission_energy_multiplier = 2.0
	band.material_override = bmat
	var bpos := mid + nrm * 2.0
	band.position = Vector3(bpos.x / PX_PER_M, base_h + h * 0.62, bpos.y / PX_PER_M)
	band.rotation.y = -atan2(edge.y, edge.x)
	mesh.add_child(band)
	return mesh


## The squash MUST be relative to the piece's own base scale. Tweening to an
## absolute scale threw away the right slingshot's mirrored (1, 1, -1) - so the
## first hit silently un-mirrored it and the wedge appeared to jump to a new
## position and stay there.
func _on_kicker_flashed(mesh: Node3D, base: Vector3) -> void:
	if not is_instance_valid(mesh):
		return
	var tw := create_tween()
	tw.tween_property(mesh, "scale", base * Vector3(1.16, 0.82, 1.16), 0.05)
	tw.tween_property(mesh, "scale", base, 0.16) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Rollover lights: flush glowing discs set into the board. Lit state is
## polled from the node, so the 3D disc always agrees with the game logic.
func _build_rollover_visuals() -> void:
	for r in get_tree().get_nodes_in_group("rollover_lights"):
		if not (r is Node2D) or r.get("is_lit") == null:
			continue
		var vis: Node = r.get_node_or_null("Visual")
		if vis is CanvasItem:
			vis.visible = false
		var radius: float = float(r.get("radius")) / PX_PER_M
		var disc := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = radius
		cyl.bottom_radius = radius
		cyl.height = 0.022
		disc.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		disc.material_override = mat
		var w := _table_to_world(r.global_position)
		disc.position = Vector3(w.x, 0.014, w.z)
		add_child(disc)

		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = radius * 0.92
		torus.outer_radius = radius * 1.1
		ring.mesh = torus
		# The rim takes the insert's own lit colour, so a rollover recoloured in
		# the editor is recoloured here too.
		var ring_col: Color = r.color_lit
		var rmat := StandardMaterial3D.new()
		rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rmat.albedo_color = ring_col
		rmat.emission_enabled = true
		rmat.emission = ring_col
		rmat.emission_energy_multiplier = 1.2
		ring.material_override = rmat
		ring.position = Vector3(w.x, 0.016, w.z)
		add_child(ring)
		_lights.append({"node": r, "mat": mat, "ring": ring})


## Spinners: a real blade on two posts, turning on a horizontal axle across the
## lane. The blade's angle is driven from the spinner node itself each frame, so
## what you see spinning is exactly what is being scored.
func _build_spinner_visuals() -> void:
	for s in get_tree().get_nodes_in_group("spinners"):
		if not (s is Node2D) or s.get("spin") == null:
			continue
		var w := _table_to_world(s.global_position)
		var span: float = float(s.width) / PX_PER_M
		var root := Node3D.new()
		root.position = Vector3(w.x, 0.0, w.z)
		root.rotation.y = -s.global_rotation
		add_child(root)

		# The axle sits at blade height; the blade hangs across the lane and
		# rotates about the axle's own length.
		var axle_y := spinner_height
		var pivot := Node3D.new()
		pivot.position = Vector3(0, axle_y, 0)
		root.add_child(pivot)

		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(span * 0.92, axle_y * 1.7, 0.022)
		blade.mesh = bm
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = accent_bright
		bmat.metallic = 0.6
		bmat.roughness = 0.25
		bmat.emission_enabled = true
		bmat.emission = accent_bright
		bmat.emission_energy_multiplier = 0.7
		bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		blade.material_override = bmat
		pivot.add_child(blade)

		for side in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var pm := CylinderMesh.new()
			pm.top_radius = 0.022
			pm.bottom_radius = 0.026
			pm.height = axle_y * 1.25
			post.mesh = pm
			var pmat := StandardMaterial3D.new()
			pmat.albedo_color = rail_color.lightened(0.4)
			pmat.metallic = 0.5
			pmat.roughness = 0.3
			post.material_override = pmat
			post.position = Vector3(side * span * 0.5, axle_y * 0.62, 0)
			root.add_child(post)

		_spinners.append({"node": s, "pivot": pivot, "mat": bmat})


## A point on the tube wall: `ang` sweeps around the channel's centreline,
## 0 = outward along the horizontal normal, PI/2 = straight up.
func _tube_pt(centre: Vector3, side: Vector3, lift: Vector3, r: float, ang: float) -> Vector3:
	return centre + side * cos(ang) * r + lift * sin(ang) * r


## Colour -> shader vec3 (shader uniforms take no alpha).
func _v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


## Where the PlayfieldArt sprite actually lands, in table pixels, so the apron
## knows which part of the board is covered by artwork. Read from the node
## rather than hard-coded, so moving or rescaling the art in the editor keeps
## the two in step. Zero rect if there is no artwork.
func _playfield_art_rect(table: Node) -> Vector4:
	var art := table.get_node_or_null("PlayfieldArt")
	if art == null or not (art is Sprite2D) or art.texture == null:
		return Vector4.ZERO
	var size: Vector2 = Vector2(art.texture.get_size()) * art.scale
	var pos: Vector2 = art.position - (size * 0.5 if art.centered else Vector2.ZERO)
	return Vector4(pos.x, pos.y, size.x, size.y)


func _table_to_world(p: Vector2) -> Vector3:
	return Vector3((p.x - TABLE_SIZE.x * 0.5) / PX_PER_M, 0.0, (p.y - TABLE_SIZE.y * 0.5) / PX_PER_M)


# ---------------------------------------------------------------- 3D walls
## Extrude every Wall / CurvedWall polyline into a low solid 3D wall:
## darker side faces + a bright top cap in the line's colour. The flat 2D
## line is hidden.
func _build_wall_visuals(table: Node2D) -> void:
	# Deck-tier walls (name "Deck*", already reparented into _vp_deck by the
	# time this runs) extrude starting at deck_height instead of the ground.
	for tier in [[table, 0.0], [_vp_deck, deck_height]]:
		var parent: Node = tier[0]
		var base_h: float = tier[1]
		for child in _descendants(parent):
			if child is Line2D and child.get("wall_bounce") != null:
				_extrude_wall(child, child, base_h)
			elif child is Path2D and child.get("wall_bounce") != null:
				var line: Line2D = child.get_node_or_null("Line")
				if line:
					_extrude_wall(line, line, base_h)


func _extrude_wall(line: Line2D, space_ref: Node2D, base_h: float = 0.0) -> void:
	var pts := line.points
	var n := pts.size()
	if n < 2:
		return
	var c := line.default_color
	var side := Color(c.r * 0.45, c.g * 0.45, c.b * 0.45)
	var w3: Array[Vector3] = []
	var perp: Array[Vector3] = []
	for i in n:
		var w := _table_to_world(space_ref.to_global(pts[i]))
		w3.append(w + Vector3(0, base_h, 0))
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
## driven every frame by the 2D flipper's position/rotation. Flippers can live
## on any tier (mid, or the upper deck); base_height positions that tier's
## flippers at the right elevation, and the mesh itself is built at LOCAL
## height 0..flipper_height (base_height is applied via node position only).
func _build_flipper_visuals() -> void:
	for tier in [[_vp_mid, 0.0], [_vp_deck, deck_height]]:
		var vp: SubViewport = tier[0]
		var base_h: float = tier[1]
		for f in _descendants(vp):
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
			# Per-instance colour comes from the flipper node's own `modulate`,
			# set right on the instance in the 2D editor - the same way bumpers
			# and slingshots are recoloured. Left white it falls back to the
			# global flipper_color.
			var top: Color = f.modulate
			if top == Color.WHITE:
				top = flipper_color
			var side := Color(top.r * 0.42, top.g * 0.42, top.b * 0.42)
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
			_flippers.append([f, mesh, base_h])


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
		elif b.get_meta("on_deck", false):
			# Riding the upper deck. Keyed on the ball's actual deck state, NOT
			# on whether it happens to be inside the deck's footprint - a
			# playfield ball passing under the deck must stay firmly below it.
			target_lift = deck_height
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
	if not balls.is_empty() and is_instance_valid(balls[0]):
		_last_ball = balls[0].global_position

	# Drift the background shapes: each tumbles on its own axis and bobs on
	# its own phase, so the void reads as alive without anything marching in
	# step.
	_elapsed += delta
	for f in _floaters:
		var node: Node3D = f["node"]
		if not is_instance_valid(node):
			continue
		node.rotate(f["axis"], f["spin"] * delta)
		node.position.y = f["base_y"] + sin(_elapsed * 0.55 + f["phase"]) * f["bob"]

	# Drop targets: driven off each target's own `is_down`, so the block sinks
	# out of sight when knocked and rises again when the bank resets, without
	# needing any extra signal plumbing.
	for t in _targets:
		var node = t["node"]
		var mesh: MeshInstance3D = t["mesh"]
		if not is_instance_valid(node) or not is_instance_valid(mesh):
			continue
		var down: bool = node.is_down
		var want_y: float = t["down_y"] if down else t["up_y"]
		var xz: Vector2 = t["xz"]
		var y: float = lerpf(mesh.position.y, want_y, 1.0 - exp(-13.0 * delta))
		mesh.position = Vector3(xz.x, y, xz.y)
		mesh.rotation.y = -float(t["rot"])
		# Fade out over the last part of the travel so it disappears into the
		# board rather than clipping through the underside.
		var span: float = maxf(t["up_y"] - t["down_y"], 0.001)
		var k: float = clampf((y - t["down_y"]) / span, 0.0, 1.0)
		var mat: StandardMaterial3D = t["mat"]
		var capmat: StandardMaterial3D = t["capmat"]
		# Alpha-blend ONLY while the plate is actually sinking. Once it latched
		# onto an alpha material it stayed there, and an alpha-blended surface
		# stops writing depth - so the board underneath blended straight through
		# the plate and the deck's colour appeared to bleed into the target.
		var sinking := k < 0.995
		var want := BaseMaterial3D.TRANSPARENCY_ALPHA if sinking else BaseMaterial3D.TRANSPARENCY_DISABLED
		if mat.transparency != want:
			mat.transparency = want
			capmat.transparency = want
		mat.albedo_color.a = k if sinking else 1.0
		capmat.albedo_color.a = k if sinking else 1.0
		capmat.emission_energy_multiplier = 3.0 * k
		mesh.visible = not (down and k < 0.06)

	# Spinner blades, driven straight off each spinner's own angle so the
	# visual can never drift from what is being scored. They also glow hotter
	# the faster they are turning.
	for sp in _spinners:
		var node = sp["node"]
		var pivot: Node3D = sp["pivot"]
		if not is_instance_valid(node) or not is_instance_valid(pivot):
			continue
		pivot.rotation.x = float(node.angle) * TAU
		var mat: StandardMaterial3D = sp["mat"]
		mat.emission_energy_multiplier = 0.7 + clampf(float(node.spin) / 8.0, 0.0, 1.0) * 2.2

	# Rollover lights: dark when idle, blazing when lit.
	for lg in _lights:
		var node = lg["node"]
		var mat: StandardMaterial3D = lg["mat"]
		var ring: MeshInstance3D = lg["ring"]
		if not is_instance_valid(node) or not is_instance_valid(ring):
			continue
		var lit: bool = node.is_lit
		# Straight from the insert's own color_lit / color_dark exports, so each
		# rollover can be coloured individually in the editor.
		var want: Color = node.color_lit if lit else node.color_dark
		mat.albedo_color = mat.albedo_color.lerp(want, 1.0 - exp(-11.0 * delta))
		mat.emission = mat.albedo_color
		mat.emission_energy_multiplier = 2.4 if lit else 0.25
		ring.scale = Vector3.ONE * (1.0 + (0.07 * sin(_elapsed * 6.0) if lit else 0.0))

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

	# 3D flipper paddles mirror their 2D physics flippers, at their tier's height.
	for entry in _flippers:
		var f: Node2D = entry[0]
		var m: MeshInstance3D = entry[1]
		var base_h: float = entry[2]
		if not is_instance_valid(f):
			continue
		var w := _table_to_world(f.global_position)
		m.position = Vector3(w.x, base_h, w.z)
		m.rotation.y = -f.rotation

	var b := _table_to_world(_last_ball)
	b.x *= side_follow
	# Where the camera SITS is capped so it never trails far past the cabinet
	# and shrinks it into the distance. Where it LOOKS still follows the real
	# ball: aiming at the capped position instead swung the view forward, off
	# the bottom of the table, and cut the main flippers out of frame - they
	# sit at almost exactly the same depth as the shooter lane, so the cap
	# applies just as much when you are actually playing them.
	var follow_z := clampf(b.z, -TABLE_SIZE.y * 0.5 / PX_PER_M, camera_near_limit)

	var target := Vector3(b.x, camera_height, follow_z + camera_back)
	_cam.position = _cam.position.lerp(target, 1.0 - exp(-follow_speed * delta))
	if _punch > 0.005:
		_cam.position += Vector3(randf_range(-_punch, _punch), randf_range(-_punch, _punch), 0)
		_punch = move_toward(_punch, 0.0, 2.2 * delta)
	_cam.look_at(Vector3(b.x, 0.0, b.z - look_ahead))


func _unhandled_input(event: InputEvent) -> void:
	# Forward input into the SubViewport so the table's own handlers
	# (Esc to menu, Enter to restart) keep working.
	_vp.push_input(event)
