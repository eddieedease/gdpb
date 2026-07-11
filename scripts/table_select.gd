extends Control
## Table select menu. Builds its UI in code so there is no fragile .tscn to
## maintain. Each table scene sets its own display/view on load.

const TABLES := [
	{"name": "CLASSIC TABLE", "desc": "The original portrait table", "scene": "res://scenes/main.tscn"},
	{"name": "CRUSH TABLE", "desc": "Wide, multi-level - stacked flippers", "scene": "res://scenes/advanced_table.tscn"},
]


func _ready() -> void:
	# Display is configured globally in project.godot (1280x720, keep_width),
	# so the menu is correct from the first frame - no runtime scaling needed.
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
