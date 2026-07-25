@tool
extends Path2D
## A ramp: a channel like Rail, but the ball rides OVER the playfield while on
## it - it ignores bumpers/walls below and renders on top, then returns to
## normal play at the far end. Draw the centre line with the Path2D tools.
##
## How it works: the ramp walls live on a separate physics layer. A portal at
## each end flips the ball onto (or off of) that layer, so a normal ball passes
## under the ramp until it enters a mouth, then is guided along it.

## Physics layers 4-8 (bits 3-7) are reserved for ramps/rails. Each channel
## instance claims its OWN bit (cycling through this pool) rather than sharing
## one - two channels whose curves happen to run near each other in world
## space would otherwise physically collide (a riding ball on channel A
## slamming into channel B's walls), which silently drains its momentum and
## can strand or misdirect it. Only matters if more than RAMP_BIT_COUNT
## channels overlap at once, which the current table never does.
const RAMP_BIT_BASE := 3
const RAMP_BIT_COUNT := 5
static var _next_bit_index := 0

var _bit := 0

## Keep this snug: ball diameter is 28, so ~38 reads as the ball filling the
## channel (the lock steering means it doesn't need physical slop).
@export var channel_width := 38.0:
	set(v):
		channel_width = v
		_refresh()
## The mouths flare open cone-like to this multiple of the channel width,
## catching approach shots.
@export var mouth_flare := 1.9:
	set(v):
		mouth_flare = v
		_refresh()
@export_range(1.0, 30.0) var smoothness := 4.0:
	set(v):
		smoothness = v
		_refresh()
@export var wall_bounce := 0.15
## Points awarded once each time a ball boards the ramp (0 = no scoring).
@export var ramp_score := 2000

## The "sucked in" feel: while captured, the ball is steered along the curve
## (speed preserved), pulled gently to the centreline, and gravity inside the
## channel is reduced so momentum carries it through climbs.
@export var guide_strength := 9.0
@export var centering := 16.0
@export var channel_gravity := 250.0
## Minimum capture speed for the whoosh sound - a slow dribble that rolls
## back out of the mouth stays silent.
@export var whoosh_min_speed := 800.0

## Boarding gates. A captured ball has its velocity snapped to the channel
## axis (speed preserved), so a ball that merely FALLS past a mouth used to
## get its downward momentum rotated along the rail and shot off up-table -
## the rail appeared to kick it for no reason. Requiring both a real shot
## speed and a heading roughly along the channel means only balls actually
## aimed into the mouth board it; everything else falls past untouched.
@export var min_board_speed := 450.0
## dot(velocity.normalized(), inward) - 0.5 is a ~60 degree cone.
@export_range(0.0, 1.0) var min_board_alignment := 0.5
## How far off the mouth's centreline a ball may be and still board, as a
## multiple of channel_width. Beyond this it visibly missed the opening.
@export var max_board_offset := 0.6

## Emitted when a ball leaves this channel. `rode_through` is true only if it
## exited the END OPPOSITE the one it boarded at (a full traversal) rather
## than backing out the way it came - a deck-feed channel only hands the ball
## to the upper deck on a genuine ride.
signal ball_released(body: Node, rode_through: bool)

## Deliberately UNTYPED. A ball drained while riding is freed without
## _release() running, so this can hold a dangling reference - and a typed
## Array[RigidBody2D] validates on erase(), refusing to remove the very entry
## that needs removing ("Attempted to erase an invalid object instance into a
## TypedArray") and re-erroring every frame from then on.
var _riding: Array = []
var _last_whoosh_ms := 0

@onready var _left: Line2D = $Left
@onready var _right: Line2D = $Right


func _ready() -> void:
	# A channel's walls are offset from its curve in LOCAL space, so a
	# non-uniform node scale squashes the corridor along one axis: the walls end
	# up different distances from the centreline depending on which way the
	# curve is heading, and the ball no longer fits the way channel_width says
	# it should. Stretch the CURVE to change a rail's length or shape, never the
	# node's scale.
	# Threshold is loose: a slight stretch (the sort you get nudging a handle in
	# the editor) is harmless, a 2x or 3x one is not.
	if absf(scale.x - scale.y) > 0.35:
		push_warning("%s has a non-uniform scale %s - this distorts the channel. Scale it uniformly and reshape the curve instead." % [name, scale])
	_bit = 1 << (RAMP_BIT_BASE + (_next_bit_index % RAMP_BIT_COUNT))
	_next_bit_index += 1
	_connect_curve()
	_refresh()
	if not Engine.is_editor_hint():
		_build_wall($Left.points)
		_build_wall($Right.points)
		_build_field()
		_build_mouths()


func _connect_curve() -> void:
	if curve and not curve.changed.is_connected(_refresh):
		curve.changed.connect(_refresh)


func _refresh() -> void:
	_connect_curve()
	if _left == null:
		_left = get_node_or_null("Left")
		_right = get_node_or_null("Right")
	if _left == null or _right == null or curve == null:
		return
	var center := curve.tessellate(5, smoothness)
	var n := center.size()
	# Per-point half-width: flared cone at the mouths, snug along the middle.
	var widths := PackedFloat32Array()
	for i in n:
		var t := float(i) / float(maxi(n - 1, 1))
		var k := clampf(minf(t, 1.0 - t) / 0.12, 0.0, 1.0)
		var sm := k * k * (3.0 - 2.0 * k)
		widths.append(lerpf(mouth_flare, 1.0, sm) * channel_width * 0.5)
	_left.points = _offset_var(center, widths, 1.0)
	_right.points = _offset_var(center, widths, -1.0)


func _offset_var(pts: PackedVector2Array, widths: PackedFloat32Array, side: float) -> PackedVector2Array:
	var raw := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var dir: Vector2
		if i == 0:
			dir = pts[1] - pts[0]
		elif i == n - 1:
			dir = pts[i] - pts[i - 1]
		else:
			dir = pts[i + 1] - pts[i - 1]
		if dir.length() < 0.001:
			dir = Vector2.RIGHT
		dir = dir.normalized()
		raw.append(pts[i] + Vector2(-dir.y, dir.x) * widths[i] * side)
	return _remove_loops(raw)


## Drop self-intersection loops so a tight bend's inner wall stays smooth.
func _remove_loops(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p)
		var m := out.size()
		if m < 4:
			continue
		for j in range(m - 3):
			if _segments_cross(out[m - 2], out[m - 1], out[j], out[j + 1]):
				var keep := out.slice(0, j + 1)
				keep.append(out[m - 1])
				out = keep
				break
	return out


func _segments_cross(a: Vector2, b: Vector2, c: Vector2, e: Vector2) -> bool:
	var r := b - a
	var s := e - c
	var rxs := r.cross(s)
	if absf(rxs) < 0.0001:
		return false
	var t := (c - a).cross(s) / rxs
	var u := (c - a).cross(r) / rxs
	return t > 0.01 and t < 0.99 and u > 0.01 and u < 0.99


func _build_wall(pts: PackedVector2Array) -> void:
	if pts.size() < 2:
		return
	var body := StaticBody2D.new()
	body.collision_layer = _bit   # only a ball riding THIS channel hits these
	body.collision_mask = 0
	var mat := PhysicsMaterial.new()
	mat.friction = 0.05
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


# A single Area2D covering the whole channel interior. The ball is "on the
# ramp" exactly while it is inside this field; leaving it by ANY route (mouth,
# side, whatever) restores normal collision, so the ball can never get stranded
# on the ramp layer and fly off-screen.
func _build_field() -> void:
	var left: PackedVector2Array = $Left.points
	var right: PackedVector2Array = $Right.points
	if left.size() < 2 or right.size() < 2:
		return
	var poly := PackedVector2Array()
	poly.append_array(left)
	for i in range(right.size() - 1, -1, -1):
		poly.append(right[i])
	var area := Area2D.new()
	area.name = "Field"
	# Only a ball already riding THIS channel (its own bit): a playfield ball
	# crossing under the channel is neither captured nor affected by it.
	area.collision_mask = _bit
	# Reduced gravity inside the channel (wins over the table's gravity zone)
	# so the riding ball keeps its momentum through climbs.
	area.gravity_space_override = Area2D.SPACE_OVERRIDE_REPLACE
	area.gravity = channel_gravity
	area.gravity_direction = Vector2.DOWN
	area.priority = 5
	var cp := CollisionPolygon2D.new()
	cp.polygon = poly
	area.add_child(cp)
	add_child(area)
	area.body_exited.connect(_on_field_exited)


## Capture zones at the two curve ends. Only a playfield ball moving INTO the
## channel boards it - so balls crossing the middle pass underneath, and a
## ball just released at the exit is not immediately recaptured.
func _build_mouths() -> void:
	var center := curve.tessellate(5, smoothness)
	if center.size() < 2:
		return
	_make_mouth(center[0], center[1])
	_make_mouth(center[center.size() - 1], center[center.size() - 2])


func _make_mouth(at: Vector2, toward: Vector2) -> void:
	var area := Area2D.new()
	area.position = at
	area.collision_mask = 1   # playfield balls only
	var cs := CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = channel_width * 0.6 * mouth_flare
	cs.shape = circ
	area.add_child(cs)
	add_child(area)
	# Inward direction in global space (pieces don't move at runtime).
	var inward: Vector2 = (to_global(toward) - to_global(at)).normalized()
	area.body_entered.connect(_on_mouth_entered.bind(inward, to_global(at)))


func _on_mouth_entered(body: Node, inward: Vector2, mouth_pos: Vector2) -> void:
	if not body.is_in_group("ball") or body.get_meta("on_ramp", false):
		return
	if not body is RigidBody2D:
		return
	# Must be genuinely shot INTO the channel: fast enough to carry through,
	# and heading along it rather than just drifting or falling across the
	# mouth (see min_board_speed / min_board_alignment).
	var v: Vector2 = body.linear_velocity
	var speed: float = v.length()
	if speed < min_board_speed:
		return
	if v.normalized().dot(inward) < min_board_alignment:
		return
	# ...and actually lined up with the opening, not skimming past its edge.
	# The capture zone is a wide cone so approach shots feed in, but a ball
	# clipping its outer edge was still boarded and then dragged sideways onto
	# the centreline - so a shot that visibly MISSED the rail appeared to run
	# alongside it for half its length before being spat back out.
	var lateral: float = absf((body.global_position - mouth_pos).dot(Vector2(-inward.y, inward.x)))
	if lateral > channel_width * max_board_offset:
		return
	# board the ramp -> ride over the playfield (but keep colliding with the
	# ramp walls so it stays guided)
	body.collision_layer = _bit
	body.collision_mask = _bit
	body.z_index = 10
	body.set_meta("on_ramp", true)
	body.set_meta("channel", self)   # lets the 3D view follow this channel's height profile
	# Where along the curve it got on, so the release checks can tell "reached
	# the far end after a real ride" from "is sitting at the end it entered".
	body.set_meta("channel_entry_off", curve.get_closest_offset(to_local(body.global_position)))
	if not _riding.has(body):
		_riding.append(body)
	# Whoosh only on a committed shot (fast enough to carry through), with a
	# short cooldown so hovering around the mouth can't re-trigger it.
	var now := Time.get_ticks_msec()
	if speed >= whoosh_min_speed and now - _last_whoosh_ms > 450:
		_last_whoosh_ms = now
		SoundManager.play("whoosh", lerpf(0.95, 1.2, clampf((speed - whoosh_min_speed) / 1600.0, 0.0, 1.0)))
	# NOTE: no score here. A channel pays out for being RIDDEN END TO END, which
	# is the shot worth making - see _release(). Scoring on entry paid out for
	# merely nudging a mouth.


func _on_field_exited(body: Node) -> void:
	if not body.is_in_group("ball") or not body.get_meta("on_ramp", false):
		return
	# Belt-and-suspenders: each channel now has its own physics bit, so this
	# shouldn't fire for a foreign ball, but only this ball's own channel may
	# ever release it.
	if body.get_meta("channel", null) != self:
		return
	# The field polygon can pinch on tight bends, so leaving it does not by
	# itself mean the ball left the channel. Only release if the ball is
	# genuinely outside the corridor or past an end; otherwise keep the lock
	# (the per-frame end/stray checks handle the real exit).
	var local := to_local(body.global_position)
	var off := curve.get_closest_offset(local)
	var dist := local.distance_to(curve.sample_baked(off))
	if dist > channel_width * 0.8 or off < 10.0 or off > curve.get_baked_length() - 10.0:
		_release(body)


func _release(body: Node) -> void:
	if not is_instance_valid(body):
		_riding.erase(body)
		return
	if not body.get_meta("on_ramp", false):
		return
	var length := curve.get_baked_length()
	var off := curve.get_closest_offset(to_local(body.global_position))
	var entry_off: float = body.get_meta("channel_entry_off", 0.0)
	body.collision_layer = 1
	body.collision_mask = 1
	body.z_index = 0
	body.set_meta("on_ramp", false)
	body.set_meta("channel", null)
	_riding.erase(body)
	var rode_through := absf(off - entry_off) > length * 0.5
	# Pay out only for a completed run: the ball went in one mouth and came
	# out the other. Backing out the way it came earns nothing.
	if rode_through and ramp_score > 0:
		GameManager.add_score(ramp_score, body.global_position)
	# Listeners (e.g. the upper deck taking delivery of the ball) decide what
	# happens next, so this stays generic - a channel knows nothing about what
	# is at either of its ends.
	ball_released.emit(body, rode_through)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _riding.is_empty() or curve == null:
		return
	# The loop variable is deliberately UNTYPED. A ball drained while riding
	# this channel is freed without _release() ever running, so it stays in
	# _riding as a dangling reference - and binding that to a `: RigidBody2D`
	# loop variable throws "Trying to assign invalid previously freed
	# instance" on the iteration itself, before any guard in the body can run.
	for ball in _riding.duplicate():
		if not is_instance_valid(ball):
			_riding.erase(ball)
			continue
		var speed: float = ball.linear_velocity.length()
		if speed < 80.0:
			continue
		# Direction of the channel at the ball's position (in global space).
		var local := to_local(ball.global_position)
		var off := curve.get_closest_offset(local)
		var length := curve.get_baked_length()
		# Unconditional safety net: once the ball has ridden a real distance
		# and reached EITHER end, release it no matter what its velocity is
		# doing. A fast ball on a short channel can cross the whole "near end"
		# window in a single physics step and never satisfy the
		# velocity-direction check below, leaving it stuck "on_ramp" (its
		# collision effectively disabled). The travelled-distance guard is
		# what makes this safe to apply at both ends: without it, a ball that
		# BOARDS at a far mouth sits at off ~= length on its very first frame
		# and is released instantly - which is exactly why shooting a rail
		# from one end worked and from the other end did nothing at all.
		var entry_off: float = ball.get_meta("channel_entry_off", 0.0)
		var end_margin := minf(4.0, length * 0.1)
		if absf(off - entry_off) > 30.0 and (off <= end_margin or off >= length - end_margin):
			_release(ball)
			continue
		# Release when the ball passes an END moving outward (the real exit),
		# or if it somehow strays out of the corridor.
		if off < 14.0:
			var inward := (to_global(curve.sample_baked(minf(24.0, length))) - to_global(curve.sample_baked(0.0))).normalized()
			if ball.linear_velocity.dot(inward) < 0.0:
				_release(ball)
				continue
		elif off > length - 14.0:
			var outward := (to_global(curve.sample_baked(length)) - to_global(curve.sample_baked(maxf(length - 24.0, 0.0)))).normalized()
			if ball.linear_velocity.dot(outward) > 0.0:
				_release(ball)
				continue
		# Tightened from 1.5x: half a channel width plus a ball radius is about
		# 0.8x, so 1.0x releases a ball that is genuinely outside the tube
		# without ejecting one that is merely riding off-centre.
		if local.distance_to(curve.sample_baked(off)) > channel_width * 1.0:
			_release(ball)
			continue
		var ahead := curve.sample_baked(minf(off + 8.0, curve.get_baked_length()))
		var behind := curve.sample_baked(maxf(off - 8.0, 0.0))
		var tangent := (to_global(ahead) - to_global(behind)).normalized()
		if tangent.length_squared() < 0.5:
			continue
		# Steer along the channel using only the speed the ball ALREADY has in
		# that direction (a signed projection - its sign is also what picks
		# which way along the rail it travels). Redirecting its FULL speed
		# instead silently converted sideways momentum into along-rail
		# momentum, so a ball drifting across a mouth got launched up a climb
		# it never had the pace for. A ball genuinely shot into the mouth is
		# already aligned, so for real shots this changes nothing.
		var along: float = ball.linear_velocity.dot(tangent)
		var target: Vector2 = tangent * along
		ball.linear_velocity = ball.linear_velocity.lerp(target, clampf(guide_strength * delta, 0.0, 1.0))
		# Gentle pull toward the centreline.
		var to_center: Vector2 = to_global(curve.sample_baked(off)) - ball.global_position
		ball.linear_velocity += to_center * centering * delta
