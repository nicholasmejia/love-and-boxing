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

func test_shake_axis_for_directions():
	# Defense SUCCESS (Block Shake) dominant axis per direction: vertical-down
	# for head/body punches, leftward for A, rightward for D. The unused axis
	# is where the per-step perpendicular jitter lives.
	assert_eq(WP.shake_axis_for(SimonSequence.Direction.HEAD), Vector2(0.0, WP._BLOCK_SHAKE_DOMINANT_PX), "W shakes downward")
	assert_eq(WP.shake_axis_for(SimonSequence.Direction.LEFT), Vector2(-WP._BLOCK_SHAKE_DOMINANT_PX, 0.0), "A shakes leftward")
	assert_eq(WP.shake_axis_for(SimonSequence.Direction.BODY), Vector2(0.0, WP._BLOCK_SHAKE_DOMINANT_PX), "S shakes downward")
	assert_eq(WP.shake_axis_for(SimonSequence.Direction.RIGHT), Vector2(WP._BLOCK_SHAKE_DOMINANT_PX, 0.0), "D shakes rightward")

func test_toss_horizontal_for_directions():
	# Attack SUCCESS (Hit Toss) horizontal offset per direction. Hooks (A, D)
	# carry larger magnitudes than jabs (W, S); signs follow the punch's
	# travel vector (left hook flies +x, right hook -x; head jab -x, body +x).
	assert_eq(WP.toss_horizontal_for(SimonSequence.Direction.LEFT), WP._ATTACK_HIT_TOSS_HORIZ_HOOK_PX, "A → +80 (left hook flies right)")
	assert_eq(WP.toss_horizontal_for(SimonSequence.Direction.RIGHT), -WP._ATTACK_HIT_TOSS_HORIZ_HOOK_PX, "D → -80 (right hook flies left)")
	assert_eq(WP.toss_horizontal_for(SimonSequence.Direction.HEAD), -WP._ATTACK_HIT_TOSS_HORIZ_JAB_PX, "W → -40 (head jab flies left)")
	assert_eq(WP.toss_horizontal_for(SimonSequence.Direction.BODY), WP._ATTACK_HIT_TOSS_HORIZ_JAB_PX, "S → +40 (body jab flies right)")
