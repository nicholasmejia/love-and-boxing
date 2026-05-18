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

@onready var _red_flash:  ColorRect = $RedFlash
@onready var _black_fade: ColorRect = $BlackFade

func play() -> void:
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
