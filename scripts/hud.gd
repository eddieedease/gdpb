extends CanvasLayer

@onready var score_label: Label = $ScoreLabel
@onready var balls_label: Label = $BallsLabel
@onready var message_label: Label = $MessageLabel


func _ready() -> void:
	GameManager.score_changed.connect(_on_score_changed)
	GameManager.balls_changed.connect(_on_balls_changed)
	GameManager.game_over.connect(_on_game_over)
	_on_score_changed(GameManager.score)
	_on_balls_changed(GameManager.balls_left)


func _on_score_changed(score: int) -> void:
	score_label.text = "SCORE  %d" % score


func _on_balls_changed(balls: int) -> void:
	balls_label.text = "BALLS  %d" % maxi(balls, 0)
	if not GameManager.is_game_over:
		message_label.visible = false


func _on_game_over() -> void:
	message_label.text = "GAME OVER\nFinal score: %d\nPress ENTER to restart" % GameManager.score
	message_label.visible = true
