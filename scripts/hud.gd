extends CanvasLayer

const MenuTheme := preload("res://scripts/menu_theme.gd")

## Mission progress bar geometry, centred at the top of the screen between the
## score and balls readouts.
const BAR_W := 520.0
const BAR_H := 16.0

@onready var score_label: Label = $ScoreLabel
@onready var balls_label: Label = $BallsLabel
@onready var message_label: Label = $MessageLabel

var _mission_label: Label
var _bar_track: ColorRect
var _bar_fill: ColorRect
var _bar_tween: Tween
var _mission_done := false


func _ready() -> void:
	# The three labels from hud.tscn are the loud kind, so they take the heavy
	# cut. Done here rather than in the scene so there is one place that decides.
	for lbl in [score_label, balls_label, message_label]:
		lbl.add_theme_font_override("font", MenuTheme.DISPLAY_FONT)
	_build_mission_bar()
	GameManager.score_changed.connect(_on_score_changed)
	GameManager.balls_changed.connect(_on_balls_changed)
	GameManager.game_over.connect(_on_game_over)
	GameManager.mission_progress.connect(_on_mission_progress)
	GameManager.mission_completed.connect(_on_mission_completed)
	_on_score_changed(GameManager.score)
	_on_balls_changed(GameManager.balls_left)


## The bar lives on the flat HUD rather than on the backbox panel. There is no
## room left on the panel, and more to the point the bottom of it is hidden
## behind the table's far edge from the play camera - a meter the player is meant
## to watch fill cannot live in a spot they cannot see.
func _build_mission_bar() -> void:
	var root := Control.new()
	root.name = "MissionBar"
	root.set_anchors_preset(Control.PRESET_TOP_WIDE)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.visible = false
	add_child(root)

	# A dark plate behind the whole group. Without it the text and bar land on top
	# of the lit backbox panel and the two fight each other for legibility.
	var plate := ColorRect.new()
	plate.color = Color(0.04, 0.04, 0.10, 0.55)
	plate.set_anchors_preset(Control.PRESET_CENTER_TOP)
	plate.offset_left = -BAR_W * 0.5 - 40.0
	plate.offset_right = BAR_W * 0.5 + 40.0
	plate.offset_top = 4.0
	plate.offset_bottom = 74.0
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(plate)

	_mission_label = Label.new()
	_mission_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_mission_label.offset_top = 12.0
	_mission_label.offset_bottom = 44.0
	_mission_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mission_label.add_theme_font_override("font", MenuTheme.DISPLAY_FONT)
	_mission_label.add_theme_font_size_override("font_size", 24)
	_mission_label.add_theme_color_override("font_color", MenuTheme.C_CREAM)
	_mission_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1))
	_mission_label.add_theme_constant_override("outline_size", 10)
	root.add_child(_mission_label)

	_bar_track = ColorRect.new()
	_bar_track.color = Color(0.05, 0.05, 0.12, 0.75)
	_bar_track.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_bar_track.offset_left = -BAR_W * 0.5
	_bar_track.offset_right = BAR_W * 0.5
	_bar_track.offset_top = 48.0
	_bar_track.offset_bottom = 48.0 + BAR_H
	root.add_child(_bar_track)

	_bar_fill = ColorRect.new()
	_bar_fill.color = MenuTheme.C_TURQ
	_bar_fill.anchor_bottom = 1.0
	_bar_fill.offset_right = 0.0
	_bar_track.add_child(_bar_fill)


func _on_score_changed(score: int) -> void:
	score_label.text = "SCORE  %d" % score


func _on_balls_changed(balls: int) -> void:
	balls_label.text = "BALLS  %d" % maxi(balls, 0)
	if not GameManager.is_game_over:
		message_label.visible = false


## SCORE drives the bar; any other objectives are appended as text beside it. A
## table with no score objective still gets the line, just without a bar.
func _on_mission_progress(title: String, items: Array) -> void:
	if not is_instance_valid(_mission_label) or _mission_done:
		return
	var root: Control = _mission_label.get_parent()
	if items.is_empty():
		root.visible = false
		return
	root.visible = true
	var parts := PackedStringArray()
	var score_text := ""
	var has_score := false
	for item in items:
		var got := int(item[1])
		var needed := int(item[2])
		if String(item[0]) == "SCORE":
			has_score = true
			_set_bar(float(got) / maxf(float(needed), 1.0))
			score_text = "%s / %s" % [_grouped(got), _grouped(needed)]
			continue
		parts.append(("%s OK" % item[0]) if got >= needed else "%s %d/%d" % [item[0], got, needed])
	_bar_track.visible = has_score
	var line := title
	if score_text != "":
		line += "   " + score_text
	if not parts.is_empty():
		line += "     " + "   ".join(parts)
	_mission_label.text = line


func _on_mission_completed(title: String) -> void:
	_mission_done = true
	if not is_instance_valid(_mission_label):
		return
	_mission_label.get_parent().visible = true
	_mission_label.text = "%s COMPLETE" % title
	_set_bar(1.0)
	if _bar_tween and _bar_tween.is_valid():
		_bar_tween.kill()
	_bar_tween = create_tween().set_loops()
	_bar_tween.tween_property(_bar_fill, "color", MenuTheme.C_CREAM, 0.22)
	_bar_tween.tween_property(_bar_fill, "color", MenuTheme.C_TURQ, 0.22)


func _set_bar(frac: float) -> void:
	if is_instance_valid(_bar_fill):
		_bar_fill.offset_right = BAR_W * clampf(frac, 0.0, 1.0)


func _grouped(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return ("-" if value < 0 else "") + out


func _on_game_over() -> void:
	message_label.text = "GAME OVER\nFinal score: %d" % GameManager.score
	message_label.visible = true
