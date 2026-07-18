extends Control
## Table select menu. Builds its UI in code so there is no fragile .tscn to
## maintain. Each table scene sets its own display/view on load.

const TABLES := [
	{"name": "CRUSH TABLE", "desc": "Wide, multi-level - stacked flippers", "scene": "res://scenes/crush_view.tscn"},
]


func _ready() -> void:
	# project.godot sets this globally (correct at cold start); we set it again
	# here so returning from the portrait Classic table restores widescreen.
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP_WIDTH
	win.content_scale_size = Vector2i(1280, 720)

	_add_joypad_ui_nav()
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# CenterContainer truly centres its child regardless of the child's size.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 22)
	center.add_child(box)

	var title := Label.new()
	title.text = "SELECT A TABLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	box.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	box.add_child(spacer)

	var first_button: Button = null
	for table in TABLES:
		var btn := Button.new()
		btn.text = "%s\n%s" % [table["name"], table["desc"]]
		btn.custom_minimum_size = Vector2(560, 96)
		btn.add_theme_font_size_override("font_size", 30)
		btn.pressed.connect(_on_table_chosen.bind(table["scene"]))
		box.add_child(btn)
		if first_button == null:
			first_button = btn

	var hint := Label.new()
	hint.text = "Arrow keys / mouse to choose  -  Enter to play  -  Esc returns here"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 20)
	hint.modulate = Color(1, 1, 1, 0.6)
	box.add_child(hint)

	if first_button:
		first_button.grab_focus()


func _on_table_chosen(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)


## Godot's built-in ui_* nav actions have no gamepad bindings in this project,
## so add them (D-pad + left stick to move, A to select, B to go back). Runs
## once - InputMap is global and persists across scene changes.
func _add_joypad_ui_nav() -> void:
	if _action_has_joypad("ui_accept"):
		return
	_add_joy_button("ui_accept", JOY_BUTTON_A)
	_add_joy_button("ui_cancel", JOY_BUTTON_B)
	_add_joy_button("ui_up", JOY_BUTTON_DPAD_UP)
	_add_joy_button("ui_down", JOY_BUTTON_DPAD_DOWN)
	_add_joy_button("ui_left", JOY_BUTTON_DPAD_LEFT)
	_add_joy_button("ui_right", JOY_BUTTON_DPAD_RIGHT)
	_add_joy_axis("ui_up", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis("ui_down", JOY_AXIS_LEFT_Y, 1.0)


func _action_has_joypad(action: String) -> bool:
	if not InputMap.has_action(action):
		return false
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton or e is InputEventJoypadMotion:
			return true
	return false


func _add_joy_button(action: String, btn: int) -> void:
	if not InputMap.has_action(action):
		return
	var e := InputEventJoypadButton.new()
	e.button_index = btn
	InputMap.action_add_event(action, e)


func _add_joy_axis(action: String, axis: int, value: float) -> void:
	if not InputMap.has_action(action):
		return
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	InputMap.action_add_event(action, e)
