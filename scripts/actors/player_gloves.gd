class_name PlayerGloves
extends Node2D

const SimonSequence = preload("res://scripts/game/simon_sequence.gd")

enum Side { LEFT, RIGHT }
enum State { IDLE, BLOCK, PUNCH }

const SWAY_AMPLITUDE_X := 6.0
const SWAY_AMPLITUDE_Y := 4.0
const SWAY_PERIOD := 1.6
const SWAY_PHASE_OFFSET := PI

# Per-WASD-direction block targets. Both gloves move.
const BLOCK_TARGETS := {
	SimonSequence.Direction.HEAD:  { "left": Vector2(600, 700),  "right": Vector2(1320, 700) },
	SimonSequence.Direction.BODY:  { "left": Vector2(600, 920),  "right": Vector2(1320, 920) },
	SimonSequence.Direction.LEFT:  { "left": Vector2(440, 860),  "right": Vector2(1360, 860) },
	SimonSequence.Direction.RIGHT: { "left": Vector2(560, 860),  "right": Vector2(1480, 860) },
}
const BLOCK_OUT_DURATION := 0.20
const BLOCK_RETURN_DURATION := 0.30
const BLOCK_OUT_TRANSITION := Tween.TRANS_BACK
const BLOCK_RETURN_TRANSITION := Tween.TRANS_QUAD

# Per-WASD-direction punch targets. Only the punching glove moves.
# Rotations tilt INWARD (toward the opponent's centerline): positive sign for
# the left glove (top tilts right), negative for the right glove (top tilts left).
const PUNCH_TARGETS := {
	SimonSequence.Direction.LEFT:  { "glove": Side.LEFT,  "pos": Vector2(700, 700),  "scale": 0.65, "rotation_deg": +15.0 },
	SimonSequence.Direction.RIGHT: { "glove": Side.RIGHT, "pos": Vector2(1220, 700), "scale": 0.65, "rotation_deg": -15.0 },
	SimonSequence.Direction.BODY:  { "glove": Side.LEFT,  "pos": Vector2(900, 780),  "scale": 0.70, "rotation_deg": +10.0 },
	SimonSequence.Direction.HEAD:  { "glove": Side.RIGHT, "pos": Vector2(1020, 500), "scale": 0.55, "rotation_deg": -20.0 },
}
const PUNCH_OUT_DURATION := 0.20
const PUNCH_RETURN_DURATION := 0.30
const PUNCH_OUT_TRANSITION := Tween.TRANS_BACK
const PUNCH_RETURN_TRANSITION := Tween.TRANS_QUAD

@onready var _left: Sprite2D = $LeftGlove
@onready var _right: Sprite2D = $RightGlove

const _STATE_TOKEN := {
	State.IDLE: "idle",
	State.BLOCK: "block",
	State.PUNCH: "punch",
}

# Initialized at declaration so any pre-`_ready()` caller (tests, editor tools)
# sees safe defaults.
var _left_base_position: Vector2 = Vector2.ZERO
var _left_base_scale: Vector2 = Vector2.ONE
var _left_base_rotation: float = 0.0
var _right_base_position: Vector2 = Vector2.ZERO
var _right_base_scale: Vector2 = Vector2.ONE
var _right_base_rotation: float = 0.0

var _left_state: int = State.IDLE
var _right_state: int = State.IDLE

var _left_tween: Tween = null
var _right_tween: Tween = null

# Last applied (state, direction) pose. When a new pose matches this exactly
# (e.g. two A-blocks in a row), the tween targets are identical to the current
# rest, so the second call produces no visible motion — `_apply_*_pose` snaps
# back to base first to force a fresh re-tween. Reset on IDLE.
var _last_pose_state: int = State.IDLE
var _last_pose_direction: int = -1

var _t: float = 0.0

func _ready() -> void:
	_left_base_position = _left.position
	_left_base_scale = _left.scale
	_left_base_rotation = _left.rotation
	_right_base_position = _right.position
	_right_base_scale = _right.scale
	_right_base_rotation = _right.rotation
	set_state(State.IDLE)

func set_state(state: int, direction: int = -1) -> void:
	match state:
		State.IDLE:
			_last_pose_state = State.IDLE
			_last_pose_direction = -1
			_set_glove_state(Side.LEFT, State.IDLE)
			_set_glove_state(Side.RIGHT, State.IDLE)
		State.BLOCK:
			assert(direction >= 0, "BLOCK requires a direction (SimonSequence.Direction)")
			_apply_block_pose(direction)
		State.PUNCH:
			assert(direction >= 0, "PUNCH requires a direction (SimonSequence.Direction)")
			_apply_punch_pose(direction)

func _apply_block_pose(direction: int) -> void:
	var is_repeat := _last_pose_state == State.BLOCK and _last_pose_direction == direction
	_last_pose_state = State.BLOCK
	_last_pose_direction = direction
	if is_repeat:
		_kill_glove_tween(Side.LEFT)
		_kill_glove_tween(Side.RIGHT)
		_snap_glove_to_base(Side.LEFT)
		_snap_glove_to_base(Side.RIGHT)
	var targets: Dictionary = BLOCK_TARGETS[direction]
	_set_glove_state(Side.LEFT, State.BLOCK)
	_set_glove_state(Side.RIGHT, State.BLOCK)
	_tween_glove_to(Side.LEFT, targets["left"], _left_base_scale, _left_base_rotation, BLOCK_OUT_DURATION, BLOCK_OUT_TRANSITION, Tween.EASE_OUT)
	_tween_glove_to(Side.RIGHT, targets["right"], _right_base_scale, _right_base_rotation, BLOCK_OUT_DURATION, BLOCK_OUT_TRANSITION, Tween.EASE_OUT)

func _apply_punch_pose(direction: int) -> void:
	var spec: Dictionary = PUNCH_TARGETS[direction]
	var side: int = spec["glove"]
	var other_side: int = Side.RIGHT if side == Side.LEFT else Side.LEFT
	var is_repeat := _last_pose_state == State.PUNCH and _last_pose_direction == direction
	_last_pose_state = State.PUNCH
	_last_pose_direction = direction
	if is_repeat:
		_kill_glove_tween(side)
		_snap_glove_to_base(side)
	# Snap the non-punching glove back to base so a previous A-punch doesn't
	# leave the left glove lingering when D fires next (and vice versa).
	_set_glove_state(other_side, State.IDLE)
	_set_glove_state(side, State.PUNCH)
	var base_scale: Vector2 = _left_base_scale if side == Side.LEFT else _right_base_scale
	var target_scale: Vector2 = base_scale * spec["scale"]
	var target_rotation: float = deg_to_rad(spec["rotation_deg"])
	_tween_glove_to(side, spec["pos"], target_scale, target_rotation, PUNCH_OUT_DURATION, PUNCH_OUT_TRANSITION, Tween.EASE_OUT)

func _set_glove_state(side: int, state: int) -> void:
	var sprite := _left if side == Side.LEFT else _right
	var side_token := "left" if side == Side.LEFT else "right"
	var safe_state: int = state if _STATE_TOKEN.has(state) else State.IDLE
	var path := "res://assets/sprites/player/player_glove_%s_%s.png" % [side_token, _STATE_TOKEN[safe_state]]
	if ResourceLoader.exists(path):
		sprite.texture = load(path)
	else:
		sprite.texture = _placeholder()
	# Tween ownership: `_tween_glove_to` kills the prior tween before creating a
	# new one on the BLOCK/PUNCH paths. The only path that halts without starting
	# a new tween is IDLE — kill there, then snap to base in the same step.
	if side == Side.LEFT:
		_left_state = state
		if state == State.IDLE:
			_kill_glove_tween(Side.LEFT)
			_snap_glove_to_base(Side.LEFT)
	else:
		_right_state = state
		if state == State.IDLE:
			_kill_glove_tween(Side.RIGHT)
			_snap_glove_to_base(Side.RIGHT)

func _tween_glove_to(side: int, target_pos: Vector2, target_scale: Vector2, target_rotation: float, duration: float, transition: int, ease: int) -> void:
	var sprite := _left if side == Side.LEFT else _right
	_kill_glove_tween(side)
	var t := create_tween().set_parallel(true)
	t.set_trans(transition).set_ease(ease)
	t.tween_property(sprite, "position", target_pos, duration)
	t.tween_property(sprite, "scale", target_scale, duration)
	t.tween_property(sprite, "rotation", target_rotation, duration)
	if side == Side.LEFT:
		_left_tween = t
	else:
		_right_tween = t

func _kill_glove_tween(side: int) -> void:
	var t := _left_tween if side == Side.LEFT else _right_tween
	if t != null and t.is_running():
		t.kill()
	if side == Side.LEFT:
		_left_tween = null
	else:
		_right_tween = null

func _snap_glove_to_base(side: int) -> void:
	if side == Side.LEFT:
		_left.position = _left_base_position
		_left.scale = _left_base_scale
		_left.rotation = _left_base_rotation
	else:
		_right.position = _right_base_position
		_right.scale = _right_base_scale
		_right.rotation = _right_base_rotation

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
