class_name Opponent
extends Node2D

const OpponentAnimationProfile = preload("res://scripts/data/opponent_animation_profile.gd")

enum Action {
	IDLE,           # default + guard stance
	GUARD_DOWN,     # arms lowered after positive riddle (no bounce — post first hit)
	KNOCKED_DOWN,   # KO'd / fallen
	TALKING,        # optional dialogue overlay
	SWING_HIGH,     # opponent telegraphs head punch (W defense)
	SWING_MID,      # opponent telegraphs body punch (S defense)
	SWING_LOW,      # opponent telegraphs hook punch (A or D defense)
	HIT_HIGH,       # player W-attack lands
	HIT_BODY,       # player S-attack lands (body)
	HIT_LOW,        # player A or D side-attack lands
}

enum Direction {
	LEFT,
	RIGHT,
}

enum ContinuousMode {
	STILL,
	IDLE_BOB,
	GUARD_BOUNCE,
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
	Action.HIT_BODY: "hit_low",  # deliberate alias — shares texture with HIT_LOW; recoil direction diverges in Task 3.3
	Action.HIT_LOW: "hit_low",
}

@onready var _sprite: Sprite2D = $Body

var _slug: String = "tofu"
var _profile: OpponentAnimationProfile = null

# Initialized at declaration so `_reset_to_base()` is safe to call even
# before `_ready()` has captured the scene's authored transform.
var _base_position: Vector2 = Vector2.ZERO
var _base_scale: Vector2 = Vector2.ONE
var _base_rotation: float = 0.0

var _continuous_mode: int = ContinuousMode.STILL
var _continuous_mode_t: float = 0.0
var _current_tween: Tween = null

func _ready() -> void:
	_base_position = _sprite.position
	_base_scale = _sprite.scale
	_base_rotation = _sprite.rotation

func configure(opponent_slug: String, profile: OpponentAnimationProfile = null) -> void:
	_slug = opponent_slug
	if profile != null:
		_profile = profile
	elif _profile == null:
		_profile = load("res://data/opponent_animation/tofu.tres") as OpponentAnimationProfile
	set_action(Action.IDLE)

func set_action(action: int, direction: int = Direction.LEFT) -> void:
	_kill_current_tween()
	_reset_to_base()
	_sprite.texture = _load_texture(action)
	_sprite.flip_h = (direction == Direction.RIGHT)
	if action == Action.IDLE:
		_set_continuous_mode(ContinuousMode.IDLE_BOB)
	else:
		_set_continuous_mode(ContinuousMode.STILL)
	if action == Action.SWING_HIGH or action == Action.SWING_MID or action == Action.SWING_LOW:
		_play_attack_lunge(action, direction)

func _play_attack_lunge(action: int, direction: int) -> void:
	var shift := Opponent.swing_shift(action, direction, _profile.attack_lunge_shift_x)
	var target_pos := _base_position + Vector2(shift, 0.0)
	var target_scale := _base_scale * _profile.attack_lunge_scale_peak
	_kill_current_tween()
	var t := create_tween()
	var out_p := t.parallel()
	out_p.tween_property(_sprite, "position", target_pos, _profile.attack_lunge_out_duration).set_trans(_profile.attack_lunge_transition_out).set_ease(Tween.EASE_OUT)
	out_p.tween_property(_sprite, "scale", target_scale, _profile.attack_lunge_out_duration).set_trans(_profile.attack_lunge_transition_out).set_ease(Tween.EASE_OUT)
	var ret_p := t.parallel()
	ret_p.tween_property(_sprite, "position", _base_position, _profile.attack_lunge_return_duration).set_trans(_profile.attack_lunge_transition_return).set_ease(Tween.EASE_IN)
	ret_p.tween_property(_sprite, "scale", _base_scale, _profile.attack_lunge_return_duration).set_trans(_profile.attack_lunge_transition_return).set_ease(Tween.EASE_IN)
	_current_tween = t

func _process(delta: float) -> void:
	# Timer is shared across continuous modes and resets on every mode transition
	# (see `_set_continuous_mode`). Incrementing unconditionally is intentional —
	# future modes (e.g. GUARD_BOUNCE in Task 4.2) read this same accumulator.
	_continuous_mode_t += delta
	match _continuous_mode:
		ContinuousMode.IDLE_BOB:
			var offset := Opponent.idle_bob_offset(
				_continuous_mode_t,
				_profile.idle_bob_amplitude_x,
				_profile.idle_bob_amplitude_y,
				_profile.idle_bob_period,
			)
			_sprite.position = _base_position + offset
		ContinuousMode.STILL, _:
			pass

# Pure math — testable without scene.
static func idle_bob_offset(t: float, amp_x: float, amp_y: float, period: float) -> Vector2:
	var phase := t * TAU / period
	var x := amp_x * sin(phase)
	var c := cos(phase)
	var y := -amp_y * c * c
	return Vector2(x, y)

static func swing_shift(action: int, direction: int, shift: float) -> float:
	match action:
		Action.SWING_HIGH: return +shift
		Action.SWING_MID:  return -shift
		Action.SWING_LOW:  return +shift if direction == Direction.LEFT else -shift
	return 0.0

func _set_continuous_mode(mode: int) -> void:
	_continuous_mode = mode
	_continuous_mode_t = 0.0

func _kill_current_tween() -> void:
	if _current_tween != null and _current_tween.is_running():
		_current_tween.kill()
	_current_tween = null

func _reset_to_base() -> void:
	_sprite.position = _base_position
	_sprite.scale = _base_scale
	_sprite.rotation = _base_rotation

func _load_texture(action: int) -> Texture2D:
	var safe_action: int = action if _ACTION_TOKEN.has(action) else Action.IDLE
	var token: String = _ACTION_TOKEN[safe_action]
	var path := "res://assets/sprites/opponents/%s/opponent_%s_body_%s.png" % [_slug, _slug, token]
	if ResourceLoader.exists(path):
		return load(path)
	return _placeholder()

func _placeholder() -> Texture2D:
	var img := Image.create(360, 540, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.4, 0.7))
	return ImageTexture.create_from_image(img)
