extends CanvasLayer
## Development cheat codes, autoloaded as Cheats. Type a code on the keyboard
## while playing and it fires - "pop" jumps straight to the next table, and so
## on. A toast in the corner confirms it registered.
##
## Codes are registered by whoever implements them (see table_game.gd) rather
## than listed here, so the effect and its name live in one place and a table
## can add its own without this file knowing anything about it.
##
## OFF in exported release builds. Pass --cheats to force them on in one, which
## is handy for testing a build without shipping cheats to players.

const MenuTheme := preload("res://scripts/menu_theme.gd")

## Letters typed more than this far apart don't count as the same code, so a
## stray keypress minutes ago can't combine with what you type now.
const GAP := 1.5
const TOAST_TIME := 1.6

signal code_entered(code: String)

var enabled := false

var _codes := {}          # code -> [label, callable]
var _buffer := ""
var _last_key := 0.0
var _toast: Label


func _ready() -> void:
	enabled = OS.is_debug_build() or "--cheats" in OS.get_cmdline_args()
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_toast()


func _build_toast() -> void:
	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.add_theme_color_override("font_color", MenuTheme.C_CREAM)
	_toast.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.10))
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_toast.offset_left = 24
	_toast.offset_top = -52
	_toast.offset_bottom = -20
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	add_child(_toast)


## Make `code` do `action`. `label` is what the toast says when it fires.
## Registering the same code again replaces it, which is what makes this safe to
## call from every table's _ready.
func register(code: String, label: String, action: Callable) -> void:
	_codes[code.to_lower()] = [label, action]


## Unhandled, so a focused text field (high score initials) gets the keystroke
## first and typing "POP" as your name doesn't teleport you.
func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var ch := char(key.unicode).to_lower()
	if ch.length() != 1 or not ch.is_valid_identifier():
		return   # letters and underscore only; digits and punctuation reset nothing

	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_key > GAP:
		_buffer = ""
	_last_key = now
	_buffer += ch
	if _buffer.length() > 16:
		_buffer = _buffer.substr(_buffer.length() - 16)

	for code in _codes:
		if not _buffer.ends_with(code):
			continue
		var entry: Array = _codes[code]
		var action: Callable = entry[1]
		# Tables come and go; a code left behind by a freed one is just dropped.
		if not action.is_valid() or not is_instance_valid(action.get_object()):
			_codes.erase(code)
			continue
		_buffer = ""
		print("[cheat] %s" % code)
		_show_toast("%s  -  %s" % [code.to_upper(), entry[0]])
		action.call()
		code_entered.emit(code)
		return


func _show_toast(text: String) -> void:
	if not is_instance_valid(_toast):
		return
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(TOAST_TIME)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.35)
