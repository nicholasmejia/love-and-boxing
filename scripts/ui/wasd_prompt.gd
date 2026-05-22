class_name WasdPrompt
extends Control

# Variant of the per-direction WASD command sprite. PROMPT is the show-phase
# telegraph; SUCCESS flashes on a correct repeat-phase keystroke; FAIL flashes
# on a miss (wrong key or input-window timeout). Sprite files live at
# `res://assets/sprites/commands/<token>_<suffix>.png` — see CONTEXT.md for
# the full manifest.
#
# SUCCESS / FAIL split into defense and attack flavors because each phase
# animates them differently: defense shakes / damage-pulses the prompt in
# place; attack tosses / miss-pulses it. The sprite suffix is unchanged
# (`<token>_success.png` for both SUCCESS variants).
enum Variant { PROMPT, SUCCESS, FAIL, SUCCESS_ATTACK, FAIL_ATTACK }

# PROMPT pulse-in tuning. The prompt grows from scale 0 to a slight overshoot
# and settles to rest while opacity climbs from 0 to 1.0 across the same
# window. After the variant's hold, opacity fades out quickly while scale
# stays at rest.
const _PROMPT_OVERSHOOT_SCALE := 1.15
const _PROMPT_PULSE_OUT_SECONDS := 0.08      # scale 0 → overshoot ; opacity rises through this stage
const _PROMPT_PULSE_SETTLE_SECONDS := 0.04   # scale overshoot → rest ; opacity tops out at end of this stage
const _PROMPT_FADE_OUT_SECONDS := 0.08

# Short fade-in for the temporary SUCCESS / FAIL fallback path so back-to-back
# same-direction inputs produce a visible delta. Replaced by per-variant
# animations in Increments 3-6.
const _FALLBACK_FADE_IN_SECONDS := 0.06

# Block Shake (defense SUCCESS). The prompt snaps to rest scale + opacity,
# then jerks along the punch's impact axis in 5 discrete linear steps with
# perpendicular jitter, settles, and fades out.
const _BLOCK_SHAKE_TOTAL_SECONDS := 0.18
const _BLOCK_SHAKE_STEPS := 5
const _BLOCK_SHAKE_DOMINANT_PX := 18.0
const _BLOCK_SHAKE_PERPENDICULAR_PX := 6.0
const _BLOCK_SETTLE_HOLD_SECONDS := 0.04
const _BLOCK_FADE_OUT_SECONDS := 0.08
# Per-step displacement on the dominant axis, expressed in px. Step 5 is 0 so
# the prompt settles at _rest_position before the fade-out. Calibrated for
# _BLOCK_SHAKE_DOMINANT_PX = 18; rescale proportionally if you tune that.
const _BLOCK_SHAKE_STEP_DISPLACEMENTS_PX: Array = [18.0, -12.0, 8.0, -4.0, 0.0]

# Damage Double-Pulse (defense FAIL). Two scale pulses (0 → overshoot → rest,
# then rest → overshoot → rest) followed by a small shake tail along the
# expected punch's impact axis, then fade out. Reads as "you missed the block
# and got tagged" — distinguishable from Block Shake by the leading
# double-pulse beat and a visibly smaller shake amplitude (~1/3).
const _DAMAGE_PULSE1_OUT := 0.06
const _DAMAGE_PULSE1_SETTLE := 0.03
const _DAMAGE_PULSE1_TOTAL := 0.09  # opacity fade-in length; equals OUT + SETTLE
const _DAMAGE_PULSE2_OUT := 0.05
const _DAMAGE_PULSE2_SETTLE := 0.03
const _DAMAGE_PULSE2_TOTAL := 0.08
const _DAMAGE_SHAKE_TOTAL := 0.10
const _DAMAGE_SHAKE_STEPS := 4
const _DAMAGE_SHAKE_DOMINANT_PX := 6.0
const _DAMAGE_SHAKE_PERPENDICULAR_PX := 2.0
const _DAMAGE_FADE_OUT_SECONDS := 0.08
# Damage shake displacement table (px on dominant axis). Last entry is 0 so
# the prompt lands at _rest_position before the fade-out. ~1/3 the amplitude
# of the Block Shake table by design.
const _DAMAGE_SHAKE_STEP_DISPLACEMENTS_PX: Array = [6.0, -4.0, 3.0, 0.0]

# Hit Toss (attack SUCCESS). Quick pulse-in (scale 0 → 1.15× → 1.0× with
# opacity 0 → 1.0), then the prompt is "tossed" — translates along the
# punch's travel vector in a vertical arc (up then back down past rest) while
# tapering in scale and fading opacity to 0. Hooks (A / D) get a larger
# horizontal offset than jabs (W / S) to match the more horizontal swing.
const _ATTACK_HIT_PULSE_OUT := 0.05
const _ATTACK_HIT_PULSE_SETTLE := 0.03
const _ATTACK_HIT_TOSS_SECONDS := 0.22
const _ATTACK_HIT_TOSS_END_SCALE := 0.95
const _ATTACK_HIT_TOSS_HORIZ_HOOK_PX := 80.0  # A / D
const _ATTACK_HIT_TOSS_HORIZ_JAB_PX := 40.0   # W / S
const _ATTACK_HIT_TOSS_APEX_Y_PX := -80.0     # peak up
const _ATTACK_HIT_TOSS_END_Y_PX := 40.0       # end position, past rest below
# Tumble rotation applied over the toss window. Sign follows the toss
# horizontal direction (rightward toss rotates clockwise, leftward CCW) so
# the prompt reads as tumbling forward in the direction it's flying.
const _ATTACK_HIT_TOSS_END_ROTATION_DEG := 10.0

# Miss Double-Pulse (attack FAIL). Two scale pulses + hold + fade. No shake
# (the punch didn't physically connect) and no toss (it missed). The pulse
# shape mirrors Damage Double-Pulse so a missed attack reads as the same
# "double-thump" beat, minus the impact-shake tail that follows getting hit.
const _ATTACK_MISS_PULSE1_OUT := 0.06
const _ATTACK_MISS_PULSE1_SETTLE := 0.03
const _ATTACK_MISS_PULSE1_TOTAL := 0.09
const _ATTACK_MISS_PULSE2_OUT := 0.05
const _ATTACK_MISS_PULSE2_SETTLE := 0.03
const _ATTACK_MISS_PULSE2_TOTAL := 0.08
const _ATTACK_MISS_HOLD := 0.10
const _ATTACK_MISS_FADE_OUT := 0.08

@onready var _label: Label = $Label
@onready var _bg: ColorRect = $Background
@onready var _image: TextureRect = $Image

var _rest_scale: Vector2 = Vector2.ONE
var _rest_position: Vector2 = Vector2.ZERO
var _active_tween: Tween
# Bumped on each new display() call. Orphaned animation coroutines whose
# generation no longer matches bail before clobbering state owned by the new
# display — protects against Godot's tween-kill semantics emitting (or not
# emitting) the `finished` signal in ways that race with the next animation.
var _display_generation: int = 0
@onready var _trace: TraceBorder = $TraceBorder

func _ready() -> void:
	_rest_scale = scale
	_rest_position = position
	# Scale needs to happen around the visible center, otherwise the pulse-in
	# collapses toward the top-left corner instead of growing from center.
	pivot_offset = size / 2.0
	visible = false

# `display` rather than `show` to avoid shadowing Node.show() — callers should
# go through WasdPromptLayer.flash / flash_success / flash_fail anyway, but a
# direct override of Node.show would silently change semantics for any future
# caller that thinks it's calling the inherited method.
#
# Variant-specific animations (Block Shake, Hit Toss, etc.) are added in later
# increments; SUCCESS / FAIL / SUCCESS_ATTACK / FAIL_ATTACK currently fall
# through to a snap-show + timed snap-hide.
func display(direction: int, variant: int, duration_seconds: float) -> void:
	_kill_active_tween()
	_display_generation += 1
	var my_gen := _display_generation
	_set_sprite(direction, variant)
	match variant:
		Variant.PROMPT:
			await _animate_prompt_pulse(duration_seconds)
		Variant.SUCCESS:
			await _animate_block_shake(direction)
		Variant.FAIL:
			await _animate_damage_double_pulse(direction)
		Variant.SUCCESS_ATTACK:
			await _animate_hit_toss(direction)
		Variant.FAIL_ATTACK:
			await _animate_miss_double_pulse()
		_:
			# SUCCESS / FAIL fallback path until Increments 3-6 land their proper
			# variant animations. The fade-in (instead of a snap to opacity 1.0)
			# is what makes a fast A→W→A or W→W input read as a fresh hit:
			# _reset_to_clean_state() drops opacity to 0, then the fade-in lifts
			# it back. Without the fade, a same-direction follow-up would not
			# produce a visible delta because the prompt was already fully opaque.
			_reset_to_clean_state()
			scale = _rest_scale
			visible = true
			_active_tween = create_tween()
			_active_tween.tween_property(self, "modulate:a", 1.0, _FALLBACK_FADE_IN_SECONDS)
			var hold := maxf(duration_seconds - _FALLBACK_FADE_IN_SECONDS, 0.0)
			if hold > 0.0:
				_active_tween.tween_interval(hold)
			await _active_tween.finished
	if my_gen != _display_generation:
		return
	visible = false

func hide_prompt() -> void:
	_kill_active_tween()
	_display_generation += 1  # invalidate any in-flight display coroutine
	_reset_to_clean_state()
	visible = false
	_trace.stop_trace()

func _animate_prompt_pulse(duration_seconds: float) -> void:
	_reset_to_clean_state()
	_trace.play_trace()
	visible = true
	var total_in := _PROMPT_PULSE_OUT_SECONDS + _PROMPT_PULSE_SETTLE_SECONDS
	# Clamp hold to 0 — at the fastest difficulty (~0.35s step budget), the
	# pulse-in + fade-out can consume the full budget, leaving no rest hold.
	var hold := maxf(duration_seconds - total_in - _PROMPT_FADE_OUT_SECONDS, 0.0)
	var overshoot := _rest_scale * _PROMPT_OVERSHOOT_SCALE
	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	# All tweeners share T=0 as start; set_delay() staggers them.
	_active_tween.tween_property(self, "scale", overshoot, _PROMPT_PULSE_OUT_SECONDS)
	_active_tween.tween_property(self, "modulate:a", 1.0, total_in)
	_active_tween.tween_property(self, "scale", _rest_scale, _PROMPT_PULSE_SETTLE_SECONDS) \
		.set_delay(_PROMPT_PULSE_OUT_SECONDS)
	_active_tween.tween_property(self, "modulate:a", 0.0, _PROMPT_FADE_OUT_SECONDS) \
		.set_delay(total_in + hold)
	await _active_tween.finished

# Horizontal toss offset for a successfully-landed attack at `direction`.
# Sign convention is "the prompt flies the way the punch was traveling":
# - W (head, right glove going up-left)  → -x (left), jab magnitude
# - A (left hook going up-right)         → +x (right), hook magnitude
# - S (body, left glove going up-right)  → +x (right), jab magnitude
# - D (right hook going up-left)         → -x (left), hook magnitude
# Vertical arc is uniform across all four directions.
static func toss_horizontal_for(direction: int) -> float:
	match direction:
		SimonSequence.Direction.HEAD: return -_ATTACK_HIT_TOSS_HORIZ_JAB_PX
		SimonSequence.Direction.LEFT: return _ATTACK_HIT_TOSS_HORIZ_HOOK_PX
		SimonSequence.Direction.BODY: return _ATTACK_HIT_TOSS_HORIZ_JAB_PX
		SimonSequence.Direction.RIGHT: return -_ATTACK_HIT_TOSS_HORIZ_HOOK_PX
	return 0.0

# Dominant shake direction for a punch landing at `direction`. The prompt is
# pushed the way the punch's force carries — W (top) and S (mid) shake
# downward; A (left hook) shakes leftward from the prompt's POV; D shakes
# rightward. The return vector's magnitude is _BLOCK_SHAKE_DOMINANT_PX; the
# perpendicular axis (the zero component) carries the jitter, applied at the
# tween use site.
static func shake_axis_for(direction: int) -> Vector2:
	match direction:
		SimonSequence.Direction.HEAD: return Vector2(0.0, _BLOCK_SHAKE_DOMINANT_PX)
		SimonSequence.Direction.LEFT: return Vector2(-_BLOCK_SHAKE_DOMINANT_PX, 0.0)
		SimonSequence.Direction.BODY: return Vector2(0.0, _BLOCK_SHAKE_DOMINANT_PX)
		SimonSequence.Direction.RIGHT: return Vector2(_BLOCK_SHAKE_DOMINANT_PX, 0.0)
	return Vector2.ZERO

func _animate_miss_double_pulse() -> void:
	# Direction-agnostic — Miss has no shake (the punch didn't land) and no
	# toss (it didn't connect), so the prompt sits at rest the whole time.
	_reset_to_clean_state()
	visible = true
	var overshoot := _rest_scale * _PROMPT_OVERSHOOT_SCALE
	var pulses_end := _ATTACK_MISS_PULSE1_TOTAL + _ATTACK_MISS_PULSE2_TOTAL
	var hold_end := pulses_end + _ATTACK_MISS_HOLD

	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	# Pulse 1: scale 0 → overshoot → rest, opacity 0 → 1.0 over the same window.
	_active_tween.tween_property(self, "scale", overshoot, _ATTACK_MISS_PULSE1_OUT)
	_active_tween.tween_property(self, "scale", _rest_scale, _ATTACK_MISS_PULSE1_SETTLE) \
		.set_delay(_ATTACK_MISS_PULSE1_OUT)
	_active_tween.tween_property(self, "modulate:a", 1.0, _ATTACK_MISS_PULSE1_TOTAL)
	# Pulse 2: scale rest → overshoot → rest (opacity already at 1.0).
	_active_tween.tween_property(self, "scale", overshoot, _ATTACK_MISS_PULSE2_OUT) \
		.set_delay(_ATTACK_MISS_PULSE1_TOTAL)
	_active_tween.tween_property(self, "scale", _rest_scale, _ATTACK_MISS_PULSE2_SETTLE) \
		.set_delay(_ATTACK_MISS_PULSE1_TOTAL + _ATTACK_MISS_PULSE2_OUT)
	# Hold + fade out.
	_active_tween.tween_property(self, "modulate:a", 0.0, _ATTACK_MISS_FADE_OUT) \
		.set_delay(hold_end)
	await _active_tween.finished

func _animate_hit_toss(direction: int) -> void:
	_reset_to_clean_state()
	visible = true
	var horiz := toss_horizontal_for(direction)
	var overshoot := _rest_scale * _PROMPT_OVERSHOOT_SCALE
	var end_scale := _rest_scale * _ATTACK_HIT_TOSS_END_SCALE
	var pulse_total := _ATTACK_HIT_PULSE_OUT + _ATTACK_HIT_PULSE_SETTLE
	var half_toss := _ATTACK_HIT_TOSS_SECONDS * 0.5

	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	# Pulse-in: scale 0 → overshoot → rest, opacity 0 → 1.0 over the same window.
	_active_tween.tween_property(self, "scale", overshoot, _ATTACK_HIT_PULSE_OUT)
	_active_tween.tween_property(self, "scale", _rest_scale, _ATTACK_HIT_PULSE_SETTLE) \
		.set_delay(_ATTACK_HIT_PULSE_OUT)
	_active_tween.tween_property(self, "modulate:a", 1.0, pulse_total)
	# Toss phase: horizontal glide, vertical up-then-down arc, scale taper,
	# opacity fade out — all running in parallel for the toss window.
	_active_tween.tween_property(self, "position:x", _rest_position.x + horiz, _ATTACK_HIT_TOSS_SECONDS) \
		.set_delay(pulse_total)
	_active_tween.tween_property(self, "position:y", _rest_position.y + _ATTACK_HIT_TOSS_APEX_Y_PX, half_toss) \
		.set_delay(pulse_total) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(self, "position:y", _rest_position.y + _ATTACK_HIT_TOSS_END_Y_PX, half_toss) \
		.set_delay(pulse_total + half_toss) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_active_tween.tween_property(self, "scale", end_scale, _ATTACK_HIT_TOSS_SECONDS) \
		.set_delay(pulse_total)
	_active_tween.tween_property(self, "modulate:a", 0.0, _ATTACK_HIT_TOSS_SECONDS) \
		.set_delay(pulse_total)
	var end_rotation := signf(horiz) * deg_to_rad(_ATTACK_HIT_TOSS_END_ROTATION_DEG)
	_active_tween.tween_property(self, "rotation", end_rotation, _ATTACK_HIT_TOSS_SECONDS) \
		.set_delay(pulse_total)
	await _active_tween.finished

func _animate_damage_double_pulse(direction: int) -> void:
	_reset_to_clean_state()
	visible = true
	var dominant_unit := shake_axis_for(direction).normalized()
	var perp_unit := Vector2(1.0, 0.0) if absf(dominant_unit.y) > absf(dominant_unit.x) else Vector2(0.0, 1.0)
	var overshoot := _rest_scale * _PROMPT_OVERSHOOT_SCALE
	var step_duration := _DAMAGE_SHAKE_TOTAL / float(_DAMAGE_SHAKE_STEPS)
	var pulses_end := _DAMAGE_PULSE1_TOTAL + _DAMAGE_PULSE2_TOTAL
	var shake_end := pulses_end + _DAMAGE_SHAKE_TOTAL

	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	# Pulse 1: scale 0 → overshoot → rest, opacity 0 → 1.0 over the same window.
	_active_tween.tween_property(self, "scale", overshoot, _DAMAGE_PULSE1_OUT)
	_active_tween.tween_property(self, "scale", _rest_scale, _DAMAGE_PULSE1_SETTLE) \
		.set_delay(_DAMAGE_PULSE1_OUT)
	_active_tween.tween_property(self, "modulate:a", 1.0, _DAMAGE_PULSE1_TOTAL)
	# Pulse 2: scale rest → overshoot → rest (opacity already at 1.0).
	_active_tween.tween_property(self, "scale", overshoot, _DAMAGE_PULSE2_OUT) \
		.set_delay(_DAMAGE_PULSE1_TOTAL)
	_active_tween.tween_property(self, "scale", _rest_scale, _DAMAGE_PULSE2_SETTLE) \
		.set_delay(_DAMAGE_PULSE1_TOTAL + _DAMAGE_PULSE2_OUT)
	# Shake tail: 4 discrete linear position steps along the impact axis.
	for i in _DAMAGE_SHAKE_STEPS:
		var step_px := float(_DAMAGE_SHAKE_STEP_DISPLACEMENTS_PX[i])
		var perp_jitter := randf_range(-_DAMAGE_SHAKE_PERPENDICULAR_PX, _DAMAGE_SHAKE_PERPENDICULAR_PX)
		var target := _rest_position + dominant_unit * step_px + perp_unit * perp_jitter
		_active_tween.tween_property(self, "position", target, step_duration) \
			.set_delay(pulses_end + i * step_duration) \
			.set_trans(Tween.TRANS_LINEAR)
	# Fade out (position has already settled to rest via the last shake step).
	_active_tween.tween_property(self, "modulate:a", 0.0, _DAMAGE_FADE_OUT_SECONDS) \
		.set_delay(shake_end)
	await _active_tween.finished

func _animate_block_shake(direction: int) -> void:
	_reset_to_clean_state()
	scale = _rest_scale
	modulate.a = 1.0
	visible = true
	var dominant := shake_axis_for(direction)
	var dominant_unit := dominant.normalized()
	# Perpendicular jitter lives on the axis the dominant shake doesn't use.
	var perp_unit := Vector2(1.0, 0.0) if absf(dominant.y) > absf(dominant.x) else Vector2(0.0, 1.0)
	var step_duration := _BLOCK_SHAKE_TOTAL_SECONDS / float(_BLOCK_SHAKE_STEPS)
	_active_tween = create_tween()
	for step_px in _BLOCK_SHAKE_STEP_DISPLACEMENTS_PX:
		var perp_jitter := randf_range(-_BLOCK_SHAKE_PERPENDICULAR_PX, _BLOCK_SHAKE_PERPENDICULAR_PX)
		var target := _rest_position + dominant_unit * float(step_px) + perp_unit * perp_jitter
		_active_tween.tween_property(self, "position", target, step_duration) \
			.set_trans(Tween.TRANS_LINEAR)
	_active_tween.tween_interval(_BLOCK_SETTLE_HOLD_SECONDS)
	_active_tween.tween_property(self, "modulate:a", 0.0, _BLOCK_FADE_OUT_SECONDS)
	await _active_tween.finished

func _set_sprite(direction: int, variant: int) -> void:
	var token := _token_for(direction)
	var suffix := _suffix_for(variant)
	_label.text = token.to_upper()
	var path := "res://assets/sprites/commands/%s_%s.png" % [token, suffix]
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		_image.texture = tex
		_image.visible = true
		_label.visible = false
		_bg.visible = false
	else:
		_image.visible = false
		_label.visible = true
		_bg.visible = true

func _reset_to_clean_state() -> void:
	position = _rest_position
	scale = Vector2.ZERO
	rotation = 0.0
	modulate.a = 0.0
	if _trace != null:
		_trace.stop_trace()

func _kill_active_tween() -> void:
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = null

func _token_for(direction: int) -> String:
	match direction:
		SimonSequence.Direction.HEAD: return "w"
		SimonSequence.Direction.LEFT: return "a"
		SimonSequence.Direction.BODY: return "s"
		SimonSequence.Direction.RIGHT: return "d"
	return ""

func _suffix_for(variant: int) -> String:
	match variant:
		Variant.SUCCESS, Variant.SUCCESS_ATTACK: return "success"
		Variant.FAIL, Variant.FAIL_ATTACK: return "fail"
		_: return "prompt"
