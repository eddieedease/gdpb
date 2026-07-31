extends CanvasLayer
## Loading overlay, autoloaded as SceneLoader. Call SceneLoader.goto(path)
## anywhere you would have called get_tree().change_scene_to_file(path).
##
## Being an autoload CanvasLayer, it survives the scene swap it is covering -
## a loading screen that lives inside a scene would be destroyed by the very
## change it exists to hide.
##
## The resource is pulled in on a background thread so a slow disk cannot freeze
## the window, and progress is shown. The new scene's own _ready still runs on
## the main thread (crush_view builds all its 3D geometry there, which is the
## bulk of the wait) - the overlay simply holds while that happens, which is
## exactly what it is for.

const MenuTheme := preload("res://scripts/menu_theme.gd")

## Kept up for at least this long. On a fast machine the whole transition can be
## under 200ms, and an overlay that flashes up and vanishes reads as a glitch -
## better to show it deliberately or not at all.
const MIN_VISIBLE := 0.5
const FADE := 0.16
## Table-to-table travel mid-game is not "leaving for somewhere else", it is more
## like walking into the next room, so it gets the shortest cover that still
## hides the swap instead of the full deliberate loading screen.
const QUICK_MIN_VISIBLE := 0.12
const QUICK_FADE := 0.07

var _root: Control
var _bar_fill: ColorRect
var _status: Label
var _busy := false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.05, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(centre)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	centre.add_child(box)

	box.add_child(MenuTheme.heading("LOADING", 64))

	# Progress track and fill, built from plain rects so it picks up the
	# front-end palette rather than the default theme.
	var track := ColorRect.new()
	track.color = Color(MenuTheme.C_DEEP.r, MenuTheme.C_DEEP.g, MenuTheme.C_DEEP.b, 0.9)
	track.custom_minimum_size = Vector2(520, 14)
	box.add_child(track)
	_bar_fill = ColorRect.new()
	_bar_fill.color = MenuTheme.C_TURQ
	_bar_fill.anchor_bottom = 1.0
	_bar_fill.offset_right = 0.0
	track.add_child(_bar_fill)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 20)
	_status.add_theme_color_override("font_color", MenuTheme.C_CREAM)
	_status.modulate = Color(1, 1, 1, 0.75)
	box.add_child(_status)


func _set_progress(frac: float, text: String) -> void:
	if is_instance_valid(_bar_fill):
		_bar_fill.offset_right = 520.0 * clampf(frac, 0.0, 1.0)
	if is_instance_valid(_status):
		_status.text = text


## Swap to `path` behind the overlay. Pass `quick` for a transition that happens
## DURING play (travelling between tables) rather than between one part of the
## game and another - it uses a much shorter hold and fade so the game gets back
## under the player's hands as fast as the load allows.
func goto(path: String, quick := false) -> void:
	if _busy:
		return
	_busy = true
	# A caller may be a pause menu, and a paused tree would stall the fades and
	# the progress polling.
	get_tree().paused = false

	var fade: float = QUICK_FADE if quick else FADE
	var hold: float = QUICK_MIN_VISIBLE if quick else MIN_VISIBLE

	_set_progress(0.0, "")
	_root.visible = true
	_root.modulate.a = 0.0
	var shown_at := Time.get_ticks_msec()
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, fade)
	await tw.finished

	var packed: PackedScene = await _load_threaded(path)
	if packed == null:
		# Fall back to a plain blocking change rather than stranding the player
		# on a loading screen that never finishes.
		get_tree().change_scene_to_file(path)
	else:
		# The scene's _ready runs on the main thread and will stall here; say so
		# rather than leaving the bar sitting at 100% looking hung.
		_set_progress(1.0, "PREPARING")
		await get_tree().process_frame
		get_tree().change_scene_to_packed(packed)

	# Let the new scene finish _ready and actually draw before uncovering it.
	await get_tree().process_frame
	await get_tree().process_frame
	# Then hold it frozen for the rest of the wait. The new table starts playing
	# the moment it is ready, so without this the ball spends the remaining
	# fraction of a second falling behind the curtain - on an arrival that feeds
	# the ball in from the top, the player misses the start of their own shot.
	# Safe because this overlay runs with PROCESS_MODE_ALWAYS.
	get_tree().paused = true
	while Time.get_ticks_msec() - shown_at < int(hold * 1000.0):
		await get_tree().process_frame

	var out := create_tween()
	out.tween_property(_root, "modulate:a", 0.0, fade)
	await out.finished
	get_tree().paused = false
	_root.visible = false
	_busy = false


## Pull the scene in off the main thread, reporting progress. Returns null if
## the load failed or the path is bad.
func _load_threaded(path: String) -> PackedScene:
	if ResourceLoader.load_threaded_request(path) != OK:
		return null
	while true:
		var progress: Array = []
		var status := ResourceLoader.load_threaded_get_status(path, progress)
		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				var frac: float = progress[0] if progress.size() > 0 else 0.0
				_set_progress(frac * 0.9, "%d%%" % roundi(frac * 100.0))
			ResourceLoader.THREAD_LOAD_LOADED:
				return ResourceLoader.load_threaded_get(path) as PackedScene
			_:
				return null
		await get_tree().process_frame
	return null
