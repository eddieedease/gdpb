extends Node

signal score_changed(score: int)
signal balls_changed(balls: int)
signal game_over
## Fired on scoring hits so the camera and other feel systems can react.
signal impact(strength: float)
## Fired when points are scored at a known table position (for popups).
signal points_scored(points: int, at: Vector2)

const NO_POS := Vector2(-99999, -99999)

const STARTING_BALLS := 3

var score := 0
var balls_left := STARTING_BALLS
var is_game_over := false


func add_score(points: int, at: Vector2 = NO_POS) -> void:
	if is_game_over:
		return
	score += points
	score_changed.emit(score)
	if at != NO_POS:
		points_scored.emit(points, at)


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
