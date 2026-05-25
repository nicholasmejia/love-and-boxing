extends GutTest

const TB = preload("res://scripts/ui/trace_border.gd")

func _make_trace(w: float, h: float) -> Node:
	var tb = TB.new()
	tb.size = Vector2(w, h)
	autofree(tb)
	return tb

const _EPS := 0.001

# Box (188, 188) → center (94, 94), inscribed radius = min(188, 188) / 2 = 94.
const _CENTER := Vector2(94.0, 94.0)
const _RADIUS := 94.0


func _assert_point_almost_eq(actual: Vector2, expected: Vector2) -> void:
	assert_almost_eq(actual.x, expected.x, _EPS)
	assert_almost_eq(actual.y, expected.y, _EPS)


func test_circle_zero_is_top():
	var tb = _make_trace(188.0, 188.0)
	_assert_point_almost_eq(tb._circle_point(0.0), _CENTER + Vector2(0.0, -_RADIUS))

func test_circle_quarter_is_right():
	var tb = _make_trace(188.0, 188.0)
	_assert_point_almost_eq(tb._circle_point(0.25), _CENTER + Vector2(_RADIUS, 0.0))

func test_circle_half_is_bottom():
	var tb = _make_trace(188.0, 188.0)
	_assert_point_almost_eq(tb._circle_point(0.5), _CENTER + Vector2(0.0, _RADIUS))

func test_circle_three_quarters_is_left():
	var tb = _make_trace(188.0, 188.0)
	_assert_point_almost_eq(tb._circle_point(0.75), _CENTER + Vector2(-_RADIUS, 0.0))

func test_circle_one_wraps_to_top():
	var tb = _make_trace(188.0, 188.0)
	_assert_point_almost_eq(tb._circle_point(1.0), tb._circle_point(0.0))

func test_circle_wraps_when_t_exceeds_one():
	var tb = _make_trace(188.0, 188.0)
	_assert_point_almost_eq(tb._circle_point(1.5), tb._circle_point(0.5))

func test_circle_wraps_when_t_negative():
	var tb = _make_trace(188.0, 188.0)
	# -0.25 % 1.0 = 0.75 → left of center
	_assert_point_almost_eq(tb._circle_point(-0.25), _CENTER + Vector2(-_RADIUS, 0.0))

func test_trail_color_head_is_red_opaque():
	var tb = _make_trace(188.0, 188.0)
	assert_eq(tb._trail_color(0), Color.from_hsv(TB._RAINBOW_HUE_START, 1.0, 1.0, 1.0))

func test_trail_color_tail_end_is_violet_transparent():
	var tb = _make_trace(188.0, 188.0)
	assert_eq(tb._trail_color(TB._SEGMENT_COUNT - 1), Color.from_hsv(TB._RAINBOW_HUE_END, 1.0, 1.0, 0.0))

func test_trail_color_fades_in_late_band():
	# Late segment (i=20 of 24) falls in the last ~40% of the trail where
	# alpha is between fully opaque and fully transparent.
	var tb = _make_trace(188.0, 188.0)
	var c = tb._trail_color(20)
	assert_gt(c.a, 0.0, "late segment alpha must be > 0")
	assert_lt(c.a, 1.0, "late segment alpha must be < 1")

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
