extends GutTest

# Locks the WasdPrompt animation tuning constants so an accidental edit
# (rebase smudge, IDE auto-format) fails CI loudly instead of silently
# changing animation feel. Per-variant constants are added as later
# increments land their animations.

const WP = preload("res://scripts/ui/wasd_prompt.gd")

func test_prompt_pulse_constants():
	assert_eq(WP._PROMPT_OVERSHOOT_SCALE, 1.15, "PROMPT pulse overshoot")
	assert_eq(WP._PROMPT_PULSE_OUT_SECONDS, 0.08, "PROMPT pulse-out duration")
	assert_eq(WP._PROMPT_PULSE_SETTLE_SECONDS, 0.04, "PROMPT pulse-settle duration")
	assert_eq(WP._PROMPT_FADE_OUT_SECONDS, 0.08, "PROMPT fade-out duration")
