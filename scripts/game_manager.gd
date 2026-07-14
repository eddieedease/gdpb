extends Node

signal score_changed(score: int)
signal balls_changed(balls: int)
signal game_over
## Fired on scoring hits so the camera and other feel systems can react.
signal impact(strength: float)

const STARTING_BALLS := 3

var score := 0
var balls_left := STARTING_BALLS
var is_game_over := false


func add_score(points: int) -> void:
	if is_game_over:
		return
	score += points
	score_changed.emit(score)


func lose_ball() -> void:
	balls_left -= 1
	balls_changed.emit(balls_left)
	if balls_left <= 0:
		is_game_over = true
		game_over.emit()


func reset() -> void:
	score = 0
	balls_left = STARTING_BALLS
	is_game_over = false
	score_changed.emit(score)
	balls_changed.emit(balls_left)
