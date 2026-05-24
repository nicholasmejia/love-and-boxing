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

# --- Phase 3 Task 8: punch_at_screen_position ---

const PlayerGlovesScene := preload("res://scenes/actors/player_gloves.tscn")

func _mount_gloves() -> PlayerGloves:
	var g: PlayerGloves = PlayerGlovesScene.instantiate()
	add_child_autoqfree(g)
	return g

func test_punch_at_screen_position_animates_right_glove_to_target():
	var gloves := _mount_gloves()
	await get_tree().process_frame  # _ready completes
	var target := Vector2(1280, 500)
	gloves.punch_at_screen_position(target)
	# Wait for the travel tween to complete (GLOVE_TRAVEL_DURATION + buffer).
	await get_tree().create_timer(PlayerGloves.GLOVE_TRAVEL_DURATION + 0.05).timeout
	var right_pos: Vector2 = (gloves.get_node("RightGlove") as Node2D).position
	# Right glove position should be within a few pixels of target after travel completes.
	assert_almost_eq(right_pos.x, target.x, 5.0, "right glove x should reach target")
	assert_almost_eq(right_pos.y, target.y, 5.0, "right glove y should reach target")

func test_punch_at_screen_position_does_not_move_left_glove():
	var gloves := _mount_gloves()
	await get_tree().process_frame
	var left_start: Vector2 = (gloves.get_node("LeftGlove") as Node2D).position
	gloves.punch_at_screen_position(Vector2(1280, 500))
	await get_tree().create_timer(PlayerGloves.GLOVE_TRAVEL_DURATION + 0.05).timeout
	var left_pos: Vector2 = (gloves.get_node("LeftGlove") as Node2D).position
	# Left glove may sway from IDLE — allow a few pixels.
	assert_almost_eq(left_pos.x, left_start.x, 10.0, "left glove x should not move during right-glove punch")
	assert_almost_eq(left_pos.y, left_start.y, 10.0, "left glove y should not move during right-glove punch")
