class_name DamageEffect
extends Control

# Tween durations and shake parameters, in seconds / pixels.
# Matches the named-constant convention in gameplay.gd and match_pacing.gd.
const _RED_FLASH_IN       := 0.05
const _RED_FLASH_OUT      := 0.10
const _BLACK_FADE_DELAY   := 0.10
const _BLACK_FADE_IN      := 0.15
const _BLACK_FADE_OUT     := 0.15
const _SHAKE_STEPS        := 8
const _SHAKE_STEP_SECONDS := 0.025
const _SHAKE_MAX_OFFSET   := 12.0

# HitSplat: the player_hit.png splat overlay that appears at the missed
# WASD prompt's position to read as "the screen took an impact here".
# Pulse-in matches the red-flash rise so the splat lands with the impact
# beat; the trailing hold + fade outlive both the shake (0.225s total)
# and the red flash (0.15s total) by a hair so the splat is the last
# thing to clear.
#   pulse-in:  0.05s   (T = 0.00 → 0.05)
#   hold:      0.12s   (T = 0.05 → 0.17)
#   fade-out:  0.10s   (T = 0.17 → 0.27)
# Total 0.27s vs shake 0.225s — the "slightly longer linger" the splat
# should carry past the screen shake / color change.
const _SPLAT_OVERSHOOT_SCALE := 1.10
const _SPLAT_PULSE_OUT        := 0.03
const _SPLAT_PULSE_SETTLE     := 0.02
const _SPLAT_HOLD             := 0.12
const _SPLAT_FADE_OUT         := 0.10

@onready var _red_flash:  ColorRect = $RedFlash
@onready var _black_fade: ColorRect = $BlackFade
@onready var _hit_splat:  TextureRect = $HitSplat

var _splat_tween: Tween

# `splat_center_global` is the screen-space point the splat should center on
# (typically the missed WASD prompt's center). Pass Vector2.ZERO to suppress
# the splat — preserved as an escape hatch for tests that mount DamageEffect
# without a WasdPromptLayer to query.
func play(splat_center_global: Vector2 = Vector2.ZERO) -> void:
	var tween := create_tween().set_parallel(true)

	# Red flash: 0 → 0.6 → 0
	tween.tween_property(_red_flash,  "modulate:a", 0.6, _RED_FLASH_IN)
	tween.tween_property(_red_flash,  "modulate:a", 0.0, _RED_FLASH_OUT) \
		.set_delay(_RED_FLASH_IN)

	# Black fade: delayed, 0 → 0.35 → 0
	tween.tween_property(_black_fade, "modulate:a", 0.35, _BLACK_FADE_IN) \
		.set_delay(_BLACK_FADE_DELAY)
	tween.tween_property(_black_fade, "modulate:a", 0.0,  _BLACK_FADE_OUT) \
		.set_delay(_BLACK_FADE_DELAY + _BLACK_FADE_IN)

	_shake()

	if splat_center_global != Vector2.ZERO:
		_play_splat(splat_center_global)

func _play_splat(splat_center_global: Vector2) -> void:
	# Position so the splat's geometric center lands on splat_center_global.
	# Use `position` (local to DamageEffect, which is fullscreen-anchored at
	# canvas origin) rather than `global_position`: Godot 4 folds pivot_offset
	# into the global transform with a (1 - scale) factor, so setting
	# global_position while scale=0 computes a position that drifts as scale
	# animates back up. Local position is scale-independent, and with the
	# pivot at the visual center (size/2), the rendered visual center is also
	# scale-invariant — it sits at position + pivot_offset throughout the
	# pulse-in/hold/fade-out chain.
	# Bug repro before the fix: only the FIRST hit drifted (by -pivot_offset).
	# Subsequent hits worked because the previous tween left scale at 1.0,
	# making the global_position setter coincide with the local one.
	var half := _hit_splat.size * 0.5
	_hit_splat.position = splat_center_global - half
	# Reset to clean state before the new pulse — a rapid back-to-back damage
	# (Simon-miss into WRONG-answer) would otherwise stack on a half-finished
	# fade-out.
	if _splat_tween and _splat_tween.is_valid():
		_splat_tween.kill()
	_hit_splat.scale = Vector2.ZERO
	_hit_splat.modulate.a = 0.0
	var pulse_total := _SPLAT_PULSE_OUT + _SPLAT_PULSE_SETTLE
	var overshoot := Vector2.ONE * _SPLAT_OVERSHOOT_SCALE
	_splat_tween = create_tween().set_parallel(true)
	# Pulse-in: scale 0 → overshoot → rest, opacity 0 → 1 over the same window.
	_splat_tween.tween_property(_hit_splat, "scale", overshoot, _SPLAT_PULSE_OUT)
	_splat_tween.tween_property(_hit_splat, "scale", Vector2.ONE, _SPLAT_PULSE_SETTLE) \
		.set_delay(_SPLAT_PULSE_OUT)
	_splat_tween.tween_property(_hit_splat, "modulate:a", 1.0, pulse_total)
	# Hold then fade. Position/scale stay put through the hold; only opacity moves.
	_splat_tween.tween_property(_hit_splat, "modulate:a", 0.0, _SPLAT_FADE_OUT) \
		.set_delay(pulse_total + _SPLAT_HOLD)

func _shake() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var origin: Vector2 = parent.position
	var tween := parent.create_tween()
	for i in range(_SHAKE_STEPS):
		var offset := Vector2(
			randf_range(-_SHAKE_MAX_OFFSET, _SHAKE_MAX_OFFSET),
			randf_range(-_SHAKE_MAX_OFFSET, _SHAKE_MAX_OFFSET)
		)
		tween.tween_property(parent, "position", origin + offset, _SHAKE_STEP_SECONDS)
	# Return to original position.
	tween.tween_property(parent, "position", origin, _SHAKE_STEP_SECONDS)
