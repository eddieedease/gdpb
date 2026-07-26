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

## Bus names created at startup if they don't already exist in the project.
const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"

signal changed

var music_volume := DEFAULT_MUSIC
var sfx_volume := DEFAULT_SFX


func _ready() -> void:
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


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.save(SAVE_PATH)
