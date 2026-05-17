class_name Opponent
extends Node2D

enum Action {
	IDLE,           # default + guard stance
	GUARD_DOWN,     # arms lowered after positive riddle
	KNOCKED_DOWN,   # KO'd
	TALKING,        # optional dialogue overlay
	SWING_HIGH,     # opponent telegraphs head punch (W defense)
	SWING_MID,      # opponent telegraphs body punch (S defense)
	SWING_LOW,      # opponent telegraphs hook punch (A or D defense)
	HIT_HIGH,       # player W-attack lands
	HIT_LOW,        # player A/S/D attack lands
}

enum Direction {
	LEFT,           # canonical sprite (designed for left-side action)
	RIGHT,          # flip_h = true (used for D-direction inputs)
}

const _ACTION_TOKEN := {
	Action.IDLE: "idle",
	Action.GUARD_DOWN: "guard_down",
	Action.KNOCKED_DOWN: "knocked_down",
	Action.TALKING: "talking",
	Action.SWING_HIGH: "swing_high",
	Action.SWING_MID: "swing_mid",
	Action.SWING_LOW: "swing_low",
	Action.HIT_HIGH: "hit_high",
	Action.HIT_LOW: "hit_low",
}

@onready var _sprite: Sprite2D = $Body

var _slug: String = "tofu"

func configure(opponent_slug: String) -> void:
	_slug = opponent_slug
	set_action(Action.IDLE)

func set_action(action: int, direction: int = Direction.LEFT) -> void:
	_sprite.texture = _load_texture(action)
	_sprite.flip_h = (direction == Direction.RIGHT)

func _load_texture(action: int) -> Texture2D:
	var token: String = _ACTION_TOKEN[action]
	var path := "res://assets/sprites/opponents/%s/opponent_%s_body_%s.png" % [_slug, _slug, token]
	if ResourceLoader.exists(path):
		return load(path)
	return _placeholder()

func _placeholder() -> Texture2D:
	var img := Image.create(360, 540, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.4, 0.7))
	return ImageTexture.create_from_image(img)
