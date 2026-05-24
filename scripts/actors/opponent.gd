class_name Opponent
extends Node2D

const OpponentAnimationProfile = preload("res://scripts/data/opponent_animation_profile.gd")

enum Action {
	IDLE,           # default + guard stance
	GUARD_DOWN,     # arms lowered after positive riddle (no bounce — post first hit)
	GUARD_DOWN_EXCITED,  # arms lowered, excited — continuous bounce while awaiting first hit
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
	Action.GUARD_DOWN_EXCITED: "guard_down",
	Action.KNOCKED_DOWN: "knocked_down",
	Action.TALKING: "talking",
	Action.SWING_HIGH: "swing_high",
	Action.SWING_MID: "swing_mid",
	Action.SWING_LOW: "swing_low",
	Action.HIT_HIGH: "hit_high",
	Action.HIT_BODY: "hit_low",  # deliberate alias — shares texture with HIT_LOW; recoil direction diverges in Task 3.3
	Action.HIT_LOW: "hit_low",
}

# Reaction emote (NEUTRAL = sweat-drop fade-slide-fade; WRONG = anger-vein
# fade-pulse-fade + body modulate flash). Emote sprites are siblings of Body
# so they don't inherit Body's lunge/recoil; their tween channels are
# independent of `_current_tween` so set_action() during an active reaction
# leaves the reaction running. clear_reaction() is the safety net for new
# prompts.
const REACTION_NEUTRAL_FADE_IN := 0.12
const REACTION_NEUTRAL_SLIDE_DOWN_PX := 40.0
const REACTION_NEUTRAL_SLIDE_DURATION := 0.9
const REACTION_NEUTRAL_FADE_OUT := 0.25
const REACTION_WRONG_FADE_IN := 0.08
const REACTION_WRONG_PULSE_SCALE := 1.18
const REACTION_WRONG_PULSE_HALF := 0.06
const REACTION_WRONG_PULSE_COUNT := 4
const REACTION_WRONG_FADE_OUT := 0.25
# 50% red tint at the apex — pulses through 3 cycles in parallel with the
# WRONG emote. Lives on _body_flash_tween, separate from _current_tween,
# so set_action() (swing/hit poses) cannot kill it mid-flash.
const REACTION_BODY_FLASH_COLOR := Color(1.0, 0.5, 0.5)
const REACTION_BODY_FLASH_HALF := 0.06
const REACTION_BODY_FLASH_COUNT := 3

@onready var _sprite: Sprite2D = $Body
@onready var _emote_neutral: Sprite2D = $ReactionEmoteNeutral
@onready var _emote_wrong: Sprite2D = $ReactionEmoteWrong
@onready var _sweat_fx: SweatFX = $SweatFX

var _slug: String = "tofu"
var _profile: OpponentAnimationProfile = null

# Initialized at declaration so `_reset_to_base()` is safe to call even
# before `_ready()` has captured the scene's authored transform.
var _base_position: Vector2 = Vector2.ZERO
var _base_scale: Vector2 = Vector2.ONE
var _base_rotation: float = 0.0

# Emote base transforms captured at _ready so authored scene values are the
# single source of tuning truth — clear_reaction() restores from these.
var _emote_neutral_base_pos: Vector2 = Vector2.ZERO
var _emote_wrong_base_pos: Vector2 = Vector2.ZERO
var _emote_wrong_base_scale: Vector2 = Vector2.ONE

var _continuous_mode: int = ContinuousMode.STILL
var _continuous_mode_t: float = 0.0
var _current_tween: Tween = null
var _emote_tween: Tween = null
var _body_flash_tween: Tween = null

func _ready() -> void:
	_base_position = _sprite.position
	_base_scale = _sprite.scale
	_base_rotation = _sprite.rotation
	_emote_neutral_base_pos = _emote_neutral.position
	_emote_wrong_base_pos = _emote_wrong.position
	_emote_wrong_base_scale = _emote_wrong.scale

func configure(opponent_slug: String, profile: OpponentAnimationProfile = null) -> void:
	_slug = opponent_slug
	if profile != null:
		_profile = profile
	elif _profile == null:
		_profile = load("res://data/opponent_animation/tofu.tres") as OpponentAnimationProfile
	clear_reaction()
	set_action(Action.IDLE)

func set_action(action: int, direction: int = Direction.LEFT) -> void:
	_kill_current_tween()
	_reset_to_base()
	_sprite.texture = _load_texture(action)
	_anchor_sprite_bottom()
	_sprite.flip_h = (direction == Direction.RIGHT)
	if action == Action.IDLE:
		_set_continuous_mode(ContinuousMode.IDLE_BOB)
	elif action == Action.GUARD_DOWN_EXCITED:
		_set_continuous_mode(ContinuousMode.GUARD_BOUNCE)
	else:
		_set_continuous_mode(ContinuousMode.STILL)
	if action == Action.SWING_HIGH or action == Action.SWING_MID or action == Action.SWING_LOW:
		_play_attack_lunge(action, direction)
	elif action == Action.HIT_HIGH or action == Action.HIT_BODY or action == Action.HIT_LOW:
		_play_hit_recoil(action, direction)

func _play_attack_lunge(action: int, direction: int) -> void:
	var shift := Opponent.swing_shift(action, direction, _profile.attack_lunge_shift_x)
	var target_pos := _base_position + Vector2(shift, 0.0)
	var target_scale := _base_scale * _profile.attack_lunge_scale_peak
	_kill_current_tween()
	# `parallel()` flags only the next tweener, so attach scale via `.parallel()`
	# on the tweener that should share a step with the preceding position tween.
	var t := create_tween()
	t.tween_property(_sprite, "position", target_pos, _profile.attack_lunge_out_duration).set_trans(_profile.attack_lunge_transition_out).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_sprite, "scale", target_scale, _profile.attack_lunge_out_duration).set_trans(_profile.attack_lunge_transition_out).set_ease(Tween.EASE_OUT)
	t.tween_property(_sprite, "position", _base_position, _profile.attack_lunge_return_duration).set_trans(_profile.attack_lunge_transition_return).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(_sprite, "scale", _base_scale, _profile.attack_lunge_return_duration).set_trans(_profile.attack_lunge_transition_return).set_ease(Tween.EASE_IN)
	_current_tween = t

func _play_hit_recoil(action: int, direction: int) -> void:
	var shift := Opponent.recoil_shift(action, direction, _profile.hit_recoil_shift_x)
	var target_pos := _base_position + Vector2(shift, 0.0)
	var target_scale := _base_scale * _profile.hit_recoil_scale_dip
	_kill_current_tween()
	# `parallel()` flags only the next tweener, so attach scale via `.parallel()`
	# on the tweener that should share a step with the preceding position tween.
	var t := create_tween()
	t.tween_property(_sprite, "position", target_pos, _profile.hit_recoil_out_duration).set_trans(_profile.hit_recoil_transition_out).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_sprite, "scale", target_scale, _profile.hit_recoil_out_duration).set_trans(_profile.hit_recoil_transition_out).set_ease(Tween.EASE_OUT)
	t.tween_property(_sprite, "position", _base_position, _profile.hit_recoil_return_duration).set_trans(_profile.hit_recoil_transition_return).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(_sprite, "scale", _base_scale, _profile.hit_recoil_return_duration).set_trans(_profile.hit_recoil_transition_return).set_ease(Tween.EASE_IN)
	_current_tween = t

func play_knockdown_fall() -> void:
	_kill_current_tween()
	_reset_to_base()
	_sprite.texture = _load_texture(Action.KNOCKED_DOWN)
	_anchor_sprite_bottom()
	_sprite.flip_h = false
	_set_continuous_mode(ContinuousMode.STILL)

	var t := create_tween()
	# Phase 1: sway_method drives position.x, scale shrinks in parallel.
	t.tween_method(
		_apply_fall_sway,
		0.0,
		_profile.knockdown_fall_sway_duration,
		_profile.knockdown_fall_sway_duration,
	)
	t.parallel().tween_property(_sprite, "scale", _base_scale * _profile.knockdown_fall_end_scale, _profile.knockdown_fall_sway_duration).set_trans(_profile.knockdown_fall_drop_transition).set_ease(Tween.EASE_IN)
	# Phase 2 (sequentially chained after Phase 1): rotation + position drop in parallel.
	t.tween_property(_sprite, "rotation", _base_rotation + deg_to_rad(_profile.knockdown_fall_rotation_degrees), _profile.knockdown_fall_drop_duration).set_trans(_profile.knockdown_fall_drop_transition).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(_sprite, "position", _base_position + Vector2(0.0, _profile.knockdown_fall_drop_y), _profile.knockdown_fall_drop_duration).set_trans(_profile.knockdown_fall_drop_transition).set_ease(Tween.EASE_IN)
	_current_tween = t
	await t.finished

func _apply_fall_sway(t_now: float) -> void:
	var amp := _profile.knockdown_fall_sway_amplitude
	var cycles := _profile.knockdown_fall_sway_cycles
	var dur := _profile.knockdown_fall_sway_duration
	if dur <= 0.0:
		return
	var phase := t_now * TAU * cycles / dur
	_sprite.position.x = _base_position.x + amp * sin(phase)

func play_knockdown_recover() -> void:
	_kill_current_tween()
	var t := create_tween().set_parallel(true)
	t.set_trans(_profile.knockdown_recover_transition).set_ease(Tween.EASE_OUT)
	t.tween_property(_sprite, "position", _base_position, _profile.knockdown_recover_duration)
	t.tween_property(_sprite, "rotation", _base_rotation, _profile.knockdown_recover_duration)
	t.tween_property(_sprite, "scale", _base_scale, _profile.knockdown_recover_duration)
	_current_tween = t
	await t.finished
	set_action(Action.IDLE, Direction.LEFT)

# Reaction emote dispatch. Called by gameplay at the impact frame for NEUTRAL
# and WRONG outcomes (RIGHT has no emote — the opponent is hit, not reacting).
# Always kills any in-flight reaction before starting the new one so
# back-to-back submissions don't stack.
func play_reaction(outcome: int) -> void:
	_kill_reaction_tweens()
	match outcome:
		Outcome.Type.NEUTRAL:
			_play_neutral_reaction()
		Outcome.Type.WRONG:
			_play_wrong_reaction()
		_:
			pass

func _play_neutral_reaction() -> void:
	_emote_neutral.position = _emote_neutral_base_pos
	_emote_neutral.modulate.a = 0.0
	var slide_target_y := _emote_neutral_base_pos.y + REACTION_NEUTRAL_SLIDE_DOWN_PX
	var t := create_tween()
	# Fade in fast, then slide down across most of the visible window, then fade out.
	t.tween_property(_emote_neutral, "modulate:a", 1.0, REACTION_NEUTRAL_FADE_IN)
	t.tween_property(_emote_neutral, "position:y", slide_target_y, REACTION_NEUTRAL_SLIDE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(_emote_neutral, "modulate:a", 0.0, REACTION_NEUTRAL_FADE_OUT)
	_emote_tween = t

func _play_wrong_reaction() -> void:
	_emote_wrong.position = _emote_wrong_base_pos
	_emote_wrong.scale = _emote_wrong_base_scale
	_emote_wrong.modulate.a = 0.0
	var apex_scale := _emote_wrong_base_scale * REACTION_WRONG_PULSE_SCALE
	var t := create_tween()
	t.tween_property(_emote_wrong, "modulate:a", 1.0, REACTION_WRONG_FADE_IN)
	for i in REACTION_WRONG_PULSE_COUNT:
		t.tween_property(_emote_wrong, "scale", apex_scale, REACTION_WRONG_PULSE_HALF) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(_emote_wrong, "scale", _emote_wrong_base_scale, REACTION_WRONG_PULSE_HALF) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(_emote_wrong, "modulate:a", 0.0, REACTION_WRONG_FADE_OUT)
	_emote_tween = t
	_play_body_flash()

# Body modulate flash (3 quick red pulses) for WRONG. Lives on its own tween
# so set_action()'s _kill_current_tween() — which fires when the opponent
# transitions to a swing pose after WRONG — does NOT kill it. _reset_to_base()
# touches position/scale/rotation only, never modulate.
func _play_body_flash() -> void:
	var t := create_tween()
	for i in REACTION_BODY_FLASH_COUNT:
		t.tween_property(_sprite, "modulate", REACTION_BODY_FLASH_COLOR, REACTION_BODY_FLASH_HALF)
		t.tween_property(_sprite, "modulate", Color.WHITE, REACTION_BODY_FLASH_HALF)
	_body_flash_tween = t

# Safety net for new prompts — kills any in-flight reaction tweens and snaps
# the emote sprites + body modulate back to rest. Tween end-states already
# reset visuals on natural completion, so clear_reaction() only matters when
# the next prompt starts mid-reaction (NEUTRAL re-display, configure() on
# match start, or back-to-back submissions).
func clear_reaction() -> void:
	_kill_reaction_tweens()
	_emote_neutral.modulate.a = 0.0
	_emote_neutral.position = _emote_neutral_base_pos
	_emote_wrong.modulate.a = 0.0
	_emote_wrong.position = _emote_wrong_base_pos
	_emote_wrong.scale = _emote_wrong_base_scale
	_sprite.modulate = Color.WHITE

func _kill_reaction_tweens() -> void:
	if _emote_tween != null and _emote_tween.is_running():
		_emote_tween.kill()
	_emote_tween = null
	if _body_flash_tween != null and _body_flash_tween.is_running():
		_body_flash_tween.kill()
	_body_flash_tween = null

func _process(delta: float) -> void:
	# Timer is shared across continuous modes and resets on every mode transition
	# (see `_set_continuous_mode`). Incrementing unconditionally is intentional —
	# IDLE_BOB and GUARD_BOUNCE both read this same accumulator.
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
		ContinuousMode.GUARD_BOUNCE:
			var bounce := Opponent.guard_bounce_offset(
				_continuous_mode_t,
				_profile.guard_bounce_amplitude_y,
				_profile.guard_bounce_period,
			)
			_sprite.position = _base_position + bounce
		ContinuousMode.STILL, _:
			pass

# Pure math — testable without scene.
static func idle_bob_offset(t: float, amp_x: float, amp_y: float, period: float) -> Vector2:
	var phase := t * TAU / period
	var x := amp_x * sin(phase)
	var c := cos(phase)
	var y := -amp_y * c * c
	return Vector2(x, y)

static func guard_bounce_offset(t: float, amp: float, period: float) -> Vector2:
	# Half-sine arc per period: max velocity at takeoff and at landing, slow at peak.
	# The velocity reversal at each period boundary reads as a sudden landing
	# rather than a smooth rebound.
	var phase := fmod(t, period)
	var y := -amp * sin(phase * PI / period)
	return Vector2(0.0, y)

static func swing_shift(action: int, direction: int, shift: float) -> float:
	match action:
		Action.SWING_HIGH: return +shift
		Action.SWING_MID:  return -shift
		Action.SWING_LOW:  return +shift if direction == Direction.LEFT else -shift
	return 0.0

static func recoil_shift(action: int, direction: int, shift: float) -> float:
	match action:
		Action.HIT_HIGH: return +shift
		Action.HIT_BODY: return -shift
		Action.HIT_LOW:  return +shift if direction == Direction.LEFT else -shift
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

# Bottom-anchor the scale pivot: shift the texture up by half its height so the
# sprite node's origin coincides with the texture's bottom-center. Without this,
# lunge/recoil scale changes move the bottom edge up/down and expose blank space.
# Must be called whenever `_sprite.texture` is reassigned (heights vary per action).
func _anchor_sprite_bottom() -> void:
	var tex := _sprite.texture
	if tex != null:
		_sprite.offset = Vector2(0, -tex.get_height() / 2.0)

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

# Trigger a per-direction sweat burst at the impact zone. Called by
# gameplay.gd from _on_attack_step_landed, on the same frame as the
# combo_success SFX and the HIT_* pose.
func play_sweat(direction: int) -> void:
	_sweat_fx.emit_for(direction)
