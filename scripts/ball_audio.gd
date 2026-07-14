extends AudioStreamPlayer2D
## Continuous rolling rumble, tied to the ball's speed. Loops a short
## seamless noise texture and rides its volume/pitch on linear_velocity so it
## fades out when the ball is resting or barely moving and swells when it's
## flying across the playfield.

const MIN_SPEED := 40.0
const MAX_SPEED := 1800.0
const MIN_VOLUME_DB := -32.0
const MAX_VOLUME_DB := -6.0
const SILENT_DB := -80.0

@onready var _ball: RigidBody2D = get_parent()


func _ready() -> void:
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	volume_db = SILENT_DB
	play()


func _physics_process(_delta: float) -> void:
	var speed := _ball.linear_velocity.length()
	if speed < MIN_SPEED:
		volume_db = SILENT_DB
		return
	var t := clampf(speed / MAX_SPEED, 0.0, 1.0)
	volume_db = lerpf(MIN_VOLUME_DB, MAX_VOLUME_DB, t)
	pitch_scale = lerpf(0.85, 1.5, t)
