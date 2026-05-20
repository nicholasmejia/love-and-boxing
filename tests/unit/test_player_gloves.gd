extends GutTest

# GUT's custom-warnings load path doesn't pick up class_name registrations made
# in the same branch as this test file. Preload explicitly so parse succeeds.
const PlayerGloves = preload("res://scripts/actors/player_gloves.gd")

# Sway math at known t values for AMP_X=6, AMP_Y=4, PERIOD=1.0, phase=0
# x = AMP_X * sin(t * 2π + phase)
# y = AMP_Y * sin(t * 2π + phase + π/2) = AMP_Y * cos(t * 2π + phase)

func test_sway_offset_left_glove_at_t_zero():
	var v := PlayerGloves.sway_offset(0.0, 6.0, 4.0, 1.0, 0.0)
	assert_almost_eq(v.x, 0.0, 0.001)
	assert_almost_eq(v.y, 4.0, 0.001)   # cos(0) = 1

func test_sway_offset_right_glove_at_t_zero():
	# Right glove uses phase = PI — sin(PI) = 0, cos(PI) = -1
	var v := PlayerGloves.sway_offset(0.0, 6.0, 4.0, 1.0, PI)
	assert_almost_eq(v.x, 0.0, 0.001)
	assert_almost_eq(v.y, -4.0, 0.001)

func test_sway_offset_at_quarter_period_left():
	var v := PlayerGloves.sway_offset(0.25, 6.0, 4.0, 1.0, 0.0)
	assert_almost_eq(v.x, 6.0, 0.001)   # sin(π/2) = 1
	assert_almost_eq(v.y, 0.0, 0.001)   # cos(π/2) = 0

func test_sway_offset_gloves_are_anti_phased():
	# At any t, left and right glove offsets should be opposite (within numerical noise)
	var left := PlayerGloves.sway_offset(0.3, 6.0, 4.0, 1.0, 0.0)
	var right := PlayerGloves.sway_offset(0.3, 6.0, 4.0, 1.0, PI)
	assert_almost_eq(left.x, -right.x, 0.001)
	assert_almost_eq(left.y, -right.y, 0.001)
