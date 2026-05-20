class_name PlayerGloves
extends Node2D

enum Side { LEFT, RIGHT }
enum State { IDLE, BLOCK, PUNCH }

const SWAY_AMPLITUDE_X := 6.0
const SWAY_AMPLITUDE_Y := 4.0
const SWAY_PERIOD := 1.6
const SWAY_PHASE_OFFSET := PI  # right glove vs left glove

@onready var _left: Sprite2D = $LeftGlove
@onready var _right: Sprite2D = $RightGlove

const _STATE_TOKEN := {
	State.IDLE: "idle",
	State.BLOCK: "block",
	State.PUNCH: "punch",
}

# Initialized at declaration so any pre-`_ready()` caller (tests, editor tools)
# sees safe defaults. Scale fields are unused this task but reserved for the
# block/punch tweens Task 2.1 lands.
var _left_base_position: Vector2 = Vector2.ZERO
var _left_base_scale: Vector2 = Vector2.ONE
var _left_base_rotation: float = 0.0
var _right_base_position: Vector2 = Vector2.ZERO
var _right_base_scale: Vector2 = Vector2.ONE
var _right_base_rotation: float = 0.0

var _left_state: int = State.IDLE
var _right_state: int = State.IDLE

var _t: float = 0.0

func _ready() -> void:
	_left_base_position = _left.position
	_left_base_scale = _left.scale
	_left_base_rotation = _left.rotation
	_right_base_position = _right.position
	_right_base_scale = _right.scale
	_right_base_rotation = _right.rotation
	set_state(Side.LEFT, State.IDLE)
	set_state(Side.RIGHT, State.IDLE)

func set_state(side: int, state: int) -> void:
	var sprite := _left if side == Side.LEFT else _right
	var side_token := "left" if side == Side.LEFT else "right"
	var safe_state: int = state if _STATE_TOKEN.has(state) else State.IDLE
	var path := "res://assets/sprites/player/player_glove_%s_%s.png" % [side_token, _STATE_TOKEN[safe_state]]
	if ResourceLoader.exists(path):
		sprite.texture = load(path)
	else:
		sprite.texture = _placeholder()
	if side == Side.LEFT:
		_left_state = state
	else:
		_right_state = state

func _process(delta: float) -> void:
	_t += delta
	if _left_state == State.IDLE:
		var lo := PlayerGloves.sway_offset(_t, SWAY_AMPLITUDE_X, SWAY_AMPLITUDE_Y, SWAY_PERIOD, 0.0)
		_left.position = _left_base_position + lo
	if _right_state == State.IDLE:
		var ro := PlayerGloves.sway_offset(_t, SWAY_AMPLITUDE_X, SWAY_AMPLITUDE_Y, SWAY_PERIOD, SWAY_PHASE_OFFSET)
		_right.position = _right_base_position + ro

# Pure math — testable without scene.
static func sway_offset(t: float, amp_x: float, amp_y: float, period: float, phase: float) -> Vector2:
	var p := t * TAU / period + phase
	return Vector2(amp_x * sin(p), amp_y * cos(p))

func _placeholder() -> Texture2D:
	var img := Image.create(160, 160, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.8, 0.6, 0.5))
	return ImageTexture.create_from_image(img)
