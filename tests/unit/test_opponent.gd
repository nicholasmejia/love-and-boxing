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
