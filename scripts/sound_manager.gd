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

var _pools := {}
var _pool_index := {}

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

	if _music.stream:
		_music.finished.connect(_music.play)
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
