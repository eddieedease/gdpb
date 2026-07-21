extends Node
## Central SFX/music player. Autoloaded as SoundManager.
## Uses a small round-robin pool of AudioStreamPlayers per SFX so overlapping
## hits (e.g. two bumpers in quick succession) don't cut each other off.

const SFX := {
	"flipper": preload("res://assets/sounds/sfx_flipper.wav"),
	"bumper": preload("res://assets/sounds/sfx_bumper.wav"),
	"slingshot": preload("res://assets/sounds/sfx_slingshot.wav"),
	"target": preload("res://assets/sounds/sfx_target.wav"),
	"launch": preload("res://assets/sounds/sfx_launch.wav"),
	"whoosh": preload("res://assets/sounds/sfx_whoosh.wav"),
	"drain": preload("res://assets/sounds/sfx_drain.wav"),
	"game_over": preload("res://assets/sounds/sfx_game_over.wav"),
}

const POOL_SIZE := 4

## Menu: a single track on repeat. In-game: cycles through all three,
## looping the whole playlist.
const MENU_TRACK := preload("res://assets/sounds/bgm1.mp3")
const GAME_PLAYLIST: Array[AudioStream] = [
	preload("res://assets/sounds/bgm0.mp3"),
	preload("res://assets/sounds/bgm2.mp3"),
	preload("res://assets/sounds/bgm3.mp3"),
]

var _pools := {}
var _pool_index := {}
var _playlist: Array[AudioStream] = [MENU_TRACK]
var _playlist_index := 0

@onready var _music: AudioStreamPlayer = $Music


func _ready() -> void:
	for name in SFX.keys():
		var pool: Array[AudioStreamPlayer] = []
		for i in POOL_SIZE:
			var p := AudioStreamPlayer.new()
			p.stream = SFX[name]
			p.bus = "Master"
			add_child(p)
			pool.append(p)
		_pools[name] = pool
		_pool_index[name] = 0

	GameManager.game_over.connect(func(): play("game_over"))

	_music.finished.connect(_advance_music)
	play_menu_music()


## Menu / table-select screen: bgm1 on repeat.
func play_menu_music() -> void:
	_set_playlist([MENU_TRACK])


## In-game: bgm0/bgm2/bgm3 cycling in a loop.
func play_game_music() -> void:
	_set_playlist(GAME_PLAYLIST)


func _set_playlist(list: Array[AudioStream]) -> void:
	_playlist = list
	_playlist_index = 0
	_music.stream = _playlist[0]
	_music.play()


func _advance_music() -> void:
	_playlist_index = (_playlist_index + 1) % _playlist.size()
	_music.stream = _playlist[_playlist_index]
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
