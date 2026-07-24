extends Control
## Table select menu. Builds its UI in code so there is no fragile .tscn to
## maintain. Each table scene sets its own display/view on load.

const TABLES := [
	{"name": "CRUSH TABLE", "desc": "Wide, multi-level - stacked flippers", "scene": "res://scenes/crush_view.tscn"},
]

## Rename the game here.
const GAME_TITLE := "NEON CRUSH"

# Tropical pool-party palette, matching the 3D cabinet in crush_view.
const C_CORAL := Color(1.0, 0.42, 0.36)
const C_TURQ := Color(0.13, 0.83, 0.78)
const C_SUN := Color(1.0, 0.80, 0.27)
const C_DEEP := Color(0.06, 0.09, 0.20)
const C_CREAM := Color(1.0, 0.97, 0.92)

## Sunset sky, banded sun and a scrolling perspective grid - all procedural, so
## the menu needs no art assets.
const MENU_SHADER := "
shader_type canvas_item;
uniform vec3 sky_top;
uniform vec3 sky_bottom;
uniform vec3 sun_color;
uniform vec3 grid_color;
void fragment() {
	vec2 uv = UV;
	vec3 col = mix(sky_top, sky_bottom, smoothstep(0.0, 0.75, uv.y));
	vec2 c = vec2(0.5, 0.40);
	float d = length((uv - c) * vec2(1.6, 1.0));
	float sun = smoothstep(0.205, 0.195, d);
	// slice the lower half of the sun into retro bands
	float bands = step(0.42, fract((uv.y - TIME * 0.012) * 46.0));
	sun *= mix(1.0, bands, smoothstep(0.30, 0.47, uv.y));
	col = mix(col, sun_color, sun);
	col += sun_color * smoothstep(0.44, 0.16, d) * 0.28;
	// perspective grid below the horizon
	if (uv.y > 0.62) {
		float persp = (uv.y - 0.62) / 0.38;
		float z = 1.0 / max(persp, 0.02);
		float vline = abs(fract((uv.x - 0.5) * z * 0.30) - 0.5);
		float hline = abs(fract(z * 0.55 + TIME * 0.20) - 0.5);
		float g = max(smoothstep(0.46, 0.5, vline), smoothstep(0.46, 0.5, hline));
		col = mix(col, grid_color, g * clamp(persp * 1.7, 0.0, 1.0) * 0.6);
	}
	COLOR = vec4(col, 1.0);
}
"


func _ready() -> void:
	# project.godot sets this globally (correct at cold start); we set it again
	# here so returning from the portrait Classic table restores widescreen.
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP_WIDTH
	win.content_scale_size = Vector2i(1280, 720)

	_add_joypad_ui_nav()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SoundManager.play_menu_music()
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = MENU_SHADER
	var smat := ShaderMaterial.new()
	smat.shader = sh
	smat.set_shader_parameter("sky_top", Vector3(C_DEEP.r, C_DEEP.g, C_DEEP.b))
	smat.set_shader_parameter("sky_bottom", Vector3(0.42, 0.13, 0.34))
	smat.set_shader_parameter("sun_color", Vector3(C_SUN.r, C_SUN.g, C_SUN.b))
	smat.set_shader_parameter("grid_color", Vector3(C_TURQ.r, C_TURQ.g, C_TURQ.b))
	bg.material = smat
	add_child(bg)

	# CenterContainer truly centres its child regardless of the child's size.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var title := Label.new()
	title.text = GAME_TITLE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 104)
	title.add_theme_color_override("font_color", C_CREAM)
	# Chunky coral drop shadow + dark outline: reads as a lit sign rather than
	# plain text sitting on the sky.
	title.add_theme_color_override("font_shadow_color", C_CORAL)
	title.add_theme_constant_override("shadow_offset_x", 6)
	title.add_theme_constant_override("shadow_offset_y", 7)
	title.add_theme_constant_override("shadow_outline_size", 0)
	title.add_theme_color_override("font_outline_color", Color(0.12, 0.05, 0.18))
	title.add_theme_constant_override("outline_size", 10)
	box.add_child(title)

	var rule := ColorRect.new()
	rule.color = C_TURQ
	rule.custom_minimum_size = Vector2(430, 4)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(rule)

	var subtitle := Label.new()
	subtitle.text = "SELECT A TABLE"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 26)
	# Cream, not sun-yellow: it lands on top of the sun disc, where yellow on
	# yellow all but disappears.
	subtitle.add_theme_color_override("font_color", C_CREAM)
	subtitle.add_theme_constant_override("outline_size", 8)
	subtitle.add_theme_color_override("font_outline_color", Color(0.12, 0.05, 0.18))
	box.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 26)
	box.add_child(spacer)

	var first_button: Button = null
	for table in TABLES:
		var btn := Button.new()
		btn.text = "%s\n%s" % [table["name"], table["desc"]]
		btn.custom_minimum_size = Vector2(560, 104)
		btn.add_theme_font_size_override("font_size", 30)
		_style_button(btn)
		btn.pressed.connect(_on_table_chosen.bind(table["scene"]))
		box.add_child(btn)
		if first_button == null:
			first_button = btn

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 18)
	box.add_child(spacer2)

	var hint := Label.new()
	hint.text = "Arrow keys / mouse to choose    Enter to play    Esc returns here"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 19)
	hint.add_theme_color_override("font_color", C_CREAM)
	hint.modulate = Color(1, 1, 1, 0.72)
	box.add_child(hint)

	if first_button:
		first_button.grab_focus()

	# Gentle breathing on the title so the screen is never fully static.
	var tw := create_tween().set_loops()
	tw.tween_property(title, "scale", Vector2(1.03, 1.03), 1.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(title, "scale", Vector2.ONE, 1.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	title.pivot_offset = Vector2(280, 60)


## Rounded neon panel styling, with clearly distinct hover/focus states so the
## menu is readable on a controller as well as a mouse.
func _style_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(C_DEEP.r, C_DEEP.g, C_DEEP.b, 0.82)
	normal.set_corner_radius_all(16)
	normal.set_border_width_all(3)
	normal.border_color = C_TURQ
	normal.content_margin_left = 18
	normal.content_margin_right = 18

	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Color(C_CORAL.r * 0.35, C_CORAL.g * 0.22, C_CORAL.b * 0.30, 0.92)
	hover.border_color = C_CORAL

	var focus: StyleBoxFlat = hover.duplicate()
	focus.border_color = C_SUN
	focus.set_border_width_all(4)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", focus)
	btn.add_theme_stylebox_override("focus", focus)
	btn.add_theme_color_override("font_color", C_CREAM)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_focus_color", Color.WHITE)


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
