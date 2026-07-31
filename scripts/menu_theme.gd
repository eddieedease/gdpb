extends RefCounted
## Shared look and input setup for the front-end screens (title screen, high
## score table): the tropical palette, the procedural sunset background, the
## neon button styling, and the gamepad bindings for menu navigation. Kept in
## one place so the screens cannot drift apart visually.

# Tropical pool-party palette, matching the 3D cabinet in crush_view.
const C_CORAL := Color(1.0, 0.42, 0.36)
const C_TURQ := Color(0.13, 0.83, 0.78)
const C_SUN := Color(1.0, 0.80, 0.27)
const C_DEEP := Color(0.06, 0.09, 0.20)
const C_CREAM := Color(1.0, 0.97, 0.92)
const C_INK := Color(0.12, 0.05, 0.18)

## Astron Boy - a retro-futuristic display family, bundled in assets/fonts/ so it
## ships with the game rather than depending on what the player has installed.
## The upright cut is the project's default font (gui/theme/custom_font) and so
## reaches every Control and Label3D on its own; it is named here only for the
## places that build text without the theme.
##
## The family also has "Wonder" (outlined) and "Video" (scanline) cuts. Both look
## great at marquee size and turn to mush below ~30px, so neither is wired in -
## swap one in here if a screen wants that effect at a large size.
const DISPLAY_FONT := preload("res://assets/fonts/Astron Boy.otf")
## The slanted cut, for headings only. On a title the lean reads as speed, which
## suits an arcade cabinet; on body text it just hurts legibility.
const TITLE_FONT := preload("res://assets/fonts/Astron Boy Italic.otf")

## Sunset sky, banded sun and a scrolling perspective grid - all procedural, so
## the front end needs no art assets.
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


## Full-screen animated backdrop. Add it first so everything draws over it.
static func background() -> ColorRect:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = MENU_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("sky_top", Vector3(C_DEEP.r, C_DEEP.g, C_DEEP.b))
	mat.set_shader_parameter("sky_bottom", Vector3(0.42, 0.13, 0.34))
	mat.set_shader_parameter("sun_color", Vector3(C_SUN.r, C_SUN.g, C_SUN.b))
	mat.set_shader_parameter("grid_color", Vector3(C_TURQ.r, C_TURQ.g, C_TURQ.b))
	bg.material = mat
	return bg


## Big display text with the chunky coral shadow and dark outline.
static func heading(text: String, size: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", TITLE_FONT)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", C_CREAM)
	lbl.add_theme_color_override("font_shadow_color", C_CORAL)
	lbl.add_theme_constant_override("shadow_offset_x", int(size * 0.06))
	lbl.add_theme_constant_override("shadow_offset_y", int(size * 0.07))
	lbl.add_theme_constant_override("shadow_outline_size", 0)
	lbl.add_theme_color_override("font_outline_color", C_INK)
	lbl.add_theme_constant_override("outline_size", maxi(int(size * 0.1), 6))
	return lbl


## Rounded neon panel styling, with clearly distinct hover/focus states so the
## menu is readable on a controller as well as a mouse.
static func style_button(btn: Button) -> void:
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

	btn.add_theme_font_override("font", DISPLAY_FONT)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", focus)
	btn.add_theme_stylebox_override("focus", focus)
	btn.add_theme_color_override("font_color", C_CREAM)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_focus_color", Color.WHITE)


## 1234500 -> "1,234,500"; a bare digit run is unreadable at a glance.
static func group_number(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if value < 0 else out


## Godot's built-in ui_* nav actions have no gamepad bindings in this project,
## so add them (D-pad + left stick to move, A to select, B to go back). Runs
## once - InputMap is global and persists across scene changes. Every front-end
## screen calls this, so a screen reached without passing through the menu
## (e.g. the high score table straight after a game) is still controllable.
static func add_joypad_ui_nav() -> void:
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
	_add_joy_axis("ui_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("ui_right", JOY_AXIS_LEFT_X, 1.0)


static func _action_has_joypad(action: String) -> bool:
	if not InputMap.has_action(action):
		return false
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton or e is InputEventJoypadMotion:
			return true
	return false


static func _add_joy_button(action: String, btn: int) -> void:
	if not InputMap.has_action(action):
		return
	var e := InputEventJoypadButton.new()
	e.button_index = btn
	InputMap.action_add_event(action, e)


static func _add_joy_axis(action: String, axis: int, value: float) -> void:
	if not InputMap.has_action(action):
		return
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	InputMap.action_add_event(action, e)
