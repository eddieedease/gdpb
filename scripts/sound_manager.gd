extends Node
## Central SFX/music player. Autoloaded as SoundManager.
## Uses a small round-robin pool of AudioStreamPlayers per SFX so overlapping
## hits (e.g. two bumpers in quick succession) don't cut each other off.

const SFX := {
	"flipper": preload("res://assets/sounds/sfx_flipper.wav"),
	"bumper": preload("res://assets/sounds/sfx_bumper.wav"),
	"slingshot": preload("res://assets/sounds/sfx_slingshot.wav"),
	"target": preload("res://assets/sounds/sfx_target.wav"),
	"drop": preload("res://assets/sounds/sfx_drop.wav"),
	"spinner": preload("res://assets/sounds/sfx_spinner.wav"),
	"launch": preload("res://assets/sounds/sfx_launch.wav"),
	"whoosh": preload("res://assets/sounds/sfx_whoosh.wav"),
	"drain": preload("res://assets/sounds/sfx_drain.wav"),
	"game_over": preload("res://assets/sounds/sfx_game_over.wav"),
}

const POOL_SIZE := 4

## One track per context, each on repeat. bgmain is the table's own theme; the
## front-end screens get their own tracks so moving between them is audible.
## Swapping any of these is a one-line change.
const GAME_TRACK := preload("res://assets/sounds/bgmain.mp3")
const MENU_TRACK := preload("res://assets/sounds/bgm2.mp3")
const HIGHSCORE_TRACK := preload("res://assets/sounds/bgm0.mp3")

## Menu music is deliberately quieter and a touch slower than in-game music -
## the title screen should feel like a poolside lounge, not a match in
## progress. Pitch below ~0.9 starts to sound obviously slowed down.
const MENU_VOLUME_DB := -9.0
const MENU_PITCH := 0.92
const MENU_FADE_IN := 2.5
const GAME_VOLUME_DB := -2.0
const GAME_PITCH := 1.0

var _pools := {}
var _pool_index := {}
var _playlist: Array[AudioStream] = [MENU_TRACK]
var _playlist_index := 0
var _music_volume_db := 0.0

@onready var _music: AudioStreamPlayer = $Music


func _ready() -> void:
	for name in SFX.keys():
		var pool: Array[AudioStreamPlayer] = []
		for i in POOL_SIZE:
			var p := AudioStreamPlayer.new()
			p.stream = SFX[name]
			# Routed through the SFX bus so the settings slider governs every
			# effect at once, including pools created here at startup.
			p.bus = Settings.SFX_BUS
			add_child(p)
			pool.append(p)
		_pools[name] = pool
		_pool_index[name] = 0

	GameManager.game_over.connect(func(): play("game_over"))

	_music.bus = Settings.MUSIC_BUS
	_music.finished.connect(_advance_music)
	play_menu_music()


## Menu / table-select screen: bgm1 on repeat, played as LOUNGE music rather
## than game music - held well back, eased down a little in pitch so it sits
## slower and warmer, and faded in instead of slamming on at full volume. To
## use a different track entirely, just point MENU_TRACK at another bgm file.
func play_menu_music() -> void:
	_set_playlist([MENU_TRACK], MENU_VOLUME_DB, MENU_PITCH, MENU_FADE_IN)


## In-game: the table's own theme, at full energy.
func play_game_music() -> void:
	_set_playlist([GAME_TRACK], GAME_VOLUME_DB, GAME_PITCH, 0.6)


## High score table: lounge treatment like the menu, but its own track.
func play_highscore_music() -> void:
	_set_playlist([HIGHSCORE_TRACK], MENU_VOLUME_DB, MENU_PITCH, 1.4)


func _set_playlist(list: Array[AudioStream], volume_db: float, pitch: float, fade_in: float) -> void:
	_playlist = list
	_playlist_index = 0
	_music_volume_db = volume_db
	_music.pitch_scale = pitch
	_music.stream = _playlist[0]
	_music.volume_db = volume_db
	_music.play()
	if fade_in > 0.0:
		_music.volume_db = volume_db - 24.0
		var tw := create_tween()
		tw.tween_property(_music, "volume_db", volume_db, fade_in) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _advance_music() -> void:
	_playlist_index = (_playlist_index + 1) % _playlist.size()
	_music.stream = _playlist[_playlist_index]
	_music.volume_db = _music_volume_db
	_music.play()


## Play an sfx by name, optionally with slight pitch/volume variance for feel.
func play(name: String, pitch := 1.0, volume_db := 0.0) -> void:
	if not _pools.has(name):
		return
	var pool: Array = _pools[name]
	var i: int = _pool_index[name]
	var player: AudioStreamPlayer = pool[i]
	_pool_index[name] = (i + 1) % pool.size()
	player.pitch_scale = pitch * randf_range(0.96, 1.04)
	player.volume_db = volume_db
	player.play()
