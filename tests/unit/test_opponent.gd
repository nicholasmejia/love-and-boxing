extends GutTest

# GUT's custom-warnings load path doesn't pick up class_name registrations made
# in the same branch as this test file. Preload explicitly so parse succeeds.
const Opponent = preload("res://scripts/actors/opponent.gd")

# Idle bob math at known t values for AMP_X=20, AMP_Y=10, PERIOD=1.0
# x = AMP_X * sin(t * 2π)
# y = -AMP_Y * cos(t * 2π)²

func test_idle_bob_offset_at_t_zero():
	var v := Opponent.idle_bob_offset(0.0, 20.0, 10.0, 1.0)
	assert_almost_eq(v.x, 0.0, 0.001)
	assert_almost_eq(v.y, -10.0, 0.001)   # cos(0)² = 1, so y = -10

func test_idle_bob_offset_at_quarter_period():
	var v := Opponent.idle_bob_offset(0.25, 20.0, 10.0, 1.0)
	assert_almost_eq(v.x, 20.0, 0.001)   # sin(π/2) = 1
	assert_almost_eq(v.y, 0.0, 0.001)    # cos(π/2)² = 0

func test_idle_bob_offset_at_half_period():
	var v := Opponent.idle_bob_offset(0.5, 20.0, 10.0, 1.0)
	assert_almost_eq(v.x, 0.0, 0.001)    # sin(π) = 0
	assert_almost_eq(v.y, -10.0, 0.001)  # cos(π)² = 1

func test_idle_bob_offset_at_three_quarter_period():
	var v := Opponent.idle_bob_offset(0.75, 20.0, 10.0, 1.0)
	assert_almost_eq(v.x, -20.0, 0.001)  # sin(3π/2) = -1
	assert_almost_eq(v.y, 0.0, 0.001)    # cos(3π/2)² = 0

# swing_shift: SWING_HIGH→+, SWING_MID→−, SWING_LOW left→+, SWING_LOW right→−, non-swing→0

func test_swing_shift_swing_high_is_positive():
	var s := Opponent.swing_shift(Opponent.Action.SWING_HIGH, Opponent.Direction.LEFT, 40.0)
	assert_almost_eq(s, 40.0, 0.001)

func test_swing_shift_swing_mid_is_negative():
	var s := Opponent.swing_shift(Opponent.Action.SWING_MID, Opponent.Direction.LEFT, 40.0)
	assert_almost_eq(s, -40.0, 0.001)

func test_swing_shift_swing_low_left_is_positive():
	var s := Opponent.swing_shift(Opponent.Action.SWING_LOW, Opponent.Direction.LEFT, 40.0)
	assert_almost_eq(s, 40.0, 0.001)

func test_swing_shift_swing_low_right_is_negative():
	var s := Opponent.swing_shift(Opponent.Action.SWING_LOW, Opponent.Direction.RIGHT, 40.0)
	assert_almost_eq(s, -40.0, 0.001)

func test_swing_shift_non_swing_returns_zero():
	var s := Opponent.swing_shift(Opponent.Action.IDLE, Opponent.Direction.LEFT, 40.0)
	assert_almost_eq(s, 0.0, 0.001)

# recoil_shift: HIT_HIGH→+, HIT_BODY→−, HIT_LOW left→+, HIT_LOW right→−, non-hit→0

func test_recoil_shift_hit_high_is_positive():
	var s := Opponent.recoil_shift(Opponent.Action.HIT_HIGH, Opponent.Direction.LEFT, 40.0)
	assert_almost_eq(s, 40.0, 0.001)

func test_recoil_shift_hit_body_is_negative():
	var s := Opponent.recoil_shift(Opponent.Action.HIT_BODY, Opponent.Direction.LEFT, 40.0)
	assert_almost_eq(s, -40.0, 0.001)

func test_recoil_shift_hit_low_left_is_positive():
	var s := Opponent.recoil_shift(Opponent.Action.HIT_LOW, Opponent.Direction.LEFT, 40.0)
	assert_almost_eq(s, 40.0, 0.001)

func test_recoil_shift_hit_low_right_is_negative():
	var s := Opponent.recoil_shift(Opponent.Action.HIT_LOW, Opponent.Direction.RIGHT, 40.0)
	assert_almost_eq(s, -40.0, 0.001)

func test_recoil_shift_non_hit_returns_zero():
	var s := Opponent.recoil_shift(Opponent.Action.IDLE, Opponent.Direction.LEFT, 40.0)
	assert_almost_eq(s, 0.0, 0.001)

# Guard bounce: y = -amp * (1 - cos(t * 2π / period)) / 2
# Always ≤ 0 (above base in Godot Y-down). Range [-amp, 0].

func test_guard_bounce_at_t_zero_is_planted():
	var v := Opponent.guard_bounce_offset(0.0, 18.0, 0.45)
	assert_almost_eq(v.x, 0.0, 0.001)
	assert_almost_eq(v.y, 0.0, 0.001)

func test_guard_bounce_at_half_period_is_peak():
	# cos(π) = -1 → (1 - (-1)) / 2 = 1 → y = -18
	var v := Opponent.guard_bounce_offset(0.225, 18.0, 0.45)
	assert_almost_eq(v.x, 0.0, 0.001)
	assert_almost_eq(v.y, -18.0, 0.01)

func test_guard_bounce_at_full_period_back_to_planted():
	# cos(2π) = 1 → (1 - 1) / 2 = 0
	var v := Opponent.guard_bounce_offset(0.45, 18.0, 0.45)
	assert_almost_eq(v.x, 0.0, 0.001)
	assert_almost_eq(v.y, 0.0, 0.01)

func test_guard_bounce_never_below_base():
	# Sample many points; y_offset must always be ≤ 0
	for i in range(100):
		var t := float(i) / 100.0 * 0.45
		var v := Opponent.guard_bounce_offset(t, 18.0, 0.45)
		assert_true(v.y <= 0.0 + 0.001, "y_offset should be ≤ 0 at t=%f, got %f" % [t, v.y])
