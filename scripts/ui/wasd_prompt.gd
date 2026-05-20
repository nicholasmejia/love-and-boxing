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

func _animate_prompt_pulse(duration_seconds: float) -> void:
	_reset_to_clean_state()
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
	modulate.a = 0.0

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
