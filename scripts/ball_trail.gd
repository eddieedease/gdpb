extends Line2D
## Fading motion trail behind the ball. Runs top_level so its points stay in
## world space instead of getting dragged around by the ball's own rotation.

const MAX_POINTS := 14
const MIN_DIST := 4.0

var _pts: PackedVector2Array = []


func _ready() -> void:
	top_level = true
	width = 10.0
	texture_mode = Line2D.LINE_TEXTURE_STRETCH
	joint_mode = Line2D.LINE_JOINT_ROUND
	begin_cap_mode = Line2D.LINE_CAP_ROUND
	end_cap_mode = Line2D.LINE_CAP_ROUND

	var grad := Gradient.new()
	grad.set_color(0, Color(0.6, 0.85, 1.0, 0.0))
	grad.set_color(1, Color(0.85, 0.95, 1.0, 0.55))
	gradient = grad

	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.15))
	curve.add_point(Vector2(1.0, 1.0))
	width_curve = curve


func _process(_delta: float) -> void:
	var pos: Vector2 = get_parent().global_position
	if _pts.is_empty() or pos.distance_to(_pts[_pts.size() - 1]) > MIN_DIST:
		_pts.append(pos)
		if _pts.size() > MAX_POINTS:
			_pts.remove_at(0)
		points = _pts
