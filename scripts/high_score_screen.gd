extends Control
## High score table, with arcade-style 3-letter name entry when the player has
## just earned a place.
##
## Fully driven by the ui_* actions, so keyboard and controller work
## identically (MenuTheme.add_joypad_ui_nav gives the ui_* actions their gamepad
## bindings). During entry: up/down changes the letter, left/right moves between
## slots, accept confirms, cancel steps back. A keyboard can also just type the
## three characters, which is faster and what most people will reach for.

## Shared front-end look (palette, backdrop, button styling, gamepad nav).
## Preloaded rather than declared with class_name: a global class only resolves
## once the editor has rescanned, which breaks running the project directly.
const MenuTheme := preload("res://scripts/menu_theme.gd")

## Characters offered when cycling a slot with up/down.
const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "

enum Mode { ENTRY, VIEW }

var _mode: int = Mode.VIEW
var _letters := ["A", "A", "A"]
var _slot := 0
var _own_row := -1
var _score := 0

var _rows_box: VBoxContainer
var _entry_box: HBoxContainer
var _slot_labels: Array[Label] = []
var _hint: Label
var _buttons_box: HBoxContainer
var _blink := 0.0


func _ready() -> void:
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP_WIDTH
	win.content_scale_size = Vector2i(1280, 720)
	MenuTheme.add_joypad_ui_nav()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	SoundManager.play_highscore_music()

	_score = HighScores.pending_score
	# Clear it immediately: the score is now this screen's business, and leaving
	# it set would prompt again if the player came back here later.
	HighScores.pending_score = 0
	_mode = Mode.ENTRY if HighScores.qualifies(_score) else Mode.VIEW

	add_child(MenuTheme.background())

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# A dark panel behind the table. The backdrop's sun disc sits right where
	# the middle rows land, and yellow-on-yellow made the names and scores
	# almost unreadable without it.
	var panel := PanelContainer.new()
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(MenuTheme.C_DEEP.r, MenuTheme.C_DEEP.g, MenuTheme.C_DEEP.b, 0.86)
	pstyle.set_corner_radius_all(22)
	pstyle.set_border_width_all(3)
	pstyle.border_color = MenuTheme.C_TURQ
	pstyle.content_margin_left = 46
	pstyle.content_margin_right = 46
	pstyle.content_margin_top = 26
	pstyle.content_margin_bottom = 26
	panel.add_theme_stylebox_override("panel", pstyle)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	box.add_child(MenuTheme.heading("HIGH SCORES", 68))

	var rule := ColorRect.new()
	rule.color = MenuTheme.C_TURQ
	rule.custom_minimum_size = Vector2(560, 4)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(rule)

	_entry_box = HBoxContainer.new()
	_entry_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_entry_box.add_theme_constant_override("separation", 18)
	box.add_child(_entry_box)
	for i in HighScores.NAME_LENGTH:
		var slot := Label.new()
		slot.text = _letters[i]
		slot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.custom_minimum_size = Vector2(74, 96)
		slot.add_theme_font_size_override("font_size", 76)
		slot.add_theme_color_override("font_color", MenuTheme.C_CREAM)
		slot.add_theme_constant_override("outline_size", 8)
		slot.add_theme_color_override("font_outline_color", MenuTheme.C_INK)
		_entry_box.add_child(slot)
		_slot_labels.append(slot)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 2)
	box.add_child(_rows_box)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
	box.add_child(spacer)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 19)
	_hint.add_theme_color_override("font_color", MenuTheme.C_CREAM)
	_hint.modulate = Color(1, 1, 1, 0.75)
	box.add_child(_hint)

	_buttons_box = HBoxContainer.new()
	_buttons_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons_box.add_theme_constant_override("separation", 20)
	box.add_child(_buttons_box)
	_add_button("PLAY AGAIN", _on_play_again)
	_add_button("MENU", _on_menu)

	_refresh()


func _add_button(text: String, handler: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(240, 62)
	btn.add_theme_font_size_override("font_size", 24)
	MenuTheme.style_button(btn)
	btn.pressed.connect(handler)
	_buttons_box.add_child(btn)


func _process(delta: float) -> void:
	if _mode != Mode.ENTRY:
		return
	# Blink the slot being edited so the caret position is obvious.
	_blink += delta
	for i in _slot_labels.size():
		var active := i == _slot
		var a := 1.0
		if active:
			a = 0.35 + 0.65 * (0.5 + 0.5 * sin(_blink * 7.0))
		_slot_labels[i].modulate = Color(1, 1, 1, a)
		_slot_labels[i].add_theme_color_override(
				"font_color", MenuTheme.C_SUN if active else MenuTheme.C_CREAM)


func _refresh() -> void:
	_entry_box.visible = _mode == Mode.ENTRY
	_buttons_box.visible = _mode == Mode.VIEW
	if _mode == Mode.ENTRY:
		_hint.text = "NEW HIGH SCORE  %s        Up/Down letter    Left/Right slot    Enter / A to confirm" % [
				MenuTheme.group_number(_score)]
	else:
		_hint.text = "Enter / A to play again      Esc / B for the menu"
	_rebuild_rows()
	if _mode == Mode.VIEW and _buttons_box.get_child_count() > 0:
		(_buttons_box.get_child(0) as Button).grab_focus()


func _rebuild_rows() -> void:
	for c in _rows_box.get_children():
		c.queue_free()
	if HighScores.entries.is_empty():
		var empty := Label.new()
		empty.text = "no scores yet - be the first"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 24)
		empty.add_theme_color_override("font_color", MenuTheme.C_CREAM)
		empty.modulate = Color(1, 1, 1, 0.7)
		_rows_box.add_child(empty)
		return
	for i in HighScores.entries.size():
		var e: Dictionary = HighScores.entries[i]
		var mine := i == _own_row
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(560, 0)
		row.add_theme_constant_override("separation", 0)
		_rows_box.add_child(row)
		# Rank / name / score as three fixed columns so the digits line up.
		row.add_child(_cell("%d" % (i + 1), 80, HORIZONTAL_ALIGNMENT_RIGHT, mine))
		row.add_child(_cell("   " + str(e["name"]), 220, HORIZONTAL_ALIGNMENT_LEFT, mine))
		row.add_child(_cell(MenuTheme.group_number(int(e["score"])), 260,
				HORIZONTAL_ALIGNMENT_RIGHT, mine))


func _cell(text: String, width: int, align: int, mine: bool) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(width, 0)
	lbl.horizontal_alignment = align
	lbl.add_theme_font_size_override("font_size", 30 if mine else 27)
	# The player's own row is called out in sun yellow; everything else is cream.
	lbl.add_theme_color_override("font_color",
			MenuTheme.C_SUN if mine else MenuTheme.C_CREAM)
	lbl.add_theme_constant_override("outline_size", 7)
	lbl.add_theme_color_override("font_outline_color", MenuTheme.C_INK)
	if not mine:
		lbl.modulate = Color(1, 1, 1, 0.88)
	return lbl


func _unhandled_input(event: InputEvent) -> void:
	if _mode == Mode.ENTRY:
		_entry_input(event)
		return
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		_on_menu()


func _entry_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		accept_event()
		_cycle(1)
	elif event.is_action_pressed("ui_down"):
		accept_event()
		_cycle(-1)
	elif event.is_action_pressed("ui_right"):
		accept_event()
		_move_slot(1)
	elif event.is_action_pressed("ui_left"):
		accept_event()
		_move_slot(-1)
	elif event.is_action_pressed("ui_accept"):
		accept_event()
		if _slot < HighScores.NAME_LENGTH - 1:
			_move_slot(1)
		else:
			_submit()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_BACKSPACE:
			accept_event()
			_letters[_slot] = "A"
			_slot_labels[_slot].text = "A"
			_move_slot(-1)
			return
		# Straight typing: the fast path on a keyboard.
		var ch := String.chr(key.unicode).to_upper()
		if ch.length() == 1 and LETTERS.find(ch) != -1:
			accept_event()
			_letters[_slot] = ch
			_slot_labels[_slot].text = ch
			SoundManager.play("target", 1.4)
			if _slot < HighScores.NAME_LENGTH - 1:
				_move_slot(1)


func _cycle(step: int) -> void:
	var idx := LETTERS.find(_letters[_slot])
	idx = wrapi(idx + step, 0, LETTERS.length())
	_letters[_slot] = LETTERS[idx]
	_slot_labels[_slot].text = _letters[_slot]
	SoundManager.play("target", 1.5)


func _move_slot(step: int) -> void:
	_slot = clampi(_slot + step, 0, HighScores.NAME_LENGTH - 1)
	_blink = 0.0


func _submit() -> void:
	var entered := "".join(_letters).strip_edges()
	if entered == "":
		entered = HighScores.DEFAULT_NAME
	_own_row = HighScores.submit(entered, _score)
	_mode = Mode.VIEW
	SoundManager.play("launch")
	_refresh()


func _on_play_again() -> void:
	SceneLoader.goto("res://scenes/crush_view.tscn")


func _on_menu() -> void:
	SceneLoader.goto("res://scenes/table_select.tscn")
