extends Node

signal score_changed(score: int)
signal balls_changed(balls: int)
signal game_over
## Fired on scoring hits so the camera and other feel systems can react.
signal impact(strength: float)
## Fired when points are scored at a known table position (for popups).
signal points_scored(points: int, at: Vector2)
## Fired when a whole group is cleared - every target in a bank knocked down,
## or every light in a rollover set lit. The 3D view throws confetti at `at`.
signal bank_completed(at: Vector2)
## Progress toward multiball changed, or multiball started/ended. The backbox
## legend reads these to show how close the player is.
signal multiball_progress(deck_clears: int, main_clears: int, light_clears: int)
signal multiball_changed(active: bool)
## The current table's mission. `items` is a list of [label, got, needed].
signal mission_progress(title: String, items: Array)
signal mission_completed(title: String)

## Set while travelling from one table to the next. It tells the arriving table
## two things: keep the score and balls (this is the same game continuing, not a
## new one), and feed the ball in at the table's entry point rather than putting
## the player back in the shooter lane.
var arriving_from_table := false

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


## Wipes the game back to the start. Called when a NEW game begins (from the
## menu, or Play Again) - deliberately NOT by a table on load, or travelling
## from one table to the next would reset the score you just earned.
func reset() -> void:
	score = 0
	balls_left = STARTING_BALLS
	is_game_over = false
	arriving_from_table = false
	score_changed.emit(score)
	balls_changed.emit(balls_left)
