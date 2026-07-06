extends RigidBody2D

const MAX_SPEED := 3000.0

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(_delta: float) -> void:
	if linear_velocity.length() > MAX_SPEED:
		linear_velocity = linear_velocity.normalized() * MAX_SPEED


func _process(_delta: float) -> void:
	# The ball texture is a JPG (square, no alpha) - keep it upright so the
	# corners never sweep visibly over darker artwork.
	sprite.global_rotation = 0.0


func _on_body_entered(body: Node) -> void:
	if body.has_method("on_ball_hit"):
		body.on_ball_hit(self)
