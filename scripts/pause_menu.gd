extends CanvasLayer
## In-game pause overlay: audio sliders and a way out. Opened with Esc / Start
## while the table is running.
##
## Runs with process_mode ALWAYS so it keeps working while the tree is paused,
## and every control is reachable with the keyboard and a controller (the
## sliders respond to left/right once focused).

const MenuTheme := preload("res://scripts/menu_theme.gd")

var _panel: PanelContainer
var _music_slider: HSlider
var _sfx_slider: HSlider
var _resume_btn: Button
var _open := false
var _percent_labels := {}


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	MenuTheme.add_joypad_ui_nav()
	_build()
	visible = false


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.07, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(MenuTheme.C_DEEP.r, MenuTheme.C_DEEP.g, MenuTheme.C_DEEP.b, 0.96)
	style.set_corner_radius_all(22)
	style.set_border_width_all(3)
	style.border_color = MenuTheme.C_TURQ
	style.content_margin_left = 54
	style.content_margin_right = 54
	style.content_margin_top = 34
	style.content_margin_bottom = 34
	_panel.add_theme_stylebox_override("panel", style)
	centre.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_panel.add_child(box)

	box.add_child(MenuTheme.heading("PAUSED", 62))

	var rule := ColorRect.new()
	rule.color = MenuTheme.C_TURQ
	rule.custom_minimum_size = Vector2(430, 4)
	box.add_child(rule)

	_music_slider = _add_slider(box, "MUSIC", Settings.music_volume, _on_music_changed)
	_sfx_slider = _add_slider(box, "SOUND EFFECTS", Settings.sfx_volume, _on_sfx_changed)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	box.add_child(spacer)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 18)
	box.add_child(buttons)
	_resume_btn = _add_button(buttons, "RESUME", _on_resume)
	_add_button(buttons, "MENU", _on_menu)

	var hint := Label.new()
	hint.text = "Left/Right adjusts a slider    Esc resumes"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", MenuTheme.C_CREAM)
	hint.modulate = Color(1, 1, 1, 0.7)
	box.add_child(hint)


func _add_slider(box: VBoxContainer, label: String, value: float, handler: Callable) -> HSlider:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	box.add_child(row)

	var head := HBoxContainer.new()
	row.add_child(head)
	var name_lbl := Label.new()
	name_lbl.text = label
	name_lbl.custom_minimum_size = Vector2(330, 0)
	name_lbl.add_theme_font_size_override("font_size", 26)
	name_lbl.add_theme_color_override("font_color", MenuTheme.C_CREAM)
	head.add_child(name_lbl)
	var pct := Label.new()
	pct.text = "%d%%" % roundi(value * 100.0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct.custom_minimum_size = Vector2(110, 0)
	pct.add_theme_font_size_override("font_size", 26)
	pct.add_theme_color_override("font_color", MenuTheme.C_SUN)
	head.add_child(pct)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(440, 30)
	slider.value_changed.connect(handler)
	row.add_child(slider)
	# Held by reference rather than looked up by node path: the containers are
	# built in code and get auto-generated names, so a path lookup misses.
	_percent_labels[slider] = pct
	return slider


func _add_button(row: HBoxContainer, text: String, handler: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(210, 56)
	btn.add_theme_font_size_override("font_size", 24)
	MenuTheme.style_button(btn)
	btn.pressed.connect(handler)
	row.add_child(btn)
	return btn


func _on_music_changed(v: float) -> void:
	Settings.set_music_volume(v)
	_refresh_percents()


func _on_sfx_changed(v: float) -> void:
	Settings.set_sfx_volume(v)
	_refresh_percents()


func _refresh_percents() -> void:
	for pair in [[_music_slider, Settings.music_volume], [_sfx_slider, Settings.sfx_volume]]:
		var lbl: Label = _percent_labels.get(pair[0])
		if lbl:
			lbl.text = "%d%%" % roundi(float(pair[1]) * 100.0)


func toggle() -> void:
	if _open:
		_on_resume()
	else:
		open()


func open() -> void:
	_open = true
	visible = true
	_music_slider.value = Settings.music_volume
	_sfx_slider.value = Settings.sfx_volume
	_refresh_percents()
	get_tree().paused = true
	_resume_btn.grab_focus()


func _on_resume() -> void:
	_open = false
	visible = false
	get_tree().paused = false


func _on_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/table_select.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_resume()
