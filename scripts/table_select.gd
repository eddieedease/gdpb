extends Control
## Table select menu. Builds its UI in code so there is no fragile .tscn to
## maintain. Each table scene sets its own display/view on load.

const TABLES := [
	{"name": "CRUSH TABLE", "desc": "Wide, multi-level - stacked flippers", "scene": "res://scenes/crush_view.tscn"},
]

## Shared front-end look (palette, backdrop, button styling, gamepad nav).
## Preloaded rather than declared with class_name: a global class only resolves
## once the editor has rescanned, which breaks running the project directly.
const MenuTheme := preload("res://scripts/menu_theme.gd")

## Rename the game here.
const GAME_TITLE := "NEON CRUSH"



func _ready() -> void:
	# project.godot sets this globally (correct at cold start); we set it again
	# here so returning from the portrait Classic table restores widescreen.
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP_WIDTH
	win.content_scale_size = Vector2i(1280, 720)

	MenuTheme.add_joypad_ui_nav()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SoundManager.play_menu_music()
	set_anchors_preset(Control.PRESET_FULL_RECT)

	add_child(MenuTheme.background())

	# CenterContainer truly centres its child regardless of the child's size.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var title := MenuTheme.heading(GAME_TITLE, 104)
	box.add_child(title)

	var rule := ColorRect.new()
	rule.color = MenuTheme.C_TURQ
	rule.custom_minimum_size = Vector2(430, 4)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(rule)

	var subtitle := Label.new()
	subtitle.text = "SELECT A TABLE"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 26)
	# Cream, not sun-yellow: it lands on top of the sun disc, where yellow on
	# yellow all but disappears.
	subtitle.add_theme_color_override("font_color", MenuTheme.C_CREAM)
	subtitle.add_theme_constant_override("outline_size", 8)
	subtitle.add_theme_color_override("font_outline_color", MenuTheme.C_INK)
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
		MenuTheme.style_button(btn)
		btn.pressed.connect(_on_table_chosen.bind(table["scene"]))
		box.add_child(btn)
		if first_button == null:
			first_button = btn

	var scores_btn := Button.new()
	scores_btn.text = "HIGH SCORES"
	scores_btn.custom_minimum_size = Vector2(560, 60)
	scores_btn.add_theme_font_size_override("font_size", 24)
	MenuTheme.style_button(scores_btn)
	scores_btn.pressed.connect(_on_high_scores)
	box.add_child(scores_btn)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 18)
	box.add_child(spacer2)

	var hint := Label.new()
	hint.text = "Arrow keys / mouse to choose    Enter to play    Esc returns here"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 19)
	hint.add_theme_color_override("font_color", MenuTheme.C_CREAM)
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


func _on_table_chosen(scene_path: String) -> void:
	# Choosing a table from the menu is what starts a NEW game - tables no
	# longer reset on load, so that travelling between them keeps the score.
	GameManager.reset()
	SceneLoader.goto(scene_path)


func _on_high_scores() -> void:
	SceneLoader.goto("res://scenes/high_scores.tscn")
