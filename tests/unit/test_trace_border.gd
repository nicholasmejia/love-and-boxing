extends GutTest

const TB = preload("res://scripts/ui/trace_border.gd")

func _make_trace(w: float, h: float) -> Node:
	var tb = TB.new()
	tb.size = Vector2(w, h)
	return tb

func test_perimeter_zero_is_origin():
	var tb = _make_trace(188.0, 188.0)
	assert_eq(tb._perimeter_point(0.0), Vector2(0.0, 0.0))

func test_perimeter_quarter_is_top_right():
	var tb = _make_trace(188.0, 188.0)
	assert_eq(tb._perimeter_point(0.25), Vector2(188.0, 0.0))

func test_perimeter_half_is_bottom_right():
	var tb = _make_trace(188.0, 188.0)
	assert_eq(tb._perimeter_point(0.5), Vector2(188.0, 188.0))

func test_perimeter_three_quarters_is_bottom_left():
	var tb = _make_trace(188.0, 188.0)
	assert_eq(tb._perimeter_point(0.75), Vector2(0.0, 188.0))

func test_perimeter_one_wraps_to_origin():
	var tb = _make_trace(188.0, 188.0)
	assert_eq(tb._perimeter_point(1.0), Vector2(0.0, 0.0))

func test_perimeter_wraps_when_t_exceeds_one():
	var tb = _make_trace(188.0, 188.0)
	assert_eq(tb._perimeter_point(1.5), tb._perimeter_point(0.5))

func test_perimeter_wraps_when_t_negative():
	var tb = _make_trace(188.0, 188.0)
	# -0.25 % 1.0 = 0.75 → bottom-left
	assert_eq(tb._perimeter_point(-0.25), Vector2(0.0, 188.0))

func test_trail_color_head_is_opaque_white():
	var tb = _make_trace(188.0, 188.0)
	assert_eq(tb._trail_color(0), TB._HEAD_COLOR)

func test_trail_color_tail_end_is_transparent_violet():
	var tb = _make_trace(188.0, 188.0)
	assert_eq(tb._trail_color(TB._SEGMENT_COUNT - 1), TB._TAIL_COLOR)

func test_trail_color_midpoint_alpha_between_zero_and_one():
	var tb = _make_trace(188.0, 188.0)
	var mid = TB._SEGMENT_COUNT / 2
	var c = tb._trail_color(mid)
	assert_gt(c.a, 0.0, "mid alpha must be > 0")
	assert_lt(c.a, 1.0, "mid alpha must be < 1")

func test_play_trace_activates_and_resets_progress():
	var tb = _make_trace(188.0, 188.0)
	tb._progress = 0.7
	tb._active = false
	tb.play_trace()
	assert_true(tb._active, "play_trace must set _active = true")
	assert_eq(tb._progress, 0.0, "play_trace must reset _progress to 0")

func test_stop_trace_deactivates():
	var tb = _make_trace(188.0, 188.0)
	tb._active = true
	tb._progress = 0.5
	tb.stop_trace()
	assert_false(tb._active, "stop_trace must set _active = false")

func test_process_advances_progress_when_active():
	var tb = _make_trace(188.0, 188.0)
	tb.play_trace()
	tb._advance(0.05)  # 0.05 / 0.20 = 0.25
	assert_almost_eq(tb._progress, 0.25, 0.001)
	assert_true(tb._active)

func test_process_deactivates_when_progress_reaches_one():
	var tb = _make_trace(188.0, 188.0)
	tb.play_trace()
	tb._advance(TB._LAP_SECONDS)
	assert_false(tb._active, "_active must clear once a full lap completes")

func test_process_noop_when_inactive():
	var tb = _make_trace(188.0, 188.0)
	tb._active = false
	tb._progress = 0.0
	tb._advance(0.10)
	assert_eq(tb._progress, 0.0, "_advance must not move progress when inactive")
