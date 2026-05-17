class_name PlayerGloves
extends Node2D

enum Side { LEFT, RIGHT }
enum State { IDLE, BLOCK, PUNCH }

@onready var _left: Sprite2D = $LeftGlove
@onready var _right: Sprite2D = $RightGlove

const _STATE_PREFIX := {
	State.IDLE: "idle",
	State.BLOCK: "block",
	State.PUNCH: "punch",
}

func _ready() -> void:
	set_state(Side.LEFT, State.IDLE)
	set_state(Side.RIGHT, State.IDLE)

func set_state(side: int, state: int) -> void:
	var sprite := _left if side == Side.LEFT else _right
	var side_token := "left" if side == Side.LEFT else "right"
	var path := "res://assets/sprites/player/player_glove_%s_%s.png" % [side_token, _STATE_PREFIX[state]]
	if ResourceLoader.exists(path):
		sprite.texture = load(path)
	else:
		sprite.texture = _placeholder()

func _placeholder() -> Texture2D:
	var img := Image.create(160, 160, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.8, 0.6, 0.5))
	return ImageTexture.create_from_image(img)
