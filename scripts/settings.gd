extends Node
## Player settings, autoloaded as Settings. Currently just the two audio levels,
## persisted to user:// so they survive a restart.
##
## Volume is applied to two audio BUSES rather than to individual players, so a
## slider affects everything on that bus - including sounds started later - and
## SoundManager doesn't have to know anything about it.

const SAVE_PATH := "user://settings.cfg"

## Defaults: music at full, effects held back so they sit under it rather than
## fighting it.
const DEFAULT_MUSIC := 1.0
const DEFAULT_SFX := 0.7
## Camera pitch, -1 (steep, looking down on the table) .. +1 (flat, looking out
## toward the horizon). 0 is the view the table was designed around. Lives here
## rather than on the view so it survives travelling between tables, and the
## restart after it.
const DEFAULT_TILT := 0.0

## Bus names created at startup if they don't already exist in the project.
const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"

signal changed

var music_volume := DEFAULT_MUSIC
var sfx_volume := DEFAULT_SFX
var camera_tilt := DEFAULT_TILT

## Camera tilt is driven by a held key, so it changes every frame while the
## player is adjusting it. Writing the file on each of those would be hundreds of
## saves for one adjustment, so it is marked dirty and flushed once things settle.
const TILT_SAVE_DELAY := 0.6
var _tilt_dirty := 0.0


func _ready() -> void:
	set_process(true)
	_ensure_buses()
	load_settings()
	_apply()


## Make sure both buses exist and route to Master, so this works on a project
## with no audio bus layout saved.
func _ensure_buses() -> void:
	for bus_name in [MUSIC_BUS, SFX_BUS]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")


func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_apply()
	save_settings()


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_apply()
	save_settings()


## Set from the live camera control. Does not write immediately - see _process.
func set_camera_tilt(v: float) -> void:
	var t := clampf(v, -1.0, 1.0)
	if is_equal_approx(t, camera_tilt):
		return
	camera_tilt = t
	_tilt_dirty = TILT_SAVE_DELAY


func _process(delta: float) -> void:
	if _tilt_dirty <= 0.0:
		return
	_tilt_dirty -= delta
	if _tilt_dirty <= 0.0:
		save_settings()


func _apply() -> void:
	_set_bus(MUSIC_BUS, music_volume)
	_set_bus(SFX_BUS, sfx_volume)
	changed.emit()


## A linear 0..1 slider mapped to decibels. linear_to_db(0) is -inf, which Godot
## handles, but muting the bus outright is cleaner and avoids denormal volumes.
func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return   # no save yet - keep the defaults
	music_volume = clampf(float(cfg.get_value("audio", "music", DEFAULT_MUSIC)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", DEFAULT_SFX)), 0.0, 1.0)
	camera_tilt = clampf(float(cfg.get_value("view", "camera_tilt", DEFAULT_TILT)), -1.0, 1.0)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("view", "camera_tilt", camera_tilt)
	cfg.save(SAVE_PATH)
	_tilt_dirty = 0.0
